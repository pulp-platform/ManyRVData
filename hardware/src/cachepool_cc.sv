// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>
//         Hong Pang  <hopang@iis.ee.ethz.ch>
//         Zexin Fu   <zexifu@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"
`include "snitch_vm/typedef.svh"
`include "reqrsp_interface/typedef.svh"

/// CachePool Core Complex (CC)
/// Contains the Snitch Integer Core + Spatz Vector Unit
module cachepool_cc
  import snitch_pkg::interrupts_t;
  import snitch_pkg::core_events_t;
  import fpnew_pkg::fpu_implementation_t; #(
    /// Address width of the buses
    parameter int                          unsigned        AddrWidth                = 0,
    /// Data width of the buses.
    parameter int                          unsigned        DataWidth                = 0,
    /// User width of the buses.
    parameter int                          unsigned        UserWidth                = 0,
    /// Data width of the AXI DMA buses.
    parameter int                          unsigned        DMADataWidth             = 0,
    /// Id width of the AXI DMA bus.
    parameter int                          unsigned        DMAIdWidth               = 0,
    parameter int                          unsigned        DMAAxiReqFifoDepth       = 0,
    parameter int                          unsigned        DMAReqFifoDepth          = 0,

    parameter int                          unsigned        SpmStackDepth            = 512,
    /// Data port request type.
    parameter type                                         dreq_t                   = logic,
    /// Data port response type.
    parameter type                                         drsp_t                   = logic,
    parameter type                                         dreq_chan_t              = logic,
    parameter type                                         drsp_chan_t              = logic,
    // TCDM port types
    parameter type                                         tcdm_req_t               = logic,
    parameter type                                         tcdm_user_t              = logic,
    parameter type                                         tcdm_req_chan_t          = logic,
    parameter type                                         tcdm_rsp_t               = logic,
    parameter type                                         tcdm_rsp_chan_t          = logic,
    /// TCDM Address Width
    parameter int                          unsigned        TCDMAddrWidth            = 0,
    /// TCDM User Payload
    parameter type                                         axi_req_t                = logic,
    parameter type                                         axi_ar_chan_t            = logic,
    parameter type                                         axi_aw_chan_t            = logic,
    parameter type                                         axi_rsp_t                = logic,
    parameter type                                         hive_req_t               = logic,
    parameter type                                         hive_rsp_t               = logic,
    parameter type                                         acc_issue_req_t          = logic,
    parameter type                                         acc_issue_rsp_t          = logic,
    parameter type                                         acc_rsp_t                = logic,
    // parameter type                                         dma_events_t             = logic,
    // parameter type                                         dma_perf_t               = logic,
    /// FPU configuration.
    parameter fpu_implementation_t                         FPUImplementation        = fpu_implementation_t'(0),
    /// Boot address of core.
    parameter logic                                 [31:0] BootAddr                 = 32'h0000_1000,

    /// Address to indicate start of L2
    parameter logic                        [AddrWidth-1:0] UartAddr                 = 32'h0C00_0000,
    /// Reduced-register extension
    parameter bit                                          RVE                      = 0,
    /// Enable F and D Extension
    parameter bit                                          RVF                      = 1,
    parameter bit                                          RVD                      = 0,
    parameter bit                                          XDivSqrt                 = 0,
    parameter bit                                          XF8                      = 0,
    parameter bit                                          XF16                     = 0,
    parameter bit                                          XF16ALT                  = 0,
    parameter bit                                          XF8ALT                   = 0,
    /// Enable Snitch DMA
    parameter bit                                          Xdma                     = 0,
    parameter int                          unsigned        NumIntOutstandingLoads   = 0,
    parameter int                          unsigned        NumIntOutstandingMem     = 0,
    parameter int                          unsigned        NumSpatzOutstandingLoads = 0,
    // Enable V Extension
    parameter bit                                          RVV                      = 1,
    // Spatz paramaters
    parameter int                          unsigned        NumSpatzFPUs             = 4,
    parameter int                          unsigned        NumSpatzIPUs             = 1,
    /// Add isochronous clock-domain crossings e.g., make it possible to operate
    /// the core in a slower clock domain.
    parameter bit                                          IsoCrossing              = 0,
    /// Timing Parameters
    /// Insert Pipeline registers into off-loading path (response)
    parameter bit                                          RegisterOffloadRsp       = 0,
    /// Insert Pipeline registers into data memory path (request)
    parameter bit                                          RegisterCoreReq          = 0,
    /// Insert Pipeline registers into data memory path (response)
    parameter bit                                          RegisterCoreRsp          = 0,
    parameter snitch_pma_pkg::snitch_pma_t                 SnitchPMACfg             = '{default: 0},
    /// DEBUG: enable Spatz<->TCDM request/response scoreboard.
    /// When 1, per-port counters and a queue of outstanding (id,addr,write)
    /// records are exposed in the waveform under
    ///   gen_spatz_req_scoreboard.gen_port[P]/{req_id_q,rsp_id_q,outstanding_q,sb_q,...}
    /// A watchdog $displays the contents of any port that has been stuck
    /// for >5 us (configurable below).  Defaults off; pass
    ///   +define+ENABLE_SPATZ_REQ_SCOREBOARD
    /// to vlog to enable globally, or override per instance.
`ifdef ENABLE_SPATZ_REQ_SCOREBOARD
    parameter bit                                          EnableSpatzReqScoreboard = 1'b1,
`else
    parameter bit                                          EnableSpatzReqScoreboard = 1'b0,
