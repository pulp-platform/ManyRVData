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
    /// Wide AXI ports to cluster level
    output axi_out_req_t        [GroupWideAxiPorts-1:0] axi_wide_req_o,
    input  axi_out_resp_t       [GroupWideAxiPorts-1:0] axi_wide_rsp_i,

    /// Cache refill ports
    output cache_trans_req_t       [NumL1CacheCtrl-1:0] cache_refill_req_o,
    input  cache_trans_rsp_t       [NumL1CacheCtrl-1:0] cache_refill_rsp_i,

    /// Peripheral signals
    output icache_events_t                [NrCores-1:0] icache_events_o,
    input  logic                                        icache_prefetch_enable_i,
    input  logic                          [NrCores-1:0] cl_interrupt_i,
    input  logic             [$clog2(AxiAddrWidth)-1:0] dynamic_offset_i,
    input  logic                                  [3:0] l1d_private_i,
    input  logic                                  [1:0] l1d_insn_i,
    input  logic                                        l1d_insn_valid_i,
    output logic                   [NumL1CacheCtrl-1:0] l1d_insn_ready_o,
    input  logic                   [NumL1CacheCtrl-1:0] l1d_busy_i,

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

  // Tile remote access signals
  // In/Out relative to the tile (out--leave a tile; in--enter a tile)
  tcdm_req_t        [NumTiles-1:0][NrTCDMPortsPerCore-1:0] tile_remote_out_req;
  tcdm_rsp_t        [NumTiles-1:0][NrTCDMPortsPerCore-1:0] tile_remote_out_rsp;
  logic             [NumTiles-1:0][NrTCDMPortsPerCore-1:0] tile_remote_in_ready,      tile_remote_out_ready;
  tcdm_req_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_out_req_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_out_req_valid, tile_remote_out_req_ready;
  tcdm_rsp_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_out_rsp_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_out_rsp_valid, tile_remote_out_rsp_ready;

  tcdm_req_t        [NumTiles-1:0][NrTCDMPortsPerCore-1:0] tile_remote_in_req;
  tcdm_rsp_t        [NumTiles-1:0][NrTCDMPortsPerCore-1:0] tile_remote_in_rsp;
  tcdm_req_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_in_req_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_in_req_valid,  tile_remote_in_req_ready;
  tcdm_rsp_chan_t   [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_in_rsp_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTiles-1:0] tile_remote_in_rsp_valid,  tile_remote_in_rsp_ready;

  // Symmetric xbar, in/out select types are the same
  remote_tile_sel_t [NumTiles-1:0][NrTCDMPortsPerCore-1:0] remote_out_sel_tile, remote_in_sel_tile;
  remote_tile_sel_t [NrTCDMPortsPerCore-1:0][NumTiles-1:0] remote_out_sel_xbar, remote_in_sel_xbar;

  for (genvar t = 0; t < NumTiles; t++) begin
    for (genvar p = 0; p < NrTCDMPortsPerCore; p++) begin
      assign tile_remote_out_req_chan [p][t] = tile_remote_out_req[t][p].q;
      assign tile_remote_out_req_valid[p][t] = tile_remote_out_req[t][p].q_valid;
      assign tile_remote_out_rsp_ready[p][t] = tile_remote_in_ready[t][p];

      assign tile_remote_out_rsp[t][p].p       = tile_remote_out_rsp_chan [p][t];
      assign tile_remote_out_rsp[t][p].p_valid = tile_remote_out_rsp_valid[p][t];
      assign tile_remote_out_rsp[t][p].q_ready = tile_remote_out_req_ready[p][t];

      assign tile_remote_in_req[t][p].q       = tile_remote_in_req_chan [p][t];
      assign tile_remote_in_req[t][p].q_valid = tile_remote_in_req_valid[p][t];
      assign tile_remote_out_ready[t][p]      = tile_remote_in_rsp_ready[p][t];

      assign tile_remote_in_rsp_chan [p][t] = tile_remote_in_rsp[t][p].p;
      assign tile_remote_in_rsp_valid[p][t] = tile_remote_in_rsp[t][p].p_valid;
      assign tile_remote_in_req_ready[p][t] = tile_remote_in_rsp[t][p].q_ready;

      // Selection signals
      assign remote_out_sel_xbar[p][t] = remote_out_sel_tile[t][p];
      assign remote_in_sel_xbar [p][t] = tile_remote_in_rsp_chan[p][t].user.tile_id;
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
      .error_o                  ( error[t]                                                    ),
      // TODO: remove hardcode
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
      .remote_req_o             ( tile_remote_out_req[t]                                      ),
      .remote_req_dst_o         ( remote_out_sel_tile[t]                                      ),
      .remote_rsp_i             ( tile_remote_out_rsp[t]                                      ),
      .remote_rsp_ready_i       ( tile_remote_out_ready[t]                                    ),
      .remote_req_i             ( tile_remote_in_req [t]                                      ),
      .remote_rsp_o             ( tile_remote_in_rsp [t]                                      ),
      .remote_rsp_ready_o       ( tile_remote_in_ready[t]                                     ),
      // Cache Refill Ports
      .cache_refill_req_o       ( cache_refill_req_o[t*NumL1CtrlTile+:NumL1CtrlTile]          ),
      .cache_refill_rsp_i       ( cache_refill_rsp_i[t*NumL1CtrlTile+:NumL1CtrlTile]          ),
      // BootROM / Core-side Cache Bypass
      .axi_wide_req_o           ( axi_wide_req_o    [t*TileWideAxiPorts+:TileWideAxiPorts]    ),
      .axi_wide_rsp_i           ( axi_wide_rsp_i    [t*TileWideAxiPorts+:TileWideAxiPorts]    ),
      // Peripherals
      .icache_events_o          ( /* unused */                                                ),
      .icache_prefetch_enable_i ( icache_prefetch_enable_i                                    ),
      .cl_interrupt_i           ( cl_interrupt_i    [t*NumCoresTile+:NumCoresTile]            ),
      .dynamic_offset_i         ( dynamic_offset_i                                            ),
      .l1d_insn_i               ( l1d_insn_i                                                  ),
      .l1d_private_i            ( l1d_private_i                                               ),
      .l1d_insn_valid_i         ( l1d_insn_valid_i                                            ),
      .l1d_insn_ready_o         ( l1d_insn_ready_o  [t*NumL1CtrlTile+:NumL1CtrlTile]          ),
      .l1d_busy_i               ( l1d_busy_i        [t*NumL1CtrlTile+:NumL1CtrlTile]          )
    );
  end

  // ------------
  // Remote XBar
  // ------------

  for (genvar p = 0; p < NrTCDMPortsPerCore; p++) begin : gen_remote_tile_xbar

    // Decide which tile to go
    reqrsp_xbar #(
      .NumInp           (NumTiles                     ),
      .NumOut           (NumTiles                     ),
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
