// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"
`include "mem_interface/assign.svh"
`include "mem_interface/typedef.svh"
`include "register_interface//assign.svh"
`include "register_interface/typedef.svh"
`include "reqrsp_interface/assign.svh"
`include "reqrsp_interface/typedef.svh"
`include "snitch_vm/typedef.svh"
`include "tcdm_interface/assign.svh"
`include "tcdm_interface/typedef.svh"

/// Group implementation for CachePool
module cachepool_group
  import cachepool_pkg::*;
  import spatz_pkg::*;
  import fpnew_pkg::fpu_implementation_t;
  import snitch_pma_pkg::snitch_pma_t;
  import snitch_icache_pkg::icache_events_t;
  #(
    /// Width of physical address.
    parameter int unsigned                              AxiAddrWidth              = 48,
    /// Width of AXI port.
    parameter int unsigned                              AxiDataWidth              = 512,
    /// AXI: id width in.
    parameter int unsigned                              AxiIdWidthIn              = 2,
    /// AXI: id width out.
    parameter int unsigned                              AxiIdWidthOut             = 2,
    /// AXI: user width.
    parameter int unsigned                              AxiUserWidth              = 1,
    /// Address from which to fetch the first instructions.
    parameter logic                              [31:0] BootAddr                  = 32'h0,
    /// Address to indicate start of UART
    parameter logic                              [31:0] UartAddr                  = 32'h0,
    /// The total amount of cores.
    parameter int unsigned                              NrCores                   = 8,
    /// Data/TCDM memory depth per cut (in words).
    parameter int unsigned                              TCDMDepth                 = 1024,
    /// Cluster peripheral address region size (in kB).
    parameter int unsigned                              ClusterPeriphSize         = 64,
    /// Number of TCDM Banks.
    parameter int unsigned                              NrBanks                   = 2 * NrCores,
    /// Size of DMA AXI buffer.
    parameter int unsigned                              DMAAxiReqFifoDepth        = 3,
    /// Size of DMA request fifo.
    parameter int unsigned                              DMAReqFifoDepth           = 3,
    /// Width of a single icache line.
    parameter     unsigned                              ICacheLineWidth           = 0,
    /// Number of icache lines per set.
    parameter int unsigned                              ICacheLineCount           = 0,
    /// Number of icache sets.
    parameter int unsigned                              ICacheSets                = 0,
    parameter snitch_pma_t                              SnitchPMACfg              = '{default: 0},
    /// # Core-global parameters
    /// FPU configuration.
    parameter fpu_implementation_t                      FPUImplementation         = fpu_implementation_t'(0),
    /// Spatz FPU/IPU Configuration
    parameter int unsigned                              NumSpatzFPUs              = 4,
    parameter int unsigned                              NumSpatzIPUs              = 1,
    /// Per-core enabling of the custom `Xdma` ISA extensions.
    parameter bit                         [NrCores-1:0] Xdma                      = '{default: '0},
    /// # Per-core parameters
    /// Per-core integer outstanding loads
    parameter int unsigned                              NumIntOutstandingLoads    = 0,
    /// Per-core integer outstanding memory operations (load and stores)
    parameter int unsigned                              NumIntOutstandingMem      = 0,
    /// Per-core Spatz outstanding loads
    parameter int unsigned                              NumSpatzOutstandingLoads  = 0,
    /// ## Timing Tuning Parameters
    /// Insert Pipeline registers into off-loading path (response)
    parameter bit                                       RegisterOffloadRsp        = 1'b0,
    /// Insert Pipeline registers into data memory path (request)
    parameter bit                                       RegisterCoreReq           = 1'b0,
    /// Insert Pipeline registers into data memory path (response)
    parameter bit                                       RegisterCoreRsp           = 1'b0,
    /// Insert Pipeline registers after each memory cut
    parameter bit                                       RegisterTCDMCuts          = 1'b0,
    /// Decouple external AXI plug
    parameter bit                                       RegisterExt               = 1'b0,
    parameter axi_pkg::xbar_latency_e                   XbarLatency               = axi_pkg::CUT_ALL_PORTS,
    /// Outstanding transactions on the AXI network
    parameter int unsigned                              MaxMstTrans               = 4,
    parameter int unsigned                              MaxSlvTrans               = 4,
    /// # Interface
    /// AXI Ports
    parameter type                                      axi_in_req_t              = logic,
    parameter type                                      axi_in_resp_t             = logic,
    parameter type                                      axi_narrow_req_t          = logic,
    parameter type                                      axi_narrow_resp_t         = logic,
    parameter type                                      axi_out_req_t             = logic,
    parameter type                                      axi_out_resp_t            = logic,
    /// SRAM configuration
    parameter type                                      impl_in_t                 = logic,
    // Memory latency parameter. Most of the memories have a read latency of 1. In
    // case you have memory macros which are pipelined you want to adjust this
    // value here. This only applies to the TCDM. The instruction cache macros will break!
    // In case you are using the `RegisterTCDMCuts` feature this adds an
    // additional cycle latency, which is taken into account here.
    parameter int unsigned                              MemoryMacroLatency        = 1 + RegisterTCDMCuts,
    /// # SRAM Configuration rules needed: L1D Tag + L1D Data + L1D FIFO + L1I Tag + L1I Data
    /*** ATTENTION: `NrSramCfg` should be changed if `L1NumDataBank` and `L1NumTagBank` is changed ***/
    parameter int unsigned                              NrSramCfg                 = 1
  ) (
    /// System clock.
    input  logic                                        clk_i,
    /// Asynchronous active high reset. This signal is assumed to be _async_.
    input  logic                                        rst_ni,
    /// Per-core debug request signal. Asserting this signals puts the
    /// corresponding core into debug mode. This signal is assumed to be _async_.
    input  logic                          [NrCores-1:0] debug_req_i,
    /// Machine external interrupt pending. Usually those interrupts come from a
    /// platform-level interrupt controller. This signal is assumed to be _async_.
    input  logic                          [NrCores-1:0] meip_i,
    /// Machine timer interrupt pending. Usually those interrupts come from a
    /// core-local interrupt controller such as a timer/RTC. This signal is
    /// assumed to be _async_.
    input  logic                          [NrCores-1:0] mtip_i,
    /// Core software interrupt pending. Usually those interrupts come from
    /// another core to facilitate inter-processor-interrupts. This signal is
    /// assumed to be _async_.
    input  logic                          [NrCores-1:0] msip_i,
    /// First hartid of the cluster. Cores of a cluster are monotonically
    /// increasing without a gap, i.e., a cluster with 8 cores and a
    /// `hart_base_id_i` of 5 get the hartids 5 - 12.
    input  logic                                  [9:0] hart_base_id_i,
    /// Base address of cluster. TCDM and cluster peripheral location are derived from
    /// it. This signal is pseudo-static.
    input  axi_addr_t                                   cluster_base_addr_i,
    /// Partitioning address
    input  axi_addr_t                                   private_start_addr_i,
    /// AXI Narrow out-port (UART/Peripheral)
    output axi_narrow_req_t   [GroupNarrowAxiPorts-1:0] axi_narrow_req_o,
    input  axi_narrow_resp_t  [GroupNarrowAxiPorts-1:0] axi_narrow_rsp_i,

    /// DRAM refill reqrsp ports (post-xbar, one per L2 channel)
    output l2_req_t        [ClusterWideOutAxiPorts-1:0] l2_req_o,
    input  l2_rsp_t        [ClusterWideOutAxiPorts-1:0] l2_rsp_i,

    /// Peripheral signals
    output icache_events_t                [NrCores-1:0] icache_events_o,
    input  logic                                        icache_prefetch_enable_i,
    input  logic                          [NrCores-1:0] cl_interrupt_i,
    input  logic             [$clog2(AxiAddrWidth)-1:0] dynamic_offset_i,
    input  logic                                  [3:0] l1d_private_i,
    input  cache_insn_t                                 l1d_insn_i,
    input  logic                                        l1d_insn_valid_i,
    output logic                       [NumTiles-1:0]   l1d_insn_ready_o,
    input  logic                       [NumTiles-1:0]   l1d_busy_i,

    /// SRAM Configuration
    input  impl_in_t                    [NrSramCfg-1:0] impl_i,
    /// Indicate the program execution is error
    output logic                                        error_o
  );


  // ---------
  // Imports
  // ---------
  import snitch_pkg::*;

  // ---------
  // Constants
  // ---------
  /// Minimum width to hold the core number.
  localparam int unsigned CoreIDWidth     = cf_math_pkg::idx_width(NrCores);
  localparam int unsigned TileIDWidth     = cf_math_pkg::idx_width(NumTiles);

  // Enlarge the address width for Spatz due to cache
  localparam int unsigned TCDMAddrWidth   = L1AddrWidth;

  // Core Request, SoC Request
  localparam int unsigned NrNarrowMasters = 2;

  localparam int unsigned WideIdWidthOut  = AxiIdWidthOut;
  localparam int unsigned WideIdWidthIn   = AxiIdWidthOut;


  // --------
  // Typedefs
  // --------
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [AxiDataWidth-1:0]      data_cache_t;
  typedef logic [AxiDataWidth/8-1:0]    strb_cache_t;
  typedef logic [WideIdWidthIn-1:0]     id_cache_mst_t;
  typedef logic [WideIdWidthOut-1:0]    id_cache_slv_t;
  typedef logic [AxiUserWidth-1:0]      user_cache_t;

  `AXI_TYPEDEF_ALL(axi_mst_cache, addr_t, id_cache_mst_t, data_cache_t, strb_cache_t, user_cache_t)
  `AXI_TYPEDEF_ALL(axi_slv_cache, addr_t, id_cache_slv_t, data_cache_t, strb_cache_t, user_cache_t)

  `REG_BUS_TYPEDEF_ALL(reg_cache, addr_t, data_cache_t, strb_cache_t)

  typedef struct packed {
    int unsigned idx;
    addr_t start_addr;
    addr_t end_addr;
  } xbar_rule_t;

  `SNITCH_VM_TYPEDEF(AxiAddrWidth)

  // ---------------
  // CachePool Tile
  // ---------------

  logic [NumTiles-1:0] error;
  assign error_o = |error;

  // Internal tile-side wide AXI: split into two flat arrays by port function
  // BootROM (TileBootROM=0): muxed into single shared bootrom in this group
  axi_mst_cache_req_t  [NumTiles-1:0] axi_tile_bootrom_req;
  axi_mst_cache_resp_t [NumTiles-1:0] axi_tile_bootrom_rsp;
  // TileMem (TileMem=1): stays in group, fed into axi_to_reqrsp
  axi_mst_cache_req_t  [NumTiles-1:0] axi_tile_mem_req;
  axi_mst_cache_resp_t [NumTiles-1:0] axi_tile_mem_rsp;

  // Mux all per-tile BootROM AXI ports into a single bootrom instance
  axi_bootrom_slv_req_t  axi_bootrom_mux_req;
  axi_bootrom_slv_resp_t axi_bootrom_mux_rsp;

  if (NumTiles > 1) begin : gen_bootrom_mux
    axi_mux #(
      .SlvAxiIDWidth ( WideIdWidthIn            ),
      .slv_aw_chan_t ( axi_mst_cache_aw_chan_t  ),
      .mst_aw_chan_t ( axi_bootrom_slv_aw_chan_t ),
      .w_chan_t      ( axi_mst_cache_w_chan_t   ),
      .slv_b_chan_t  ( axi_mst_cache_b_chan_t   ),
      .mst_b_chan_t  ( axi_bootrom_slv_b_chan_t  ),
      .slv_ar_chan_t ( axi_mst_cache_ar_chan_t  ),
      .mst_ar_chan_t ( axi_bootrom_slv_ar_chan_t ),
      .slv_r_chan_t  ( axi_mst_cache_r_chan_t   ),
      .mst_r_chan_t  ( axi_bootrom_slv_r_chan_t  ),
      .slv_req_t     ( axi_mst_cache_req_t      ),
      .slv_resp_t    ( axi_mst_cache_resp_t     ),
      .mst_req_t     ( axi_bootrom_slv_req_t    ),
      .mst_resp_t    ( axi_bootrom_slv_resp_t   ),
      .NoSlvPorts    ( NumTiles                 ),
      .FallThrough   ( 0                        ),
      .SpillAw       ( XbarLatency[4]           ),
      .SpillW        ( XbarLatency[3]           ),
      .SpillB        ( XbarLatency[2]           ),
      .SpillAr       ( XbarLatency[1]           ),
      .SpillR        ( XbarLatency[0]           ),
      .MaxWTrans     ( 2                        )
    ) i_axi_bootrom_mux (
      .clk_i      ( clk_i                ),
      .rst_ni     ( rst_ni               ),
      .test_i     ( '0                   ),
      .slv_reqs_i ( axi_tile_bootrom_req ),
      .slv_resps_o( axi_tile_bootrom_rsp ),
      .mst_req_o  ( axi_bootrom_mux_req  ),
      .mst_resp_i ( axi_bootrom_mux_rsp  )
    );
  end else begin : gen_bootrom_connect
    // NumTiles==1: direct connect, no ID widening needed
    assign axi_bootrom_mux_req             = axi_bootrom_slv_req_t'(axi_tile_bootrom_req[0]);
    assign axi_tile_bootrom_rsp[0]         = axi_mst_cache_resp_t'(axi_bootrom_mux_rsp);
  end

  // Single BootROM instance shared across all tiles in the group
  `REG_BUS_TYPEDEF_ALL(reg_bootrom, addr_t, data_cache_t, strb_cache_t)
  reg_bootrom_req_t bootrom_reg_req;
  reg_bootrom_rsp_t bootrom_reg_rsp;

  axi_to_reg #(
    .ADDR_WIDTH         ( AxiAddrWidth           ),
    .DATA_WIDTH         ( AxiDataWidth           ),
    .AXI_MAX_WRITE_TXNS ( 1                      ),
    .AXI_MAX_READ_TXNS  ( 1                      ),
    .DECOUPLE_W         ( 0                      ),
    .ID_WIDTH           ( BootRomAxiSlvIdWidth   ),
    .USER_WIDTH         ( AxiUserWidth           ),
    .axi_req_t          ( axi_bootrom_slv_req_t  ),
    .axi_rsp_t          ( axi_bootrom_slv_resp_t ),
    .reg_req_t          ( reg_bootrom_req_t      ),
    .reg_rsp_t          ( reg_bootrom_rsp_t      )
  ) i_axi_to_reg_bootrom (
    .clk_i      ( clk_i              ),
    .rst_ni     ( rst_ni             ),
    .testmode_i ( 1'b0               ),
    .axi_req_i  ( axi_bootrom_mux_req ),
    .axi_rsp_o  ( axi_bootrom_mux_rsp ),
    .reg_req_o  ( bootrom_reg_req    ),
    .reg_rsp_i  ( bootrom_reg_rsp    )
  );

  bootrom i_bootrom (
    .clk_i   ( clk_i                             ),
    .req_i   ( bootrom_reg_req.valid             ),
    .addr_i  ( addr_t'(bootrom_reg_req.addr)     ),
    .rdata_o ( bootrom_reg_rsp.rdata             )
  );

  `FF(bootrom_reg_rsp.ready, bootrom_reg_req.valid, 1'b0)
  assign bootrom_reg_rsp.error = 1'b0;

  // Cache refill ports from tiles (NumL1CacheCtrl = NumCores total)
  cache_trans_req_t [NumL1CacheCtrl-1:0] cache_refill_req;
  cache_trans_rsp_t [NumL1CacheCtrl-1:0] cache_refill_rsp;

  // cache_core_req/rsp: icache-bypass path, one per tile (from axi_to_reqrsp)
  cache_trans_req_t [NumTiles-1:0] cache_core_req;
  cache_trans_rsp_t [NumTiles-1:0] cache_core_rsp;

  // Flat xbar input channels: NumTiles * NumClusterMst ports
  cache_trans_req_chan_t [NumTiles*NumClusterMst-1:0] tile_req_chan;
  cache_trans_rsp_chan_t [NumTiles*NumClusterMst-1:0] tile_rsp_chan;
  logic                  [NumTiles*NumClusterMst-1:0] tile_req_valid, tile_req_ready,
                                                      tile_rsp_valid, tile_rsp_ready;

  // Xbar output channels: one per L2 channel
  cache_trans_req_chan_t [ClusterWideOutAxiPorts-1:0] l2_req_chan;
  cache_trans_rsp_chan_t [ClusterWideOutAxiPorts-1:0] l2_rsp_chan;
  logic                  [ClusterWideOutAxiPorts-1:0] l2_req_valid, l2_req_ready,
                                                      l2_rsp_valid, l2_rsp_ready;

  // Selection types
  typedef logic [$clog2(NumClusterMst*NumTiles)-1:0] l2_sel_t;
  typedef logic [$clog2(ClusterWideOutAxiPorts)  :0] tile_sel_err_t; // one extra bit for OOB
  typedef logic [$clog2(ClusterWideOutAxiPorts)-1:0] tile_sel_t;

  tile_sel_err_t [NumTiles*NumClusterMst-1:0] tile_sel_err;
  tile_sel_t     [NumTiles*NumClusterMst-1:0] tile_sel;
  l2_sel_t       [ClusterWideOutAxiPorts-1:0] tile_selected;
  l2_sel_t       [ClusterWideOutAxiPorts-1:0] l2_sel;
  tile_sel_t     [NumTiles*NumClusterMst-1:0] l2_rsp_rr;

  logic          [NumTiles*NumClusterMst-1:0] rr_lock_d, rr_lock_q;
  tile_sel_t     [NumTiles*NumClusterMst-1:0] l2_prio_d, l2_prio_q;

  // port_id: which xbar input port does each L2 channel response target
  l2_sel_t [ClusterWideOutAxiPorts-1:0] port_id;
  for (genvar i = 0; i < ClusterWideOutAxiPorts; i++) begin
    assign port_id[i] = l2_rsp_i[i].p.user.tile_id * NumClusterMst
                      + l2_rsp_i[i].p.user.bank_id;
  end

  // ---------------------
  // axi_to_reqrsp: TileMem (icache-bypass) path, one per tile
  // ---------------------
  for (genvar t = 0; t < NumTiles; t++) begin : gen_axi_converter
    axi_to_reqrsp #(
      .axi_req_t    ( axi_mst_cache_req_t       ),
      .axi_rsp_t    ( axi_mst_cache_resp_t      ),
      .AddrWidth    ( AxiAddrWidth              ),
      .DataWidth    ( AxiDataWidth              ),
      .UserWidth    ( $bits(refill_user_t)      ),
      .IdWidth      ( AxiIdWidthIn              ),
      .BufDepth     ( NumSpatzOutstandingLoads  ),
      .reqrsp_req_t ( cache_trans_req_t         ),
      .reqrsp_rsp_t ( cache_trans_rsp_t         )
    ) i_axi2reqrsp (
      .clk_i        ( clk_i                     ),
      .rst_ni       ( rst_ni                    ),
      .busy_o       (                           ),
      .axi_req_i    ( axi_tile_mem_req[t]  ),
      .axi_rsp_o    ( axi_tile_mem_rsp[t]  ),
      .reqrsp_req_o ( cache_core_req[t]         ),
      .reqrsp_rsp_i ( cache_core_rsp[t]         )
    );
  end

  // ---------------------
  // Wiring: assemble flat xbar input from icache-bypass and refill paths
  // ---------------------
  // Port layout per tile: p=0 -> icache-bypass (cache_core_req),
  //                       p=1..NumL1CtrlTile -> refill (cache_refill_req)
  localparam int unsigned ReqrspPortsTile = NumL1CtrlTile + 1;
  always_comb begin
    for (int t = 0; t < NumTiles; t++) begin
      for (int p = 0; p < ReqrspPortsTile; p++) begin
        automatic int unsigned xbar_idx   = t * ReqrspPortsTile + p;
        automatic int unsigned refill_idx = t * NumL1CtrlTile   + p - 1;

        if (p == 0) begin
          // icache-bypass path
          tile_req_chan  [xbar_idx]              = cache_core_req[t].q;
          tile_req_chan  [xbar_idx].addr         = scrambleAddr(cache_core_req[t].q.addr);
          tile_req_valid [xbar_idx]              = cache_core_req[t].q_valid;
          cache_core_rsp [t].q_ready             = tile_req_ready[xbar_idx];

          cache_core_rsp [t].p                   = tile_rsp_chan [xbar_idx];
          cache_core_rsp [t].p_valid             = tile_rsp_valid[xbar_idx];
          tile_rsp_ready [xbar_idx]              = cache_core_req[t].p_ready;
          tile_req_chan  [xbar_idx].user.tile_id  = t;
        end else begin
          // refill path
          tile_req_chan  [xbar_idx]              = cache_refill_req[refill_idx].q;
          tile_req_chan  [xbar_idx].addr         = scrambleAddr(cache_refill_req[refill_idx].q.addr);
          tile_req_valid [xbar_idx]              = cache_refill_req[refill_idx].q_valid;
          cache_refill_rsp[refill_idx].q_ready   = tile_req_ready[xbar_idx];

          cache_refill_rsp[refill_idx].p         = tile_rsp_chan [xbar_idx];
          cache_refill_rsp[refill_idx].p_valid   = tile_rsp_valid[xbar_idx];
          tile_rsp_ready [xbar_idx]              = cache_refill_req[refill_idx].p_ready;
          tile_req_chan  [xbar_idx].user.tile_id  = t;
        end
      end
    end
  end

  // ---------------------
  // Address decoder: select L2 channel per xbar input port
  // ---------------------
  typedef struct packed {
    int unsigned idx;
    logic [AxiAddrWidth-1:0] base;
    logic [AxiAddrWidth-1:0] mask;
  } reqrsp_rule_t;

  reqrsp_rule_t [ClusterWideOutAxiPorts-1:0] xbar_rule;
  for (genvar i = 0; i < ClusterWideOutAxiPorts; i++) begin
    assign xbar_rule[i] = '{
      idx  : i,
      base : DramAddr + DramPerChSize * i,
      mask : ({AxiAddrWidth{1'b1}} << $clog2(DramPerChSize))
    };
  end

  logic [$clog2(ClusterWideOutAxiPorts):0] default_idx;
  assign default_idx = ClusterWideOutAxiPorts;

  for (genvar inp = 0; inp < NumClusterMst*NumTiles; inp++) begin : gen_xbar_sel
    addr_decode_napot #(
      .NoIndices ( ClusterWideOutAxiPorts+1 ),
      .NoRules   ( ClusterWideOutAxiPorts   ),
      .addr_t    ( axi_addr_t               ),
      .rule_t    ( reqrsp_rule_t            )
    ) i_snitch_decode_napot (
      .addr_i           ( tile_req_chan[inp].addr ),
      .addr_map_i       ( xbar_rule               ),
      .idx_o            ( tile_sel_err[inp]        ),
      .dec_valid_o      ( /* unused */             ),
      .dec_error_o      ( /* unused */             ),
      .en_default_idx_i ( 1'b1                     ),
      .default_idx_i    ( default_idx              )
    );
    assign tile_sel[inp] = tile_sel_err[inp][$clog2(ClusterWideOutAxiPorts)-1:0];

`ifndef TARGET_SYNTHESIS
    IllegalMemAccess : assert property (
      @(posedge clk_i) disable iff (!rst_ni)
      (tile_req_valid[inp] |-> !tile_sel_err[inp][$clog2(ClusterWideOutAxiPorts)]))
      else $error("Visited illegal address: time=%0t, port=%0d, addr=0x%08h",
                  $time, inp, tile_req_chan[inp].addr);
`endif
  end

  // ---------------------
  // Burst protection logic
  // ---------------------
  if (Burst_Enable) begin : gen_burst_ext_sel
    `FF(rr_lock_q, rr_lock_d, 1'b0)
    `FF(l2_prio_q, l2_prio_d, 1'b0)

    for (genvar port = 0; port < NumTiles*NumClusterMst; port++) begin : gen_rsp_rr
      tile_sel_t l2_rr;
      logic [ClusterWideOutAxiPorts-1:0] arb_valid;

      for (genvar i = 0; i < ClusterWideOutAxiPorts; i++) begin
        assign arb_valid[i] = (port_id[i] == port) & l2_rsp_valid[i];
      end

      always_comb begin
        l2_prio_d[port] = l2_prio_q[port];
        rr_lock_d[port] = rr_lock_q[port];

        if (|arb_valid) begin
          if (rr_lock_q[port]) begin
            l2_prio_d[port] = l2_prio_q[port];
          end else begin
            l2_prio_d[port] = l2_rr;
          end
        end
        l2_rsp_rr[port] = l2_prio_d[port];

        if (tile_rsp_chan[port].user.burst.is_burst & |arb_valid) begin
          if (tile_rsp_chan[port].user.burst.burst_len == 0) begin
            rr_lock_d[port] = 1'b0;
          end else begin
            rr_lock_d[port] = 1'b1;
          end
        end
      end

      rr_arb_tree #(
        .NumIn     ( ClusterWideOutAxiPorts ),
        .DataType  ( logic                  ),
        .ExtPrio   ( 1'b0                   ),
        .AxiVldRdy ( 1'b1                   ),
        .LockIn    ( 1'b1                   )
      ) i_rr_arb_tree (
        .clk_i   ( clk_i               ),
        .rst_ni  ( rst_ni              ),
        .flush_i ( '0                  ),
        .rr_i    ( '0                  ),
        .req_i   ( arb_valid           ),
        .gnt_o   ( /* not used */      ),
        .data_i  ( '0                  ),
        .req_o   ( /* not used */      ),
        .gnt_i   ( tile_rsp_ready[port]),
        .data_o  ( /* not used */      ),
        .idx_o   ( l2_rr               )
      );
    end
  end else begin
    assign l2_prio_d = '0;
    assign l2_prio_q = '0;
    assign rr_lock_d = '0;
    assign rr_lock_q = '0;
    assign l2_rsp_rr = '0;
  end

  // ---------------------
  // Refill (DRAM) xbar
  // ---------------------
  reqrsp_xbar #(
    .NumInp          ( NumClusterMst*NumTiles  ),
    .NumOut          ( ClusterWideOutAxiPorts  ),
    .PipeReg         ( 1'b1                    ),
    .ExtReqPrio      ( 1'b0                    ),
    .ExtRspPrio      ( Burst_Enable            ),
    .tcdm_req_chan_t ( cache_trans_req_chan_t  ),
    .tcdm_rsp_chan_t ( cache_trans_rsp_chan_t  )
  ) i_refill_xbar (
    .clk_i           ( clk_i          ),
    .rst_ni          ( rst_ni         ),
    .slv_req_i       ( tile_req_chan  ),
    .slv_req_valid_i ( tile_req_valid ),
    .slv_req_ready_o ( tile_req_ready ),
    .slv_rsp_o       ( tile_rsp_chan  ),
    .slv_rsp_valid_o ( tile_rsp_valid ),
    .slv_rsp_ready_i ( tile_rsp_ready ),
    .slv_sel_i       ( tile_sel[NumTiles*NumClusterMst-1:0] ),
    .slv_rr_i        ( '0            ),
    .slv_selected_o  ( tile_selected ),
    .mst_req_o       ( l2_req_chan   ),
    .mst_req_valid_o ( l2_req_valid  ),
    .mst_req_ready_i ( l2_req_ready  ),
    .mst_rsp_i       ( l2_rsp_chan   ),
    .mst_rr_i        ( l2_rsp_rr     ),
    .mst_rsp_valid_i ( l2_rsp_valid  ),
    .mst_rsp_ready_o ( l2_rsp_ready  ),
    .mst_sel_i       ( l2_sel        )
  );

  // ---------------------
  // l2_req/rsp packing: bridge xbar channels <-> l2_req_t/l2_rsp_t port
  // ---------------------
  for (genvar ch = 0; ch < ClusterWideOutAxiPorts; ch++) begin : gen_l2_pack
    always_comb begin
      // Request: xbar -> group output port
      l2_req_o[ch].q       = '{
        addr  : l2_req_chan[ch].addr,
        write : l2_req_chan[ch].write,
        amo   : l2_req_chan[ch].amo,
        data  : l2_req_chan[ch].data,
        strb  : l2_req_chan[ch].strb,
        size  : l2_req_chan[ch].size,
        default: '0
      };
      l2_req_o[ch].q.user  = l2_req_chan[ch].user;
      l2_req_o[ch].q_valid = l2_req_valid[ch];
      l2_req_ready[ch]     = l2_rsp_i[ch].q_ready;

      // Response: group input port -> xbar
      l2_rsp_chan[ch]      = '{
        data  : l2_rsp_i[ch].p.data,
        error : l2_rsp_i[ch].p.error,
        write : l2_rsp_i[ch].p.write,
        default: '0
      };
      l2_rsp_chan[ch].user = l2_rsp_i[ch].p.user;
      l2_rsp_valid[ch]     = l2_rsp_i[ch].p_valid;
      l2_req_o[ch].p_ready = l2_rsp_ready[ch];

      // Response demux: which xbar input port does this response target?
      l2_sel[ch]           = l2_rsp_i[ch].p.user.tile_id * NumClusterMst
                           + l2_rsp_i[ch].p.user.bank_id;
    end
  end

  // Tile remote access signals
  // In/Out relative to the tile (out--leave a tile; in--enter a tile)
  // Tile-side flat layout: index = j + r*NrTCDMPortsPerCore (j=xbar idx, r=remote slot within xbar)
  tcdm_req_t        [NumTiles-1:0][NumRemotePortTile-1:0] tile_remote_out_req;
  tcdm_rsp_t        [NumTiles-1:0][NumRemotePortTile-1:0] tile_remote_out_rsp;
  logic             [NumTiles-1:0][NumRemotePortTile-1:0] tile_remote_in_ready, tile_remote_out_ready;

  tcdm_req_t        [NumTiles-1:0][NumRemotePortTile-1:0] tile_remote_in_req;
  tcdm_rsp_t        [NumTiles-1:0][NumRemotePortTile-1:0] tile_remote_in_rsp;

  // Xbar-side: NrTCDMPortsPerCore xbars, each with NumTiles*NumRemotePortCore ports
  // Xbar port index = t*NumRemotePortCore + r
  tcdm_req_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_out_req_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_out_req_valid, tile_remote_out_req_ready;
  tcdm_rsp_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_out_rsp_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_out_rsp_valid, tile_remote_out_rsp_ready;

  tcdm_req_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_in_req_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_in_req_valid,  tile_remote_in_req_ready;
  tcdm_rsp_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_in_rsp_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] tile_remote_in_rsp_valid,  tile_remote_in_rsp_ready;

  // Tile-side selection: narrow type, only carries tile_id
  remote_tile_sel_t [NumTiles-1:0][NumRemotePortTile-1:0]                    remote_out_sel_tile;
  // Xbar-side selection: wider type, encodes tile_id*NumRemotePortCore + core_id%NumRemotePortCore
  remote_xbar_sel_t [NrTCDMPortsPerCore-1:0][NumTiles*NumRemotePortCore-1:0] remote_out_sel_xbar, remote_in_sel_xbar;

  for (genvar t = 0; t < NumTiles; t++) begin
    for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin
      for (genvar r = 0; r < NumRemotePortCore; r++) begin
        // tile flat index: j + r*NrTCDMPortsPerCore
        // xbar port index: t*NumRemotePortCore + r
        assign tile_remote_out_req_chan [j][t*NumRemotePortCore+r] = tile_remote_out_req[t][j+r*NrTCDMPortsPerCore].q;
        assign tile_remote_out_req_valid[j][t*NumRemotePortCore+r] = tile_remote_out_req[t][j+r*NrTCDMPortsPerCore].q_valid;
        assign tile_remote_out_rsp_ready[j][t*NumRemotePortCore+r] = tile_remote_in_ready[t][j+r*NrTCDMPortsPerCore];

        assign tile_remote_out_rsp[t][j+r*NrTCDMPortsPerCore].p       = tile_remote_out_rsp_chan [j][t*NumRemotePortCore+r];
        assign tile_remote_out_rsp[t][j+r*NrTCDMPortsPerCore].p_valid = tile_remote_out_rsp_valid[j][t*NumRemotePortCore+r];
        assign tile_remote_out_rsp[t][j+r*NrTCDMPortsPerCore].q_ready = tile_remote_out_req_ready[j][t*NumRemotePortCore+r];

        assign tile_remote_in_req[t][j+r*NrTCDMPortsPerCore].q       = tile_remote_in_req_chan [j][t*NumRemotePortCore+r];
        assign tile_remote_in_req[t][j+r*NrTCDMPortsPerCore].q_valid = tile_remote_in_req_valid[j][t*NumRemotePortCore+r];
        assign tile_remote_out_ready[t][j+r*NrTCDMPortsPerCore]      = tile_remote_in_rsp_ready[j][t*NumRemotePortCore+r];

        assign tile_remote_in_rsp_chan [j][t*NumRemotePortCore+r] = tile_remote_in_rsp[t][j+r*NrTCDMPortsPerCore].p;
        assign tile_remote_in_rsp_valid[j][t*NumRemotePortCore+r] = tile_remote_in_rsp[t][j+r*NrTCDMPortsPerCore].p_valid;
        assign tile_remote_in_req_ready[j][t*NumRemotePortCore+r] = tile_remote_in_rsp[t][j+r*NrTCDMPortsPerCore].q_ready;

        // Request selection: convert narrow tile_id to wide xbar index by appending
        // core_id % NumRemotePortCore (available in the request channel user field)
        assign remote_out_sel_xbar[j][t*NumRemotePortCore+r] = remote_xbar_sel_t'(
            remote_out_sel_tile[t][j+r*NrTCDMPortsPerCore] * NumRemotePortCore
          + tile_remote_out_req_chan[j][t*NumRemotePortCore+r].user.core_id % NumRemotePortCore);

        // Response selection: recover xbar port from tile_id and core_id in response user field
        assign remote_in_sel_xbar[j][t*NumRemotePortCore+r] = remote_xbar_sel_t'(
            tile_remote_in_rsp_chan[j][t*NumRemotePortCore+r].user.tile_id * NumRemotePortCore
          + tile_remote_in_rsp_chan[j][t*NumRemotePortCore+r].user.core_id % NumRemotePortCore);
      end
    end
  end

  for (genvar t = 0; t < NumTiles; t ++) begin : gen_tiles
    logic [9:0] hart_base_id;
    assign hart_base_id = hart_base_id_i + t * NumCoresTile;

    logic [TileIDWidth-1:0] tile_id;
    assign tile_id = t;

    cachepool_tile #(
      .AxiAddrWidth             ( AxiAddrWidth             ),
      .AxiDataWidth             ( AxiDataWidth             ),
      .AxiIdWidthIn             ( AxiIdWidthIn             ),
      .AxiIdWidthOut            ( WideIdWidthIn            ),
      .AxiUserWidth             ( AxiUserWidth             ),
      .BootAddr                 ( BootAddr                 ),
      .UartAddr                 ( UartAddr                 ),
      .ClusterPeriphSize        ( ClusterPeriphSize        ),
      .NrCores                  ( NumCoresTile             ),
      .TCDMDepth                ( TCDMDepth                ),
      .NrBanks                  ( NrBanks                  ),
      .ICacheLineWidth          ( ICacheLineWidth          ),
      .ICacheLineCount          ( ICacheLineCount          ),
      .ICacheSets               ( ICacheSets               ),
      .FPUImplementation        ( FPUImplementation        ),
      .NumSpatzFPUs             ( NumSpatzFPUs             ),
      .NumSpatzIPUs             ( NumSpatzIPUs             ),
      .SnitchPMACfg             ( SnitchPMACfg             ),
      .NumIntOutstandingLoads   ( NumIntOutstandingLoads   ),
      .NumIntOutstandingMem     ( NumIntOutstandingMem     ),
      .NumSpatzOutstandingLoads ( NumSpatzOutstandingLoads ),
      .axi_in_req_t             ( axi_in_req_t             ),
      .axi_in_resp_t            ( axi_in_resp_t            ),
      .axi_narrow_req_t         ( axi_narrow_req_t         ),
      .axi_narrow_resp_t        ( axi_narrow_resp_t        ),
      .axi_out_req_t            ( axi_mst_cache_req_t      ),
      .axi_out_resp_t           ( axi_mst_cache_resp_t     ),
      .Xdma                     ( Xdma                     ),
      .TileIDWidth              ( TileIDWidth              ),
      .DMAAxiReqFifoDepth       ( DMAAxiReqFifoDepth       ),
      .DMAReqFifoDepth          ( DMAReqFifoDepth          ),
      .RegisterOffloadRsp       ( RegisterOffloadRsp       ),
      .RegisterCoreReq          ( RegisterCoreReq          ),
      .RegisterCoreRsp          ( RegisterCoreRsp          ),
      .RegisterTCDMCuts         ( RegisterTCDMCuts         ),
      .RegisterExt              ( RegisterExt              ),
      .XbarLatency              ( XbarLatency              ),
      .MaxMstTrans              ( MaxMstTrans              ),
      .MaxSlvTrans              ( MaxSlvTrans              )
    ) i_tile (
      .clk_i                    ( clk_i                                                       ),
      .rst_ni                   ( rst_ni                                                      ),
      .impl_i                   ( impl_i                                                      ),
      .error_o                  ( error             [t]                                       ),
      .debug_req_i              ( debug_req_i       [t*NumCoresTile+:NumCoresTile]            ),
      .meip_i                   ( meip_i            [t*NumCoresTile+:NumCoresTile]            ),
      .mtip_i                   ( mtip_i            [t*NumCoresTile+:NumCoresTile]            ),
      .msip_i                   ( msip_i            [t*NumCoresTile+:NumCoresTile]            ),
      .hart_base_id_i           ( hart_base_id                                                ),
      .cluster_base_addr_i      ( cluster_base_addr_i                                         ),
      .tile_id_i                ( tile_id                                                     ),
      .private_start_addr_i     ( private_start_addr_i                                        ),
      // AXI out for UART
      .axi_out_req_o            ( axi_narrow_req_o  [t*TileNarrowAxiPorts+:TileNarrowAxiPorts]),
      .axi_out_resp_i           ( axi_narrow_rsp_i  [t*TileNarrowAxiPorts+:TileNarrowAxiPorts]),
      // Remote Access Ports
      .remote_req_o             ( tile_remote_out_req  [t]                                    ),
      .remote_req_dst_o         ( remote_out_sel_tile  [t]                                    ),
      .remote_rsp_i             ( tile_remote_out_rsp  [t]                                    ),
      .remote_rsp_ready_i       ( tile_remote_out_ready[t]                                    ),
      .remote_req_i             ( tile_remote_in_req   [t]                                    ),
      .remote_rsp_o             ( tile_remote_in_rsp   [t]                                    ),
      .remote_rsp_ready_o       ( tile_remote_in_ready [t]                                    ),
      // Cache Refill Ports (now internal, connected to group-level xbar)
      .cache_refill_req_o       ( cache_refill_req[t*NumL1CtrlTile+:NumL1CtrlTile]            ),
      .cache_refill_rsp_i       ( cache_refill_rsp[t*NumL1CtrlTile+:NumL1CtrlTile]            ),
      // BootROM (goes to cluster) / Core-side Cache Bypass (stays in group)
      .axi_wide_req_o           ( {axi_tile_mem_req[t],     axi_tile_bootrom_req[t]}          ),
      .axi_wide_rsp_i           ( {axi_tile_mem_rsp[t],     axi_tile_bootrom_rsp[t]}          ),
      // Peripherals
      .icache_events_o          ( /* unused */                                                ),
      .icache_prefetch_enable_i ( icache_prefetch_enable_i                                    ),
      .cl_interrupt_i           ( cl_interrupt_i    [t*NumCoresTile+:NumCoresTile]            ),
      .dynamic_offset_i         ( dynamic_offset_i                                            ),
      .l1d_insn_i               ( l1d_insn_i                                                  ),
      .l1d_private_i            ( l1d_private_i                                               ),
      .l1d_insn_valid_i         ( l1d_insn_valid_i                                            ),
      .l1d_insn_ready_o         ( l1d_insn_ready_o  [t]                                       ),
      .l1d_busy_i               ( l1d_busy_i        [t]                                       )
    );
  end

  // ------------
  // Remote XBar
  // ------------

  for (genvar p = 0; p < NrTCDMPortsPerCore; p++) begin : gen_remote_tile_xbar

    // Decide which tile to go
    reqrsp_xbar #(
      .NumInp           (NumTiles * NumRemotePortCore ),
      .NumOut           (NumTiles * NumRemotePortCore ),
      .PipeReg          (1'b1                         ),
      .RspReg           (1'b1                         ),
      .ExtReqPrio       (1'b0                         ),
      .ExtRspPrio       (1'b0                         ),
      .tcdm_req_chan_t  (tcdm_req_chan_t              ),
      .tcdm_rsp_chan_t  (tcdm_rsp_chan_t              )
    ) i_tile_remote_xbar (
      .clk_i            (clk_i                        ),
      .rst_ni           (rst_ni                       ),
      .slv_req_i        (tile_remote_out_req_chan [p] ),
      .slv_req_valid_i  (tile_remote_out_req_valid[p] ),
      .slv_req_ready_o  (tile_remote_out_req_ready[p] ),
      .slv_rsp_o        (tile_remote_out_rsp_chan [p] ),
      .slv_rsp_valid_o  (tile_remote_out_rsp_valid[p] ),
      .slv_rsp_ready_i  (tile_remote_out_rsp_ready[p] ),
      .slv_sel_i        (remote_out_sel_xbar      [p] ),
      .slv_rr_i         ('0                           ),
      .slv_selected_o   (/*selection info in cid*/    ),
      .mst_req_o        (tile_remote_in_req_chan  [p] ),
      .mst_req_valid_o  (tile_remote_in_req_valid [p] ),
      .mst_req_ready_i  (tile_remote_in_req_ready [p] ),
      .mst_rsp_i        (tile_remote_in_rsp_chan  [p] ),
      .mst_rsp_valid_i  (tile_remote_in_rsp_valid [p] ),
      .mst_rsp_ready_o  (tile_remote_in_rsp_ready [p] ),
      .mst_rr_i         ('0                           ),
      .mst_sel_i        (remote_in_sel_xbar       [p] )
    );
  end

endmodule