`endif
    /// DEBUG: scoreboard depth (entries per port).
    parameter int                          unsigned        SpatzReqScoreboardDepth  = 64,
    /// DEBUG: watchdog timeout in ps. 0 disables the watchdog.
    parameter longint                      unsigned        SpatzReqScoreboardWdogPs = 5_000_000,
    /// Derived parameter *Do not override*
    parameter int                          unsigned        NumSpatzFUs              = (NumSpatzFPUs > NumSpatzIPUs) ? NumSpatzFPUs : NumSpatzIPUs,
    parameter int                          unsigned        NumMemPortsPerSpatz      = NumSpatzFUs,
    parameter int                          unsigned        TCDMPorts                = RVV ? NumMemPortsPerSpatz + 1 : 1,
    parameter type                                         addr_t                   = logic [AddrWidth-1:0],
    parameter type                                         req_id_t                 = logic [$clog2(NumSpatzOutstandingLoads)-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         testmode_i,
    input  logic         [31:0]          hart_id_i,
    input  interrupts_t                  irq_i,
    output hive_req_t                    hive_req_o,
    input  hive_rsp_t                    hive_rsp_i,
    // Core data ports
    output dreq_t                        data_req_o,
    input  drsp_t                        data_rsp_i,
    // TCDM Streamer Ports
    output tcdm_req_t    [TCDMPorts-1:0] tcdm_req_o,
    input  tcdm_rsp_t    [TCDMPorts-1:0] tcdm_rsp_i,
    // Core event strobes
    output core_events_t                 core_events_o,
    input  addr_t                        tcdm_addr_base_i
  );

  // FMA architecture is "merged" -> mulexp and macexp instructions are supported
  localparam bit FPEn = RVF | RVD | XF16 | XF8;
  localparam int unsigned FLEN =
  RVD ? 64  : // D ext.
  RVF ? 32  : // F ext.
  XF16 ? 16 : // Xf16 ext.
  XF8 ? 8   : // Xf8 ext.
  0;          // Unused in case of no FP

  acc_issue_req_t acc_snitch_req;
  acc_issue_req_t acc_snitch_demux;
  acc_issue_rsp_t acc_snitch_resp;

  acc_rsp_t acc_demux_snitch;
  acc_rsp_t acc_resp;

  logic acc_snitch_demux_qvalid, acc_snitch_demux_qready;
  logic acc_qvalid, acc_qready;

  logic acc_pvalid, acc_pready;
  logic acc_demux_snitch_valid, acc_demux_snitch_ready;

  fpnew_pkg::roundmode_e fpu_rnd_mode;
  fpnew_pkg::fmt_mode_t fpu_fmt_mode;
  fpnew_pkg::status_t fpu_status;

  core_events_t snitch_events;

  // Snitch Integer Core
  dreq_t snitch_dreq_d, snitch_dreq_q, merged_cache_dreq;
  drsp_t snitch_drsp_d, snitch_drsp_q, merged_cache_drsp;

  // Spatz Memory consistency signals
  logic [1:0] spatz_mem_finished;
  logic [1:0] spatz_mem_str_finished;

  `SNITCH_VM_TYPEDEF(AddrWidth)

  snitch #(
    .AddrWidth              (AddrWidth             ),
    .DataWidth              (DataWidth             ),
    .acc_issue_req_t        (acc_issue_req_t       ),
    .acc_issue_rsp_t        (acc_issue_rsp_t       ),
    .acc_rsp_t              (acc_rsp_t             ),
    .dreq_t                 (dreq_t                ),
    .drsp_t                 (drsp_t                ),
    .pa_t                   (pa_t                  ),
    .l0_pte_t               (l0_pte_t              ),
    .id_t                   (req_id_t              ),
    .BootAddr               (BootAddr              ),
    .SnitchPMACfg           (SnitchPMACfg          ),
    .NumIntOutstandingLoads (NumIntOutstandingLoads),
    .NumIntOutstandingMem   (NumIntOutstandingMem  ),
    .VMSupport              (1'b0                  ),
    .RVE                    (RVE                   ),
    .FP_EN                  (FPEn                  ),
    .Xdma                   (Xdma                  ),
    .RVF                    (RVF                   ),
    .RVD                    (RVD                   ),
    .RVV                    (RVV                   ),
    .XDivSqrt               (XDivSqrt              ),
    .XF16                   (XF16                  ),
    .XF16ALT                (XF16ALT               ),
    .XF8                    (XF8                   ),
    .XF8ALT                 (XF8ALT                ),
    .FLEN                   (FLEN                  )
  ) i_snitch (
    .clk_i                 (clk_i                    ),
    .rst_i                 (!rst_ni                  ),
    .hart_id_i             (hart_id_i                ),
    .irq_i                 (irq_i                    ),
    .flush_i_valid_o       (hive_req_o.flush_i_valid ),
    .flush_i_ready_i       (hive_rsp_i.flush_i_ready ),
    .inst_addr_o           (hive_req_o.inst_addr     ),
    .inst_cacheable_o      (hive_req_o.inst_cacheable),
    .inst_data_i           (hive_rsp_i.inst_data     ),
    .inst_valid_o          (hive_req_o.inst_valid    ),
    .inst_ready_i          (hive_rsp_i.inst_ready    ),
    .acc_qreq_o            (acc_snitch_demux         ),
    .acc_qrsp_i            (acc_snitch_resp          ),
    .acc_qvalid_o          (acc_snitch_demux_qvalid  ),
    .acc_qready_i          (acc_snitch_demux_qready  ),
    .acc_prsp_i            (acc_demux_snitch         ),
    .acc_pvalid_i          (acc_demux_snitch_valid   ),
    .acc_pready_o          (acc_demux_snitch_ready   ),
    .acc_mem_finished_i    (spatz_mem_finished       ),
    .acc_mem_str_finished_i(spatz_mem_str_finished   ),
    .data_req_o            (snitch_dreq_d            ),
    .data_rsp_i            (snitch_drsp_d            ),
    .ptw_valid_o           (hive_req_o.ptw_valid     ),
    .ptw_ready_i           (hive_rsp_i.ptw_ready     ),
    .ptw_va_o              (hive_req_o.ptw_va        ),
    .ptw_ppn_o             (hive_req_o.ptw_ppn       ),
    .ptw_pte_i             (hive_rsp_i.ptw_pte       ),
    .ptw_is_4mega_i        (hive_rsp_i.ptw_is_4mega  ),
    .fpu_rnd_mode_o        (fpu_rnd_mode             ),
    .fpu_fmt_mode_o        (fpu_fmt_mode             ),
    .fpu_status_i          (fpu_status               ),
    .core_events_o         (snitch_events            )
  );

  typedef logic [DataWidth-1:0]   data_t;
  typedef logic [DataWidth/8-1:0] strb_t;

  `REQRSP_TYPEDEF_ALL(reqrsp, addr_t, data_t, strb_t, tcdm_user_t)

  spill_register #(
    .T      ( reqrsp_req_chan_t      ),
    .Bypass ( !RegisterCoreReq       )
  ) i_spill_register_req (
    .clk_i                            ,
    .rst_ni  ( rst_ni                ),
    .valid_i ( snitch_dreq_d.q_valid ),
    .ready_o ( snitch_drsp_d.q_ready ),
    .data_i  ( snitch_dreq_d.q       ),
    .valid_o ( snitch_dreq_q.q_valid ),
    .ready_i ( snitch_drsp_q.q_ready ),
    .data_o  ( snitch_dreq_q.q       )
  );

  spill_register #(
    .T      ( reqrsp_rsp_chan_t                ),
    .Bypass ( !IsoCrossing && !RegisterCoreRsp )
  ) i_spill_register_rsp (
    .clk_i                            ,
    .rst_ni  ( rst_ni                ),
    .valid_i ( snitch_drsp_q.p_valid ),
    .ready_o ( snitch_dreq_q.p_ready ),
    .data_i  ( snitch_drsp_q.p       ),
    .valid_o ( snitch_drsp_d.p_valid ),
    .ready_i ( snitch_dreq_d.p_ready ),
    .data_o  ( snitch_drsp_d.p       )
  );

  assign acc_qvalid = acc_snitch_demux_qvalid;
  assign acc_snitch_demux_qready = acc_qready;

  // There is no shared muldiv in this configuration
  assign hive_req_o.acc_qvalid = 1'b0;
  assign hive_req_o.acc_pready = 1'b0;
  assign hive_req_o.acc_req    = '0;
  assign acc_snitch_req        = acc_snitch_demux;

  assign acc_demux_snitch = acc_resp;
  assign acc_demux_snitch_valid = acc_pvalid;
  assign acc_pready = acc_demux_snitch_ready;

  dreq_t fp_lsu_mem_req;
  drsp_t fp_lsu_mem_rsp;

  tcdm_req_chan_t [NumMemPortsPerSpatz-1:0] spatz_mem_req;
  logic           [NumMemPortsPerSpatz-1:0] spatz_mem_req_valid;
  logic           [NumMemPortsPerSpatz-1:0] spatz_mem_req_ready;
  tcdm_rsp_chan_t [NumMemPortsPerSpatz-1:0] spatz_mem_rsp, spatz_mem_fifo;
  logic           [NumMemPortsPerSpatz-1:0] spatz_mem_rsp_valid;
  logic           [NumMemPortsPerSpatz-1:0] spatz_mem_rsp_ready;
  logic           [NumMemPortsPerSpatz-1:0] spatz_mem_rsp_empty, spatz_mem_rsp_full;
  logic           [NumMemPortsPerSpatz-1:0] spatz_mem_rsp_pop, spatz_mem_rsp_push;
  localparam int unsigned SpatzRspFifoDepth =
    (NumSpatzOutstandingLoads > 0) ? NumSpatzOutstandingLoads : 1;

  spatz #(
    .NrMemPorts         (NumMemPortsPerSpatz     ),
    .NumOutstandingLoads(NumSpatzOutstandingLoads),
    .FPUImplementation  (FPUImplementation       ),
    .RegisterRsp        (RegisterOffloadRsp      ),
    .dreq_t             (dreq_t                  ),
    .drsp_t             (drsp_t                  ),
    .spatz_mem_req_t    (tcdm_req_chan_t         ),
    .spatz_mem_rsp_t    (tcdm_rsp_chan_t         ),
    .spatz_issue_req_t  (acc_issue_req_t         ),
    .spatz_issue_rsp_t  (acc_issue_rsp_t         ),
    .spatz_rsp_t        (acc_rsp_t               )
  ) i_spatz (
    .clk_i                   (clk_i                 ),
    .rst_ni                  (rst_ni                ),
    .testmode_i              (testmode_i            ),
    .hart_id_i               (hart_id_i             ),
    .issue_valid_i           (acc_qvalid            ),
    .issue_ready_o           (acc_qready            ),
    .issue_req_i             (acc_snitch_req        ),
    .issue_rsp_o             (acc_snitch_resp       ),
    .rsp_valid_o             (acc_pvalid            ),
    .rsp_ready_i             (acc_pready            ),
    .rsp_o                   (acc_resp              ),
    .spatz_mem_req_o         (spatz_mem_req         ),
    .spatz_mem_req_valid_o   (spatz_mem_req_valid   ),
    .spatz_mem_req_ready_i   (spatz_mem_req_ready   ),
    .spatz_mem_rsp_i         (spatz_mem_rsp         ),
    .spatz_mem_rsp_valid_i   (spatz_mem_rsp_valid   ),
    .spatz_mem_rsp_ready_o   (spatz_mem_rsp_ready   ),
    .spatz_mem_finished_o    (spatz_mem_finished    ),
    .spatz_mem_str_finished_o(spatz_mem_str_finished),
    .fp_lsu_mem_req_o        (fp_lsu_mem_req        ),
    .fp_lsu_mem_rsp_i        (fp_lsu_mem_rsp        ),
    .fpu_rnd_mode_i          (fpu_rnd_mode          ),
    .fpu_fmt_mode_i          (fpu_fmt_mode          ),
    .fpu_status_o            (fpu_status            )
  );

  for (genvar p = 0; p < NumMemPortsPerSpatz; p++) begin : gen_spatz_mem_ports
    assign tcdm_req_o[p] = '{
         q      : spatz_mem_req[p],
         q_valid: spatz_mem_req_valid[p]
       };
    assign spatz_mem_req_ready[p] = tcdm_rsp_i[p].q_ready;

    fifo_v3 #(
      .dtype        (tcdm_rsp_chan_t    ),
      .DEPTH        (SpatzRspFifoDepth  ),
      .FALL_THROUGH (1                  )
    ) i_spatz_rsp_fifo (
      .clk_i     (clk_i                 ),
      .rst_ni    (rst_ni                ),
      .flush_i   (1'b0                  ),
      .testmode_i(1'b0                  ),
      .data_i    (tcdm_rsp_i[p].p       ),
      .push_i    (spatz_mem_rsp_push[p] ),
      .data_o    (spatz_mem_fifo[p]     ),
      .pop_i     (spatz_mem_rsp_pop[p]  ),
      .full_o    (spatz_mem_rsp_full[p] ),
      .empty_o   (spatz_mem_rsp_empty[p]),
      .usage_o   (/* Unused */          )
    );
    always_comb begin
      spatz_mem_rsp_valid[p] = !spatz_mem_rsp_empty[p];
      spatz_mem_rsp[p]       = spatz_mem_fifo[p];
      // Queue every response to avoid lossy bypass under backpressure.
      spatz_mem_rsp_push[p]  = tcdm_rsp_i[p].p_valid;
      spatz_mem_rsp_pop[p]   = spatz_mem_rsp_valid[p] & spatz_mem_rsp_ready[p];
    end

`ifndef TARGET_SYNTHESIS
    always_ff @(posedge clk_i) begin
      if (rst_ni && tcdm_rsp_i[p].p_valid && spatz_mem_rsp_full[p] && !spatz_mem_rsp_pop[p]) begin
        $error("[cachepool_cc] Spatz response FIFO overflow on port %0d", p);
      end
    end
