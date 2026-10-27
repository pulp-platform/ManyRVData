// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Based on periph_to_reg from register_interface.
// Converts REQRSP protocol to register interface with 1-cycle response latency.
// Assumes the target answers in the cycle it raises ready (e.g., regtool CSRs, BootROM).
// A request is only issued when the response register is free or drained in the same
// cycle, so a response is held until its handshake and carries its own user field.

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module reqrsp_to_reg #(
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32,
  parameter int unsigned UserWidth  = 1,
  // Shift response data right by the request byte offset so the addressed bytes land at
  // [31:0], for regbus targets wider than the requester (e.g. 512b BootROM, 32b loads).
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

  // Response register state
  logic                 rsp_valid_q;
  logic [DataWidth-1:0] rsp_rdata_d, rsp_rdata_q;
  logic                 rsp_error_q;
  logic                 rsp_write_q;
  user_t                rsp_user_q;

  // The response register can take a new response this cycle
  logic rsp_free;
  assign rsp_free = ~rsp_valid_q | reqrsp_req_i.p_ready;

  // Request grant: target ready and room for the response
  logic req_valid, gnt;
  assign req_valid = reqrsp_req_i.q_valid & rsp_free;
  assign gnt       = req_valid & reg_rsp_i.ready;

  // Forward request to regbus. valid is gated as well, so a write cannot take effect
  // while its grant is held back.
  assign reg_req_o.addr  = reqrsp_req_i.q.addr;
  assign reg_req_o.write = reqrsp_req_i.q.write;
  assign reg_req_o.wdata = reqrsp_req_i.q.data;
  assign reg_req_o.wstrb = reqrsp_req_i.q.strb;
  assign reg_req_o.valid = req_valid;

  assign reqrsp_rsp_o.q_ready = gnt;

  // Shift rdata by the combinational request address. Safe for constant-latency targets:
  // q.addr is held until q_ready (= gnt), which fires in the cycle rdata becomes valid.
  if (ShiftResponse) begin : gen_shift
    assign rsp_rdata_d = reg_rsp_i.rdata >> (reqrsp_req_i.q.addr[ByteOffset-1:0] * 8);
  end else begin : gen_no_shift
    assign rsp_rdata_d = reg_rsp_i.rdata;
  end

  // Set on grant, cleared on handshake
  `FF(rsp_valid_q, gnt | (rsp_valid_q & ~reqrsp_req_i.p_ready), 1'b0)
  `FFL(rsp_rdata_q, rsp_rdata_d,          gnt, '0)
  `FFL(rsp_error_q, reg_rsp_i.error,      gnt, 1'b0)
  `FFL(rsp_write_q, reqrsp_req_i.q.write, gnt, 1'b0)
  `FFL(rsp_user_q,  reqrsp_req_i.q.user,  gnt, '0)

  // REQRSP response channel
  assign reqrsp_rsp_o.p.data  = rsp_rdata_q;
  assign reqrsp_rsp_o.p.error = rsp_error_q;
  assign reqrsp_rsp_o.p.write = rsp_write_q;
  assign reqrsp_rsp_o.p.user  = rsp_user_q;
  assign reqrsp_rsp_o.p_valid = rsp_valid_q;

  `ifndef TARGET_SYNTHESIS
  // Target is read-only when ShiftResponse is enabled (e.g., BootROM)
  if (ShiftResponse) begin : gen_no_write_assert
    `ASSERT(NoWrite, !(reg_req_o.valid && reg_req_o.write), clk_i, rst_ni)
  end
  `ASSERT(RspStable, reqrsp_rsp_o.p_valid && !reqrsp_req_i.p_ready |=>
          reqrsp_rsp_o.p_valid && $stable(reqrsp_rsp_o.p), clk_i, rst_ni)
  `endif

endmodule
