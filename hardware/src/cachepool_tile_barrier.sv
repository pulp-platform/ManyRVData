// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Author: Fabian Schuiki <fschuiki@iis.ee.ethz.ch>
// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Hardware barrier to synchronize cores in a tile.
/// When all participating cores reach the barrier address, asserts `barrier_o`.
/// Waits for `barrier_done_i` from cluster level before releasing cores.
/// Supports partial barriers: a write to the barrier address carries a
/// per-core participant mask as its write data; a read is treated as the
/// legacy full-tile barrier (all cores participate).

// This barrier is designed by halting the q_ready signal of barrier request
// IMPORTANT: spill registers on the path to barrier may bring in unwanted behavior
module cachepool_tile_barrier
  import snitch_pkg::*;
  import cachepool_peripheral_reg_pkg::*;
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

  // Direct-wire barrier interface (bypasses NoC)
  output logic               barrier_o,
  input  logic               barrier_done_i,

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
  assign barrier_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_HW_BARRIER_OFFSET;

  logic [NrPorts-1:0] is_barrier;
  logic local_barrier;
  // barrier_o is registered: asserted when all local cores reach the barrier
  logic barrier_d, barrier_q;

  // Partial-barrier participant mask, encoded in the barrier request itself:
  // a write to barrier_addr carries the participant mask as its write data
  // (one bit per local core port); a read (the legacy full-barrier access)
  // is treated as "all ports participate". Whichever port's request is
  // first to arrive in a round has its mask latched for that round.
  typedef enum logic {
    MaskIdle,
    MaskActive
  } mask_state_e;

  mask_state_e         mask_state_d, mask_state_q;
  logic [NrPorts-1:0]  core_mask_d,  core_mask_q;
  logic [NrPorts-1:0]  barrier_hit;
  logic [NrPorts-1:0]  req_mask [NrPorts];
  logic [$clog2(NrPorts)-1:0] first_hit_idx;

  always_comb begin
    for (int i = 0; i < NrPorts; i++) begin
      barrier_hit[i] = (state_q[i] == Idle) && in_req_i[i].q_valid
                        && (in_req_i[i].q.addr == barrier_addr);
      req_mask[i]    = in_req_i[i].q.write ? in_req_i[i].q.data[NrPorts-1:0]
                                            : {NrPorts{1'b1}};
    end
  end

  always_comb begin
    first_hit_idx = '0;
    for (int i = NrPorts-1; i >= 0; i--) begin
      if (barrier_hit[i]) first_hit_idx = i[$clog2(NrPorts)-1:0];
    end
  end

  always_comb begin
    mask_state_d = mask_state_q;
    core_mask_d  = core_mask_q;
    case (mask_state_q)
      MaskIdle: begin
        // A new round starts once some local core hits the barrier address.
        if (|barrier_hit) begin
          core_mask_d  = req_mask[first_hit_idx];
          mask_state_d = MaskActive;
        end
      end
      MaskActive: begin
        // Round ends once the (masked) set of participants has all arrived.
        if (local_barrier) mask_state_d = MaskIdle;
      end
      default: mask_state_d = MaskIdle;
    endcase
  end

  // Masked barrier: only cores selected by core_mask_q must arrive.
  // core_mask_q == '0 can only happen before any round has started
  // (MaskIdle), so it can never trivially satisfy this comparison.
  assign local_barrier = (is_barrier & core_mask_q) == core_mask_q;
  assign barrier_o     = barrier_q;

  always_comb begin
    state_d       = state_q;
    user_d        = user_q;
    barrier_d     = barrier_q;
    is_barrier    = '0;
    out_req_o     = in_req_i;
    in_rsp_o      = out_rsp_i;

    for (int i = 0; i < NrPorts; i++) begin
      out_req_o[i].q.user.core_id = i;
      case (state_q[i])
        Idle: begin
          // If we have a barrier request => start to wait for other cores
          if (in_req_i[i].q_valid && (in_req_i[i].q.addr == barrier_addr)) begin
            state_d[i] = Wait;
            // Do not forward barrier request upstream
            out_req_o[i].q_valid = 0;
            in_rsp_o[i].q_ready  = 0;
          end
        end
        Wait: begin
          is_barrier[i]  = 1;
          in_rsp_o[i].q_ready  = 0;
          out_req_o[i].q_valid = 0;

          // When all participating cores have reached the barrier, assert barrier_o and move to Global
          if (local_barrier) begin
            barrier_d   = 1'b1;
            state_d[i]  = Global;
          end
        end
        Global: begin
          // All local cores are at the barrier.
          // Wait for cluster-level barrier_done_i signal.
          in_rsp_o[i].q_ready  = 0;
          out_req_o[i].q_valid = 0;

          if (barrier_done_i) begin
            state_d[i] = Take;
            // Release the barrier by accepting all requests
            in_rsp_o[i].q_ready = 1;
            // Record the user for response generating
            user_d[i] = out_req_o[i].q.user;
            // Deassert barrier_o
            barrier_d = 1'b0;
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

  `FFARN(barrier_q, barrier_d, 1'b0, clk_i, rst_ni)
  `FFARN(mask_state_q, mask_state_d, MaskIdle,       clk_i, rst_ni)
  `FFARN(core_mask_q,  core_mask_d,  {NrPorts{1'b1}}, clk_i, rst_ni)

  for (genvar i = 0; i < NrPorts; i++) begin : gen_ff
    `FFARN(state_q[i], state_d[i], Idle, clk_i, rst_ni)
    `FFARN(user_q[i],  user_d[i],  '0,   clk_i, rst_ni)
  end

endmodule
