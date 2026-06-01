// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Zexin Fu, ETH Zurich
//
// =============================================================================
// cachepool_tile_tcdm_checker
// =============================================================================
// Sim-only verification IP for the per-tile core-side TCDM bus, factored out of
// cachepool_tile.sv (PR review: keep verification code in its own file) and
// `bind`-attached to every cachepool_tile instance.  Two passive monitors, both
// drive nothing:
//
//   1. Pre-strip request TRACER -- logs every accepted tcdm_req in an address
//      window [+sb_pretrace_addr_lo, +sb_pretrace_addr_hi] so the originating
//      (core, port) of a request the L1 scoreboard later sees post-strip can be
//      identified.
//
//   2. Per-port TCDM Memory-Model VIP -- a byte-granular shadow of TCDM-visible
//      memory built from every accepted write, checked against every read
//      response.  Enabled with +mm_enable=1.
//
// The whole file is guarded by `ifndef TARGET_SYNTHESIS so synthesis/lint never
// see it.  The trailing `bind` wires the monitor to the tile's internal
// tcdm_req / tcdm_rsp arrays.
// =============================================================================

`ifndef TARGET_SYNTHESIS
module cachepool_tile_tcdm_checker
  import cachepool_pkg::*;
#(
  parameter int unsigned NrTCDMPortsCores   = 0,
  parameter int unsigned NrTCDMPortsPerCore = 0
) (
  input  logic                              clk_i,
  input  logic                              rst_ni,
  input  tcdm_req_t [NrTCDMPortsCores-1:0]  tcdm_req,
  input  tcdm_rsp_t [NrTCDMPortsCores-1:0]  tcdm_rsp
);

  // ---------------------------------------------------------------------
  // Verification: per-port pre-strip request tracer.
  // Logs every accepted tcdm_req[k] whose addr lies in
  // [+sb_pretrace_addr_lo, +sb_pretrace_addr_hi] (inclusive).
  // Identifies the originating (core, port) for the request that the
  // L1 cache scoreboard will later see post-strip.  All output is via
  // `$display`; no signal is driven.
  // ---------------------------------------------------------------------
  longint unsigned tracer_addr_lo = '1;
  longint unsigned tracer_addr_hi = '0;
  initial begin
    void'($value$plusargs("sb_pretrace_addr_lo=%h", tracer_addr_lo));
    void'($value$plusargs("sb_pretrace_addr_hi=%h", tracer_addr_hi));
    if (tracer_addr_lo != '1 || tracer_addr_hi != '0) begin
      $display("[TRACER %m] tracing pre-strip TCDM reqs in 0x%0h..0x%0h",
               tracer_addr_lo, tracer_addr_hi);
    end
  end

  // Stateless monitor (drives nothing); rst_ni is in the sensitivity list per
  // house style, used only to suppress tracing during reset.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni && (tracer_addr_lo != '1 || tracer_addr_hi != '0)) begin
      for (int k = 0; k < NrTCDMPortsCores; k++) begin
        if (tcdm_req[k].q_valid && tcdm_rsp[k].q_ready) begin
          automatic logic [31:0] a = tcdm_req[k].q.addr;
          if (a >= tracer_addr_lo[31:0] && a <= tracer_addr_hi[31:0]) begin
            $display({"[TRACER %m] t=%0t  core=%0d port=%0d  addr=0x%0h  %s  ",
                      "data=0x%0h  strb=0x%0h  user=0x%0h"},
                     $time, k / NrTCDMPortsPerCore, k % NrTCDMPortsPerCore,
                     a,
                     tcdm_req[k].q.write ? "WRITE" : "READ ",
                     tcdm_req[k].q.data, tcdm_req[k].q.strb, tcdm_req[k].q.user);
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------
  // Verification: per-port TCDM Memory Model (VIP C1).
  //
  // Maintains a byte-granular shadow of TCDM-visible memory built from
  // EVERY accepted write request, then verifies EVERY read response
  // matches.  Catches any class of bug where:
  //   - a store doesn't update the cache (data lost),
  //   - a load returns stale data inconsistent with prior writes,
  //   - a store update gets clobbered by an unrelated refill / aliasing,
  // ... independent of where the cache is internally hit/missing/evicting.
  //
  // Per-port outstanding-request FIFOs maintain rsp ordering: every
  // accepted upstream req pushes an entry; every rsp pops one and
  // compares (for reads) or skips (for writes).
  //
  // LIMITATION: bytes NEVER written via TCDM are skipped (we don't know
  // their DRAM-initialised value).  Use combined with the wrapper-level
  // SB (which checks against cache's stored data) for full coverage.
  // ---------------------------------------------------------------------
  typedef struct {
    logic                 is_write;
    logic [31:0]          addr;
    logic [31:0]          expected_data;
    logic [3:0]           expected_mask;   // 1 = byte was tracked (and must match)
  } mm_outstanding_t;

  mm_outstanding_t mm_q [NrTCDMPortsCores][$];
  byte unsigned    mm_mem [longint unsigned];

  longint unsigned mm_writes_seen    = 0;
  longint unsigned mm_reads_seen     = 0;
  longint unsigned mm_rsps_seen      = 0;
  longint unsigned mm_data_mismatch  = 0;
  longint unsigned mm_orphan_rsp     = 0;  // rsp w/o matching req
  longint unsigned mm_type_mismatch  = 0;  // rsp.write != req.write
  longint unsigned mm_bytes_checked  = 0;
  longint unsigned mm_bytes_unknown  = 0;

  // Enable/disable via plusarg; off by default to keep the rest of the
  // checks fast for kernels that haven't been characterised yet.
  bit mm_enable = 1'b0;

  initial begin
    void'($value$plusargs("mm_enable=%d", mm_enable));
    if (mm_enable)
      $display("[MM %m] Memory Model enabled.");
  end

  // Shadow-memory checker.
  //
  // This is a passive verification scoreboard, NOT synthesizable sequential
  // logic, so it uses a plain clocked `always` (not `always_ff`) with BLOCKING
  // assignments -- the standard idiom for SV scoreboards (cf. UVM).  Both are
  // required here, not stylistic:
  //   * No flip-flop is modelled.  There is no `q <= d` next-state register;
  //     every target is either a SystemVerilog queue / associative array or a
  //     plain counter.  `always_ff` advertises "I am a flop" to lint/synthesis,
  //     which is false for this block -- so `always @(posedge clk_i)` is the
  //     honest, waiver-free keyword.
  //   * Queue / assoc-array updates have no non-blocking form: `mm_q[k]
  //     .push_back()/.pop_front()/.delete()` and `mm_mem[a]=d` are procedural
  //     method calls / element writes, evaluated in order within the edge.
  //   * Counters are read-modify-written MULTIPLE times per edge: e.g. the
  //     byte loop can hit `mm_bytes_checked++`/`mm_data_mismatch++` up to 4x
  //     per response, across all ports.  With non-blocking `<=`, every `++` in
  //     the same time step reads the SAME pre-edge value and resolves to
  //     old+1, so all but one increment is lost.  Blocking `=` accumulates
  //     correctly (old -> old+1 -> old+2 ...).
  //   * The per-iteration scratch `e` is filled and consumed (`push_back(e)`)
  //     in the same iteration; NBA would queue a stale `e`.
  // Reset just clears the shadow state; no registered output is driven.
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Clear shadow state on reset (counters re-zero; pending FIFOs flushed).
      mm_writes_seen   = 0;
      mm_reads_seen    = 0;
      mm_rsps_seen     = 0;
      mm_data_mismatch = 0;
      mm_orphan_rsp    = 0;
      mm_type_mismatch = 0;
      mm_bytes_checked = 0;
      mm_bytes_unknown = 0;
      for (int k = 0; k < NrTCDMPortsCores; k++) mm_q[k].delete();
    end else if (mm_enable) begin
      // -- Req side: update mem_model on writes, snapshot expected on reads --
      // The TCDM bus carries a 32-bit data word; req.addr may be byte-
      // unaligned but strb[i] / data[i*8+:8] always refers to byte i of
      // the WORD at (addr & ~3).  Word-align before indexing.
      for (int k = 0; k < NrTCDMPortsCores; k++) begin
        if (tcdm_req[k].q_valid && tcdm_rsp[k].q_ready) begin
          automatic logic [31:0]   a_word = tcdm_req[k].q.addr & 32'hFFFFFFFC;
          automatic mm_outstanding_t e;
          e.is_write      = tcdm_req[k].q.write;
          e.addr          = a_word;
          e.expected_data = '0;
          e.expected_mask = '0;
          if (tcdm_req[k].q.write) begin
            for (int b = 0; b < 4; b++) begin
              if (tcdm_req[k].q.strb[b]) begin
                mm_mem[a_word + b] = tcdm_req[k].q.data[b*8 +: 8];
              end
            end
            mm_writes_seen++;
          end else begin
            // Snapshot bytes the model has tracked.  Reads ignore strb on
            // most TCDM masters -- the full word is returned and the core
            // extracts the requested byte.
            for (int b = 0; b < 4; b++) begin
              if (mm_mem.exists(a_word + b)) begin
                e.expected_data[b*8 +: 8] = mm_mem[a_word + b];
                e.expected_mask[b]        = 1'b1;
              end
            end
            mm_reads_seen++;
          end
          mm_q[k].push_back(e);
        end
      end
      // -- Rsp side: pop & compare --
      for (int k = 0; k < NrTCDMPortsCores; k++) begin
        if (tcdm_rsp[k].p_valid) begin
          mm_rsps_seen++;
          if (mm_q[k].size() == 0) begin
            mm_orphan_rsp++;
            $error({"[MM %m port=%0d] ORPHAN_RSP  t=%0t  rsp_data=0x%0h  ",
                    "write=%0b  (no outstanding req in FIFO)"},
                   k, $time, tcdm_rsp[k].p.data, tcdm_rsp[k].p.write);
          end else begin
            automatic mm_outstanding_t e = mm_q[k].pop_front();
            if (e.is_write != tcdm_rsp[k].p.write) begin
              mm_type_mismatch++;
              $error({"[MM %m port=%0d] TYPE_MISMATCH  t=%0t  addr=0x%0h  ",
                      "req_was_write=%0b rsp.write=%0b"},
                     k, $time, e.addr, e.is_write, tcdm_rsp[k].p.write);
            end else if (!e.is_write) begin
              // Read response: compare per byte
              for (int b = 0; b < 4; b++) begin
                if (e.expected_mask[b]) begin
                  mm_bytes_checked++;
                  if (tcdm_rsp[k].p.data[b*8 +: 8] !== e.expected_data[b*8 +: 8]) begin
                    mm_data_mismatch++;
                    $error({"[MM %m port=%0d] DATA_MISMATCH  t=%0t  addr=0x%0h  ",
                            "byte=%0d  expected=0x%02h  got=0x%02h"},
                           k, $time, e.addr, b,
                           e.expected_data[b*8 +: 8],
                           tcdm_rsp[k].p.data[b*8 +: 8]);
                  end
                end else begin
                  mm_bytes_unknown++;
                end
              end
            end
          end
        end
      end
    end
  end

  final begin
    if (mm_enable) begin
      $display({"[MM %m] ============================ Memory-Model Summary ",
                "============================"});
      $display("[MM %m]   Writes seen     : %0d", mm_writes_seen);
      $display("[MM %m]   Reads  seen     : %0d", mm_reads_seen);
      $display("[MM %m]   Rsps   seen     : %0d", mm_rsps_seen);
      $display("[MM %m]   Bytes checked   : %0d", mm_bytes_checked);
      $display({"[MM %m]   Bytes unknown   : %0d ",
                "(read addrs never previously written via TCDM)"}, mm_bytes_unknown);
      $display("[MM %m]   Data mismatches : %0d", mm_data_mismatch);
      $display("[MM %m]   Type mismatches : %0d", mm_type_mismatch);
      $display("[MM %m]   Orphan rsps     : %0d", mm_orphan_rsp);
      if (mm_data_mismatch == 0 && mm_type_mismatch == 0 && mm_orphan_rsp == 0)
        $display("[MM %m]   STATUS: PASS");
      else
        $display("[MM %m]   STATUS: FAIL (%0d violations)",
                 mm_data_mismatch + mm_type_mismatch + mm_orphan_rsp);
      $display({"[MM %m] ========================================",
                "======================================="});
    end
  end

endmodule

// Attach the checker to every cachepool_tile instance.  The bound instance
// lives in the tile's scope, so its ports bind directly to the tile's internal
// tcdm_req / tcdm_rsp arrays and the NrTCDMPorts* localparams.
bind cachepool_tile cachepool_tile_tcdm_checker #(
  .NrTCDMPortsCores  (NrTCDMPortsCores  ),
  .NrTCDMPortsPerCore(NrTCDMPortsPerCore)
) i_tcdm_checker (
  .clk_i   (clk_i   ),
  .rst_ni  (rst_ni  ),
  .tcdm_req(tcdm_req),
  .tcdm_rsp(tcdm_rsp)
);
`endif
