// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

/// Arbitrates 2 Snitch acc interfaces onto 1 shared Spatz acc interface for
/// cachepool_cc_dual, gated by cachepool_spatz_lock's owner/locked/waiting
/// state. Locked: only the owner passes through, real access, no
/// arbitration. Idle: both hosts get real round-robin access, one request
/// outstanding at a time -- a FIFO tracks which host is owed the in-flight
/// response (pushed on grant, popped on response), so a new request is only
/// arbitrated once the FIFO is empty.
/// Exclusive-owner-path response draining stays active through owner_active_i
/// (Locked and RelWait, since owner_id_i is valid through both), decoupled
/// from new-issue forwarding (locked_i only, steady-state Locked) -- a
/// response already in flight when release is requested would otherwise
/// have no drain path once locked_i drops for RelWait.
module acc_mux #(
  parameter type acc_issue_req_t = logic,
  parameter type acc_issue_rsp_t = logic,
  parameter type acc_rsp_t       = logic
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  input  logic            owner_id_i,
  input  logic            locked_i,
  input  logic            waiting_i,
  input  logic            owner_active_i,

  // Per-host Snitch acc interfaces
  input  acc_issue_req_t [1:0] acc_snitch_req_i,
  output acc_issue_rsp_t [1:0] acc_snitch_rsp_o,
  input  logic            [1:0] acc_snitch_qvalid_i,
  output logic            [1:0] acc_snitch_qready_o,
  output acc_rsp_t        [1:0] acc_snitch_prsp_o,
  output logic            [1:0] acc_snitch_pvalid_o,
  input  logic            [1:0] acc_snitch_pready_i,

  // Shared Spatz acc interface
  output acc_issue_req_t  spatz_issue_req_o,
  input  acc_issue_rsp_t  spatz_issue_rsp_i,
  output logic            spatz_issue_valid_o,
  input  logic            spatz_issue_ready_i,
  input  acc_rsp_t        spatz_rsp_i,
  input  logic            spatz_rsp_valid_i,
  output logic            spatz_rsp_ready_o,

  // Drain feed for the lock's outstanding counter (owner path and Idle-mode
  // arbitrated path both count, since both represent real Spatz traffic).
  output logic            req_fire_o,
  output logic            rsp_fire_o,

  // Host most recently issued to Spatz; gates spatz_mem_finished etc. in cachepool_cc_dual.sv.
  output logic            last_req_host_o
);

  logic req_fire_any;
  assign req_fire_any = spatz_issue_valid_o & spatz_issue_ready_i;

  // Only a writeback-producing issue leaves something for the lock to drain
  // before a switch; a non-writeback op completes at the same-cycle accept.
  assign req_fire_o = req_fire_any & spatz_issue_rsp_i.writeback;
  assign rsp_fire_o = spatz_rsp_valid_i & spatz_rsp_ready_o;

  // Idle-mode round-robin arbitration, offered only while nothing is already outstanding.
  logic            idle_gnt_i, idle_req_o;
  logic            idle_winner;
  logic      [1:0] idle_req_i;
  acc_issue_req_t  idle_data_o;
  logic      [1:0] idle_gnt_o;

  logic route_fifo_empty, route_fifo_push, route_fifo_pop, route_fifo_route_q;
  logic route_fifo_full;

  assign idle_req_i = (!locked_i && !waiting_i && route_fifo_empty) ? acc_snitch_qvalid_i : 2'b00;
  assign idle_gnt_i = spatz_issue_ready_i;

  rr_arb_tree #(
    .NumIn     (2              ),
    .DataType  (acc_issue_req_t),
    .AxiVldRdy (1'b1           ),
    .LockIn    (1'b1           )
  ) i_idle_arb (
    .clk_i,
    .rst_ni,
    .flush_i (1'b0            ),
    .rr_i    ('0              ),
    .req_i   (idle_req_i      ),
    .gnt_o   (idle_gnt_o      ),
    .data_i  (acc_snitch_req_i),
    .req_o   (idle_req_o      ),
    .gnt_i   (idle_gnt_i      ),
    .data_o  (idle_data_o     ),
    .idx_o   (idle_winner     )
  );

  // Only track requests with a real completion coming: non-writeback ops never produce a later acc_rsp_t.
  assign route_fifo_push = idle_req_o && idle_gnt_i && spatz_issue_rsp_i.writeback;
  assign route_fifo_pop  = rsp_fire_o && !owner_active_i;

  // Depth 2 for safety margin; only 1 entry is ever pushed at a time.
  fifo_v3 #(
    .DEPTH (2    ),
    .dtype (logic)
  ) i_route_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0              ),
    .testmode_i (1'b0              ),
    .full_o     (route_fifo_full   ),
    .empty_o    (route_fifo_empty  ),
    .usage_o    (                  ),
    .data_i     (idle_winner       ),
    .push_i     (route_fifo_push   ),
    .data_o     (route_fifo_route_q),
    .pop_i      (route_fifo_pop    )
  );

  logic last_req_host_d, last_req_host_q;

  always_comb begin
    last_req_host_d = last_req_host_q;
    if (req_fire_any) last_req_host_d = locked_i ? owner_id_i : idle_winner;
  end

  `FF(last_req_host_q, last_req_host_d, 1'b0, clk_i, rst_ni)
  assign last_req_host_o = last_req_host_q;

  always_comb begin
    spatz_issue_req_o   = acc_issue_req_t'('0);
    spatz_issue_valid_o = 1'b0;
    spatz_rsp_ready_o    = 1'b0;

    acc_snitch_qready_o = '0;
    acc_snitch_rsp_o    = '0;
    acc_snitch_prsp_o   = '0;
    acc_snitch_pvalid_o = '0;

    if (owner_active_i) begin
      // Exclusive owner path: response draining stays active through Locked
      // and RelWait; new-issue forwarding only happens in steady-state
      // Locked, never while a switch is pending.
      spatz_rsp_ready_o               = acc_snitch_pready_i[owner_id_i];
      acc_snitch_prsp_o[owner_id_i]   = spatz_rsp_i;
      acc_snitch_pvalid_o[owner_id_i] = spatz_rsp_valid_i;

      if (locked_i) begin
        spatz_issue_req_o   = acc_snitch_req_i[owner_id_i];
        spatz_issue_valid_o = acc_snitch_qvalid_i[owner_id_i];

        acc_snitch_qready_o[owner_id_i] = spatz_issue_ready_i;
        acc_snitch_rsp_o[owner_id_i]    = spatz_issue_rsp_i;
      end
    end else begin
      // Draining is unconditional on waiting_i; only new-request arbitration is not.
      if (!route_fifo_empty) begin
        spatz_rsp_ready_o                      = acc_snitch_pready_i[route_fifo_route_q];
        acc_snitch_prsp_o[route_fifo_route_q]   = spatz_rsp_i;
        acc_snitch_pvalid_o[route_fifo_route_q] = spatz_rsp_valid_i;
      end else if (!waiting_i) begin
        spatz_issue_req_o                = idle_data_o;
        spatz_issue_valid_o              = idle_req_o;
        acc_snitch_qready_o[idle_winner] = idle_req_o && spatz_issue_ready_i;
        acc_snitch_rsp_o[idle_winner]    = spatz_issue_rsp_i;
      end
    end
  end

endmodule
