// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

/// Arbitrates 2 Snitch acc interfaces onto 1 shared Spatz acc interface for
/// cachepool_cc_dual, gated by cachepool_spatz_lock's owner/locked/waiting
/// state. Locked: only the owner passes through, real access, no arbitration.
/// Free: both hosts get real round-robin access, one request outstanding at
/// a time -- a FIFO tracks which host is owed the in-flight response.
/// Response draining stays active through owner_active_i (Locked and
/// RelWait); new-issue forwarding is gated separately on locked_i alone, so
/// a response already in flight when release is requested still has a drain path.
/// Also demuxes Spatz's LSU-consistency signals (mem_finished/mem_str_finished/
/// st_rsp_done) to the issuing host, attributed by current-cycle owner so a
/// same-cycle issue+finish (e.g. stores) is never misrouted to a stale owner.
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

  // Spatz's raw LSU-consistency signals, demuxed to the per-host outputs below.
  input  logic            [1:0] spatz_mem_finished_i,
  input  logic            [1:0] spatz_mem_str_finished_i,
  input  logic                  spatz_st_rsp_done_i,

  // Drain feed for the lock's outstanding counter (owner and Free-mode paths both count).
  output logic            req_fire_o,
  output logic            rsp_fire_o,

  // Per-host demuxed copies of the signals above, attributed to the actual current-cycle
  // owner (not a registered value that can go stale by one cycle on same-cycle completions).
  output logic       [1:0][1:0] acc_mem_finished_o,
  output logic       [1:0][1:0] acc_mem_str_finished_o,
  output logic            [1:0] acc_st_rsp_done_o
);

  logic req_fire_any;
  assign req_fire_any = spatz_issue_valid_o & spatz_issue_ready_i;

  // Only a writeback-producing issue leaves something for the lock to drain
  // before a switch; a non-writeback op completes at the same-cycle accept.
  assign req_fire_o = req_fire_any & spatz_issue_rsp_i.writeback;
  assign rsp_fire_o = spatz_rsp_valid_i & spatz_rsp_ready_o;

  // Free-mode round-robin arbitration, offered only while nothing is already outstanding.
  logic            free_gnt_i, free_req_o;
  logic            free_winner;
  logic      [1:0] free_req_i;
  acc_issue_req_t  free_data_o;
  logic      [1:0] free_gnt_o;

  logic route_fifo_empty, route_fifo_push, route_fifo_pop, route_fifo_route_q;
  logic route_fifo_full;

  // Holds off the next Free-mode grant until the current LSU op has actually
  // drained (not just accepted), so last_req_host_q can't go stale mid-drain.
  logic lsu_busy_d, lsu_busy_q;

  always_comb begin
    lsu_busy_d = lsu_busy_q;
    if (req_fire_any && spatz_issue_rsp_i.loadstore) lsu_busy_d = 1'b1;
    if (spatz_mem_finished_i[0] || spatz_mem_finished_i[1]) lsu_busy_d = 1'b0;
  end

  `FF(lsu_busy_q, lsu_busy_d, 1'b0, clk_i, rst_ni)

  assign free_req_i = (!locked_i && !waiting_i && route_fifo_empty && !lsu_busy_q) ? acc_snitch_qvalid_i : 2'b00;
  assign free_gnt_i = spatz_issue_ready_i;

  rr_arb_tree #(
    .NumIn     (2              ),
    .DataType  (acc_issue_req_t),
    .AxiVldRdy (1'b1           ),
    .LockIn    (1'b1           )
  ) i_free_arb (
    .clk_i,
    .rst_ni,
    .flush_i (1'b0            ),
    .rr_i    ('0              ),
    .req_i   (free_req_i      ),
    .gnt_o   (free_gnt_o      ),
    .data_i  (acc_snitch_req_i),
    .req_o   (free_req_o      ),
    .gnt_i   (free_gnt_i      ),
    .data_o  (free_data_o     ),
    .idx_o   (free_winner     )
  );

  // Only track requests with a real completion coming: non-writeback ops never produce a later acc_rsp_t.
  assign route_fifo_push = free_req_o && free_gnt_i && spatz_issue_rsp_i.writeback;
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
    .data_i     (free_winner       ),
    .push_i     (route_fifo_push   ),
    .data_o     (route_fifo_route_q),
    .pop_i      (route_fifo_pop    )
  );

  // Current owner for this cycle's LSU-consistency demux: the just-issued host when a
  // grant is firing right now (covers same-cycle issue+finish, e.g. stores), else the
  // latched host from whichever grant is still draining (covers delayed completions).
  logic last_req_host_q;
  logic cur_owner;
  assign cur_owner = req_fire_any ? (locked_i ? owner_id_i : free_winner) : last_req_host_q;

  `FF(last_req_host_q, cur_owner, 1'b0, clk_i, rst_ni)

  for (genvar h = 0; h < 2; h++) begin : gen_lsu_consistency_demux
    assign acc_mem_finished_o[h]     = (cur_owner == h[0]) ? spatz_mem_finished_i     : '0;
    assign acc_mem_str_finished_o[h] = (cur_owner == h[0]) ? spatz_mem_str_finished_i : '0;
    assign acc_st_rsp_done_o[h]      = (cur_owner == h[0]) ? spatz_st_rsp_done_i      : 1'b1;
  end

  always_comb begin
    spatz_issue_req_o   = acc_issue_req_t'('0);
    spatz_issue_valid_o = 1'b0;
    spatz_rsp_ready_o    = 1'b0;

    acc_snitch_qready_o = '0;
    acc_snitch_rsp_o    = '0;
    acc_snitch_prsp_o   = '0;
    acc_snitch_pvalid_o = '0;

    if (owner_active_i) begin
      // Draining runs through Locked/RelWait; new-issue forwarding is steady-state-Locked only.
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
        spatz_issue_req_o                = free_data_o;
        spatz_issue_valid_o              = free_req_o;
        acc_snitch_qready_o[free_winner] = free_req_o && spatz_issue_ready_i;
        acc_snitch_rsp_o[free_winner]    = spatz_issue_rsp_i;
      end
    end
  end