`endif
  end

  // ---------------------------------------------------------------------------
  // Spatz<->TCDM request/response scoreboard (DEBUG ONLY).
  //
  // Compile-time gated by `EnableSpatzReqScoreboard`.  When the parameter is
  // 1'b0 the entire `gen_spatz_req_scoreboard` block is elaborated empty and
  // synthesizes to nothing.
  //
  // The scoreboard is a per-port table indexed by `user.req_id` (NOT a
  // FIFO).  This is critical because:
  //
  //   * The 4 cache banks can return responses in any global order.
  //   * Each cache bank has MSHRs and supports hit-under-miss / miss-under-
  //     miss, so even a single bank can return responses out-of-order.
  //
  // A FIFO scoreboard would mis-attribute out-of-order responses to the
  // wrong issued request.  Indexing the slot table by `user.req_id` makes
  // the match correct regardless of arrival order: when a response arrives
  // its `user.req_id` directly identifies which outstanding entry it
  // resolves.
  //
  // Per port:
  //   sb_q[p][id]     -- {valid, write, global_id, addr, issue_time}
  //                      Slot is filled on req_fire (idx = req's user.req_id);
  //                      cleared on rsp_fire (idx = rsp's user.req_id).
  //                      `valid` set means an outstanding request with that
  //                      `user.req_id` is currently in flight.
  //   req_id_q        -- 32-bit cumulative count of issued reqs (sanity)
  //   rsp_id_q        -- 32-bit cumulative count of received rsps (sanity)
  //   outstanding_q   -- req_id_q - rsp_id_q (in-flight count)
  //   req_fire/rsp_fire -- per-cycle handshake strobes (waveform aid)
  //
  // The slot table size = `NumSpatzOutstandingLoads`, which is the maximum
  // number of unique `user.req_id` values Spatz can issue per port.  Spatz
  // does not reuse a `user.req_id` while another request with the same id
  // is in flight, so each slot can hold at most one entry at any time.
  //
  // SVA / watchdog:
  //   * sba_no_dup_push  : asserts a slot is not already valid when pushed.
  //   * sba_pop_was_valid: asserts a slot was valid when popped.
  //   * watchdog $displays valid entries of stuck ports every WdogPs ps.
  // ---------------------------------------------------------------------------
  localparam int unsigned SpatzSbPorts    = NumMemPortsPerSpatz;
  localparam int unsigned SpatzSbReqIdW   = (NumSpatzOutstandingLoads <= 1) ? 1
                                          : $clog2(NumSpatzOutstandingLoads);
  localparam int unsigned SpatzSbDepth    = (NumSpatzOutstandingLoads <= 1) ? 1
                                          : NumSpatzOutstandingLoads;

  typedef struct packed {
    logic         valid;
    logic         write;
    logic [31:0]  global_id;     // monotonic counter at issue time
    logic [31:0]  addr;
    logic [63:0]  issue_time;    // $time at issue (sim only)
  } spatz_sb_entry_t;

  if (EnableSpatzReqScoreboard) begin : gen_spatz_req_scoreboard

    // Module-scope arrays.  Adding the array name once in the wave window
    // expands to all ports / all ids.
    logic            [SpatzSbPorts-1:0][31:0]                  req_id_q,      req_id_d;
    logic            [SpatzSbPorts-1:0][31:0]                  rsp_id_q,      rsp_id_d;
    logic            [SpatzSbPorts-1:0][31:0]                  outstanding_q, outstanding_d;
    spatz_sb_entry_t [SpatzSbPorts-1:0][SpatzSbDepth-1:0]      sb_q,          sb_d;
    logic            [SpatzSbPorts-1:0]                        req_fire;
    logic            [SpatzSbPorts-1:0]                        rsp_fire;
    // Per-cycle indices used (waveform aid)
    logic            [SpatzSbPorts-1:0][SpatzSbReqIdW-1:0]     req_idx;
    logic            [SpatzSbPorts-1:0][SpatzSbReqIdW-1:0]     rsp_idx;
`ifndef TARGET_SYNTHESIS
    logic [SpatzSbPorts-1:0][63:0]                             last_progress_time_q;
    logic [SpatzSbPorts-1:0][63:0]                             last_warn_time_q;
