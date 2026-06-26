// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Based on periph_to_reg from register_interface.
// Converts REQRSP protocol to register interface with 1-cycle response latency.
// Assumes in-order, constant-latency target (e.g., BootROM).
// A FIFO preserves the REQRSP user field from request to response.

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module reqrsp_to_reg #(
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32,
  parameter int unsigned UserWidth  = 1,
  // FIFO depth for buffering user field (should match max outstanding)
  parameter int unsigned FifoDepth  = 2,
  // When enabled, shift response data right by the request byte offset
  // so that the addressed bytes land at [31:0]. Useful when the regbus
  // target is wider than the REQRSP requester (e.g., 512b BootROM
  // accessed by 32b core data loads). Aligned requests (offset=0)
  // see no change.
  parameter bit          ShiftResponse = 1'b0,
  parameter type         user_t     = logic [UserWidth-1:0],
  parameter type         reqrsp_req_t = logic,
  parameter type         reqrsp_rsp_t = logic,
  parameter type         reg_req_t  = logic,
  parameter type         reg_rsp_t  = logic
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  reqrsp_req_t reqrsp_req_i,
  output reqrsp_rsp_t reqrsp_rsp_o,
  output reg_req_t    reg_req_o,
  input  reg_rsp_t    reg_rsp_i
);

  localparam int unsigned ByteOffset = $clog2(DataWidth / 8);

  // Request grant: accepted when both sides are valid/ready
  logic gnt;
  assign gnt = reqrsp_req_i.q_valid & reg_rsp_i.ready;

  // Forward request to regbus (combinational)
  assign reg_req_o.addr  = reqrsp_req_i.q.addr;
  assign reg_req_o.write = reqrsp_req_i.q.write;
  assign reg_req_o.wdata = reqrsp_req_i.q.data;
  assign reg_req_o.wstrb = reqrsp_req_i.q.strb;
  assign reg_req_o.valid = reqrsp_req_i.q_valid;

  // REQRSP q_ready: grant the request
  assign reqrsp_rsp_o.q_ready = gnt;

  // Register response (1-cycle latency, same as periph_to_reg)
  logic                 rsp_valid_q;
  logic [DataWidth-1:0] rsp_rdata_d, rsp_rdata_q;
  logic                 rsp_error_q;
  logic                 rsp_write_q;

  `FF(rsp_valid_q, gnt,                    1'b0)
  `FF(rsp_rdata_q, rsp_rdata_d,            '0)
  `FF(rsp_error_q, reg_rsp_i.error,        1'b0)
  `FF(rsp_write_q, reqrsp_req_i.q.write,   1'b0)

  // Optional response data shift: use the combinational request address
  // to shift rdata right so the addressed bytes land at the LSB.
  // Safe because REQRSP holds q.addr stable until q_ready (= gnt),
  // and gnt fires on the same cycle rdata becomes valid (regbus
  // ready follows valid by 1 cycle for constant-latency targets).
  if (ShiftResponse) begin : gen_shift
    assign rsp_rdata_d = reg_rsp_i.rdata >> (reqrsp_req_i.q.addr[ByteOffset-1:0] * 8);
  end else begin : gen_no_shift
    assign rsp_rdata_d = reg_rsp_i.rdata;
  end

  // User FIFO: push on grant, pop when response is consumed
  user_t user_fifo_out;
  logic  user_fifo_full, user_fifo_empty;
  logic  user_fifo_push, user_fifo_pop;

  assign user_fifo_push = gnt;
  assign user_fifo_pop  = rsp_valid_q & reqrsp_req_i.p_ready;

  fifo_v3 #(
    .FALL_THROUGH ( 1'b0      ),
    .DEPTH        ( FifoDepth ),
    .dtype        ( user_t    )
  ) i_user_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    ( 1'b0            ),
    .testmode_i ( 1'b0            ),
    .full_o     ( user_fifo_full  ),
    .empty_o    ( user_fifo_empty ),
    .usage_o    ( /* unused */    ),
    .data_i     ( reqrsp_req_i.q.user ),
    .push_i     ( user_fifo_push ),
    .data_o     ( user_fifo_out  ),
    .pop_i      ( user_fifo_pop  )
  );

  // REQRSP response channel
  assign reqrsp_rsp_o.p.data  = rsp_rdata_q;
  assign reqrsp_rsp_o.p.error = rsp_error_q;
  assign reqrsp_rsp_o.p.write = rsp_write_q;
  assign reqrsp_rsp_o.p.user  = user_fifo_out;
  assign reqrsp_rsp_o.p_valid = rsp_valid_q;

  // Target is read-only when ShiftResponse is enabled (e.g., BootROM)
  `ifndef TARGET_SYNTHESIS
  if (ShiftResponse) begin : gen_no_write_assert
    `ASSERT(NoWrite, !(reg_req_o.valid && reg_req_o.write), clk_i, rst_ni)
  end
  `endif

endmodule
