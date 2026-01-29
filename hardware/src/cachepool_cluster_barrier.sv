// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Last level of barrier in CachePool
/// Can perform partial/full barrier based on tile numbers
module cachepool_cluster_barrier
  import snitch_pkg::*;
  import cachepool_peripheral_reg_pkg::*;
#(
  parameter int unsigned AddrWidth  = 0,
  parameter int          NrPorts    = 0,
  parameter type axi_req_t      = logic,
  parameter type axi_rsp_t      = logic,
  // Used to generate response
  parameter type axi_id_t       = logic,
  parameter type axi_user_t     = logic,
  /// Derived parameter *Do not override*
  parameter type addr_t         = logic [AddrWidth-1:0]
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,
  // AXI input
  input  axi_req_t    [NrPorts-1:0]  axi_slv_req_i,
  output axi_rsp_t    [NrPorts-1:0]  axi_slv_rsp_o,
  // AXI output
  output axi_req_t    [NrPorts-1:0]  axi_mst_req_o,
  input  axi_rsp_t    [NrPorts-1:0]  axi_mst_rsp_i,

  input  logic        [NrPorts-1:0]  barrier_i,
  input  addr_t                      cluster_periph_start_address_i
);

  typedef enum logic [1:0] {
    Idle,
    Wait,
    Take,
    Global
  } barrier_state_e;

  // FSM State of the barrier
  barrier_state_e [NrPorts-1:0] state_d,   state_q;
  // the tiles participate in global barrier
  logic           [NrPorts-1:0] barrier_d, barrier_q;

  // Infomation stored for response generation
  typedef struct packed {
    axi_id_t    id;
    axi_user_t  user;
  } info_t;

  info_t [NrPorts-1:0] info_d, info_q;

  addr_t barrier_addr;
  assign barrier_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_HW_BARRIER_OFFSET;

  logic [NrPorts-1:0] is_barrier;
  logic take_barrier;

  // xnor between the is_barrier and the barrier needs to be taken
  assign take_barrier  = ~(|(barrier_q ^ is_barrier));

  always_comb begin
    state_d     = state_q;
    barrier_d   = barrier_q;
    info_d      = info_q;
    is_barrier  = '0;

    // Pass through the signals by default
    axi_mst_req_o = axi_slv_req_i;
    axi_slv_rsp_o = axi_mst_rsp_i;

    // Maximum barrier counter may only be configured in Idle state
    barrier_d = (|is_barrier == '0) ? barrier_i : barrier_q;

    for (int i = 0; i < NrPorts; i++) begin

      case (state_q[i])
        Idle: begin
          if (axi_slv_req_i[i].ar_valid & axi_slv_req_i[i].ar.addr == barrier_addr) begin
            // We have received a barrier request
            // Do not forward it further
            axi_mst_req_o[i].ar_valid = 0;
            // Accept the request
            axi_slv_rsp_o[i].ar_ready = 1;
            // Record the info need for response
            info_d[i] = '{
              id:   axi_slv_req_i[i].ar.id,
              user: axi_slv_req_i[i].ar.user
            };
            // Switch to next state
            if (barrier_q[i]) begin
              // Wait for global barrier
              state_d[i] = Wait;
            end else begin
              // Local tile barrier, no need to sync
              state_d[i] = Take;
            end
          end
        end

        Wait: begin
          is_barrier[i] = 1;

          if (take_barrier) begin
            // Means all tile participate in the barrier have reach the point
            state_d[i] = Take;
          end
        end

        Take: begin
          if (!axi_mst_rsp_i[i].r_valid) begin
            // Make sure no r packet is in transition
            axi_slv_rsp_o[i].r        = '0;
            axi_slv_rsp_o[i].r_valid  = 1'b1;
            axi_slv_rsp_o[i].r.last   = 1'b1;
            axi_slv_rsp_o[i].r.id     = info_q[i].id;
            axi_slv_rsp_o[i].r.user   = info_q[i].user;

            if (axi_slv_req_i[i].r_ready) begin
              // response accepted, switch back state
              state_d[i] = Idle;
              info_d[i]  = '0;
            end
          end
        end

        default: state_d[i] = Idle;
      endcase
    end
  end

  for (genvar i = 0; i < NrPorts; i++) begin : gen_ff
    `FFARN(state_q[i],    state_d[i],   Idle, clk_i, rst_ni)
    `FFARN(barrier_q[i],  barrier_d[i], '0,   clk_i, rst_ni)
    `FFARN(info_q[i],     info_d[i],    '0,   clk_i, rst_ni)
  end

endmodule