`endif

    `FFARN(req_id_q,      req_id_d,      '0, clk_i, rst_ni)
    `FFARN(rsp_id_q,      rsp_id_d,      '0, clk_i, rst_ni)
    `FFARN(outstanding_q, outstanding_d, '0, clk_i, rst_ni)
    `FFARN(sb_q,          sb_d,          '0, clk_i, rst_ni)

    for (genvar p = 0; p < SpatzSbPorts; p++) begin : gen_port
      assign req_fire[p] = spatz_mem_req_valid[p] & spatz_mem_req_ready[p];
      assign rsp_fire[p] = spatz_mem_rsp_valid[p] & spatz_mem_rsp_ready[p];
      // Slot index is the lower SpatzSbReqIdW bits of user.req_id.
      // (`reqid_t` is exactly that width, so this is a width match.)
      assign req_idx[p]  = SpatzSbReqIdW'(spatz_mem_req[p].user.req_id);
      assign rsp_idx[p]  = SpatzSbReqIdW'(spatz_mem_rsp[p].user.req_id);

      always_comb begin
        req_id_d[p]      = req_id_q[p];
        rsp_id_d[p]      = rsp_id_q[p];
        sb_d[p]          = sb_q[p];

        // Push (slot indexed by request's user.req_id).
        if (req_fire[p]) begin
          req_id_d[p]                          = req_id_q[p] + 32'd1;
          sb_d[p][req_idx[p]].valid            = 1'b1;
          sb_d[p][req_idx[p]].write            = spatz_mem_req[p].write;
          sb_d[p][req_idx[p]].global_id        = req_id_q[p];
          sb_d[p][req_idx[p]].addr             = 32'(spatz_mem_req[p].addr);
`ifndef TARGET_SYNTHESIS
          sb_d[p][req_idx[p]].issue_time       = 64'($time);
`else
          sb_d[p][req_idx[p]].issue_time       = '0;
`endif
        end

        // Pop (slot indexed by response's user.req_id).
        // If both fire same cycle for the SAME id, the pop wins (rare,
        // would require Spatz to re-issue the id in the same cycle the
        // previous one resolves; semantics match a straight-through hit).
        if (rsp_fire[p]) begin
          rsp_id_d[p]                          = rsp_id_q[p] + 32'd1;
          sb_d[p][rsp_idx[p]].valid            = 1'b0;
        end

        outstanding_d[p] = (req_id_d[p] - rsp_id_d[p]);
      end
    end : gen_port

`ifndef TARGET_SYNTHESIS
    // SVA: a request must not push to a slot that is already valid (would
    // mean Spatz reused a user.req_id while a previous one with the same
    // id was still in flight -- a protocol violation).
    for (genvar p = 0; p < SpatzSbPorts; p++) begin : gen_assert_dup_push
      property p_no_dup_push;
        @(posedge clk_i) disable iff (!rst_ni)
        req_fire[p] |-> !sb_q[p][req_idx[p]].valid;
      endproperty
      sba_no_dup_push: assert property (p_no_dup_push)
        else $error("[SPATZ-SB %m port %0d] DUP-PUSH: req_id=0x%h slot already valid (prior global_id=%0d addr=0x%08h)",
                    p, req_idx[p],
                    sb_q[p][req_idx[p]].global_id,
                    sb_q[p][req_idx[p]].addr);

      // SVA: a response must not pop a slot that is invalid (would mean
      // a response arrived for a request that was never issued or already
      // resolved).
      property p_pop_was_valid;
        @(posedge clk_i) disable iff (!rst_ni)
        rsp_fire[p] |-> sb_q[p][rsp_idx[p]].valid;
      endproperty
      sba_pop_was_valid: assert property (p_pop_was_valid)
        else $error("[SPATZ-SB %m port %0d] STRAY-RSP: rsp_id=0x%h has no matching outstanding request",
                    p, rsp_idx[p]);
    end

    // Watchdog: when a port has not received any rsp for SpatzReqScoreboardWdogPs
    // and outstanding > 0, dump the still-valid entries (each is the
    // exact `user.req_id` whose response is missing).  Re-warns every
    // WdogPs while still stuck.
    if (SpatzReqScoreboardWdogPs > 0) begin : gen_wdog
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          last_progress_time_q <= '0;
          last_warn_time_q     <= '0;
        end else begin
          for (int unsigned p = 0; p < SpatzSbPorts; p++) begin
            if (rsp_fire[p] || outstanding_q[p] == 32'd0) begin
              last_progress_time_q[p] <= 64'($time);
              last_warn_time_q[p]     <= 64'($time);
            end
            if (outstanding_q[p] != 32'd0 &&
                (64'($time) - last_progress_time_q[p]) > SpatzReqScoreboardWdogPs &&
                (64'($time) - last_warn_time_q[p])     > SpatzReqScoreboardWdogPs) begin
              last_warn_time_q[p] <= 64'($time);
              $display("[%0t] [SPATZ-SB %m port %0d] STUCK: req_cnt=%0d rsp_cnt=%0d outstanding=%0d (entries below indexed by user.req_id)",
                       $time, p, req_id_q[p], rsp_id_q[p], outstanding_q[p]);
              for (int unsigned ii = 0; ii < SpatzSbDepth; ii++) begin
                if (sb_q[p][ii].valid) begin
                  $display("    user.req_id=0x%02h global_id=%0d addr=0x%08h write=%0b issued@%0t (age=%0t)",
                           ii, sb_q[p][ii].global_id, sb_q[p][ii].addr, sb_q[p][ii].write,
                           sb_q[p][ii].issue_time,
                           64'($time) - sb_q[p][ii].issue_time);
                end
              end
            end
          end
        end
      end
    end
`endif
  end : gen_spatz_req_scoreboard

  typedef enum integer {
    SnitchMem       = 0,
    FPUMem          = 1
  } scalar_mem_mst_e;

  typedef enum integer {
    MainMem         = 0,
    TotStack        = 1,
    SpmStack        = 2,
    Periph          = 3
  } scalar_mem_slv_e;

  localparam int unsigned NrScalarXbarMst = 2;
  localparam int unsigned NrScalarXbarSlv = 4;

  // Snitch and Spatz FPU Sequencer
  dreq_chan_t [NrScalarXbarMst-1:0] core_req_chan;
  drsp_chan_t [NrScalarXbarMst-1:0] core_rsp_chan;
  logic [NrScalarXbarMst-1:0] core_req_valid, core_req_ready;
  logic [NrScalarXbarMst-1:0] core_rsp_valid, core_rsp_ready;

  // SPM Stack, L1 Stack, L1, Periph&BootROM
  dreq_chan_t [NrScalarXbarSlv-1:0] mem_req_chan;
  drsp_chan_t [NrScalarXbarSlv-1:0] mem_rsp_chan;
  logic [NrScalarXbarSlv-1:0] mem_req_valid, mem_req_ready;
  logic [NrScalarXbarSlv-1:0] mem_rsp_valid, mem_rsp_ready;

  dreq_t [NrScalarXbarSlv-1:0] mem_req;
  drsp_t [NrScalarXbarSlv-1:0] mem_rsp;

  localparam int unsigned SelectMstWidth   = cf_math_pkg::idx_width(NrScalarXbarSlv);
  localparam int unsigned SelectSlvWidth   = cf_math_pkg::idx_width(NrScalarXbarMst);
  typedef logic [SelectMstWidth-1:0] select_mst_t;
  typedef logic [SelectSlvWidth-1:0] select_slv_t;
  // select_t snitch_select;
  // select_t fpu_select;
  select_mst_t [NrScalarXbarMst-1:0] core_req_sel;
  select_slv_t [NrScalarXbarSlv-1:0] core_selected, mem_rsp_sel;


  assign core_req_chan  [SnitchMem] = snitch_dreq_q.q;
  assign core_req_valid [SnitchMem] = snitch_dreq_q.q_valid;
  assign core_rsp_ready [SnitchMem] = snitch_dreq_q.p_ready;

  assign snitch_drsp_q = '{
    p      : core_rsp_chan  [SnitchMem],
    p_valid: core_rsp_valid [SnitchMem],
    q_ready: core_req_ready [SnitchMem]
  };

  assign core_req_chan  [FPUMem]    = fp_lsu_mem_req.q;
  assign core_req_valid [FPUMem]    = fp_lsu_mem_req.q_valid;
  assign core_rsp_ready [FPUMem]    = fp_lsu_mem_req.p_ready;

  assign fp_lsu_mem_rsp = '{
    p      : core_rsp_chan  [FPUMem],
    p_valid: core_rsp_valid [FPUMem],
    q_ready: core_req_ready [FPUMem]
  };

  typedef struct packed {
    int unsigned idx;
    logic [AddrWidth-1:0] base;
    logic [AddrWidth-1:0] size;
  } reqrsp_rule_t;

  reqrsp_rule_t [NrScalarXbarSlv-2:0] addr_map;

  // We divide the regions into the following for scalar core's visit:
  // 0. DRAM region  => Cache
  // 1. Stack region => SPM (stack)
  // 2. Others       => Peripheral (bypass cache)

  // SPM Region (Stack SPM)
  // Give stack higher priority for winning the conflict
  assign addr_map[SpmStack] = '{
    idx : SpmStack,
    base: tcdm_addr_base_i + cachepool_pkg::TCDMSize - cachepool_pkg::SpmStackSize,
    size: cachepool_pkg::SpmStackSize
  };
  assign addr_map[TotStack] = '{
    idx : TotStack,
    base: tcdm_addr_base_i,
    size: cachepool_pkg::TotStackSize
  };
  // Main Memory Region
  assign addr_map[MainMem] = '{
    idx : MainMem,
    base: cachepool_pkg::DramAddr,
    size: cachepool_pkg::DramSize
  };

  // Snitch needs to decide: Stack, Data or Peripheral
  for (genvar i = 0; i < NrScalarXbarMst; i ++) begin : addr_decode
    always_comb begin
      // Default to peripheral
      core_req_sel[i] = Periph;
      for (int j = 0; j < NrScalarXbarSlv-1; j ++) begin
        if ((addr_map[j].base <= core_req_chan[i].addr) & (core_req_chan[i].addr < (addr_map[j].size+addr_map[j].base))) begin
          core_req_sel[i] = j;
        end
      end
    end
  end

  reqrsp_xbar #(
    .NumInp           (NrScalarXbarMst  ),
    .NumOut           (NrScalarXbarSlv  ),
    .PipeReg          (1'b0             ),
    .ExtReqPrio       (1'b0             ),
    .ExtRspPrio       (1'b0             ),
    .tcdm_req_chan_t  (dreq_chan_t      ),
    .tcdm_rsp_chan_t  (drsp_chan_t      )
  ) i_scalar_xbar (
    .clk_i            (clk_i            ),
    .rst_ni           (rst_ni           ),
    .slv_req_i        (core_req_chan    ),
    .slv_req_valid_i  (core_req_valid   ),
    .slv_req_ready_o  (core_req_ready   ),
    .slv_rsp_o        (core_rsp_chan    ),
    .slv_rsp_valid_o  (core_rsp_valid   ),
    .slv_rsp_ready_i  (core_rsp_ready   ),
    .slv_sel_i        (core_req_sel     ),
    .slv_rr_i         ('0               ),
    .slv_selected_o   (core_selected    ),
    .mst_req_o        (mem_req_chan     ),
    .mst_req_valid_o  (mem_req_valid    ),
    .mst_req_ready_i  (mem_req_ready    ),
    .mst_rsp_i        (mem_rsp_chan     ),
    .mst_rr_i         ('0               ),
    .mst_rsp_valid_i  (mem_rsp_valid    ),
    .mst_rsp_ready_o  (mem_rsp_ready    ),
    .mst_sel_i        (mem_rsp_sel      )
  );

  localparam int unsigned TotStackAddrWidth = $clog2(cachepool_pkg::TotStackSize);

  logic [$clog2(cachepool_pkg::NumCores)-1:0] stack_addr_check;
  assign stack_addr_check = mem_req_chan[TotStack].addr[($clog2(cachepool_pkg::TotStackSize)-1)-:$clog2(cachepool_pkg::NumCores)];

  always_comb begin
    for (int i = 0; i < NrScalarXbarSlv; i ++) begin
      mem_req[i].q             = mem_req_chan [i];
      mem_req[i].q_valid       = mem_req_valid[i];
      mem_req[i].p_ready       = mem_rsp_ready[i];
      mem_req[i].q.user.is_fpu = (core_selected[i] == FPUMem);
      // Alter the address for sw stack
      if (i == TotStack) begin
        // Change the higher bits to core id
        // All cores need unique stack in shared stack region
        mem_req[i].q.addr[($clog2(cachepool_pkg::TotStackSize)-1)-:$clog2(cachepool_pkg::NumCores)] =
          hart_id_i[$clog2(cachepool_pkg::NumCores)-1:0];

      end

      mem_rsp_chan [i] = mem_rsp[i].p;
      mem_rsp_valid[i] = mem_rsp[i].p_valid;
      mem_req_ready[i] = mem_rsp[i].q_ready;
      mem_rsp_sel  [i] = (mem_rsp[i].p.user.is_fpu == FPUMem);
    end
  end

  assign data_req_o = mem_req[Periph];
  assign mem_rsp[Periph] = data_rsp_i;

  // Merge the L1 stack access with L1 memory access
  reqrsp_mux #(
    .NrPorts     (2                 ),
    .AddrWidth   (AddrWidth         ),
    .DataWidth   (DataWidth         ),
    .UserWidth   ($bits(tcdm_user_t)),
    .req_t       (dreq_t            ),
    .rsp_t       (drsp_t            ),
    // TODO(zarubaf): Wire-up to top-level.
    .RespDepth   (4                 ),
    .RegisterReq ({1'b0, 1'b0}      )
  ) i_spm_reqrsp_mux (
    .clk_i     (clk_i                                ),
    .rst_ni    (rst_ni                               ),
    .slv_req_i ({mem_req[MainMem], mem_req[TotStack]}),
    .slv_rsp_o ({mem_rsp[MainMem], mem_rsp[TotStack]}),
    .mst_req_o (merged_cache_dreq                    ),
    .mst_rsp_i (merged_cache_drsp                    ),
    .idx_o     (/*not connected*/                    )
  );

  // Stack SPM
  localparam int unsigned StackLatency    = 1;
  localparam int unsigned StackAddrWidth  = $clog2(SpmStackDepth);

  typedef logic [$clog2(NumSpatzOutstandingLoads)-1:0] reqid_t;
  typedef logic [StackAddrWidth-1:0]  tcdm_stack_addr_t;

  typedef struct packed {
    tcdm_user_t user;
    logic       valid;
    logic       write;
  } stack_meta_t;

  // Memory bank signals
  logic           stack_valid, stack_we;
  tcdm_stack_addr_t stack_add;
  strb_t          stack_be;
  data_t          stack_rdata, stack_wdata;

  // Meta infomation signals
  stack_meta_t stack_req_meta, stack_rsp_meta;

  // Converter/reg signals
  tcdm_req_t stack_req;
  tcdm_rsp_t stack_rsp;

  // Converter for buffering the response if xbar congested
  reqrsp_to_tcdm #(
    .AddrWidth    (AddrWidth          ),
    .DataWidth    (DataWidth          ),
    .BufDepth     (4                  ),
    .UserWidth    ($bits(tcdm_user_t) ),
    .reqrsp_req_t (dreq_t             ),
    .reqrsp_rsp_t (drsp_t             ),
    .tcdm_req_t   (tcdm_req_t         ),
    .tcdm_rsp_t   (tcdm_rsp_t         )
  ) i_core_to_stack (
    .clk_i        (clk_i              ),
    .rst_ni       (rst_ni             ),
    .reqrsp_req_i (mem_req[SpmStack]  ),
    .reqrsp_rsp_o (mem_rsp[SpmStack]  ),
    .tcdm_req_o   (stack_req          ),
    .tcdm_rsp_i   (stack_rsp          )
  );

  // Match the type for the memory bank
  assign stack_valid = stack_req.q_valid;
  assign stack_we    = stack_req.q.write;
  assign stack_add   = stack_req.q.addr[StackAddrWidth+1:2];
  assign stack_wdata = stack_req.q.data;
  assign stack_be    = stack_req.q.strb;

  assign stack_req_meta = '{
    user:  stack_req.q.user,
    valid: stack_req.q_valid,
    write: stack_req.q.write
  };

  assign stack_rsp.p.data  = stack_rdata;
  assign stack_rsp.p.user  = stack_rsp_meta.user;
  assign stack_rsp.p.write = stack_rsp_meta.write;
  assign stack_rsp.p_valid = stack_rsp_meta.valid;
  assign stack_rsp.q_ready = 1'b1;

  tc_sram_impl #(
    .NumWords  (SpmStackDepth ),
    .DataWidth (DataWidth     ),
    .ByteWidth (8             ),
    .NumPorts  (1             ),
    .Latency   (StackLatency  ),
    .SimInit   ("zeros"       )
  ) i_spm_mem  (
    .clk_i     (clk_i         ),
    .rst_ni    (rst_ni        ),
    .impl_i    ('0            ),
    .impl_o    (/* Unused */  ),
    .req_i     (stack_valid   ),
    .we_i      (stack_we      ),
    .addr_i    (stack_add     ),
    .wdata_i   (stack_wdata   ),
    .be_i      (stack_be      ),
    .rdata_o   (stack_rdata   )
  );

  shift_reg #(
    .dtype (stack_meta_t      ),
    .Depth (StackLatency      )
  ) i_req_meta_pipe (
    .clk_i (clk_i             ),
    .rst_ni(rst_ni            ),
    .d_i   (stack_req_meta    ),
    .d_o   (stack_rsp_meta    )
  );

  reqrsp_to_tcdm #(
    .AddrWidth    (AddrWidth          ),
    .DataWidth    (DataWidth          ),
    .BufDepth     (4                  ),
    .reqrsp_req_t (dreq_t             ),
    .reqrsp_rsp_t (drsp_t             ),
    .UserWidth    ($bits(tcdm_user_t) ),
    .tcdm_req_t   (tcdm_req_t         ),
    .tcdm_rsp_t   (tcdm_rsp_t         )
  ) i_reqrsp_to_tcdm (
    .clk_i        (clk_i                          ),
    .rst_ni       (rst_ni                         ),
    .reqrsp_req_i (merged_cache_dreq              ),
    .reqrsp_rsp_o (merged_cache_drsp              ),
    .tcdm_req_o   (tcdm_req_o[NumMemPortsPerSpatz]),
    .tcdm_rsp_i   (tcdm_rsp_i[NumMemPortsPerSpatz])
  );

  // Core events for performance counters
  assign core_events_o.retired_instr     = snitch_events.retired_instr;
  assign core_events_o.retired_load      = snitch_events.retired_load;
  assign core_events_o.retired_i         = snitch_events.retired_i;
  assign core_events_o.retired_acc       = snitch_events.retired_acc;
  assign core_events_o.issue_fpu         = '0;
  assign core_events_o.issue_core_to_fpu = '0;
  assign core_events_o.issue_fpu_seq     = '0;

  // --------------------------
  // Tracer
  // --------------------------
