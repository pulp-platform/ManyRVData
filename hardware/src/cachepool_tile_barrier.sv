// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Author: Fabian Schuiki <fschuiki@iis.ee.ethz.ch>
// Author: Diyou Shen     <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Hardware barrier to synchronize cores in a tile.
/// When all participating cores reach the barrier address, asserts `barrier_o`.
/// Waits for `barrier_rsp_i.done` from group level before releasing cores,
/// unless the round only needs this tile (see skip-Global fast path below).
/// Supports partial barriers: a write to the barrier address carries a
/// per-core participant mask, a per-tile participant mask (within the
/// group), a `local_only` bit, and a barrier slot id as its write data;
/// a read is treated as the legacy full-cluster barrier on slot 0
/// (everyone participates). Independent round trackers are replicated
/// NumSlots times (one per barrier slot, see cachepool_pkg::
/// NumBarrierSlots) so concurrently-live rounds on different slots never
/// serialize behind each other, even within the same tile.

// This barrier is designed by halting the q_ready signal of barrier request
// IMPORTANT: spill registers on the path to barrier may bring in unwanted behavior
module cachepool_tile_barrier
  import snitch_pkg::*;
  import cachepool_pkg::*;
  import cachepool_peripheral_reg_pkg::*;
#(
  parameter int unsigned AddrWidth    = 0,
  parameter int          NrPorts      = 0,
  parameter int unsigned LocalTileIdx = 0,
  parameter int unsigned NumSlots     = cachepool_pkg::NumBarrierSlots,
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

  // Direct-wire barrier interface to group level (bypasses NoC), one per slot
  output logic         [NumSlots-1:0] barrier_o,
  output barrier_req_t [NumSlots-1:0] barrier_req_o,
  input  barrier_rsp_t [NumSlots-1:0] barrier_rsp_i,

  input  addr_t              cluster_periph_start_address_i
);

  localparam int unsigned SlotIdWidth = $clog2(NumSlots);

  typedef enum logic [1:0] {
    Idle,
    Wait,
    Global,
    Take
  } barrier_state_e;

  barrier_state_e [NrPorts-1:0] state_d, state_q;
  user_t          [NrPorts-1:0] user_d, user_q;
  // Slot this core's in-flight round belongs to, latched on Idle -> Wait.
  logic [NrPorts-1:0][SlotIdWidth-1:0] slot_d, slot_q;

  addr_t barrier_addr;
  assign barrier_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_HW_BARRIER_OFFSET;

  // is_barrier[i]: core i is currently waiting in this round (slot given by slot_q[i]).
  logic [NrPorts-1:0] is_barrier;
  logic [NumSlots-1:0] local_barrier;
  // barrier_o is registered per slot: asserted when all local cores reach the
  // barrier and the round needs to leave this tile (see skip_global below).
  logic [NumSlots-1:0] barrier_d, barrier_q;

  // Write-data field offsets within the 32-bit barrier request payload:
  // [7:0] core mask (this block), [15:8] tile mask, [16] local_only,
  // [16+SlotIdWidth:17] barrier slot id.
  localparam int unsigned TileMaskLsb  = 8;
  localparam int unsigned LocalOnlyBit = 16;
  localparam int unsigned BarrierIdLsb = 17;

  // Partial-barrier participant mask, encoded in the barrier request itself:
  // a write to barrier_addr carries the core/tile participant masks, the
  // local_only bit, and the slot id as its write data; a read (the legacy
  // full-barrier access) is treated as "everyone participates, cluster-wide,
  // slot 0". Whichever port's request is first to arrive for a given slot in
  // a round has its fields latched for that slot.
  typedef enum logic {
    MaskIdle,
    MaskActive
  } mask_state_e;

  mask_state_e  [NumSlots-1:0]              mask_state_d,  mask_state_q;
  logic         [NumSlots-1:0][NrPorts-1:0] core_mask_d,   core_mask_q;
  barrier_req_t [NumSlots-1:0]              req_d,         req_q;
  logic         [NumSlots-1:0]              mask_status_d, mask_status_q;

  logic         [NrPorts-1:0]     barrier_hit;
  logic         [NrPorts-1:0]     req_core_mask  [NrPorts];
  barrier_req_t                   req_desc       [NrPorts];
  logic         [SlotIdWidth-1:0] req_barrier_id [NrPorts];

  logic [NumSlots-1:0][NrPorts-1:0]         barrier_hit_for_slot;
  logic [NumSlots-1:0][$clog2(NrPorts)-1:0] first_hit_idx;

  // Skip the group/cluster round entirely when nothing outside this tile
  // is needed: only this tile in the tile mask, and no cluster forwarding.
  logic [NumSlots-1:0] skip_global;

  always_comb begin
    for (int i = 0; i < NrPorts; i++) begin
      barrier_hit[i]         = (state_q[i] == Idle) && in_req_i[i].q_valid
                             && (in_req_i[i].q.addr == barrier_addr);
      req_core_mask[i]       = in_req_i[i].q.write ? in_req_i[i].q.data[NrPorts-1:0]
                                                    : {NrPorts{1'b1}};
      req_desc[i].tile_mask  = in_req_i[i].q.write ? in_req_i[i].q.data[TileMaskLsb +: NumTilesPerGroup]
                                                    : {NumTilesPerGroup{1'b1}};
      req_desc[i].local_only = in_req_i[i].q.write ? in_req_i[i].q.data[LocalOnlyBit] : 1'b0;
      req_barrier_id[i]      = in_req_i[i].q.write ? in_req_i[i].q.data[BarrierIdLsb +: SlotIdWidth]
                                                    : '0;
    end
  end

  for (genvar s = 0; s < NumSlots; s++) begin : gen_slot_arbitration
    always_comb begin
      for (int i = 0; i < NrPorts; i++) begin
        barrier_hit_for_slot[s][i] = barrier_hit[i] && (req_barrier_id[i] == s[SlotIdWidth-1:0]);
      end
    end

    always_comb begin
      first_hit_idx[s] = '0;
      for (int i = NrPorts-1; i >= 0; i--) begin
        if (barrier_hit_for_slot[s][i]) first_hit_idx[s] = i[$clog2(NrPorts)-1:0];
      end
    end

    always_comb begin
      mask_state_d[s] = mask_state_q[s];
      core_mask_d[s]  = core_mask_q[s];
      req_d[s]        = req_q[s];
      case (mask_state_q[s])
        MaskIdle: begin
          // A new round starts once some local core hits this slot's barrier.
          if (|barrier_hit_for_slot[s]) begin
            core_mask_d[s]  = req_core_mask[first_hit_idx[s]];
            req_d[s]        = req_desc[first_hit_idx[s]];
            mask_state_d[s] = MaskActive;
          end
        end
        MaskActive: begin
          // Round ends once the (masked) set of participants has all arrived.
          if (local_barrier[s]) mask_state_d[s] = MaskIdle;
        end
        default: mask_state_d[s] = MaskIdle;
      endcase
    end

    // is_barrier[i] restricted to slot s: core i is waiting and its latched
    // round is this slot.
    logic [NrPorts-1:0] is_barrier_slot;
    always_comb begin
      for (int i = 0; i < NrPorts; i++) begin
        is_barrier_slot[i] = is_barrier[i] && (slot_q[i] == s[SlotIdWidth-1:0]);
      end
    end

    // Masked barrier: only cores selected by core_mask_q[s] must arrive.
    // core_mask_q[s] == '0 can only happen before any round has started
    // (MaskIdle), so it can never trivially satisfy this comparison.
    assign local_barrier[s] = (is_barrier_slot & core_mask_q[s]) == core_mask_q[s];
    // tile_mask == 0 is a self-only sentinel (no round has zero tiles).
    logic self_only;
    assign self_only        = req_q[s].tile_mask == (NumTilesPerGroup'(1) << LocalTileIdx)
                            || req_q[s].tile_mask == '0;
    assign skip_global[s]   = req_q[s].local_only && self_only;
    assign barrier_o[s]     = barrier_q[s];
    assign barrier_req_o[s] = req_q[s];

    `FFARN(mask_state_q[s],  mask_state_d[s],  MaskIdle,        clk_i, rst_ni)
    `FFARN(core_mask_q[s],   core_mask_d[s],   {NrPorts{1'b1}}, clk_i, rst_ni)
    `FFARN(req_q[s],         req_d[s],         '0,              clk_i, rst_ni)
    `FFARN(barrier_q[s],     barrier_d[s],     1'b0,            clk_i, rst_ni)
    `FFARN(mask_status_q[s], mask_status_d[s], 1'b0,            clk_i, rst_ni)
  end

  always_comb begin
    state_d       = state_q;
    user_d        = user_q;
    slot_d        = slot_q;
    barrier_d     = barrier_q;
    mask_status_d = mask_status_q;
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
            slot_d[i]  = req_barrier_id[i];
            // Do not forward barrier request upstream
            out_req_o[i].q_valid = 0;
            in_rsp_o[i].q_ready  = 0;
          end
        end
        Wait: begin
          is_barrier[i]  = 1;
          in_rsp_o[i].q_ready  = 0;
          out_req_o[i].q_valid = 0;

          // When all participating cores have reached the barrier: if
          // nothing outside this tile is needed, take immediately;
          // otherwise assert barrier_o and move to Global.
          if (local_barrier[slot_q[i]]) begin
            if (skip_global[slot_q[i]]) begin
              state_d[i]  = Take;
              in_rsp_o[i].q_ready = 1;
              user_d[i]   = out_req_o[i].q.user;
            end else begin
              barrier_d[slot_q[i]] = 1'b1;
              state_d[i]  = Global;
            end
          end
        end
        Global: begin
          // All local cores are at the barrier. Wait for group-level done.
          in_rsp_o[i].q_ready  = 0;
          out_req_o[i].q_valid = 0;

          if (barrier_rsp_i[slot_q[i]].done) begin
            state_d[i] = Take;
            // Release the barrier by accepting all requests
            in_rsp_o[i].q_ready = 1;
            // Record the user for response generating
            user_d[i] = out_req_o[i].q.user;
            // Deassert barrier_o
            barrier_d[slot_q[i]] = 1'b0;
            mask_status_d[slot_q[i]] = barrier_rsp_i[slot_q[i]].mask_status;
          end
        end
        Take: begin
          // Send back the response to finish the barrier sequence
          in_rsp_o[i]         = '0;
          in_rsp_o[i].p_valid = 1;
          in_rsp_o[i].p.user  = user_q[i];
`ifndef TARGET_SYNTHESIS
          if (mask_status_q[slot_q[i]]) begin
            $display("[%0t] cachepool_tile_barrier: mask mismatch reported by group level (port %0d, slot %0d)",
                      $time, i, slot_q[i]);
          end
`endif

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
    `FFARN(slot_q[i],  slot_d[i],  '0,   clk_i, rst_ni)
  end

endmodule
