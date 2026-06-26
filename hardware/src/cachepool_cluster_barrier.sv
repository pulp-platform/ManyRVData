// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Cluster-level barrier controller.
/// Collects per-tile barrier signals (direct wires, no AXI/NoC) and broadcasts
/// a done signal when all participating tiles have reached the barrier.
/// Supports partial barriers via `barrier_mask_i`.
module cachepool_cluster_barrier
#(
  parameter int unsigned NrTiles = 0
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  // Per-tile barrier request (active-high, held until barrier completes)
  input  logic [NrTiles-1:0]     tile_barrier_i,
  // Broadcast barrier completion to all tiles
  output logic                   barrier_done_o,
  // Which tiles participate in the barrier (active-high mask).
  // Active-low bits mark tiles that are excluded from synchronization.
  input  logic [NrTiles-1:0]     barrier_mask_i
);

  typedef enum logic [1:0] {
    Idle,
    Wait,
    Done
  } barrier_state_e;

  barrier_state_e state_d, state_q;

  // Latch the mask when barrier starts, so it stays stable during the sequence
  logic [NrTiles-1:0] mask_d, mask_q;

  // Masked barrier: only participating tiles matter
  logic all_arrived;
  assign all_arrived = (tile_barrier_i & mask_q) == mask_q;

  always_comb begin
    state_d        = state_q;
    mask_d         = mask_q;
    barrier_done_o = 1'b0;

    case (state_q)
      Idle: begin
        // When any participating tile asserts barrier, latch the mask and wait.
        // Use barrier_mask_i directly here since mask_q may hold the previous mask.
        if (|(tile_barrier_i & barrier_mask_i)) begin
          mask_d  = barrier_mask_i;
          if ((tile_barrier_i & barrier_mask_i) == barrier_mask_i) begin
            state_d = Done;
          end else begin
            state_d = Wait;
          end
        end
      end

      Wait: begin
        // Wait until all participating tiles have reached the barrier
        if (all_arrived) begin
          state_d = Done;
        end
      end

      Done: begin
        // Assert barrier_done for one cycle, then return to Idle.
        // Tiles deassert barrier_o the cycle after seeing barrier_done_i,
        // and no new barrier can start until cores complete the Take sequence.
        barrier_done_o = 1'b1;
        state_d        = Idle;
      end

      default: state_d = Idle;
    endcase
  end

  `FFARN(state_q, state_d, Idle, clk_i, rst_ni)
  `FFARN(mask_q,  mask_d,  '0,   clk_i, rst_ni)

endmodule
