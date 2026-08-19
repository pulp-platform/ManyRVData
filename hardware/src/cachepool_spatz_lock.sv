// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

/// Spatz ownership lock/switch for a dual-Snitch cachepool_cc_dual.
/// Host 0 is the implicit owner while Idle; a write of 1 to the lock
/// address acquires ownership (blocks until granted), a write of 0
/// releases it (owner only). Pure arbiter: does not route the acc/data
/// traffic itself (that lives in acc_mux.sv/cachepool_cc_dual.sv) -- only
/// decides ownership and exposes owner_id_o/locked_o/waiting_o for the CC
/// to apply, and counts real Spatz acc handshakes (via
/// req_fire_i/rsp_fire_i, fed back by acc_mux) to gate a switch until
/// fully drained.
/// Also hosts the pass-through memory-path register cuts (moved here from
/// the per-core spill registers in cachepool_cc.sv).
module cachepool_spatz_lock
  import cachepool_peripheral_reg_pkg::*;
#(
  parameter int unsigned AddrWidth       = 0,
  parameter int unsigned NumHosts        = 2,
  parameter type         dreq_t          = logic,
  parameter type         drsp_t          = logic,
  parameter type         dreq_chan_t     = logic,
  parameter type         drsp_chan_t     = logic,
  parameter type         user_t          = logic,
  parameter bit          RegisterCoreReq = 1'b0,
  parameter bit          RegisterCoreRsp = 1'b0,
  /// Derived parameter *Do not override*
  parameter type         addr_t          = logic [AddrWidth-1:0]
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,

  // memory interface, used to set the lock
  input  dreq_t           [NumHosts-1:0] in_req_i,
  output drsp_t           [NumHosts-1:0] in_rsp_o,
  output dreq_t           [NumHosts-1:0] out_req_o,
  input  drsp_t           [NumHosts-1:0] out_rsp_i,

  // Real Spatz acc handshake fires, fed back by acc_mux purely for drain counting.
  input  logic                           req_fire_i,
  input  logic                           rsp_fire_i,

  // owner/lock status and error
  output logic                           owner_id_o,
  output logic                           locked_o,
  output logic                           waiting_o,
  output logic                           error_o,

  // peripheral base address
  input  addr_t                          cluster_periph_start_address_i
);

  addr_t lock_addr;
  assign lock_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_SPATZ_LOCK_OFFSET;

  // Single lock FSM. Idle/Locked are the two "real" states (host 0 is the
  // implicit owner while Idle); AcqWait/RelWait are drain-wait sub-states
  // on the way to an actual ownership switch.
  //   Idle    -(acquire, other host)-> AcqWait -(drain_done)-> Locked (new owner)
  //   Locked  -(release, owner)     -> RelWait -(drain_done)-> Idle   (owner = host 0)
  // Self-acquire completes immediately only if already drained; otherwise it
  // waits through AcqWait too. Reads always complete immediately.
  // A non-owner acquire/release, or any lock op during a wait, is stalled
  // (never accepted) and sets the sticky error_o.
  //
  // Handshake timing: the q-channel is accepted (q_ready=1) exactly on the
  // deciding cycle (the last cycle of a wait, or immediately for the
  // no-wait cases); the response (p_valid=1) is then held starting the
  // following cycle until the host takes it via p_ready.
  typedef enum logic [1:0] {
    Idle,
    AcqWait,
    RelWait,
    Locked
  } lock_state_e;

  lock_state_e lock_d, lock_q;
  logic        owner_d, owner_q;
  logic        error_d, error_q;
  logic        active_d, active_q;
  user_t       user_d, user_q;

  // Outstanding acc handshakes on the owner's path; must reach 0 before a wait can complete.
  logic [7:0] outstanding_d, outstanding_q;
  logic       drain_done, waiting;

  assign owner_id_o = owner_q;
  assign locked_o   = (lock_q == Locked);
  assign waiting_o  = waiting;
  assign error_o    = error_q;

  assign waiting    = (lock_q == AcqWait) || (lock_q == RelWait);
  assign drain_done = (outstanding_q == '0);

  `ASSERT(NoOutstandingUnderflow, rsp_fire_i |-> (outstanding_q != '0))

  always_comb begin
    outstanding_d = outstanding_q;
    if (req_fire_i && !rsp_fire_i) begin
      // one insn issued
      outstanding_d = outstanding_q + 8'd1;
    end else if (!req_fire_i && rsp_fire_i) begin
      // one insn finished
      outstanding_d = outstanding_q - 8'd1;
    end
  end

  // write 1 for acquire, write 0 for release, read returns the lock status
  logic [1:0] is_acquire, is_release, is_read, lock_hit;

  for (genvar i = 0; i < 2; i++) begin
    assign is_acquire[i] = in_req_i[i].q.write &&  in_req_i[i].q.data[0];
    assign is_release[i] = in_req_i[i].q.write && !in_req_i[i].q.data[0];
    assign is_read[i]    = !in_req_i[i].q.write;
    assign lock_hit[i]   = in_req_i[i].q_valid && (in_req_i[i].q.addr == lock_addr);
  end

  // The owner's hit always wins arbitration, so a non-owner's (always-illegal-in-Locked)
  // request can never starve the owner's legitimate one.
  logic hit_any, winner;
  assign hit_any = lock_hit[0] || lock_hit[1];
  assign winner  = lock_hit[owner_q] ? owner_q : ~owner_q;

  // Pending, not-yet-delivered completion response (one at a time; a new lock op is
  // only arbitrated once the previous one's response has been taken).
  logic       resp_pending_d, resp_pending_q;
  logic       resp_host_d,    resp_host_q;
  user_t      resp_user_d,    resp_user_q;
  logic       resp_read_d,    resp_read_q;
  logic [1:0] resp_status_d,  resp_status_q;

  // Register cuts on the pass-through path (moved here from cachepool_cc.sv's per-core
  // spill registers), placed at the module's output side.
  logic       [1:0] mem_req_valid, mem_req_ready, mem_rsp_valid;
  drsp_chan_t [1:0] mem_rsp_chan;

  for (genvar i = 0; i < 2; i++) begin : gen_out_cut
    assign mem_req_valid[i] = in_req_i[i].q_valid && !lock_hit[i];

    spill_register #(
      .T      ( dreq_chan_t      ),
      .Bypass ( !RegisterCoreReq )
    ) i_spill_register_req (
      .clk_i,
      .rst_ni,
      .valid_i ( mem_req_valid[i]     ),
      .ready_o ( mem_req_ready[i]     ),
      .data_i  ( in_req_i[i].q        ),
      .valid_o ( out_req_o[i].q_valid ),
      .ready_i ( out_rsp_i[i].q_ready ),
      .data_o  ( out_req_o[i].q       )
    );

    spill_register #(
      .T      ( drsp_chan_t      ),
      .Bypass ( !RegisterCoreRsp )
    ) i_spill_register_rsp (
      .clk_i,
      .rst_ni,
      .valid_i ( out_rsp_i[i].p_valid ),
      .ready_o ( out_req_o[i].p_ready ),
      .data_i  ( out_rsp_i[i].p       ),
      .valid_o ( mem_rsp_valid[i]     ),
      .ready_i ( in_req_i[i].p_ready  ),
      .data_o  ( mem_rsp_chan[i]      )
    );
  end

  always_comb begin
    lock_d         = lock_q;
    owner_d        = owner_q;
    error_d        = error_q;
    active_d       = active_q;
    user_d         = user_q;
    resp_pending_d = resp_pending_q;
    resp_host_d    = resp_host_q;
    resp_user_d    = resp_user_q;
    resp_read_d    = resp_read_q;
    resp_status_d  = resp_status_q;

    // Default: pass through the (registered) memory path; blocked on a lock-address hit.
    for (int i = 0; i < 2; i++) begin
      in_rsp_o[i]         = '0;
      in_rsp_o[i].q_ready = lock_hit[i] ? 1'b0 : mem_req_ready[i];
      in_rsp_o[i].p_valid = mem_rsp_valid[i];
      in_rsp_o[i].p       = mem_rsp_chan[i];
    end

    // Deliver a pending completion response, starting the cycle after it was accepted.
    if (resp_pending_q) begin
      in_rsp_o[resp_host_q]         = '0;
      in_rsp_o[resp_host_q].p_valid = 1'b1;
      in_rsp_o[resp_host_q].p.user  = resp_user_q;
      if (resp_read_q) begin
        in_rsp_o[resp_host_q].p.data[0] = resp_status_q[0];
        in_rsp_o[resp_host_q].p.data[1] = resp_status_q[1];
      end
      if (in_req_i[resp_host_q].p_ready) resp_pending_d = 1'b0;
    end

    case (lock_q)
      // Host 0 is the implicit owner. Its own release is a no-op (immediate grant);
      // its own acquire grants immediately only if drained, else waits like host 1's;
      // host 1's release is meaningless (nothing to release) and stalled.
      Idle: begin
        if (hit_any && !resp_pending_q) begin
          if (is_acquire[winner]) begin
            if (winner == owner_q && drain_done) begin
              // host 0 self-acquire, nothing outstanding: immediate grant
              lock_d      = Locked;
              in_rsp_o[winner].q_ready = 1'b1;
              resp_pending_d           = 1'b1;
              resp_host_d              = winner;
              resp_user_d              = in_req_i[winner].q.user;
              resp_read_d              = 1'b0;
            end else begin
              // host 1 wants the lock, or host 0 self-acquires while Idle-mode
              // traffic (from either host) is still outstanding -> drain first
              active_d = winner;
              user_d   = in_req_i[winner].q.user;
              lock_d   = AcqWait;
            end
          end else if (is_release[winner]) begin
            if (winner == owner_q) begin
              // "self release": nothing to release, immediate no-op grant
              in_rsp_o[winner].q_ready = 1'b1;
              resp_pending_d           = 1'b1;
              resp_host_d              = winner;
              resp_user_d              = in_req_i[winner].q.user;
              resp_read_d              = 1'b0;
            end else begin
              // host 1 release: stalled, never accepted
              error_d = 1'b1;
            end
          end else if (is_read[winner]) begin
            in_rsp_o[winner].q_ready = 1'b1;
            resp_pending_d           = 1'b1;
            resp_host_d              = winner;
            resp_user_d              = in_req_i[winner].q.user;
            resp_read_d              = 1'b1;
            resp_status_d            = {1'b0, owner_q};
          end
        end
      end

      // Only the owner's acquire (no-op) or release (drains, reverts to Idle) is ever
      // legal; a non-owner's acquire/release is stalled and flagged.
      Locked: begin
        if (hit_any && !resp_pending_q) begin
          if (is_acquire[winner]) begin
            if (winner == owner_q) begin
              // owner self-acquire: no-op, immediate grant
              in_rsp_o[winner].q_ready = 1'b1;
              resp_pending_d           = 1'b1;
              resp_host_d              = winner;
              resp_user_d              = in_req_i[winner].q.user;
              resp_read_d              = 1'b0;
            end else begin
              // non-owner acquire: stalled, never accepted
              error_d = 1'b1;
            end
          end else if (is_release[winner]) begin
            if (winner == owner_q) begin
              // owner release -> drain, then revert to Idle
              active_d = winner;
              user_d   = in_req_i[winner].q.user;
              lock_d   = RelWait;
            end else begin
              // non-owner release: stalled, never accepted
              error_d = 1'b1;
            end
          end else if (is_read[winner]) begin
            in_rsp_o[winner].q_ready = 1'b1;
            resp_pending_d           = 1'b1;
            resp_host_d              = winner;
            resp_user_d              = in_req_i[winner].q.user;
            resp_read_d              = 1'b1;
            resp_status_d            = {1'b1, owner_q};
          end
        end
      end

      // No lock op is accepted from anyone while waiting.
      AcqWait: begin
        if (drain_done) begin
          owner_d                    = active_q;
          lock_d                     = Locked;
          in_rsp_o[active_q].q_ready = 1'b1;
          resp_pending_d             = 1'b1;
          resp_host_d                = active_q;
          resp_user_d                = user_q;
          resp_read_d                = 1'b0;
        end
      end

      RelWait: begin
        if (drain_done) begin
          owner_d                    = 1'b0;
          lock_d                     = Idle;
          in_rsp_o[active_q].q_ready = 1'b1;
          resp_pending_d             = 1'b1;
          resp_host_d                = active_q;
          resp_user_d                = user_q;
          resp_read_d                = 1'b0;
        end
      end

      default: lock_d = Idle;
    endcase
  end

  `FF(lock_q,         lock_d,         Idle, clk_i, rst_ni)
  `FF(owner_q,        owner_d,        1'b0, clk_i, rst_ni)
  `FF(error_q,        error_d,        1'b0, clk_i, rst_ni)
  `FF(active_q,       active_d,       1'b0, clk_i, rst_ni)
  `FF(user_q,         user_d,         '0,   clk_i, rst_ni)
  `FF(outstanding_q,  outstanding_d,  '0,   clk_i, rst_ni)
  `FF(resp_pending_q, resp_pending_d, 1'b0, clk_i, rst_ni)
  `FF(resp_host_q,    resp_host_d,    1'b0, clk_i, rst_ni)
  `FF(resp_user_q,    resp_user_d,    '0,   clk_i, rst_ni)
  `FF(resp_read_q,    resp_read_d,    1'b0, clk_i, rst_ni)
  `FF(resp_status_q,  resp_status_d,  '0,   clk_i, rst_ni)

endmodule
