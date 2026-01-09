// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Author: Fabian Schuiki <fschuiki@iis.ee.ethz.ch>
// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Hardware barrier to synchronize all cores in a cluster.
/// Adapted from Spatz cluster's barrier to fit for a NUMA system
/// The barrier will notify the CSR for global sync

// This barrier is designed by halting the q_ready signal of barrier request
// IMPORTANT: spill registers on the path to barrier may bring in unwanted behavior
module cachepool_tile_barrier
  import snitch_pkg::*;
  import spatz_cluster_peripheral_reg_pkg::*;
#(
  parameter int unsigned AddrWidth = 0,
  parameter int  NrPorts = 0,
  parameter type dreq_t = logic,
  parameter type user_t = logic,
  parameter type drsp_t = logic,
  /// Derived parameter *Do not override*
  parameter type addr_t = logic [AddrWidth-1:0]
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  dreq_t [NrPorts-1:0] in_req_i,
  output drsp_t [NrPorts-1:0] in_rsp_o,

  output dreq_t [NrPorts-1:0] out_req_o,
  input  drsp_t [NrPorts-1:0] out_rsp_i,

  input  addr_t              cluster_periph_start_address_i
);

  typedef enum logic [1:0] {
    Idle,
    Wait,
    Global,
    Take
  } barrier_state_e;

  barrier_state_e [NrPorts-1:0] state_d, state_q;
  user_t          [NrPorts-1:0] user_d, user_q;

  addr_t barrier_addr;
  assign barrier_addr = cluster_periph_start_address_i + SPATZ_CLUSTER_PERIPHERAL_HW_BARRIER_OFFSET;

  logic [NrPorts-1:0] is_barrier, done_barrier;
  logic take_barrier;
  logic local_barrier;

  assign local_barrier = &is_barrier;
  assign take_barrier  = &done_barrier;

  always_comb begin
    state_d       = state_q;
    user_d        = user_q;
    is_barrier    = '0;
    done_barrier  = '0;
    out_req_o     = in_req_i;
    in_rsp_o      = out_rsp_i;

    for (int i = 0; i < NrPorts; i++) begin
      out_req_o[i].q.user.core_id = i;
      case (state_q[i])
        Idle: begin
          // If we have a barrier request => start to wait for other cores
          if (in_req_i[i].q_valid && (in_req_i[i].q.addr == barrier_addr)) begin
            state_d[i] = Wait;
            // we do not send the request to CSR
            out_req_o[i].q_valid = 0;
            in_rsp_o[i].q_ready  = 0;
          end
        end
        Wait: begin
          is_barrier[i]  = 1;
          in_rsp_o[i].q_ready  = 0;
          out_req_o[i].q_valid = 0;

          // Pause the request to CSR until all cores have enter the barrier
          if (local_barrier) begin
            if (i == 0) begin
              // Port 0 will be used to sync with other tiles
              // Sned out the barrier request
              out_req_o[i].q_valid = 1;
              if (out_rsp_i[i].q_ready) begin
                // Global barrier accepted, waiting for response
                state_d[i] = Global;
                // out_req_o[i].q_valid = 0;
              end
            end else begin
              // Other ports can directly enter Global state
              state_d[i] = Global;
            end
          end
        end
        Global: begin
          // The local barrier of the tile has complete
          // Waiting for CSR to grant the global one => configurable in CSR for barrier size
          // We will now send **ONE** request to CSR for cleaerance

          // Do not release the barrier yet
          in_rsp_o[i].q_ready  = 0;
          out_req_o[i].q_valid = 0;

          if (i == 0) begin
            // Waiting for response for global barrier
            if (out_rsp_i[i].p_valid) begin
              // Mute the response for now
              in_rsp_o[i].p_valid   = 0;

              done_barrier[i]       = 1;
            end
          end else begin
            // Waiting for port 0 finish global barrier
            done_barrier[i]      = 1;
          end

          if (take_barrier) begin
            state_d[i] = Take;
            // Release the barrier by accepting all requests
            in_rsp_o[i].q_ready = 1;
            // Record the user for response generating
            user_d[i] = out_req_o[i].q.user;
          end
        end
        Take: begin
          // Send back the response to finish the barrier sequence
          in_rsp_o[i]         = '0;
          in_rsp_o[i].p_valid = 1;
          in_rsp_o[i].p.user  = user_q[i];

          if (in_req_i[i].p_ready) begin
            // Response has been taken
            state_d[i] = Idle;
            user_d[i]  = '0;
          end
        end

        default: state_d[i] = Idle;
      endcase
    end
  end

  for (genvar i = 0; i < NrPorts; i++) begin : gen_ff
    `FFARN(state_q[i], state_d[i], Idle, clk_i, rst_ni)
    `FFARN(user_q[i],  user_d[i],  '0,   clk_i, rst_ni)
  end

endmodule