`ifndef TARGET_SYNTHESIS
  // Debug-only: verbose per-event log (+acc_mux_verbose plusarg) and a
  // stuck-transaction watchdog. Added to debug the FPU-enabled dual-CC
  // boot hang; temporary instrumentation, safe to strip once resolved.
  bit acc_mux_verbose = 1'b0;
  initial begin
    // verilog_lint: waive plusarg-assignment
    acc_mux_verbose = $test$plusargs("acc_mux_verbose");
  end

  logic spatz_rsp_valid_q;
  `FF(spatz_rsp_valid_q, spatz_rsp_valid_i, 1'b0, clk_i, rst_ni)

  always_ff @(posedge clk_i) begin
    if (rst_ni && acc_mux_verbose) begin
      if (free_req_o && free_gnt_i) begin
        $display({"[ACC-MUX %0t %m] FREE-GRANT host=%0d accept=%0b writeback=%0b ",
                  "loadstore=%0b isfloat=%0b"},
                 $time, free_winner, spatz_issue_rsp_i.accept, spatz_issue_rsp_i.writeback,
                 spatz_issue_rsp_i.loadstore, spatz_issue_rsp_i.isfloat);
      end
      if (route_fifo_push) begin
        $display("[ACC-MUX %0t %m] ROUTE-FIFO PUSH host=%0d", $time, free_winner);
      end
      if (route_fifo_pop) begin
        $display("[ACC-MUX %0t %m] ROUTE-FIFO POP  host=%0d", $time, route_fifo_route_q);
      end
      if (req_fire_any) begin
        $display({"[ACC-MUX %0t %m] REQ-FIRE  owner_active=%0b locked=%0b owner=%0d ",
                  "writeback=%0b"},
                 $time, owner_active_i, locked_i, owner_id_i, spatz_issue_rsp_i.writeback);
      end
      if (rsp_fire_o) begin
        $display("[ACC-MUX %0t %m] RSP-FIRE  owner_active=%0b route_host=%0d",
                 $time, owner_active_i, route_fifo_route_q);
      end
      if (spatz_mem_finished_i[0] || spatz_mem_finished_i[1]) begin
        $display("[ACC-MUX %0t %m] LSU-FINISH cur_owner=%0d mem_finished=%0b",
                 $time, cur_owner, spatz_mem_finished_i);
      end
      // Edge-triggered: which side of the p-channel handshake (valid vs.
      // ready) is actually stuck once route_fifo has something owed.
      if (spatz_rsp_valid_i != spatz_rsp_valid_q) begin
        $display({"[ACC-MUX %0t %m] SPATZ-RSP-VALID -> %0b route_fifo_empty=%0b ",
                  "route_host=%0d owner_active=%0b spatz_rsp_ready=%0b"},
                 $time, spatz_rsp_valid_i, route_fifo_empty, route_fifo_route_q,
                 owner_active_i, spatz_rsp_ready_o);
      end
    end
  end

  // Watchdog: warn if a round-robin (Free-mode) transaction has been
  // accepted by Spatz but its response hasn't drained (route_fifo stuck
  // non-empty) for more than AccMuxWdogPs, re-warning every AccMuxWdogPs
  // while still stuck.
  localparam longint unsigned AccMuxWdogPs = 5_000_000;
  logic [63:0] acc_mux_last_progress_q, acc_mux_last_warn_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      acc_mux_last_progress_q <= '0;
      acc_mux_last_warn_q     <= '0;
    end else begin
      if (route_fifo_empty || route_fifo_push || route_fifo_pop) begin
        acc_mux_last_progress_q <= 64'($time);
        acc_mux_last_warn_q     <= 64'($time);
      end
      if (!route_fifo_empty &&
          (64'($time) - acc_mux_last_progress_q) > AccMuxWdogPs &&
          (64'($time) - acc_mux_last_warn_q)     > AccMuxWdogPs) begin
        acc_mux_last_warn_q <= 64'($time);
        $display({"[%0t] [ACC-MUX %m] STUCK: route_fifo non-empty, owed host=%0d ",
                  "locked=%0b waiting=%0b owner_active=%0b free_req_i=%0b ",
                  "spatz_rsp_valid=%0b spatz_rsp_ready=%0b"},
                 $time, route_fifo_route_q, locked_i, waiting_i, owner_active_i,
                 free_req_i, spatz_rsp_valid_i, spatz_rsp_ready_o);
      end
    end
  end
`endif // TARGET_SYNTHESIS

endmodule
