// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

/// Spatz ownership lock/switch for a dual-Snitch cachepool_cc_dual.
/// Host 0 is the implicit owner while Free. Two dedicated addresses are
/// intercepted: a load to ACQUIRE attempts to acquire, a load to RELEASE
/// attempts to release -- both always complete immediately (q_ready is
/// never withheld), and the loaded word encodes the outcome (fail/
/// success/success-wait) plus current owner/locked status, so software is
/// never blocked in hardware and can always retry or bail out on its own.
/// Pure arbiter: does not route the acc/data traffic itself (that lives in
/// acc_mux.sv/cachepool_cc_dual.sv) -- only decides ownership and exposes
/// owner_id_o/locked_o/waiting_o/owner_active_o for the CC to apply, and
/// counts real Spatz acc handshakes (via req_fire_i/rsp_fire_i, fed back
/// by acc_mux) to gate a switch until fully drained. Separately tracks
/// outstanding vle/vse ops (invisible to req_fire_i/rsp_fire_i, since they
/// never produce an acc_rsp_t writeback) via Spatz's own
/// spatz_mem_finished_i/spatz_st_rsp_done_i.
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

  // memory interface, used to attempt acquire/release
  input  dreq_t           [NumHosts-1:0] in_req_i,
  output drsp_t           [NumHosts-1:0] in_rsp_o,
  output dreq_t           [NumHosts-1:0] out_req_o,
  input  drsp_t           [NumHosts-1:0] out_rsp_i,

  // Real Spatz acc handshake fires, fed back by acc_mux purely for drain counting.
  input  logic                           req_fire_i,
  input  logic                           rsp_fire_i,

  // Spatz LSU drain tracking: vle/vse never produce an acc_rsp_t completion
  // (writeback=0), so they are invisible to req_fire_i/rsp_fire_i above and
  // need their own outstanding count, gated by Spatz's own signals.
  input  logic                           spatz_lsu_issue_fire_i,
  input  logic                    [1:0]  spatz_mem_finished_i,
  input  logic                           spatz_st_rsp_done_i,

  // owner/lock status
  output logic                           owner_id_o,
  output logic                           locked_o,
  output logic                           waiting_o,
  // True while the exclusive owner path may still have in-flight traffic to
  // drain (Locked and RelWait); acc_mux uses this to keep response draining
  // active through RelWait even though new-issue forwarding must stop.
  output logic                           owner_active_o,

  // peripheral base address
  input  addr_t                          cluster_periph_start_address_i
);

  addr_t acquire_addr, release_addr;
  assign acquire_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_SPATZ_LOCK_ACQUIRE_OFFSET;
  assign release_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_SPATZ_LOCK_RELEASE_OFFSET;

  // Single lock FSM. Free/Locked are the two "real" states (host 0 is the
  // implicit owner while Free); AcqWait/RelWait are drain-wait sub-states
  // on the way to an actual ownership switch, resolved autonomously once
  // drain_done -- no response is owed for that internal transition, since
  // the triggering request already got a SUCCESS-WAIT answer up front.
  //   Free    -(acquire, other host)-> AcqWait -(drain_done)-> Locked (new owner)
  //   Locked  -(release, owner)     -> RelWait -(drain_done)-> Free   (owner = host 0)
  // Every hit always completes immediately (q_ready is never withheld);
  // the response encodes an outcome (FAIL/SUCCESS/SUCCESS-WAIT) instead of
  // stalling the requester. A hit during AcqWait/RelWait, from either host,
  // always gets FAIL(PENDING) -- only the one already-in-flight transition
  // is ever active at a time.
  //
  // Handshake timing: the q-channel is accepted (q_ready=1) exactly on the
  // deciding cycle; the response (p_valid=1) is then held starting the
  // following cycle until the host takes it via p_ready.
  typedef enum logic [1:0] {
    Free,
    AcqWait,
    RelWait,
    Locked
  } lock_state_e;

  // Response payload bit layout (see note.md): [1:0]=outcome, [4:2]=reason
  // (valid only on FAIL), [5]=owner, [6]=locked -- all post-decision.
  typedef enum logic [1:0] {
    OutcomeFail        = 2'd0,
    OutcomeSuccess     = 2'd1,
    OutcomeSuccessWait = 2'd2
  } lock_outcome_e;

  typedef enum logic [2:0] {
    ReasonNotOwner = 3'd0,
    ReasonBusy     = 3'd1,
    ReasonPending  = 3'd2
  } lock_fail_reason_e;

  lock_state_e lock_d, lock_q;
  logic        owner_d, owner_q;
  logic        active_d, active_q;

  // Outstanding acc handshakes on the owner's path; must reach 0 before a wait can complete.
  logic [7:0] outstanding_d, outstanding_q;
  // Outstanding Spatz vle/vse ops; mirrors snitch.sv's own acc_mem_cnt_q so a
  // switch can't happen while a load/store is still draining through the cache.
  logic [7:0] lsu_outstanding_d, lsu_outstanding_q;
  logic       drain_done;

  assign owner_id_o      = owner_q;
  assign locked_o        = (lock_q == Locked);
  assign waiting_o       = (lock_q == AcqWait) || (lock_q == RelWait);
  assign owner_active_o  = (lock_q == Locked) || (lock_q == RelWait);

  assign drain_done = (outstanding_q == '0) && (lsu_outstanding_q == '0) && spatz_st_rsp_done_i;

  `ASSERT(NoOutstandingUnderflow, rsp_fire_i |-> (outstanding_q != '0))
  `ASSERT(NoLsuOutstandingUnderflow,
      (spatz_mem_finished_i[0] || spatz_mem_finished_i[1]) |-> (lsu_outstanding_q != '0))

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

  always_comb begin
    lsu_outstanding_d = lsu_outstanding_q;
    if (spatz_lsu_issue_fire_i) begin
      lsu_outstanding_d = lsu_outstanding_d + 8'd1;
    end
    if (spatz_mem_finished_i[0]) begin
      lsu_outstanding_d = lsu_outstanding_d - 8'd1;
    end
    if (spatz_mem_finished_i[1]) begin
      lsu_outstanding_d = lsu_outstanding_d - 8'd1;
    end
  end

  // Address-based op decode: a hit on either address is serviced regardless
  // of q.write, since only loads carry a usable result back to software.
  logic [1:0] acquire_hit, release_hit, lock_hit;

  for (genvar i = 0; i < 2; i++) begin
    assign acquire_hit[i] = in_req_i[i].q_valid && (in_req_i[i].q.addr == acquire_addr);
    assign release_hit[i] = in_req_i[i].q_valid && (in_req_i[i].q.addr == release_addr);
    assign lock_hit[i]    = acquire_hit[i] || release_hit[i];
  end

  // The owner's hit always wins arbitration when both hosts hit the same
  // cycle; the loser simply waits one extra cycle for resp_pending_q to
  // clear (both eventually get answered, this is only a tie-break).
  logic hit_any, winner;
  assign hit_any = lock_hit[0] || lock_hit[1];
  assign winner  = lock_hit[owner_q] ? owner_q : ~owner_q;

  // Pending, not-yet-delivered completion response (one at a time; a new lock op is
  // only arbitrated once the previous one's response has been taken).
  logic              resp_pending_d, resp_pending_q;
  logic              resp_host_d,    resp_host_q;
  user_t             resp_user_d,    resp_user_q;
  lock_outcome_e     resp_outcome_d, resp_outcome_q;
  lock_fail_reason_e resp_reason_d,  resp_reason_q;
  logic              resp_owner_d,   resp_owner_q;
  logic              resp_locked_d,  resp_locked_q;

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
    active_d       = active_q;
    resp_pending_d = resp_pending_q;
    resp_host_d    = resp_host_q;
    resp_user_d    = resp_user_q;
    resp_outcome_d = resp_outcome_q;
    resp_reason_d  = resp_reason_q;
    resp_owner_d   = resp_owner_q;
    resp_locked_d  = resp_locked_q;

    // Default: pass through the (registered) memory path; blocked on a lock-address hit.
    for (int i = 0; i < 2; i++) begin
      in_rsp_o[i]         = '0;
      in_rsp_o[i].q_ready = lock_hit[i] ? 1'b0 : mem_req_ready[i];
      in_rsp_o[i].p_valid = mem_rsp_valid[i];
      in_rsp_o[i].p       = mem_rsp_chan[i];
    end

    // Deliver a pending completion response, starting the cycle after it was accepted.
    if (resp_pending_q) begin
      in_rsp_o[resp_host_q]             = '0;
      in_rsp_o[resp_host_q].p_valid     = 1'b1;
      in_rsp_o[resp_host_q].p.user      = resp_user_q;
      in_rsp_o[resp_host_q].p.data[1:0] = resp_outcome_q;
      in_rsp_o[resp_host_q].p.data[4:2] = resp_reason_q;
      in_rsp_o[resp_host_q].p.data[5]   = resp_owner_q;
      in_rsp_o[resp_host_q].p.data[6]   = resp_locked_q;
      if (in_req_i[resp_host_q].p_ready) resp_pending_d = 1'b0;
    end

    case (lock_q)
      // Host 0 is the implicit owner. Its own release is a no-op (immediate grant);
      // an acquire from either host grants immediately once drained, else waits.
      Free: begin
        if (hit_any && !resp_pending_q) begin
          in_rsp_o[winner].q_ready = 1'b1;
          resp_pending_d           = 1'b1;
          resp_host_d              = winner;
          resp_user_d              = in_req_i[winner].q.user;

          if (acquire_hit[winner]) begin
            if (drain_done) begin
              lock_d         = Locked;
              owner_d        = winner;
              resp_outcome_d = OutcomeSuccess;
              resp_owner_d   = winner;
              resp_locked_d  = 1'b1;
            end else begin
              active_d       = winner;
              lock_d         = AcqWait;
              resp_outcome_d = OutcomeSuccessWait;
              resp_owner_d   = owner_q;
              resp_locked_d  = 1'b0;
            end
          end else begin // release_hit[winner]
            if (winner == owner_q) begin
              // host 0 "self release": nothing to release, immediate no-op grant
              resp_outcome_d = OutcomeSuccess;
              resp_owner_d   = owner_q;
              resp_locked_d  = 1'b0;
            end else begin
              // host 1 release: never held it
              resp_outcome_d = OutcomeFail;
              resp_reason_d  = ReasonNotOwner;
              resp_owner_d   = owner_q;
              resp_locked_d  = 1'b0;
            end
          end
        end
      end

      // Only the owner's acquire (no-op) or release is meaningful; a non-owner's
      // acquire/release always fails outright (no queueing for a future handoff).
      Locked: begin
        if (hit_any && !resp_pending_q) begin
          in_rsp_o[winner].q_ready = 1'b1;
          resp_pending_d           = 1'b1;
          resp_host_d              = winner;
          resp_user_d              = in_req_i[winner].q.user;

          if (acquire_hit[winner]) begin
            resp_outcome_d = (winner == owner_q) ? OutcomeSuccess : OutcomeFail;
            resp_reason_d  = ReasonBusy;
            resp_owner_d   = owner_q;
            resp_locked_d  = 1'b1;
          end else begin // release_hit[winner]
            if (winner == owner_q) begin
              if (drain_done) begin
                lock_d         = Free;
                owner_d        = 1'b0;
                resp_outcome_d = OutcomeSuccess;
                resp_owner_d   = 1'b0;
                resp_locked_d  = 1'b0;
              end else begin
                active_d       = winner;
                lock_d         = RelWait;
                resp_outcome_d = OutcomeSuccessWait;
                resp_owner_d   = owner_q;
                resp_locked_d  = 1'b1;
              end
            end else begin
              resp_outcome_d = OutcomeFail;
              resp_reason_d  = ReasonNotOwner;
              resp_owner_d   = owner_q;
              resp_locked_d  = 1'b1;
            end
          end
        end
      end

      // Drain-wait sub-states: any hit (either host, either op) always fails with
      // PENDING -- the one already-registered transition (active_q) resolves on
      // its own once drain_done, with no response owed for that completion.
      AcqWait: begin
        if (hit_any && !resp_pending_q) begin
          in_rsp_o[winner].q_ready = 1'b1;
          resp_pending_d           = 1'b1;
          resp_host_d              = winner;
          resp_user_d              = in_req_i[winner].q.user;
          resp_outcome_d           = OutcomeFail;
          resp_reason_d            = ReasonPending;
          resp_owner_d             = owner_q;
          resp_locked_d            = 1'b0;
        end
        if (drain_done) begin
          owner_d = active_q;
          lock_d  = Locked;
        end
      end

      RelWait: begin
        if (hit_any && !resp_pending_q) begin
          in_rsp_o[winner].q_ready = 1'b1;
          resp_pending_d           = 1'b1;
          resp_host_d              = winner;
          resp_user_d              = in_req_i[winner].q.user;
          resp_outcome_d           = OutcomeFail;
          resp_reason_d            = ReasonPending;
          resp_owner_d             = owner_q;
          resp_locked_d            = 1'b1;
        end
        if (drain_done) begin
          owner_d = 1'b0;
          lock_d  = Free;
        end
      end

      default: lock_d = Free;
    endcase
  end

  `FF(lock_q,         lock_d,         Free,          clk_i, rst_ni)
  `FF(owner_q,        owner_d,        1'b0,          clk_i, rst_ni)
  `FF(active_q,       active_d,       1'b0,          clk_i, rst_ni)
  `FF(outstanding_q,     outstanding_d,     '0,      clk_i, rst_ni)
  `FF(lsu_outstanding_q, lsu_outstanding_d, '0,       clk_i, rst_ni)
  `FF(resp_pending_q, resp_pending_d, 1'b0,          clk_i, rst_ni)
  `FF(resp_host_q,    resp_host_d,    1'b0,          clk_i, rst_ni)
  `FF(resp_user_q,    resp_user_d,    '0,            clk_i, rst_ni)
  `FF(resp_outcome_q, resp_outcome_d, OutcomeFail,   clk_i, rst_ni)
  `FF(resp_reason_q,  resp_reason_d,  ReasonNotOwner,clk_i, rst_ni)
  `FF(resp_owner_q,   resp_owner_d,   1'b0,          clk_i, rst_ni)
  `FF(resp_locked_q,  resp_locked_d,  1'b0,          clk_i, rst_ni)

endmodule
