// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Group-level hardware barrier: aggregates direct-wire barrier requests
/// from tiles within one group. A round whose participant tile mask and
/// local_only bit (both encoded in the originating core's barrier write,
/// forwarded here by cachepool_tile_barrier) only needs this group
/// resolves and releases without ever contacting the cluster; otherwise
/// a single request is forwarded to cachepool_cluster_barrier. Unlike
/// cachepool_tile_barrier this module never touches the core-facing bus:
/// it is purely wires in, wires out. Replicated NumSlots times (one
/// independent round tracker per barrier slot) so concurrently-live
/// rounds on different slots never serialize behind each other.
module cachepool_group_barrier
  import cachepool_pkg::*;
#(
  parameter int unsigned NumSlots = NumBarrierSlots
) (
  input  logic clk_i,
  input  logic rst_ni,

  // Direct-wire interface to local tiles
  input  logic         [NumSlots-1:0][NumTilesPerGroup-1:0] tile_barrier_i,
  input  barrier_req_t [NumSlots-1:0][NumTilesPerGroup-1:0] tile_req_i,
  output barrier_rsp_t [NumSlots-1:0][NumTilesPerGroup-1:0] tile_rsp_o,

  // Direct-wire interface to cluster level
  output logic [NumSlots-1:0] group_barrier_o,
  input  logic [NumSlots-1:0] barrier_done_i
);

  typedef enum logic [1:0] {
    Idle,
    Wait,
    ClusterWait,
    Done
  } barrier_state_e;

  barrier_state_e [NumSlots-1:0] state_d, state_q;

  // Round descriptor, latched from whichever tile is first to hit.
  barrier_req_t [NumSlots-1:0] req_d, req_q;

  // Debug-only: an arriving tile whose own descriptor disagrees with this round's latched one.
  logic [NumSlots-1:0][NumTilesPerGroup-1:0] mismatch_now, mismatch_d, mismatch_q;

  for (genvar s = 0; s < NumSlots; s++) begin : gen_slot
    logic [$clog2(NumTilesPerGroup)-1:0] first_hit_idx;

    always_comb begin
      first_hit_idx = '0;
      for (int i = NumTilesPerGroup-1; i >= 0; i--) begin
        if (tile_barrier_i[s][i]) first_hit_idx = i[$clog2(NumTilesPerGroup)-1:0];
      end
    end

    always_comb begin
      for (int i = 0; i < NumTilesPerGroup; i++) begin
        mismatch_now[s][i] = tile_barrier_i[s][i] && req_q[s].tile_mask[i]
                              && (tile_req_i[s][i] != req_q[s]);
      end
    end

    always_comb begin
      state_d[s]         = state_q[s];
      req_d[s]           = req_q[s];
      mismatch_d[s]      = mismatch_q[s];
      group_barrier_o[s] = 1'b0;

      case (state_q[s])
        Idle: begin
          // A new round starts once some local tile hits the barrier.
          if (|tile_barrier_i[s]) begin
            req_d[s] = tile_req_i[s][first_hit_idx];
            if ((tile_barrier_i[s] & tile_req_i[s][first_hit_idx].tile_mask)
                == tile_req_i[s][first_hit_idx].tile_mask) begin
              state_d[s] = tile_req_i[s][first_hit_idx].local_only ? Done : ClusterWait;
            end else begin
              state_d[s] = Wait;
            end
          end
        end

        Wait: begin
          // Round ends once all tiles in the latched mask have arrived.
          if ((tile_barrier_i[s] & req_q[s].tile_mask) == req_q[s].tile_mask) begin
            state_d[s] = req_q[s].local_only ? Done : ClusterWait;
          end
        end

        ClusterWait: begin
          group_barrier_o[s] = 1'b1;
          if (barrier_done_i[s]) state_d[s] = Done;
        end

        Done: begin
          // One-cycle pulse; tiles' activate lines clear on the same edge.
          mismatch_d[s] = mismatch_now[s];
          state_d[s]    = Idle;
        end

        default: state_d[s] = Idle;
      endcase
    end

    always_comb begin
      for (int i = 0; i < NumTilesPerGroup; i++) begin
        tile_rsp_o[s][i].done        = (state_q[s] == Done) && req_q[s].tile_mask[i];
        tile_rsp_o[s][i].mask_status = mismatch_q[s][i];
      end
    end

    `FF(state_q[s],    state_d[s],    Idle, clk_i, rst_ni)
    `FF(req_q[s],      req_d[s],      '0,   clk_i, rst_ni)
    `FF(mismatch_q[s], mismatch_d[s], '0,   clk_i, rst_ni)
  end

endmodule
