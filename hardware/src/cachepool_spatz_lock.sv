// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

/// Spatz ownership lock/switch for a dual-Snitch cachepool_cc_dual. Two
/// dedicated addresses (ACQUIRE/RELEASE) are intercepted as loads that
/// always complete immediately, encoding the outcome and current
/// owner/locked status in the returned word (see note.md). Pure arbiter:
/// does not route acc/data traffic itself (see acc_mux.sv); only decides
/// ownership and counts real Spatz acc handshakes to gate a switch until
/// fully drained. Also hosts the pass-through memory-path register cuts
/// (moved here from the per-core spill registers in cachepool_cc.sv).
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

  // Spatz LSU drain tracking: vle/vse have no acc_rsp_t completion, so they need their own count.
  input  logic                           spatz_lsu_issue_fire_i,
  input  logic                    [1:0]  spatz_mem_finished_i,
  input  logic                           spatz_st_rsp_done_i,

  // owner/lock status
  output logic                           owner_id_o,
  output logic                           locked_o,
  output logic                           waiting_o,
  // True during Locked/RelWait; lets acc_mux keep draining through RelWait after new issues stop.
  output logic                           owner_active_o,

  // peripheral base address
  input  addr_t                          cluster_periph_start_address_i
);

  addr_t acquire_addr, release_addr;
  assign acquire_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_SPATZ_LOCK_ACQUIRE_OFFSET;
  assign release_addr = cluster_periph_start_address_i + CACHEPOOL_PERIPHERAL_SPATZ_LOCK_RELEASE_OFFSET;

  // Single lock FSM (host 0 is the implicit owner while Free). AcqWait/RelWait
  // are drain-wait sub-states, resolved autonomously once drain_done -- no
  // response is owed then, since the triggering request already got SUCCESS-WAIT.
  //   Free   -(acquire, other host)-> AcqWait -(drain_done)-> Locked (new owner)
  //   Locked -(release, owner)     -> RelWait -(drain_done)-> Free   (owner = host 0)
  // Every hit completes immediately with an outcome (FAIL/SUCCESS/SUCCESS-WAIT)
  // instead of stalling; a hit during AcqWait/RelWait always gets FAIL(PENDING).
  // Handshake timing: q_ready fires on the deciding cycle; p_valid is held
  // starting the next cycle until the host takes it via p_ready.
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
  // Outstanding Spatz vle/vse ops; mirrors snitch.sv's own acc_mem_cnt_q.
  logic [7:0] lsu_outstanding_d, lsu_outstanding_q;
  logic       drain_done;

  assign owner_id_o      = owner_q;
  assign locked_o        = (lock_q == Locked);
  assign waiting_o       = (lock_q == AcqWait) || (lock_q == RelWait);
  assign owner_active_o  = (lock_q == Locked) || (lock_q == RelWait);

  assign drain_done = (outstanding_q == '0) && (lsu_outstanding_q == '0) && spatz_st_rsp_done_i;

  `ASSERT(NoOutstandingUnderflow, rsp_fire_i |-> (outstanding_q != '0))
  // Checked against the net balance for this cycle, not the pre-update register alone:
  // a scalar FP store's finish can land in the same cycle as its own issue.
  `ASSERT(NoLsuOutstandingUnderflow,
      (spatz_mem_finished_i[0] || spatz_mem_finished_i[1]) |->
      (lsu_outstanding_q + spatz_lsu_issue_fire_i >= (spatz_mem_finished_i[0] + spatz_mem_finished_i[1])))

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

  // Owner's hit wins on a same-cycle tie; the loser just waits one cycle for resp_pending_q to clear.
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
          end else begin
            // release_hit[winner]
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

      // Non-owner acquire/release always fails outright, no queueing for a future handoff.
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
          end else begin
            // release_hit[winner]
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

      // Any hit here fails with PENDING; active_q's transition resolves on its own, no response owed.
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

`ifndef TARGET_SYNTHESIS
  // Debug-only: verbose state-transition/response log (+spatz_lock_verbose
  // plusarg) and a stuck-in-wait watchdog. Added to debug the FPU-enabled
  // dual-CC boot hang; temporary instrumentation, safe to strip once resolved.
  bit spatz_lock_verbose = 1'b0;
  initial begin
    // verilog_lint: waive plusarg-assignment
    spatz_lock_verbose = $test$plusargs("spatz_lock_verbose");
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni && spatz_lock_verbose) begin
      if (lock_d != lock_q) begin
        $display({"[SPATZ-LOCK %0t %m] STATE %s -> %s owner_d=%0d active_d=%0d ",
                  "outstanding_q=%0d lsu_outstanding_q=%0d"},
                 $time, lock_q.name(), lock_d.name(), owner_d, active_d,
                 outstanding_q, lsu_outstanding_q);
      end
      if (hit_any && !resp_pending_q) begin
        $display({"[SPATZ-LOCK %0t %m] HIT host=%0d acquire=%0b release=%0b ",
                  "state=%s outstanding_q=%0d lsu_outstanding_q=%0d ",
                  "spatz_st_rsp_done=%0b"},
                 $time, winner, acquire_hit[winner], release_hit[winner],
                 lock_q.name(), outstanding_q, lsu_outstanding_q, spatz_st_rsp_done_i);
      end
      if (resp_pending_d && !resp_pending_q) begin
        $display({"[SPATZ-LOCK %0t %m] RESP host=%0d outcome=%s reason=%s owner=%0d ",
                  "locked=%0b"},
                 $time, resp_host_d, resp_outcome_d.name(), resp_reason_d.name(),
                 resp_owner_d, resp_locked_d);
      end
    end
  end

  // Watchdog: warn if the FSM has been stuck in AcqWait/RelWait (waiting on
  // drain_done) for more than SpatzLockWdogPs, re-warning every
  // SpatzLockWdogPs while still stuck.
  localparam longint unsigned SpatzLockWdogPs = 5_000_000;
  logic [63:0] spatz_lock_last_progress_q, spatz_lock_last_warn_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      spatz_lock_last_progress_q <= '0;
      spatz_lock_last_warn_q     <= '0;
    end else begin
      if (lock_q != AcqWait && lock_q != RelWait) begin
        spatz_lock_last_progress_q <= 64'($time);
        spatz_lock_last_warn_q     <= 64'($time);
      end
      if ((lock_q == AcqWait || lock_q == RelWait) &&
          (64'($time) - spatz_lock_last_progress_q) > SpatzLockWdogPs &&
          (64'($time) - spatz_lock_last_warn_q)     > SpatzLockWdogPs) begin
        spatz_lock_last_warn_q <= 64'($time);
        $display({"[%0t] [SPATZ-LOCK %m] STUCK: state=%s active_q=%0d owner_q=%0d ",
                  "outstanding_q=%0d lsu_outstanding_q=%0d spatz_st_rsp_done=%0b ",
                  "drain_done=%0b"},
                 $time, lock_q.name(), active_q, owner_q, outstanding_q,
                 lsu_outstanding_q, spatz_st_rsp_done_i, drain_done);
      end
    end
  end
`endif // TARGET_SYNTHESIS

endmodule
