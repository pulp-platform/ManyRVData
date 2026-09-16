// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Cluster-level barrier controller.
/// Collects per-group barrier signals (direct wires, no AXI/NoC) and broadcasts
/// a done signal when all participating groups have reached the barrier.
/// Supports partial barriers via `barrier_mask_i`. Replicated NumSlots times
/// (one independent round tracker per barrier slot, see cachepool_pkg::
/// NumBarrierSlots) so concurrently-live rounds on different slots -- even
/// ones that both reach cluster level -- never serialize behind each other.
module cachepool_cluster_barrier
  import cachepool_pkg::*;
#(
  parameter int unsigned NrGroups = 0,
  parameter int unsigned NumSlots = NumBarrierSlots,
  parameter int unsigned WaitCyc  = 2
) (
  input  logic                              clk_i,
  input  logic                              rst_ni,
  // Per-slot, per-group barrier request (active-high, held until barrier completes)
  input  logic [NumSlots-1:0][NrGroups-1:0] group_barrier_i,
  // Broadcast per-slot barrier completion to all groups
  output logic [NumSlots-1:0]               barrier_done_o,
  // Which groups participate in each slot's barrier (active-high mask).
  // Active-low bits mark groups that are excluded from synchronization.
  input  logic [NumSlots-1:0][NrGroups-1:0] barrier_mask_i
);

  typedef enum logic [1:0] {
    Idle,
    Wait,
    Done
  } barrier_state_e;

  barrier_state_e [NumSlots-1:0] state_d, state_q;

  // Latch the mask when barrier starts, so it stays stable during the sequence
  logic [NumSlots-1:0][NrGroups-1:0] mask_d, mask_q;

  // Exit counter for one iteration of barrier
  logic [NumSlots-1:0][1:0] cnt_d, cnt_q;

  // Masked barrier: only participating groups matter
  logic [NumSlots-1:0] all_arrived;

  for (genvar s = 0; s < NumSlots; s++) begin : gen_slot
    assign all_arrived[s] = (group_barrier_i[s] & mask_q[s]) == mask_q[s];

    always_comb begin
      state_d[s]        = state_q[s];
      mask_d[s]         = mask_q[s];
      cnt_d[s]          = cnt_q[s];
      barrier_done_o[s] = 1'b0;

      case (state_q[s])
        Idle: begin
          cnt_d[s] = '0;
          // When any participating group asserts barrier, latch the mask and wait.
          // Use barrier_mask_i directly here since mask_q may hold the previous mask.
          if (|(group_barrier_i[s] & barrier_mask_i[s])) begin
            mask_d[s] = barrier_mask_i[s];
            if ((group_barrier_i[s] & barrier_mask_i[s]) == barrier_mask_i[s]) begin
              state_d[s] = Done;
            end else begin
              state_d[s] = Wait;
            end
          end
        end

        Wait: begin
          // Wait until all participating groups have reached the barrier
          cnt_d[s] = '0;
          if (all_arrived[s]) begin
            state_d[s] = Done;
          end
        end

        Done: begin
          // Assert barrier_done for one cycle, then return to Idle.
          // Groups deassert group_barrier_o the cycle after seeing barrier_done_i,
          // and no new barrier can start until cores complete the Take sequence.
          if (cnt_q[s] == '0) begin
            // We assert done flag in first cycle
            // We need to wait all groups receive the propogated signal
            // And it will travel back => need to wait 2 cycles
            barrier_done_o[s] = 1'b1;
            cnt_d[s] = cnt_q[s] + 1;
          end else if (cnt_q[s] < WaitCyc) begin
            cnt_d[s] = cnt_q[s] + 1;
          end else begin
            // We have finished counting, let's move back for next barrier
            state_d[s] = Idle;
          end
        end

        default: state_d[s] = Idle;
      endcase
    end

    `FF(state_q[s], state_d[s], Idle, clk_i, rst_ni)
    `FF(mask_q[s],  mask_d[s],  '0,   clk_i, rst_ni)
    `FF(cnt_q[s],   cnt_d[s],   '0,   clk_i, rst_ni)
  end

endmodule
