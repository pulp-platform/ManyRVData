// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

/// CachePool cluster: instantiates NumGroups groups connected via FlooNoC mesh,
/// with shared L2 memory and peripheral fabric.
module cachepool_cluster
  import cachepool_pkg::*;
  import spatz_pkg::*;
  import fpnew_pkg::fpu_implementation_t;
  import snitch_pma_pkg::snitch_pma_t;
  #(
    /// Width of physical address.
    parameter int                     unsigned               AxiAddrWidth                       = 48,
    /// Width of AXI port.
    parameter int                     unsigned               AxiDataWidth                       = 512,
    /// AXI: id width in.
    parameter int                     unsigned               AxiIdWidthIn                       = 2,
    /// AXI: id width out.
    parameter int                     unsigned               AxiIdWidthOut                      = 2,
    /// AXI: user width.
    parameter int                     unsigned               AxiUserWidth                       = 1,
    /// Address from which to fetch the first instructions.
    parameter logic                            [31:0]        BootAddr                           = 32'h0,
    /// Address to indicate start of UART
    parameter logic                            [31:0]        UartAddr                           = 32'h0,
    /// The total amount of cores.
    parameter int                     unsigned               NrCores                            = 8,
    /// Data/TCDM memory depth per cut (in words).
    parameter int                     unsigned               TCDMDepth                          = 1024,
    /// Cluster peripheral address region size (in kB).
    parameter int                     unsigned               ClusterPeriphSize                  = 64,
    /// Number of TCDM Banks.
    parameter int                     unsigned               NrBanks                            = 2 * NrCores,
    /// Width of a single icache line.
    parameter                         unsigned               ICacheLineWidth                    = 0,
    /// Number of icache lines per set.
    parameter int                     unsigned               ICacheLineCount                    = 0,
    /// Number of icache sets.
    parameter int                     unsigned               ICacheSets                         = 0,
    // PMA Configuration
    parameter snitch_pma_t                                   SnitchPMACfg                       = '{default: 0},
    /// # Core-global parameters
    /// FPU configuration.
    parameter fpu_implementation_t                           FPUImplementation                  = '0,
    /// Spatz FPU/IPU Configuration
    parameter int                     unsigned               NumSpatzFPUs                       = 4,
    parameter int                     unsigned               NumSpatzIPUs                       = 1,
    /// # Per-core parameters
    /// Per-core integer outstanding loads
    parameter int                     unsigned               NumIntOutstandingLoads             = 0,
    /// Per-core integer outstanding memory operations (load and stores)
    parameter int                     unsigned               NumIntOutstandingMem               = 0,
    /// Per-core Spatz outstanding loads
    parameter int                     unsigned               NumSpatzOutstandingLoads           = 0,
    /// ## Timing Tuning Parameters
    /// Insert Pipeline registers into off-loading path (response)
    parameter bit                                            RegisterOffloadRsp                 = 1'b0,
    /// Insert Pipeline registers into data memory path (request)
    parameter bit                                            RegisterCoreReq                    = 1'b0,
    /// Insert Pipeline registers into data memory path (response)
    parameter bit                                            RegisterCoreRsp                    = 1'b0,
    /// Insert Pipeline registers after each memory cut
    parameter bit                                            RegisterTCDMCuts                   = 1'b0,
    /// Decouple external AXI plug
    parameter bit                                            RegisterExt                        = 1'b0,
    parameter axi_pkg::xbar_latency_e                        XbarLatency                        = axi_pkg::CUT_ALL_PORTS,
    /// Outstanding transactions on the AXI network
    parameter int                     unsigned               MaxMstTrans                        = 4,
    parameter int                     unsigned               MaxSlvTrans                        = 4,
    /// # Interface
    /// AXI Ports
    parameter type                                           axi_in_req_t                       = logic,
    parameter type                                           axi_in_resp_t                      = logic,
    parameter type                                           axi_narrow_req_t                   = logic,
    parameter type                                           axi_narrow_resp_t                  = logic,
    parameter type                                           axi_out_req_t                      = logic,
    parameter type                                           axi_out_resp_t                     = logic,
    /// SRAM configuration
    parameter type                                           impl_in_t                          = logic,
    // Memory latency parameter. Most of the memories have a read latency of 1. In
    // case you have memory macros which are pipelined you want to adjust this
    // value here. This only applies to the TCDM. The instruction cache macros will break!
    // In case you are using the `RegisterTCDMCuts` feature this adds an
    // additional cycle latency, which is taken into account here.
    parameter int                     unsigned               MemoryMacroLatency                 = 1 + RegisterTCDMCuts,
    /// # SRAM Configuration rules needed: L1D Tag + L1D Data + L1D FIFO + L1I Tag + L1I Data
    /*** ATTENTION: `NrSramCfg` should be changed if `L1NumDataBank` and `L1NumTagBank` is changed ***/
    parameter int                     unsigned               NrSramCfg                          = 1
  ) (
    /// System clock.
    input  logic                                  clk_i,
    /// Asynchronous active high reset. This signal is assumed to be _async_.
    input  logic                                  rst_ni,
    /// Per-core debug request signal. Asserting this signals puts the
    /// corresponding core into debug mode. This signal is assumed to be _async_.
    input  logic                                  debug_req_i,
    /// End of Computing indicator to notify the host/tb
    output logic          [3:0]                   eoc_o,
    /// Machine external interrupt pending. Usually those interrupts come from a
    /// platform-level interrupt controller. This signal is assumed to be _async_.
    input  logic                                  meip_i,
    /// Machine timer interrupt pending. Usually those interrupts come from a
    /// core-local interrupt controller such as a timer/RTC. This signal is
    /// assumed to be _async_.
    input  logic                                  mtip_i,
    /// Core software interrupt pending. Usually those interrupts come from
    /// another core to facilitate inter-processor-interrupts. This signal is
    /// assumed to be _async_.
    input  logic                                  msip_i,
    /// First hartid of the cluster. Cores of a cluster are monotonically
    /// increasing without a gap, i.e., a cluster with 8 cores and a
    /// `hart_base_id_i` of 5 get the hartids 5 - 12.
    input  logic          [9:0]                   hart_base_id_i,
    /// Base address of cluster. TCDM and cluster peripheral location are derived from
    /// it. This signal is pseudo-static.
    input  logic          [AxiAddrWidth-1:0]      cluster_base_addr_i,
    /// Per-cluster probe on the cluster status. Can be written by the cores to indicate
    /// to the overall system that the cluster is executing something.
    output logic                                  cluster_probe_o,
    /// AXI Core cluster in-port.
    input  axi_in_req_t                           axi_in_req_i,
    output axi_in_resp_t                          axi_in_resp_o,
    /// AXI Narrow out-port (UART)
    output axi_uart_req_t                         axi_narrow_req_o,
    input  axi_uart_resp_t                        axi_narrow_resp_i,
    /// AXI Core cluster out-port to main memory.
    output axi_out_req_t  [ClusterWideOutAxiPorts-1:0]     axi_out_req_o,
    input  axi_out_resp_t [ClusterWideOutAxiPorts-1:0]     axi_out_resp_i,
    /// SRAM Configuration: L1D Data + L1D Tag + L1D FIFO + L1I Data + L1I Tag
    input  impl_in_t      [NrSramCfg-1:0]         impl_i,
    /// Indicate the program execution is error
    output logic                                  error_o
  );
  // ---------
  // Imports
  // ---------
  import snitch_pkg::*;

  // ---------
  // Constants
  // ---------
  localparam int unsigned WideIdWidthOut  = AxiIdWidthOut;
  localparam int unsigned WideIdWidthIn   = WideIdWidthOut - ClusterRouteIdWidth - GroupMuxIdBits;

  // Pre-mux AXI ID width: per-group reqrsp_to_axi output.
  // The multi-group axi_mux adds GroupMuxIdBits on top to reach WideIdWidthOut.
  localparam int unsigned WideIdWidthPreMux = WideIdWidthOut - GroupMuxIdBits;

  // --------
  // Typedefs
  // --------
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [AxiDataWidth-1:0]      data_cache_t;
  typedef logic [AxiDataWidth/8-1:0]    strb_cache_t;
  typedef logic [WideIdWidthIn-1:0]     id_cache_mst_t;
  typedef logic [WideIdWidthOut-1:0]    id_cache_slv_t;
  typedef logic [AxiUserWidth-1:0]      user_cache_t;

  // reqrsp_to_axi output type: full GroupAxiIdOutWidth-bit IDs (decoupled from WideIdWidthPreMux
  // which now equals WideRefillIdWidth after per-group ID remapping).
  typedef logic [GroupAxiIdOutWidth-1:0] id_cache_premux_t;
  // Remapper output / mux slave input type: bounded WideRefillIdWidth-bit IDs.
  typedef logic [WideIdWidthPreMux-1:0]  id_cache_remap_t;

  `AXI_TYPEDEF_ALL(axi_mst_cache,    addr_t, id_cache_mst_t,    data_cache_t, strb_cache_t, user_cache_t)
  // Post-mux AXI types (same as before — used for axi_cut and output).
  `AXI_TYPEDEF_ALL(axi_slv_cache,    addr_t, id_cache_slv_t,    data_cache_t, strb_cache_t, user_cache_t)
  // reqrsp_to_axi output AXI types (full GroupAxiIdOutWidth-bit IDs).
  `AXI_TYPEDEF_ALL(axi_premux_cache, addr_t, id_cache_premux_t, data_cache_t, strb_cache_t, user_cache_t)
  // Remapped AXI types: WideRefillIdWidth-bit IDs, fed into the inter-group mux / future NoC.
  `AXI_TYPEDEF_ALL(axi_remap_cache,  addr_t, id_cache_remap_t,  data_cache_t, strb_cache_t, user_cache_t)

  // ----------------
  // Wire Definitions
  // ----------------
  // 1. AXI
  // Post-mux wide AXI (one per L2 channel, merged across groups).
  axi_slv_cache_req_t  [ClusterWideOutAxiPorts-1:0] wide_axi_slv_req;
  axi_slv_cache_resp_t [ClusterWideOutAxiPorts-1:0] wide_axi_slv_rsp;
  // Per-group pre-mux wide AXI (per group, per L2 channel): full GroupAxiIdOutWidth-bit IDs.
  axi_premux_cache_req_t  [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] wide_axi_premux_req;
  axi_premux_cache_resp_t [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] wide_axi_premux_rsp;
  // Per-group remapped wide AXI: WideRefillIdWidth-bit IDs, fed into the inter-group mux.
  axi_remap_cache_req_t   [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] wide_axi_remap_req;
  axi_remap_cache_resp_t  [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] wide_axi_remap_rsp;
  // Narrow AXI per tile (UART + Periph).
  axi_narrow_req_t     [NumTiles-1:0][1:0]          axi_out_req;
  axi_narrow_resp_t    [NumTiles-1:0][1:0]          axi_out_resp;

  // 3. Peripherals
  axi_addr_t                                private_start_addr;
  logic                                     icache_prefetch_enable;
  logic         [$clog2(L1AddrWidth)-1:0]   dynamic_offset;
  cache_insn_t                              l1d_insn;
  logic                                     l1d_insn_valid;
  logic         [NumTiles-1:0]              l1d_insn_ready;
  logic         [NumTiles-1:0]              l1d_busy;
  logic         [$clog2(NumL1CtrlTile):0]   l1d_private;

  // Per-group error signals.
  logic              [NumGroups-1:0]       group_error;

  // Inter-group NoC mesh signals (indexed by group, then direction, then port)
  noc_group_req_t [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_out;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_out_valid;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_out_ready;
  noc_group_req_t [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_in;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_in_valid;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_in_ready;
  noc_group_rsp_t [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_out;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_out_valid;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_out_ready;
  noc_group_rsp_t [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_in;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_in_valid;
  logic           [NumGroups-1:0][3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_in_ready;

  // ---------------
  // CachePool Group
  // ---------------

  // Per-group L2 reqrsp ports (one per L2 channel per group).
  l2_req_t [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] l2_req;
  l2_rsp_t [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] l2_rsp;

  assign error_o = |group_error;

  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_group_y
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_group_x
      // Flat group index: g = gy * NumGroupsX + gx
      localparam int unsigned g = gy * NumGroupsX + gx;
      cachepool_group_noc_wrapper #(
        .AxiAddrWidth             ( AxiAddrWidth             ),
        .AxiDataWidth             ( AxiDataWidth             ),
        .AxiIdWidthIn             ( AxiIdWidthIn             ),
        .AxiIdWidthOut            ( WideIdWidthIn            ),
        .AxiUserWidth             ( AxiUserWidth             ),
        .BootAddr                 ( BootAddr                 ),
        .UartAddr                 ( UartAddr                 ),
        .ClusterPeriphSize        ( ClusterPeriphSize        ),
        .NrCores                  ( NumCoreGroup             ),
        .TCDMDepth                ( TCDMDepth                ),
        .NrBanks                  ( NrBanks / NumGroups      ),
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
        .RegisterOffloadRsp       ( RegisterOffloadRsp       ),
        .RegisterCoreReq          ( RegisterCoreReq          ),
        .RegisterCoreRsp          ( RegisterCoreRsp          ),
        .RegisterTCDMCuts         ( RegisterTCDMCuts         ),
        .RegisterExt              ( RegisterExt              ),
        .XbarLatency              ( XbarLatency              ),
        .MaxMstTrans              ( MaxMstTrans              ),
        .MaxSlvTrans              ( MaxSlvTrans              )
      ) i_group (
        .clk_i                    ( clk_i                                           ),
        .rst_ni                   ( rst_ni                                          ),
        .impl_i                   ( impl_i                                          ),
        .error_o                  ( group_error[g]                                  ),
        .debug_req_i              ( debug_req_i                                     ),
        .meip_i                   ( meip_i                                          ),
        .mtip_i                   ( mtip_i                                          ),
        .msip_i                   ( msip_i                                          ),
        .hart_base_id_i           ( hart_base_id_i + 10'(g * NumCoreGroup)          ),
        .tile_base_id_i           ( TileIDWidth'(g * NumTilesPerGroup)              ),
        .cluster_base_addr_i      ( cluster_base_addr_i                             ),
        .private_start_addr_i     ( private_start_addr                              ),
        .axi_narrow_req_o         ( axi_out_req [g*NumTilesPerGroup +: NumTilesPerGroup]  ),
        .axi_narrow_rsp_i         ( axi_out_resp[g*NumTilesPerGroup +: NumTilesPerGroup]  ),
        // DRAM refill reqrsp (post-xbar, one per L2 channel)
        .l2_req_o                 ( l2_req[g]                                       ),
        .l2_rsp_i                 ( l2_rsp[g]                                       ),
        // Peripherals
        .icache_events_o          ( /* unused */                                    ),
        .icache_prefetch_enable_i ( icache_prefetch_enable                          ),
        .cl_interrupt_i           ( '0                                              ),
        .dynamic_offset_i         ( dynamic_offset                                  ),
        .l1d_private_i            ( l1d_private                                     ),
        .l1d_insn_i               ( l1d_insn                                        ),
        .l1d_insn_valid_i         ( l1d_insn_valid                                  ),
        .l1d_insn_ready_o         ( l1d_insn_ready[g*NumTilesPerGroup +: NumTilesPerGroup]),
        .l1d_busy_i               ( l1d_busy      [g*NumTilesPerGroup +: NumTilesPerGroup]),
        .group_xy_id_i            ( group_xy_id_t'{x:       gx,
                                                   y:       gy,
                                                   port_id: 1'b0}                          ),
        .noc_req_o                ( noc_req_out      [g]                                   ),
        .noc_req_valid_o          ( noc_req_out_valid[g]                                   ),
        .noc_req_ready_i          ( noc_req_out_ready[g]                                   ),
        .noc_req_i                ( noc_req_in       [g]                                   ),
        .noc_req_valid_i          ( noc_req_in_valid [g]                                   ),
        .noc_req_ready_o          ( noc_req_in_ready [g]                                   ),
        .noc_rsp_o                ( noc_rsp_out      [g]                                   ),
        .noc_rsp_valid_o          ( noc_rsp_out_valid[g]                                   ),
        .noc_rsp_ready_i          ( noc_rsp_out_ready[g]                                   ),
        .noc_rsp_i                ( noc_rsp_in       [g]                                   ),
        .noc_rsp_valid_i          ( noc_rsp_in_valid [g]                                   ),
        .noc_rsp_ready_o          ( noc_rsp_in_ready [g]                                   )
      );
    end
  end

  // ----------------------------
  // Inter-group NoC mesh wiring
  // ----------------------------

  // East-West (horizontal) interior connections
  for (genvar gx = 0; gx < NumGroupsX-1; gx++) begin : gen_ew_conn
    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_ew_conn_y
      // East output of (gx,gy) → West input of (gx+1,gy)
      assign noc_req_in      [gx+1 + gy*NumGroupsX][3] = noc_req_out      [gx + gy*NumGroupsX][1];
      assign noc_req_in_valid[gx+1 + gy*NumGroupsX][3] = noc_req_out_valid[gx + gy*NumGroupsX][1];
      assign noc_req_out_ready[gx  + gy*NumGroupsX][1] = noc_req_in_ready [gx+1 + gy*NumGroupsX][3];
      assign noc_rsp_in      [gx+1 + gy*NumGroupsX][3] = noc_rsp_out      [gx + gy*NumGroupsX][1];
      assign noc_rsp_in_valid[gx+1 + gy*NumGroupsX][3] = noc_rsp_out_valid[gx + gy*NumGroupsX][1];
      assign noc_rsp_out_ready[gx  + gy*NumGroupsX][1] = noc_rsp_in_ready [gx+1 + gy*NumGroupsX][3];
      // West output of (gx+1,gy) → East input of (gx,gy)
      assign noc_req_in      [gx   + gy*NumGroupsX][1] = noc_req_out      [gx+1 + gy*NumGroupsX][3];
      assign noc_req_in_valid[gx   + gy*NumGroupsX][1] = noc_req_out_valid[gx+1 + gy*NumGroupsX][3];
      assign noc_req_out_ready[gx+1 + gy*NumGroupsX][3] = noc_req_in_ready[gx  + gy*NumGroupsX][1];
      assign noc_rsp_in      [gx   + gy*NumGroupsX][1] = noc_rsp_out      [gx+1 + gy*NumGroupsX][3];
      assign noc_rsp_in_valid[gx   + gy*NumGroupsX][1] = noc_rsp_out_valid[gx+1 + gy*NumGroupsX][3];
      assign noc_rsp_out_ready[gx+1 + gy*NumGroupsX][3] = noc_rsp_in_ready[gx  + gy*NumGroupsX][1];
    end
  end

  // North-South (vertical) interior connections
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_ns_conn
    for (genvar gy = 0; gy < NumGroupsY-1; gy++) begin : gen_ns_conn_y
      // North output of (gx,gy) (dir 0) → South input of (gx,gy+1) (dir 2)
      assign noc_req_in      [gx + (gy+1)*NumGroupsX][2] = noc_req_out      [gx + gy*NumGroupsX][0];
      assign noc_req_in_valid[gx + (gy+1)*NumGroupsX][2] = noc_req_out_valid[gx + gy*NumGroupsX][0];
      assign noc_req_out_ready[gx +  gy   *NumGroupsX][0] = noc_req_in_ready[gx + (gy+1)*NumGroupsX][2];
      assign noc_rsp_in      [gx + (gy+1)*NumGroupsX][2] = noc_rsp_out      [gx + gy*NumGroupsX][0];
      assign noc_rsp_in_valid[gx + (gy+1)*NumGroupsX][2] = noc_rsp_out_valid[gx + gy*NumGroupsX][0];
      assign noc_rsp_out_ready[gx +  gy   *NumGroupsX][0] = noc_rsp_in_ready[gx + (gy+1)*NumGroupsX][2];
      // South output of (gx,gy+1) (dir 2) → North input of (gx,gy) (dir 0)
      assign noc_req_in      [gx +  gy   *NumGroupsX][0] = noc_req_out      [gx + (gy+1)*NumGroupsX][2];
      assign noc_req_in_valid[gx +  gy   *NumGroupsX][0] = noc_req_out_valid[gx + (gy+1)*NumGroupsX][2];
      assign noc_req_out_ready[gx + (gy+1)*NumGroupsX][2] = noc_req_in_ready[gx +  gy   *NumGroupsX][0];
      assign noc_rsp_in      [gx +  gy   *NumGroupsX][0] = noc_rsp_out      [gx + (gy+1)*NumGroupsX][2];
      assign noc_rsp_in_valid[gx +  gy   *NumGroupsX][0] = noc_rsp_out_valid[gx + (gy+1)*NumGroupsX][2];
      assign noc_rsp_out_ready[gx + (gy+1)*NumGroupsX][2] = noc_rsp_in_ready[gx +  gy   *NumGroupsX][0];
    end
  end

  // West boundary: gx=0 has no West neighbor (dir 3)
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_west_bnd
    assign noc_req_in      [gy*NumGroupsX][3]  = '0;
    assign noc_req_in_valid[gy*NumGroupsX][3]  = '0;
    assign noc_req_out_ready[gy*NumGroupsX][3] = '1;
    assign noc_rsp_in      [gy*NumGroupsX][3]  = '0;
    assign noc_rsp_in_valid[gy*NumGroupsX][3]  = '0;
    assign noc_rsp_out_ready[gy*NumGroupsX][3] = '1;
  end

  // East boundary: gx=NumGroupsX-1 has no East neighbor (dir 1)
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_east_bnd
    assign noc_req_in      [(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_req_in_valid[(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_req_out_ready[(NumGroupsX-1) + gy*NumGroupsX][1] = '1;
    assign noc_rsp_in      [(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_rsp_in_valid[(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_rsp_out_ready[(NumGroupsX-1) + gy*NumGroupsX][1] = '1;
  end

  // South boundary: gy=0 has no South neighbor (dir 2)
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_south_bnd
    assign noc_req_in      [gx][2]  = '0;
    assign noc_req_in_valid[gx][2]  = '0;
    assign noc_req_out_ready[gx][2] = '1;
    assign noc_rsp_in      [gx][2]  = '0;
    assign noc_rsp_in_valid[gx][2]  = '0;
    assign noc_rsp_out_ready[gx][2] = '1;
  end

  // North boundary: gy=NumGroupsY-1 has no North neighbor (dir 0)
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_north_bnd
    assign noc_req_in      [gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_req_in_valid[gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_req_out_ready[gx + (NumGroupsY-1)*NumGroupsX][0] = '1;
    assign noc_rsp_in      [gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_rsp_in_valid[gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_rsp_out_ready[gx + (NumGroupsY-1)*NumGroupsX][0] = '1;
  end

  // -------------
  // To Main Memory: reqrsp_to_axi per group, then axi_mux across groups
  // -------------

  // Step 1: Per-group reqrsp_to_axi conversion.
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_per_group_l2
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_per_group_l2
      localparam int unsigned g = gy * NumGroupsX + gx;
      for (genvar ch = 0; ch < ClusterWideOutAxiPorts; ch++) begin : gen_per_ch
      reqrsp_to_axi #(
        .MaxTrans           ( NumSpatzOutstandingLoads*2 ),
        .ID                 ( '0                         ),
        .EnBurst            ( 1                          ),
        .ShuffleId          ( 1                          ),
        .UserWidth          ( $bits(refill_user_t)       ),
        .ReqUserFallThrough ( 1'b0                       ),
        .DataWidth          ( AxiDataWidth               ),
        .AxiUserWidth       ( AxiUserWidth               ),
        .reqrsp_req_t       ( l2_req_t                   ),
        .reqrsp_rsp_t       ( l2_rsp_t                   ),
        .axi_req_t          ( axi_premux_cache_req_t     ),
        .axi_rsp_t          ( axi_premux_cache_resp_t    )
      ) i_reqrsp2axi        (
        .clk_i              ( clk_i                      ),
        .rst_ni             ( rst_ni                     ),
        .user_i             ( l2_req[g][ch].q.user       ),
        .reqrsp_req_i       ( l2_req[g][ch]              ),
        .reqrsp_rsp_o       ( l2_rsp[g][ch]              ),
        .axi_req_o          ( wide_axi_premux_req[g][ch] ),
        .axi_rsp_i          ( wide_axi_premux_rsp[g][ch] )
      );
      end
    end
  end

  // Step 2: Per-L2-channel axi_mux across groups.
  if (NumGroups > 1) begin : gen_l2_group_mux
    for (genvar ch = 0; ch < ClusterWideOutAxiPorts; ch++) begin : gen_l2_ch_mux
      // Per-group ID remapper: reduces GroupAxiIdOutWidth to WideRefillIdWidth before the mux.
      // axi_id_remap preserves ID independence (unlike axi_id_serialize) for performance.
      // AxiSlvPortMaxUniqIds = NumSpatzOutstandingLoads*2 matches the reqrsp_to_axi MaxTrans
      // so the remapper never stalls.
      for (genvar g = 0; g < NumGroups; g++) begin : gen_l2_mux_remap
        axi_id_remap #(
          .AxiSlvPortIdWidth    ( GroupAxiIdOutWidth           ),
          .AxiSlvPortMaxUniqIds ( NumSpatzOutstandingLoads * 2 ),
          .AxiMaxTxnsPerId      ( NumSpatzOutstandingLoads     ),
          .AxiMstPortIdWidth    ( WideIdWidthPreMux            ),
          .slv_req_t            ( axi_premux_cache_req_t       ),
          .slv_resp_t           ( axi_premux_cache_resp_t      ),
          .mst_req_t            ( axi_remap_cache_req_t        ),
          .mst_resp_t           ( axi_remap_cache_resp_t       )
        ) i_l2_id_remap (
          .clk_i      ( clk_i                           ),
          .rst_ni     ( rst_ni                           ),
          .slv_req_i  ( wide_axi_premux_req[g][ch]       ),
          .slv_resp_o ( wide_axi_premux_rsp[g][ch]       ),
          .mst_req_o  ( wide_axi_remap_req[g][ch]        ),
          .mst_resp_i ( wide_axi_remap_rsp[g][ch]        )
        );
      end

      // Collect remapped per-group inputs for the mux.
      axi_remap_cache_req_t  [NumGroups-1:0] l2_mux_slv_req;
      axi_remap_cache_resp_t [NumGroups-1:0] l2_mux_slv_rsp;

      for (genvar g = 0; g < NumGroups; g++) begin : gen_l2_mux_connect
        assign l2_mux_slv_req[g]          = wide_axi_remap_req[g][ch];
        assign wide_axi_remap_rsp[g][ch]  = l2_mux_slv_rsp[g];
      end

      axi_mux #(
        .SlvAxiIDWidth ( WideIdWidthPreMux            ),
        .slv_aw_chan_t ( axi_remap_cache_aw_chan_t    ),
        .mst_aw_chan_t ( axi_slv_cache_aw_chan_t      ),
        .w_chan_t      ( axi_slv_cache_w_chan_t       ),
        .slv_b_chan_t  ( axi_remap_cache_b_chan_t     ),
        .mst_b_chan_t  ( axi_slv_cache_b_chan_t       ),
        .slv_ar_chan_t ( axi_remap_cache_ar_chan_t    ),
        .mst_ar_chan_t ( axi_slv_cache_ar_chan_t      ),
        .slv_r_chan_t  ( axi_remap_cache_r_chan_t     ),
        .mst_r_chan_t  ( axi_slv_cache_r_chan_t       ),
        .slv_req_t     ( axi_remap_cache_req_t        ),
        .slv_resp_t    ( axi_remap_cache_resp_t       ),
        .mst_req_t     ( axi_slv_cache_req_t          ),
        .mst_resp_t    ( axi_slv_cache_resp_t         ),
        .NoSlvPorts    ( NumGroups                    ),
        .FallThrough   ( 0                            ),
        .SpillAw       ( XbarLatency[4]               ),
        .SpillW        ( XbarLatency[3]               ),
        .SpillB        ( XbarLatency[2]               ),
        .SpillAr       ( XbarLatency[1]               ),
        .SpillR        ( XbarLatency[0]               ),
        .MaxWTrans     ( 2                            )
      ) i_axi_l2_mux   (
        .clk_i         ( clk_i                        ),
        .rst_ni        ( rst_ni                       ),
        .test_i        ( '0                           ),
        .slv_reqs_i    ( l2_mux_slv_req               ),
        .slv_resps_o   ( l2_mux_slv_rsp               ),
        .mst_req_o     ( wide_axi_slv_req[ch]         ),
        .mst_resp_i    ( wide_axi_slv_rsp[ch]         )
      );
    end
  end else begin : gen_l2_no_mux
    // Single group: direct connection, no mux needed.
    for (genvar ch = 0; ch < ClusterWideOutAxiPorts; ch++) begin : gen_l2_ch_direct
      assign wide_axi_slv_req[ch] = wide_axi_premux_req[0][ch];
      assign wide_axi_premux_rsp[0][ch] = wide_axi_slv_rsp[ch];
    end
  end

  // Optionally decouple the external wide AXI master port.
  for (genvar port = 0; port < ClusterWideOutAxiPorts; port ++) begin : gen_axi_out_cut
    axi_cut #(
      .Bypass     (0                          ),
      .aw_chan_t  (axi_slv_cache_aw_chan_t    ),
      .w_chan_t   (axi_slv_cache_w_chan_t     ),
      .b_chan_t   (axi_slv_cache_b_chan_t     ),
      .ar_chan_t  (axi_slv_cache_ar_chan_t    ),
      .r_chan_t   (axi_slv_cache_r_chan_t     ),
      .axi_req_t  (axi_slv_cache_req_t        ),
      .axi_resp_t (axi_slv_cache_resp_t       )
    ) i_cut_ext_wide_out (
      .clk_i      (clk_i                      ),
      .rst_ni     (rst_ni                     ),
      .slv_req_i  (wide_axi_slv_req[port]     ),
      .slv_resp_o (wide_axi_slv_rsp[port]     ),
      .mst_req_o  (axi_out_req_o   [port]     ),
      .mst_resp_i (axi_out_resp_i  [port]     )
    );
  end

  // ---------
  // Slaves
  // ---------

  /***** UART ****/
  axi_narrow_req_t   [NumTiles-1:0] axi_uart_mux_req;
  axi_narrow_resp_t  [NumTiles-1:0] axi_uart_mux_rsp;

  if (NumTiles > 1) begin : gen_uart_mux
    for (genvar tile = 0; tile < NumTiles; tile++) begin
      assign axi_uart_mux_req[tile] =  axi_out_req[tile][ClusterUart];
      assign axi_out_resp[tile][ClusterUart] = axi_uart_mux_rsp[tile];
    end

    axi_mux #(
      .SlvAxiIDWidth ( CsrAxiMstIdWidth       ),
      .slv_aw_chan_t ( axi_csr_mst_aw_chan_t  ),
      .mst_aw_chan_t ( axi_uart_aw_chan_t     ),
      .w_chan_t      ( axi_uart_w_chan_t      ),
      .slv_b_chan_t  ( axi_csr_mst_b_chan_t   ),
      .mst_b_chan_t  ( axi_uart_b_chan_t      ),
      .slv_ar_chan_t ( axi_csr_mst_ar_chan_t  ),
      .mst_ar_chan_t ( axi_uart_ar_chan_t     ),
      .slv_r_chan_t  ( axi_csr_mst_r_chan_t   ),
      .mst_r_chan_t  ( axi_uart_r_chan_t      ),
      .slv_req_t     ( axi_csr_mst_req_t      ),
      .slv_resp_t    ( axi_csr_mst_resp_t     ),
      .mst_req_t     ( axi_uart_req_t         ),
      .mst_resp_t    ( axi_uart_resp_t        ),
      .NoSlvPorts    ( NumTiles               ),
      .FallThrough   ( 0                      ),
      .SpillAw       ( XbarLatency[4]         ),
      .SpillW        ( XbarLatency[3]         ),
      .SpillB        ( XbarLatency[2]         ),
      .SpillAr       ( XbarLatency[1]         ),
      .SpillR        ( XbarLatency[0]         ),
      .MaxWTrans     ( 2                      )
    ) i_axi_uart_mux (
      .clk_i         ( clk_i                  ),
      .rst_ni        ( rst_ni                 ),
      .test_i        ( '0                     ),
      .slv_reqs_i    ( axi_uart_mux_req       ),
      .slv_resps_o   ( axi_uart_mux_rsp       ),
      .mst_req_o     ( axi_narrow_req_o       ),
      .mst_resp_i    ( axi_narrow_resp_i      )
    );
  end else begin : gen_uart_connect
    assign axi_narrow_req_o = axi_out_req[0][ClusterUart];
    assign axi_out_resp[0][ClusterUart] = axi_narrow_resp_i;
  end

  /***** CSR/Peripherals *****/

  `REG_BUS_TYPEDEF_ALL(reg, narrow_addr_t, narrow_data_t, narrow_strb_t)

  reg_req_t reg_req;
  reg_rsp_t reg_rsp;

  axi_csr_slv_req_t  axi_csr_req;
  axi_csr_slv_resp_t axi_csr_rsp;

  axi_narrow_req_t  [NumTiles-1:0] axi_core_csr_req, axi_barrier_req;
  axi_narrow_resp_t [NumTiles-1:0] axi_core_csr_rsp, axi_barrier_rsp;

  // Serialized CSR signals: one entry per tile plus one for the external axi_in port.
  // Index [NumTiles] = axi_in_req_i, indices [NumTiles-1:0] = per-tile CSR outputs.
  axi_csr_ser_req_t  [NumTiles:0] axi_csr_pre_mux_req;
  axi_csr_ser_resp_t [NumTiles:0] axi_csr_pre_mux_rsp;


  for (genvar t = 0; t < NumTiles; t++) begin
    assign axi_barrier_req[t] = axi_out_req [t][ClusterPeriph];
    assign axi_out_resp [t][ClusterPeriph] = axi_barrier_rsp[t];
  end

  // Calculate the peripheral base address
  localparam logic        [AxiAddrWidth-1:0] TCDMMask = ~(TCDMSize-1);
  addr_t tcdm_start_address, tcdm_end_address;
  assign tcdm_start_address = (cluster_base_addr_i & TCDMMask);
  assign tcdm_end_address   = (tcdm_start_address + TCDMSize) & TCDMMask;


  logic [NumTiles-1:0] use_barrier;
  // TODO: Connect to CSR
  assign use_barrier = {NumTiles{1'b1}};

  cachepool_cluster_barrier #(
    .AddrWidth    (AxiAddrWidth       ),
    .NrPorts      (NumTiles           ),
    .axi_req_t    (axi_narrow_req_t   ),
    .axi_rsp_t    (axi_narrow_resp_t  ),
    .axi_id_t     (axi_id_in_t        ),
    .axi_user_t   (axi_user_t         )
  ) i_cachepool_cluster_barrier (
    .clk_i                          ( clk_i             ),
    .rst_ni                         ( rst_ni            ),
    .axi_slv_req_i                  ( axi_barrier_req   ),
    .axi_slv_rsp_o                  ( axi_barrier_rsp   ),
    .axi_mst_req_o                  ( axi_core_csr_req  ),
    .axi_mst_rsp_i                  ( axi_core_csr_rsp  ),
    .barrier_i                      ( use_barrier       ),
    .cluster_periph_start_address_i ( tcdm_end_address  )
  );

  // Per-tile CSR ID serializers: reduce CsrAxiMstIdWidth to CsrSerIdWidth before the mux
  // so the mux output stays bounded regardless of NumTiles.
  for (genvar t = 0; t < NumTiles; t++) begin : gen_csr_id_serialize
    axi_id_serialize #(
      .AxiSlvPortIdWidth      ( CsrAxiMstIdWidth        ),
      .AxiSlvPortMaxTxns      ( 2                       ),
      .AxiMstPortIdWidth      ( CsrSerIdWidth           ),
      .AxiMstPortMaxUniqIds   ( 1                       ),
      .AxiMstPortMaxTxnsPerId ( 2                       ),
      .AxiAddrWidth           ( AxiAddrWidth            ),
      .AxiDataWidth           ( SpatzAxiNarrowDataWidth ),
      .AxiUserWidth           ( SpatzAxiUserWidth       ),
      .AtopSupport            ( 1'b0                    ),
      .slv_req_t              ( axi_narrow_req_t        ),
      .slv_resp_t             ( axi_narrow_resp_t       ),
      .mst_req_t              ( axi_csr_ser_req_t       ),
      .mst_resp_t             ( axi_csr_ser_resp_t      ),
      // Provide one dummy entry to avoid [IdMapNumEntries-1:0] underflow when 0.
      // Entry maps ID 0 -> 0, which is identical to the default modulo formula.
      .IdMapNumEntries        ( 1                       ),
      .IdMap                  ( '{'{32'd0, 32'd0}}      )
    ) i_csr_id_serialize (
      .clk_i      ( clk_i                   ),
      .rst_ni     ( rst_ni                   ),
      .slv_req_i  ( axi_core_csr_req[t]      ),
      .slv_resp_o ( axi_core_csr_rsp[t]      ),
      .mst_req_o  ( axi_csr_pre_mux_req[t]   ),
      .mst_resp_i ( axi_csr_pre_mux_rsp[t]   )
    );
  end

  // Serializer for the external axi_in port (SoC CSR access).
  axi_id_serialize #(
    .AxiSlvPortIdWidth      ( AxiIdWidthIn            ),
    .AxiSlvPortMaxTxns      ( 2                       ),
    .AxiMstPortIdWidth      ( CsrSerIdWidth           ),
    .AxiMstPortMaxUniqIds   ( 1                       ),
    .AxiMstPortMaxTxnsPerId ( 2                       ),
    .AxiAddrWidth           ( AxiAddrWidth            ),
    .AxiDataWidth           ( SpatzAxiNarrowDataWidth ),
    .AxiUserWidth           ( SpatzAxiUserWidth       ),
    .AtopSupport            ( 1'b0                    ),
    .slv_req_t              ( axi_in_req_t            ),
    .slv_resp_t             ( axi_in_resp_t           ),
    .mst_req_t              ( axi_csr_ser_req_t       ),
    .mst_resp_t             ( axi_csr_ser_resp_t      ),
    // Provide one dummy entry to avoid [IdMapNumEntries-1:0] underflow when 0.
    // Entry maps ID 0 -> 0, which is identical to the default modulo formula.
    .IdMapNumEntries        ( 1                       ),
    .IdMap                  ( '{'{32'd0, 32'd0}}      )
  ) i_csr_in_id_serialize (
    .clk_i      ( clk_i                          ),
    .rst_ni     ( rst_ni                          ),
    .slv_req_i  ( axi_in_req_i                    ),
    .slv_resp_o ( axi_in_resp_o                   ),
    .mst_req_o  ( axi_csr_pre_mux_req[NumTiles]   ),
    .mst_resp_i ( axi_csr_pre_mux_rsp[NumTiles]   )
  );

  axi_mux #(
    .SlvAxiIDWidth ( CsrSerIdWidth          ),
    .slv_aw_chan_t ( axi_csr_ser_aw_chan_t  ),
    .mst_aw_chan_t ( axi_csr_slv_aw_chan_t  ),
    .w_chan_t      ( axi_csr_slv_w_chan_t   ),
    .slv_b_chan_t  ( axi_csr_ser_b_chan_t   ),
    .mst_b_chan_t  ( axi_csr_slv_b_chan_t   ),
    .slv_ar_chan_t ( axi_csr_ser_ar_chan_t  ),
    .mst_ar_chan_t ( axi_csr_slv_ar_chan_t  ),
    .slv_r_chan_t  ( axi_csr_ser_r_chan_t   ),
    .mst_r_chan_t  ( axi_csr_slv_r_chan_t   ),
    .slv_req_t     ( axi_csr_ser_req_t      ),
    .slv_resp_t    ( axi_csr_ser_resp_t     ),
    .mst_req_t     ( axi_csr_slv_req_t      ),
    .mst_resp_t    ( axi_csr_slv_resp_t     ),
    .NoSlvPorts    ( NumTiles + 1           ),
    .FallThrough   ( 0                      ),
    .SpillAw       ( XbarLatency[4]         ),
    .SpillW        ( XbarLatency[3]         ),
    .SpillB        ( XbarLatency[2]         ),
    .SpillAr       ( XbarLatency[1]         ),
    .SpillR        ( XbarLatency[0]         ),
    .MaxWTrans     ( 2                      )
  ) i_axi_csr_mux (
    .clk_i       ( clk_i                              ),
    .rst_ni      ( rst_ni                             ),
    .test_i      ('0                                  ),
    .slv_reqs_i  ( axi_csr_pre_mux_req  ),
    .slv_resps_o ( axi_csr_pre_mux_rsp  ),
    .mst_req_o   ( axi_csr_req                        ),
    .mst_resp_i  ( axi_csr_rsp                        )
  );

  axi_to_reg #(
    .ADDR_WIDTH         (AxiAddrWidth             ),
    .DATA_WIDTH         (SpatzAxiNarrowDataWidth  ),
    .AXI_MAX_WRITE_TXNS (1                        ),
    .AXI_MAX_READ_TXNS  (1                        ),
    .DECOUPLE_W         (0                        ),
    .ID_WIDTH           (CsrAxiSlvIdWidth         ),
    .USER_WIDTH         (SpatzAxiUserWidth        ),
    .axi_req_t          (axi_csr_slv_req_t        ),
    .axi_rsp_t          (axi_csr_slv_resp_t       ),
    .reg_req_t          (reg_req_t                ),
    .reg_rsp_t          (reg_rsp_t                )
  ) i_csr_axi_to_reg (
    .clk_i              (clk_i                    ),
    .rst_ni             (rst_ni                   ),
    .testmode_i         (1'b0                     ),
    .axi_req_i          (axi_csr_req              ),
    .axi_rsp_o          (axi_csr_rsp              ),
    .reg_req_o          (reg_req                  ),
    .reg_rsp_i          (reg_rsp                  )
  );

  cachepool_peripheral #(
    .AddrWidth     (AxiAddrWidth    ),
    .SPMWidth      ($clog2(L1NumSet)),
    .NumTiles      (NumTiles        ),
    .reg_req_t     (reg_req_t       ),
    .reg_rsp_t     (reg_rsp_t       ),
    .cache_insn_t  (cache_insn_t    )
  ) i_cachepool_cluster_peripheral (
    .clk_i                    (clk_i                 ),
    .rst_ni                   (rst_ni                ),
    .eoc_o                    (eoc_o                 ),
    .reg_req_i                (reg_req               ),
    .reg_rsp_o                (reg_rsp               ),
    /// The TCDM always starts at the cluster base.
    .tcdm_start_address_i     (tcdm_start_address    ),
    .tcdm_end_address_i       (tcdm_end_address      ),
    .icache_prefetch_enable_o (icache_prefetch_enable),
    .cluster_hart_base_id_i   (hart_base_id_i        ),
    .cluster_probe_o          (cluster_probe_o       ),
    .dynamic_offset_o         (dynamic_offset        ),
    .private_start_addr_o     (private_start_addr    ),
    .l1d_spm_size_o           (                      ),
    .l1d_private_o            (l1d_private           ),
    .l1d_insn_o               (l1d_insn              ),
    .l1d_insn_valid_o         (l1d_insn_valid        ),
    .l1d_insn_ready_i         (l1d_insn_ready        ),
    .l1d_busy_o               (l1d_busy              )
  );

endmodule
