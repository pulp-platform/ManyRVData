// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"
`include "snitch_vm/typedef.svh"
`include "reqrsp_interface/typedef.svh"

/// CachePool Core Complex (dual flavor): 2 Snitch Integer Cores sharing
/// 1 Spatz Vector Unit, gated by cachepool_spatz_lock. cachepool_cc.sv
/// (single-hart) is untouched; this is a sibling module for tiles built
/// with num_scalar_per_core=2.
module cachepool_cc_dual
  import snitch_pkg::interrupts_t;
  import fpnew_pkg::fpu_implementation_t; #(
    /// Address width of the buses
    parameter int                          unsigned        AddrWidth                = 0,
    /// Data width of the buses.
    parameter int                          unsigned        DataWidth                = 0,
    /// User width of the buses.
    parameter int                          unsigned        UserWidth                = 0,

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
    parameter type                                         hive_req_t               = logic,
    parameter type                                         hive_rsp_t               = logic,
    parameter type                                         acc_issue_req_t          = logic,
    parameter type                                         acc_issue_rsp_t          = logic,
    parameter type                                         acc_rsp_t                = logic,
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
    /// Derived parameter *Do not override*
    parameter int                          unsigned        NumSpatzFUs              = (NumSpatzFPUs > NumSpatzIPUs) ? NumSpatzFPUs : NumSpatzIPUs,
    parameter int                          unsigned        NumMemPortsPerSpatz      = NumSpatzFUs,
    /// 2 dedicated scalar ports (one per host) instead of 1 merged one.
    parameter int                          unsigned        TCDMPorts                = RVV ? NumMemPortsPerSpatz + 2 : 2,
    parameter type                                         addr_t                   = logic [AddrWidth-1:0],
    parameter type                                         req_id_t                 = logic [$clog2(NumSpatzOutstandingLoads)-1:0]
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         testmode_i,
    input  logic         [1:0][31:0]     hart_id_i,
    input  interrupts_t  [1:0]           irq_i,
    output hive_req_t    [1:0]           hive_req_o,
    input  hive_rsp_t    [1:0]           hive_rsp_i,
    // Core data ports (one per host, bypasses cache/TCDM)
    output dreq_t        [1:0]           data_req_o,
    input  drsp_t        [1:0]           data_rsp_i,
    // TCDM Streamer Ports
    output tcdm_req_t    [TCDMPorts-1:0] tcdm_req_o,
    input  tcdm_rsp_t    [TCDMPorts-1:0] tcdm_rsp_i,
    // Response-side ready, reflecting real downstream capacity (Spatz + scalar ports).
    output logic         [TCDMPorts-1:0] tcdm_rsp_ready_o,
    input  addr_t                        tcdm_addr_base_i,
    input  addr_t                        cluster_periph_start_address_i,
    // Spatz lock/switch status (debug)
    output logic                         owner_id_o
  );

  // FMA architecture is "merged" -> mulexp and macexp instructions are supported
  localparam bit FPEn = RVF | RVD | XF16 | XF8;
  localparam int unsigned FLEN =
    RVD ? 64  : // D ext.
    RVF ? 32  : // F ext.
    XF16 ? 16 : // Xf16 ext.
    XF8 ? 8   : // Xf8 ext.
    0;          // Unused in case of no FP

  `SNITCH_VM_TYPEDEF(AddrWidth)

  typedef logic [DataWidth-1:0]   data_t;
  typedef logic [DataWidth/8-1:0] strb_t;

  `REQRSP_TYPEDEF_ALL(reqrsp, addr_t, data_t, strb_t, tcdm_user_t)

  logic owner_id, locked, waiting, owner_active;
  logic req_fire, rsp_fire;
  assign owner_id_o = owner_id;

  // Raw per-host Snitch data port, and its acc issue/response bundle.
  dreq_t [1:0] snitch_dreq_d;
  drsp_t [1:0] snitch_drsp_d;

  acc_issue_req_t [1:0] acc_snitch_req;
  acc_issue_rsp_t [1:0] acc_snitch_rsp;
  logic           [1:0] acc_snitch_qvalid, acc_snitch_qready;
  acc_rsp_t       [1:0] acc_snitch_prsp;
  logic           [1:0] acc_snitch_pvalid, acc_snitch_pready;

  fpnew_pkg::roundmode_e [1:0] fpu_rnd_mode_h;
  fpnew_pkg::fmt_mode_t  [1:0] fpu_fmt_mode_h;
  fpnew_pkg::status_t          fpu_status;

  // Spatz's raw LSU-consistency signals; acc_mux demuxes these to the issuing host.
  logic [1:0] spatz_mem_finished;
  logic [1:0] spatz_mem_str_finished;
  logic       spatz_st_rsp_done;

  logic [1:0][1:0] acc_mem_finished_h;
  logic [1:0][1:0] acc_mem_str_finished_h;
  logic [1:0]      acc_st_rsp_done_h;

  for (genvar h = 0; h < 2; h++) begin : gen_snitch
    snitch #(
      .AddrWidth              (AddrWidth             ),
      .DataWidth              (DataWidth             ),
      .acc_issue_req_t        (acc_issue_req_t       ),
      .acc_issue_rsp_t        (acc_issue_rsp_t       ),
      .acc_rsp_t               (acc_rsp_t             ),
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
      .Xdma                   (1'b0                  ),
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
      .clk_i                 (clk_i                       ),
      .rst_i                 (!rst_ni                     ),
      .hart_id_i             (hart_id_i[h]                ),
      .irq_i                 (irq_i[h]                    ),
      .flush_i_valid_o       (hive_req_o[h].flush_i_valid ),
      .flush_i_ready_i       (hive_rsp_i[h].flush_i_ready ),
      .inst_addr_o           (hive_req_o[h].inst_addr     ),
      .inst_cacheable_o      (hive_req_o[h].inst_cacheable),
      .inst_data_i           (hive_rsp_i[h].inst_data     ),
      .inst_valid_o          (hive_req_o[h].inst_valid    ),
      .inst_ready_i          (hive_rsp_i[h].inst_ready    ),
      .acc_qreq_o            (acc_snitch_req[h]           ),
      .acc_qrsp_i            (acc_snitch_rsp[h]           ),
      .acc_qvalid_o          (acc_snitch_qvalid[h]        ),
      .acc_qready_i          (acc_snitch_qready[h]        ),
      .acc_prsp_i            (acc_snitch_prsp[h]          ),
      .acc_pvalid_i          (acc_snitch_pvalid[h]        ),
      .acc_pready_o          (acc_snitch_pready[h]        ),
      .acc_mem_finished_i    (acc_mem_finished_h[h]       ),
      .acc_mem_str_finished_i(acc_mem_str_finished_h[h]   ),
      .acc_st_rsp_done_i     (acc_st_rsp_done_h[h]        ),
      .data_req_o            (snitch_dreq_d[h]            ),
      .data_rsp_i            (snitch_drsp_d[h]            ),
      .ptw_valid_o           (hive_req_o[h].ptw_valid     ),
      .ptw_ready_i           (hive_rsp_i[h].ptw_ready     ),
      .ptw_va_o              (hive_req_o[h].ptw_va        ),
      .ptw_ppn_o             (hive_req_o[h].ptw_ppn       ),
      .ptw_pte_i             (hive_rsp_i[h].ptw_pte       ),
      .ptw_is_4mega_i        (hive_rsp_i[h].ptw_is_4mega  ),
      .fpu_rnd_mode_o        (fpu_rnd_mode_h[h]           ),
      .fpu_fmt_mode_o        (fpu_fmt_mode_h[h]           ),
      .fpu_status_i          (fpu_status                  ),
      .core_events_o         (/* unused */                )
    );

    // There is no shared muldiv in this configuration
    assign hive_req_o[h].acc_qvalid = 1'b0;
    assign hive_req_o[h].acc_pready = 1'b0;
    assign hive_req_o[h].acc_req    = '0;
  end

  // Spatz issue/response bundle, owner-routed by the lock.
  acc_issue_req_t spatz_issue_req;
  acc_issue_rsp_t spatz_issue_rsp;
  logic           spatz_issue_valid, spatz_issue_ready;
  acc_rsp_t       spatz_rsp;
  logic           spatz_rsp_valid, spatz_rsp_ready;

  // LSU issue handshake fire, gates the lock's LSU drain counter.
  logic spatz_lsu_issue_fire;
  assign spatz_lsu_issue_fire = spatz_issue_valid && spatz_issue_ready && spatz_issue_rsp.loadstore;

  // Lock-module pass-through data interface (accept/deliver on the module's
  // own registered output side; see cachepool_spatz_lock.sv).
  dreq_t [1:0] lock_out_req;
  drsp_t [1:0] lock_out_rsp;

  cachepool_spatz_lock #(
    .AddrWidth       (AddrWidth        ),
    .NumHosts        (2                ),
    .dreq_t          (dreq_t           ),
    .drsp_t          (drsp_t           ),
    .dreq_chan_t     (dreq_chan_t      ),
    .drsp_chan_t     (drsp_chan_t      ),
    .user_t          (tcdm_user_t      ),
    .RegisterCoreReq (RegisterCoreReq  ),
    .RegisterCoreRsp (RegisterCoreRsp  ),
    .addr_t          (addr_t           )
  ) i_spatz_lock (
    .clk_i                          (clk_i               ),
    .rst_ni                         (rst_ni              ),
    .in_req_i                       (snitch_dreq_d       ),
    .in_rsp_o                       (snitch_drsp_d       ),
    .out_req_o                      (lock_out_req        ),
    .out_rsp_i                      (lock_out_rsp        ),
    .req_fire_i                     (req_fire            ),
    .rsp_fire_i                     (rsp_fire            ),
    .spatz_lsu_issue_fire_i         (spatz_lsu_issue_fire),
    .spatz_mem_finished_i           (spatz_mem_finished  ),
    .spatz_st_rsp_done_i            (spatz_st_rsp_done   ),
    .owner_id_o                     (owner_id            ),
    .locked_o                       (locked              ),
    .waiting_o                      (waiting             ),
    .owner_active_o                 (owner_active        ),
    .cluster_periph_start_address_i (cluster_periph_start_address_i)
  );

  // Acc mux: real round-robin access to Spatz for both hosts while
  // unlocked, exclusive owner access while locked. See acc_mux.sv.
  acc_mux #(
    .acc_issue_req_t (acc_issue_req_t),
    .acc_issue_rsp_t (acc_issue_rsp_t),
    .acc_rsp_t       (acc_rsp_t      )
  ) i_acc_mux (
    .clk_i                   (clk_i                  ),
    .rst_ni                  (rst_ni                 ),
    .owner_id_i              (owner_id               ),
    .locked_i                (locked                 ),
    .waiting_i               (waiting                ),
    .owner_active_i          (owner_active           ),
    .acc_snitch_req_i        (acc_snitch_req         ),
    .acc_snitch_rsp_o        (acc_snitch_rsp         ),
    .acc_snitch_qvalid_i     (acc_snitch_qvalid      ),
    .acc_snitch_qready_o     (acc_snitch_qready      ),
    .acc_snitch_prsp_o       (acc_snitch_prsp        ),
    .acc_snitch_pvalid_o     (acc_snitch_pvalid      ),
    .acc_snitch_pready_i     (acc_snitch_pready      ),
    .spatz_issue_req_o       (spatz_issue_req        ),
    .spatz_issue_rsp_i       (spatz_issue_rsp        ),
    .spatz_issue_valid_o     (spatz_issue_valid      ),
    .spatz_issue_ready_i     (spatz_issue_ready      ),
    .spatz_rsp_i             (spatz_rsp              ),
    .spatz_rsp_valid_i       (spatz_rsp_valid        ),
    .spatz_rsp_ready_o       (spatz_rsp_ready        ),
    .spatz_mem_finished_i    (spatz_mem_finished     ),
    .spatz_mem_str_finished_i(spatz_mem_str_finished ),
    .spatz_st_rsp_done_i     (spatz_st_rsp_done      ),
    .req_fire_o              (req_fire               ),
    .rsp_fire_o              (rsp_fire               ),
    .acc_mem_finished_o      (acc_mem_finished_h     ),
    .acc_mem_str_finished_o  (acc_mem_str_finished_h ),
    .acc_st_rsp_done_o       (acc_st_rsp_done_h      )
  );

  // FPU rounding-mode/format CSRs: Spatz has one FPU, so it only ever sees the
  // current owner's config; its status broadcasts back to both hosts.
  fpnew_pkg::roundmode_e fpu_rnd_mode;
  fpnew_pkg::fmt_mode_t  fpu_fmt_mode;
  assign fpu_rnd_mode = fpu_rnd_mode_h[owner_id];
  assign fpu_fmt_mode = fpu_fmt_mode_h[owner_id];

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
    .hart_id_i               (hart_id_i[owner_id]   ),
    .issue_valid_i           (spatz_issue_valid     ),
    .issue_ready_o           (spatz_issue_ready     ),
    .issue_req_i             (spatz_issue_req       ),
    .issue_rsp_o             (spatz_issue_rsp       ),
    .rsp_valid_o             (spatz_rsp_valid       ),
    .rsp_ready_i             (spatz_rsp_ready       ),
    .rsp_o                   (spatz_rsp             ),
    .spatz_mem_req_o         (spatz_mem_req         ),
    .spatz_mem_req_valid_o   (spatz_mem_req_valid   ),
    .spatz_mem_req_ready_i   (spatz_mem_req_ready   ),
    .spatz_mem_rsp_i         (spatz_mem_rsp         ),
    .spatz_mem_rsp_valid_i   (spatz_mem_rsp_valid   ),
    .spatz_mem_rsp_ready_o   (spatz_mem_rsp_ready   ),
    .spatz_mem_finished_o    (spatz_mem_finished    ),
    .spatz_mem_str_finished_o(spatz_mem_str_finished),
    .spatz_st_rsp_done_o     (spatz_st_rsp_done     ),
    .fp_lsu_mem_req_o        (fp_lsu_mem_req        ),
    .fp_lsu_mem_rsp_i        (fp_lsu_mem_rsp        ),
    .fpu_rnd_mode_i          (fpu_rnd_mode          ),
    .fpu_fmt_mode_i          (fpu_fmt_mode          ),
    .fpu_status_o            (fpu_status            )
  );

  // Vector-FU TCDM ports pin to host 0's crossbar row (only one physical
  // row per CC pair); acc_mux re-attributes responses to the true owner.
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
    assign tcdm_rsp_ready_o[p] = !spatz_mem_rsp_full[p];

    always_comb begin
      spatz_mem_rsp_valid[p] = !spatz_mem_rsp_empty[p];
      spatz_mem_rsp[p]       = spatz_mem_fifo[p];
      // Only push once the handshake completes (valid & ready), else the fifo overflows silently.
      spatz_mem_rsp_push[p]  = tcdm_rsp_i[p].p_valid & tcdm_rsp_ready_o[p];
      spatz_mem_rsp_pop[p]   = spatz_mem_rsp_valid[p] & spatz_mem_rsp_ready[p];
    end
  end

  // ---------------------------------------------------------------------
  // Per-host scalar crossbar: {SnitchHMem, FPUMem-when-owner==h} ->
  // {CacheMemH, SpmStackH, PeriphH}. Two small crossbars instead of one
  // all-to-all one -- see note.md "Per-host crossbars".
  // ---------------------------------------------------------------------
  typedef enum integer {
    SnitchMst = 0,
    FpuMst    = 1
  } scalar_mem_mst_e;

  typedef enum integer {
    CacheMem = 0,
    SpmStack = 1,
    Periph   = 2
  } scalar_mem_slv_e;

  localparam int unsigned NrScalarXbarMst = 2;
  localparam int unsigned NrScalarXbarSlv = 3;

  localparam int unsigned SelectMstWidth = cf_math_pkg::idx_width(NrScalarXbarSlv);
  localparam int unsigned SelectSlvWidth = cf_math_pkg::idx_width(NrScalarXbarMst);
  typedef logic [SelectMstWidth-1:0] select_mst_t;
  typedef logic [SelectSlvWidth-1:0] select_slv_t;

  localparam int unsigned StackAddrWidth = $clog2(SpmStackDepth);
  typedef logic [StackAddrWidth-1:0] tcdm_stack_addr_t;
  typedef struct packed {
    tcdm_user_t user;
    logic       valid;
    logic       write;
  } stack_meta_t;

  drsp_t [1:0] fpu_rsp_per_host;

  assign fp_lsu_mem_rsp = fpu_rsp_per_host[owner_id];

  // Per-host signals, hoisted out of gen_host as 2D arrays (indexed [host][...])
  // for debug visibility, rather than living inside separate generate scopes.
  dreq_t [1:0] fpu_req_gated;

  dreq_chan_t [1:0][NrScalarXbarMst-1:0] core_req_chan;
  drsp_chan_t [1:0][NrScalarXbarMst-1:0] core_rsp_chan;
  logic       [1:0][NrScalarXbarMst-1:0] core_req_valid, core_req_ready;
  logic       [1:0][NrScalarXbarMst-1:0] core_rsp_valid, core_rsp_ready;

  dreq_chan_t [1:0][NrScalarXbarSlv-1:0] mem_req_chan;
  drsp_chan_t [1:0][NrScalarXbarSlv-1:0] mem_rsp_chan;
  logic       [1:0][NrScalarXbarSlv-1:0] mem_req_valid, mem_req_ready;
  logic       [1:0][NrScalarXbarSlv-1:0] mem_rsp_valid, mem_rsp_ready;

  dreq_t [1:0][NrScalarXbarSlv-1:0] mem_req;
  drsp_t [1:0][NrScalarXbarSlv-1:0] mem_rsp;

  select_mst_t [1:0][NrScalarXbarMst-1:0] core_req_sel;
  select_slv_t [1:0][NrScalarXbarSlv-1:0] core_selected, mem_rsp_sel;

  logic [1:0] is_totstack;

  logic              [1:0] stack_valid, stack_we;
  tcdm_stack_addr_t  [1:0] stack_add;
  strb_t             [1:0] stack_be;
  data_t             [1:0] stack_rdata, stack_wdata;
  stack_meta_t       [1:0] stack_req_meta, stack_rsp_meta;
  tcdm_req_t         [1:0] stack_req;
  tcdm_rsp_t         [1:0] stack_rsp;

  for (genvar h = 0; h < 2; h++) begin : gen_host
    // FPU's request only ever contends on the crossbar matching the current owner.
    assign fpu_req_gated[h] = '{
      q      : fp_lsu_mem_req.q,
      q_valid: fp_lsu_mem_req.q_valid && (owner_id == h[0]),
      p_ready: fp_lsu_mem_req.p_ready
    };

    assign core_req_chan  [h][SnitchMst] = lock_out_req[h].q;
    assign core_req_valid [h][SnitchMst] = lock_out_req[h].q_valid;
    assign core_rsp_ready [h][SnitchMst] = lock_out_req[h].p_ready;
    assign lock_out_rsp[h] = '{
      p      : core_rsp_chan  [h][SnitchMst],
      p_valid: core_rsp_valid [h][SnitchMst],
      q_ready: core_req_ready [h][SnitchMst]
    };

    assign core_req_chan  [h][FpuMst] = fpu_req_gated[h].q;
    assign core_req_valid [h][FpuMst] = fpu_req_gated[h].q_valid;
    assign core_rsp_ready [h][FpuMst] = fpu_req_gated[h].p_ready;
    assign fpu_rsp_per_host[h] = '{
      p      : core_rsp_chan  [h][FpuMst],
      p_valid: core_rsp_valid [h][FpuMst],
      q_ready: core_req_ready [h][FpuMst]
    };

    // Give SpmStack higher priority for winning an overlap; TotStack-range
    // addresses share the CacheMem slot with MainMem (patched below).
    always_comb begin
      for (int i = 0; i < NrScalarXbarMst; i++) begin
        core_req_sel[h][i] = Periph;
        if ((tcdm_addr_base_i + cachepool_pkg::TCDMSize - cachepool_pkg::SpmStackSize <= core_req_chan[h][i].addr)
            && (core_req_chan[h][i].addr < tcdm_addr_base_i + cachepool_pkg::TCDMSize)) begin
          core_req_sel[h][i] = SpmStack;
        end else if ((tcdm_addr_base_i <= core_req_chan[h][i].addr)
            && (core_req_chan[h][i].addr < tcdm_addr_base_i + cachepool_pkg::TotStackSize)) begin
          core_req_sel[h][i] = CacheMem;
        end else if ((cachepool_pkg::DramAddr <= core_req_chan[h][i].addr)
            && (core_req_chan[h][i].addr < cachepool_pkg::DramAddr + cachepool_pkg::DramSize)) begin
          core_req_sel[h][i] = CacheMem;
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
      .clk_i            (clk_i               ),
      .rst_ni           (rst_ni              ),
      .slv_req_i        (core_req_chan  [h]  ),
      .slv_req_valid_i  (core_req_valid [h]  ),
      .slv_req_ready_o  (core_req_ready [h]  ),
      .slv_rsp_o        (core_rsp_chan  [h]  ),
      .slv_rsp_valid_o  (core_rsp_valid [h]  ),
      .slv_rsp_ready_i  (core_rsp_ready [h]  ),
      .slv_sel_i        (core_req_sel   [h]  ),
      .slv_rr_i         ('0                  ),
      .slv_selected_o   (core_selected  [h]  ),
      .mst_req_o        (mem_req_chan   [h]  ),
      .mst_req_valid_o  (mem_req_valid  [h]  ),
      .mst_req_ready_i  (mem_req_ready  [h]  ),
      .mst_rsp_i        (mem_rsp_chan   [h]  ),
      .mst_rr_i         ('0                  ),
      .mst_rsp_valid_i  (mem_rsp_valid  [h]  ),
      .mst_rsp_ready_o  (mem_rsp_ready  [h]  ),
      .mst_sel_i        (mem_rsp_sel    [h]  )
    );

    // TotStack hits get patched with host h's own id regardless of which
    // master won, since the FPU only ever wins here when already gated to owner_id==h.
    assign is_totstack[h] = (tcdm_addr_base_i <= mem_req_chan[h][CacheMem].addr)
                          && (mem_req_chan[h][CacheMem].addr < tcdm_addr_base_i + cachepool_pkg::TotStackSize);

    always_comb begin
      for (int i = 0; i < NrScalarXbarSlv; i++) begin
        mem_req[h][i].q             = mem_req_chan [h][i];
        mem_req[h][i].q_valid       = mem_req_valid[h][i];
        mem_req[h][i].p_ready       = mem_rsp_ready[h][i];
        mem_req[h][i].q.user.is_fpu = (core_selected[h][i] == FpuMst);
      end
      if (is_totstack[h]) begin
        mem_req[h][CacheMem].q.addr[($clog2(cachepool_pkg::TotStackSize)-1)-:$clog2(cachepool_pkg::NumCores)] =
          hart_id_i[h][$clog2(cachepool_pkg::NumCores)-1:0];
      end
      for (int i = 0; i < NrScalarXbarSlv; i++) begin
        mem_rsp_chan [h][i] = mem_rsp[h][i].p;
        mem_rsp_valid[h][i] = mem_rsp[h][i].p_valid;
        mem_req_ready[h][i] = mem_rsp[h][i].q_ready;
        mem_rsp_sel  [h][i] = (mem_rsp[h][i].p.user.is_fpu == FpuMst);
      end
    end

    assign data_req_o[h]     = mem_req[h][Periph];
    assign mem_rsp[h][Periph] = data_rsp_i[h];

    // Host's own dedicated Stack SPM
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
      .clk_i        (clk_i                 ),
      .rst_ni       (rst_ni                ),
      .reqrsp_req_i (mem_req[h][SpmStack]  ),
      .reqrsp_rsp_o (mem_rsp[h][SpmStack]  ),
      .tcdm_req_o   (stack_req[h]          ),
      .tcdm_rsp_i   (stack_rsp[h]          )
    );

    assign stack_valid[h] = stack_req[h].q_valid;
    assign stack_we[h]    = stack_req[h].q.write;
    assign stack_add[h]   = stack_req[h].q.addr[StackAddrWidth+1:2];
    assign stack_wdata[h] = stack_req[h].q.data;
    assign stack_be[h]    = stack_req[h].q.strb;

    assign stack_req_meta[h] = '{
      user:  stack_req[h].q.user,
      valid: stack_req[h].q_valid,
      write: stack_req[h].q.write
    };

    assign stack_rsp[h].p.data  = stack_rdata[h];
    assign stack_rsp[h].p.user  = stack_rsp_meta[h].user;
    assign stack_rsp[h].p.write = stack_rsp_meta[h].write;
    assign stack_rsp[h].p_valid = stack_rsp_meta[h].valid;
    assign stack_rsp[h].q_ready = 1'b1;

    tc_sram_impl #(
      .NumWords  (SpmStackDepth ),
      .DataWidth (DataWidth     ),
      .ByteWidth (8             ),
      .NumPorts  (1             ),
      .Latency   (1             ),
      .SimInit   ("zeros"       )
    ) i_spm_mem  (
      .clk_i     (clk_i             ),
      .rst_ni    (rst_ni            ),
      .impl_i    ('0                ),
      .impl_o    (/* Unused */      ),
      .req_i     (stack_valid[h]    ),
      .we_i      (stack_we[h]       ),
      .addr_i    (stack_add[h]      ),
      .wdata_i   (stack_wdata[h]    ),
      .be_i      (stack_be[h]       ),
      .rdata_o   (stack_rdata[h]    )
    );

    shift_reg #(
      .dtype (stack_meta_t ),
      .Depth (1            )
    ) i_req_meta_pipe (
      .clk_i (clk_i             ),
      .rst_ni(rst_ni            ),
      .d_i   (stack_req_meta[h] ),
      .d_o   (stack_rsp_meta[h] )
    );

    // Host's own dedicated scalar TCDM port to the cache.
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
      .clk_i        (clk_i                              ),
      .rst_ni       (rst_ni                             ),
      .reqrsp_req_i (mem_req[h][CacheMem]               ),
      .reqrsp_rsp_o (mem_rsp[h][CacheMem]               ),
      .tcdm_req_o   (tcdm_req_o[NumMemPortsPerSpatz+h]  ),
      .tcdm_rsp_i   (tcdm_rsp_i[NumMemPortsPerSpatz+h]  )
    );
    // Scalar port: left on its existing unconditional-accept behavior for now.
    assign tcdm_rsp_ready_o[NumMemPortsPerSpatz+h] = 1'b1;
  end

endmodule