`ifndef VERILATOR

  // pragma translate_off
  int           f;
  string        fn;
  logic  [63:0] cycle;

  `ASSERT(stack_overflow, mem_req_valid[TotStack] |-> (&stack_addr_check == 1'b1), clk_i, !rst_ni,
            "Core ID bits cannot be used for stack")

  int spatz_f;
  string spatz_f_name;

  initial begin
    // We need to schedule the assignment into a safe region, otherwise
    // `hart_id_i` won't have a value assigned at the beginning of the first
    // delta cycle.
    /* verilator lint_off STMTDLY */
    @(posedge clk_i);
    /* verilator lint_on STMTDLY */
    $system("mkdir sim/bin/logs -p");
    $sformat(fn, "sim/bin/logs/trace_hart_%05x.dasm", hart_id_i);
    f = $fopen(fn, "w");
    $display("[Tracer] Logging Hart %d to %s", hart_id_i, fn);

    $sformat(spatz_f_name, "sim/bin/logs/monitor_spatz_%05x.txt", hart_id_i);
    spatz_f = $fopen(spatz_f_name, "w");
  end

  // verilog_lint: waive-start always-ff-non-blocking
  always_ff @(posedge clk_i) begin
    automatic string trace_entry;
    automatic string extras_str;
    automatic snitch_pkg::snitch_trace_port_t extras_snitch;
    automatic snitch_pkg::fpu_trace_port_t extras_fpu;
    automatic snitch_pkg::fpu_sequencer_trace_port_t extras_fpu_seq_out;

    if (rst_ni) begin
      extras_snitch = '{
        // State
        source      : snitch_pkg::SrcSnitch,
        stall       : i_snitch.stall,
        exception   : i_snitch.exception,
        // Decoding
        rs1         : i_snitch.rs1,
        rs2         : i_snitch.rs2,
        rd          : i_snitch.rd,
        is_load     : i_snitch.is_load,
        is_store    : i_snitch.is_store,
        is_branch   : i_snitch.is_branch,
        pc_d        : i_snitch.pc_d,
        // Operands
        opa         : i_snitch.opa,
        opb         : i_snitch.opb,
        opa_select  : i_snitch.opa_select,
        opb_select  : i_snitch.opb_select,
        write_rd    : i_snitch.write_rd,
        csr_addr    : i_snitch.inst_data_i[31:20],
        // Pipeline writeback
        writeback   : i_snitch.alu_writeback,
        // Load/Store
        gpr_rdata_1 : i_snitch.gpr_rdata[1],
        ls_size     : i_snitch.ls_size,
        ld_result_32: i_snitch.ld_result[31:0],
        lsu_rd      : i_snitch.lsu_rd,
        retire_load : i_snitch.retire_load,
        alu_result  : i_snitch.alu_result,
        // Atomics
        ls_amo      : i_snitch.ls_amo,
        // Accelerator
        retire_acc  : i_snitch.retire_acc,
        acc_pid     : i_snitch.acc_prsp_i.id,
        acc_pdata_32: i_snitch.acc_prsp_i.data[31:0],
        // FPU offload
        fpu_offload : (i_snitch.acc_qready_i && i_snitch.acc_qvalid_o && i_snitch.acc_qreq_o.addr == 0),
        is_seq_insn : '0
      };

      cycle++;
      // Trace snitch iff:
      // we are not stalled <==> we have issued and processed an instruction (including offloads)
      // OR we are retiring (issuing a writeback from) a load or accelerator instruction
      if (!i_snitch.stall || i_snitch.retire_load || i_snitch.retire_acc) begin
        $sformat(trace_entry, "%t %1d %8d 0x%h DASM(%h) #; %s\n",
          $time, cycle, i_snitch.priv_lvl_q, i_snitch.pc_q, i_snitch.inst_data_i,
          snitch_pkg::print_snitch_trace(extras_snitch));
        $fwrite(f, trace_entry);
      end
      if (FPEn) begin
        // Trace FPU iff:
        // an incoming handshake on the accelerator bus occurs <==> an instruction was issued
        // OR an FPU result is ready to be written back to an FPR register or the bus
        // OR an LSU result is ready to be written back to an FPR register or the bus
        // OR an FPU result, LSU result or bus value is ready to be written back to an FPR register
        if (extras_fpu.acc_q_hs || extras_fpu.fpu_out_hs
            || extras_fpu.lsu_q_hs || extras_fpu.fpr_we) begin
          $sformat(trace_entry, "%t %1d %8d 0x%h DASM(%h) #; %s\n",
            $time, cycle, i_snitch.priv_lvl_q, 32'hz, extras_fpu.op_in,
            snitch_pkg::print_fpu_trace(extras_fpu));
          $fwrite(f, trace_entry);
        end
      end
    end else begin
      cycle <= '0;
    end
  end

  final begin
    `ifndef TARGET_SYNTHESIS
    /***** Controller Report *****/
    automatic real ctrl_vlsu_insn       = i_spatz.i_controller.ctrl_vlsu_insn_q;
    automatic real ctrl_vlsu_stall      = i_spatz.i_controller.ctrl_vlsu_stall_q;
    automatic real ctrl_vlsu_active     = i_spatz.i_controller.ctrl_vlsu_active_q;
    automatic real ctrl_vlsu_wvalid     = i_spatz.i_controller.ctrl_wvalid_cnt_q[1];
    automatic real ctrl_vlsu_wtrans     = i_spatz.i_controller.ctrl_wtrans_cnt_q[1];
    automatic real ctrl_vlsu_wstall     = ctrl_vlsu_wvalid - ctrl_vlsu_wtrans;

    automatic real ctrl_vfu_insn        = i_spatz.i_controller.ctrl_vfu_insn_q;
    automatic real ctrl_vfu_stall       = i_spatz.i_controller.ctrl_vfu_stall_q;
    automatic real ctrl_vfu_active      = i_spatz.i_controller.ctrl_vfu_active_q;
    automatic real ctrl_vfu_wvalid      = i_spatz.i_controller.ctrl_wvalid_cnt_q[0];
    automatic real ctrl_vfu_wtrans      = i_spatz.i_controller.ctrl_wtrans_cnt_q[0];
    automatic real ctrl_vfu_wstall      = ctrl_vfu_wvalid - ctrl_vfu_wtrans;

    automatic real ctrl_vsldu_insn      = i_spatz.i_controller.ctrl_vsldu_insn_q;
    automatic real ctrl_vsldu_stall     = i_spatz.i_controller.ctrl_vsldu_stall_q;
    automatic real ctrl_vsldu_active    = i_spatz.i_controller.ctrl_vsldu_active_q;
    automatic real ctrl_vsldu_wvalid    = i_spatz.i_controller.ctrl_wvalid_cnt_q[2];
    automatic real ctrl_vsldu_wtrans    = i_spatz.i_controller.ctrl_wtrans_cnt_q[2];
    automatic real ctrl_vsldu_wstall    = ctrl_vsldu_wvalid - ctrl_vsldu_wtrans;


    /***** VLSU Report *****/
    automatic real vlsu_wvalid          = i_spatz.i_vlsu.vrf_wvalid_cnt_q;
    automatic real vlsu_wtrans          = i_spatz.i_vlsu.vrf_wtrans_cnt_q;
    automatic real vlsu_vrf_w_util      = i_spatz.i_vlsu.vrf_wvalid_cnt_q == 0 ?
                                          0 : 100 * i_spatz.i_vlsu.vrf_wtrans_cnt_q / i_spatz.i_vlsu.vrf_wvalid_cnt_q;
    automatic real vlsu_vrf_w_avg_cyc   = i_spatz.i_vlsu.vrf_wtrans_cnt_q == 0 ?
                                          0 : i_spatz.i_vlsu.vrf_wvalid_cnt_q / i_spatz.i_vlsu.vrf_wtrans_cnt_q;

    automatic real vlsu_mem_cnt_tot     = i_spatz.i_vlsu.mem_valid_cnt_q;
    automatic real vlsu_mem_tran_tot    = i_spatz.i_vlsu.mem_trans_cnt_q;
    automatic real vlsu_mem_util        = vlsu_mem_cnt_tot == 0 ?
                                          0 : 100 * vlsu_mem_tran_tot / vlsu_mem_cnt_tot;
    automatic real vlsu_mem_avg_cyc     = vlsu_mem_tran_tot == 0 ?
                                          0 : vlsu_mem_cnt_tot / vlsu_mem_tran_tot;

    // ROB in use for x cycle, total usage Y: Utilization = Y/(X*depth)
    automatic real vlsu_rob_usage_avg   = i_spatz.i_vlsu.rob_use_cyc_q == 0 ?
                                          0 : 100 * i_spatz.i_vlsu.rob_usage_q / i_spatz.i_vlsu.rob_use_cyc_q / NumSpatzOutstandingLoads;
    automatic real vlsu_rob_peak_util   = 100 * i_spatz.i_vlsu.rob_peak_q / NumSpatzOutstandingLoads;

    automatic real vlsu_stall_cyc       = i_spatz.i_vlsu.rob_full_cyc_q;

    // Average instruction cycle can be used to caclulate the latency from VLSU to memory
    // AVG_insn_cyc / VLEN = AVG_LD_cyc_per_elem
    automatic real vlsu_insn_cnt        = i_spatz.i_vlsu.vlsu_insn_cnt_q;
    automatic real vlsu_avg_insn_cyc    = i_spatz.i_vlsu.vlsu_insn_valid_cyc_q / i_spatz.i_vlsu.vlsu_insn_cnt_q;

    /***** VFU Report *****/
    automatic real vfu_wvalid           = i_spatz.i_vfu.vrf_wvalid_cnt_q;
    automatic real vfu_wtrans           = i_spatz.i_vfu.vrf_wtrans_cnt_q;
    automatic real vfu_vrf_w_util       = i_spatz.i_vfu.vrf_wvalid_cnt_q == 0 ?
                                          0 : (100 * i_spatz.i_vfu.vrf_wtrans_cnt_q / i_spatz.i_vfu.vrf_wvalid_cnt_q);
    automatic real vfu_vrf_w_avg_cyc    = i_spatz.i_vfu.vrf_wtrans_cnt_q == 0 ?
                                          0 : (i_spatz.i_vfu.vrf_wvalid_cnt_q / i_spatz.i_vfu.vrf_wtrans_cnt_q);

    automatic real vfu_rvalid0          = i_spatz.i_vfu.vrf_rvalid_cnt_q[0];
    automatic real vfu_rtrans0          = i_spatz.i_vfu.vrf_rtrans_cnt_q[0];
    automatic real vfu_vrf_r_util0      = i_spatz.i_vfu.vrf_rvalid_cnt_q[0] == 0 ?
                                          0 : (100 * i_spatz.i_vfu.vrf_rtrans_cnt_q[0] / i_spatz.i_vfu.vrf_rvalid_cnt_q[0]);
    automatic real vfu_vrf_r_avg_cyc0   = i_spatz.i_vfu.vrf_rtrans_cnt_q[0] == 0 ?
                                          0 : (i_spatz.i_vfu.vrf_rvalid_cnt_q[0] / i_spatz.i_vfu.vrf_rtrans_cnt_q[0]);

    automatic real vfu_rvalid1          = i_spatz.i_vfu.vrf_rvalid_cnt_q[1];
    automatic real vfu_rtrans1          = i_spatz.i_vfu.vrf_rtrans_cnt_q[1];
    automatic real vfu_vrf_r_util1      = i_spatz.i_vfu.vrf_rvalid_cnt_q[1] == 0 ?
                                          0 : (100 * i_spatz.i_vfu.vrf_rtrans_cnt_q[1] / i_spatz.i_vfu.vrf_rvalid_cnt_q[1]);
    automatic real vfu_vrf_r_avg_cyc1   = i_spatz.i_vfu.vrf_rvalid_cnt_q[1] == 0 ?
                                          0 : (i_spatz.i_vfu.vrf_rvalid_cnt_q[1] / i_spatz.i_vfu.vrf_rtrans_cnt_q[1]);

    automatic real vfu_rvalid2          = i_spatz.i_vfu.vrf_rvalid_cnt_q[2];
    automatic real vfu_rtrans2          = i_spatz.i_vfu.vrf_rtrans_cnt_q[2];
    automatic real vfu_vrf_r_util2      = i_spatz.i_vfu.vrf_rvalid_cnt_q[2] == 0 ?
                                          0 : (100 * i_spatz.i_vfu.vrf_rtrans_cnt_q[2] / i_spatz.i_vfu.vrf_rvalid_cnt_q[2]);
    automatic real vfu_vrf_r_avg_cyc2   = i_spatz.i_vfu.vrf_rvalid_cnt_q[2] == 0 ?
                                          0 : (i_spatz.i_vfu.vrf_rvalid_cnt_q[2] / i_spatz.i_vfu.vrf_rtrans_cnt_q[2]);

    automatic real vfu_insn_cnt         = i_spatz.i_vfu.vfu_insn_cnt_q;
    automatic real vfu_avg_insn_cyc     = i_spatz.i_vfu.vfu_insn_cnt_q == 0 ?
                                          0 : (i_spatz.i_vfu.vfu_insn_valid_cyc_q / i_spatz.i_vfu.vfu_insn_cnt_q);

    $fwrite(spatz_f, "*********************************************************************\n");
    $fwrite(spatz_f, "***            Spatz Controller Utilization Report                ***\n");
    $fwrite(spatz_f, "*********************************************************************\n");
    $fwrite(spatz_f, "   VLSU:\n"                                                             );
    $fwrite(spatz_f, "   VLSU Active (not accurate):       %32d\n", ctrl_vlsu_active          );
    $fwrite(spatz_f, "   VLSU Num Instructions:            %32d\n", ctrl_vlsu_insn            );
    $fwrite(spatz_f, "   VLSU Stall Cycles:                %32d\n", ctrl_vlsu_stall           );
    $fwrite(spatz_f, "   VLSU WR Stalls:                   %32d\n", ctrl_vlsu_wstall          );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   VFU:\n"                                                              );
    $fwrite(spatz_f, "   VFU Active (not accurate):        %32d\n", ctrl_vfu_active           );
    $fwrite(spatz_f, "   VFU Num Instructions:             %32d\n", ctrl_vfu_insn             );
    $fwrite(spatz_f, "   VFU Stall Cycles:                 %32d\n", ctrl_vfu_stall            );
    $fwrite(spatz_f, "   VFU WR Stalls:                    %32d\n", ctrl_vfu_wstall           );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   VSLDU:\n"                                                            );
    $fwrite(spatz_f, "   VSLDU Active (not accurate):      %32d\n", ctrl_vsldu_active         );
    $fwrite(spatz_f, "   VSLDU Num Instructions:           %32d\n", ctrl_vsldu_insn           );
    $fwrite(spatz_f, "   VSLDU Stall Cycles:               %32d\n", ctrl_vsldu_stall          );
    $fwrite(spatz_f, "   VSLDU WR Stalls:                  %32d\n", ctrl_vsldu_wstall         );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "*********************************************************************\n");
    $fwrite(spatz_f, "***            Spatz VLSU Utilization Report                      ***\n");
    $fwrite(spatz_f, "*********************************************************************\n");
    $fwrite(spatz_f, "   Number of VRF Valid Cycles:       %32d\n", vlsu_wvalid               );
    $fwrite(spatz_f, "   Number of VRF Transaction Counts: %32d\n", vlsu_wtrans               );
    $fwrite(spatz_f, "   VRF W Utilization:                %32.2f\n", vlsu_vrf_w_util         );
    $fwrite(spatz_f, "   VRF W AVG Cycles:                 %32.2f\n", vlsu_vrf_w_avg_cyc      );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   Number of Mem Valid Cycles:       %32d\n", vlsu_mem_cnt_tot          );
    $fwrite(spatz_f, "   Number of Mem Transaction Counts: %32d\n", vlsu_mem_tran_tot         );
    $fwrite(spatz_f, "   Mem Utilization:                  %32.2f\n",vlsu_mem_util            );
    $fwrite(spatz_f, "   Mem AVG Req Accept Cycles:        %32.2f\n",vlsu_mem_avg_cyc         );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   VLSU Stall Cycles (ROB Full):     %32d\n", vlsu_stall_cyc            );
    $fwrite(spatz_f, "   ROB AVG Utilization:              %32.2f\n", vlsu_rob_usage_avg      );
    $fwrite(spatz_f, "   ROB Peak Utilization:             %32.2f\n", vlsu_rob_peak_util      );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   Total Insn Count:                 %32.2f\n", vlsu_insn_cnt           );
    $fwrite(spatz_f, "   AVG Insn Cycles:                  %32.2f\n", vlsu_avg_insn_cyc       );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "*********************************************************************\n");
    $fwrite(spatz_f, "***            Spatz VFU Utilization Report                       ***\n");
    $fwrite(spatz_f, "*********************************************************************\n");
    $fwrite(spatz_f, "   VRF Write Port:\n"                                                   );
    $fwrite(spatz_f, "   Number of VRF Valid Cycles:       %32d\n", vfu_wvalid                );
    $fwrite(spatz_f, "   Number of VRF Transaction Counts: %32d\n", vfu_wtrans                );
    $fwrite(spatz_f, "   VRF W Utilization:                %32.2f\n", vfu_vrf_w_util          );
    $fwrite(spatz_f, "   VRF W AVG Cycles:                 %32.2f\n", vfu_vrf_w_avg_cyc       );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   VRF Read Port 0:\n"                                                  );
    $fwrite(spatz_f, "   Number of VRF Valid Cycles:       %32d\n", vfu_rvalid0               );
    $fwrite(spatz_f, "   Number of VRF Transaction Counts: %32d\n", vfu_rtrans0               );
    $fwrite(spatz_f, "   VRF W Utilization:                %32.2f\n", vfu_vrf_r_util0         );
    $fwrite(spatz_f, "   VRF W AVG Cycles:                 %32.2f\n", vfu_vrf_r_avg_cyc0      );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   VRF Read Port 1:\n"                                                  );
    $fwrite(spatz_f, "   Number of VRF Valid Cycles:       %32d\n", vfu_rvalid1               );
    $fwrite(spatz_f, "   Number of VRF Transaction Counts: %32d\n", vfu_rtrans1               );
    $fwrite(spatz_f, "   VRF W Utilization:                %32.2f\n", vfu_vrf_r_util1         );
    $fwrite(spatz_f, "   VRF W AVG Cycles:                 %32.2f\n", vfu_vrf_r_avg_cyc1      );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   VRF Read Port 2:\n"                                                  );
    $fwrite(spatz_f, "   Number of VRF Valid Cycles:       %32d\n", vfu_rvalid2               );
    $fwrite(spatz_f, "   Number of VRF Transaction Counts: %32d\n", vfu_rtrans2               );
    $fwrite(spatz_f, "   VRF W Utilization:                %32.2f\n", vfu_vrf_r_util2         );
    $fwrite(spatz_f, "   VRF W AVG Cycles:                 %32.2f\n", vfu_vrf_r_avg_cyc2      );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "\n"                                                                     );
    $fwrite(spatz_f, "   Total Insn Count:                 %32.2f\n", vfu_insn_cnt            );
    $fwrite(spatz_f, "   AVG Insn Cycles:                  %32.2f\n", vfu_avg_insn_cyc        );
    $fwrite(spatz_f, "*********************************************************************\n");

    `endif
    $fclose(f);
    $fclose(spatz_f);

  end

  // verilog_lint: waive-stop always-ff-non-blocking
  // pragma translate_on

  `ASSERT_INIT(BootAddrAligned, BootAddr[1:0] == 2'b00)

`endif

endmodule
