// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "axi/typedef.svh"
`include "register_interface/typedef.svh"
`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

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
    parameter int                     unsigned               NrSramCfg                          = 1,
    /// Folded data bank configuration (0 = auto: min(4, L1AssoPerCtrl)).
    parameter bit                                            UseFoldedDataBanks               = 1'b1,
    parameter int                     unsigned               FoldWayGroup                     = 0,
    parameter bit                                            UseHashWaySelect                 = 1'b1,
    /// Enable the SRAM forwarding buffer (default on; requires UseHashWaySelect).
    parameter bit                                            UseForwardingBuffer              = 1'b1
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
    /// External peripheral REQRSP in-port (from TB/SoC, 32b narrow, refill_user_t).
    input  peri_narrow_req_t                      peri_ext_req_i,
    output peri_narrow_rsp_t                      peri_ext_rsp_o,
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
  // Per-group wide AXI ID width, passed as AxiIdWidthOut to each group.
  // With the FlooNoC mesh, this is independent of WideIdWidthOut (no star mux).
  localparam int unsigned WideIdWidthIn   = GroupWideIdWidth;

  // --------
  // Typedefs
  // --------
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [AxiDataWidth-1:0]      data_cache_t;
  typedef logic [AxiDataWidth/8-1:0]    strb_cache_t;
  typedef logic [WideIdWidthOut-1:0]    id_cache_slv_t;
  typedef logic [AxiUserWidth-1:0]      user_cache_t;

  // Post-chimney AXI types (used for axi_cut and DRAM output).
  `AXI_TYPEDEF_ALL(axi_slv_cache,    addr_t, id_cache_slv_t,    data_cache_t, strb_cache_t, user_cache_t)

  // ----------------
  // Wire Definitions
  // ----------------
  // 1. AXI — post-chimney wide AXI (one per L2/HBM channel).
  axi_slv_cache_req_t  [ClusterWideOutAxiPorts-1:0] wide_axi_slv_req;
  axi_slv_cache_resp_t [ClusterWideOutAxiPorts-1:0] wide_axi_slv_rsp;

  // HBM0 peripheral demux port: narrowed 32b REQRSP with refill_user_t (same user as wide side).
  peri_narrow_req_t  hbm0_peri_narrow_req;
  peri_narrow_rsp_t  hbm0_peri_narrow_rsp;

  // 2. Peripherals
  axi_addr_t                                  private_start_addr;
  logic                                       icache_prefetch_enable;
  logic         [$clog2(L1AddrWidth)-1:0]     dynamic_offset;
  cache_insn_t                                l1d_insn;
  logic                                       l1d_insn_valid;
  logic         [NumTiles-1:0]                l1d_insn_ready;
  logic         [NumTiles-1:0]                l1d_busy;
  logic         [$clog2(NumL1CtrlTile):0]     l1d_private;

  // Per-group error signals.
  logic         [NumGroups-1:0]               group_error;

  // Direct-wire barrier: one bit per tile across all groups
  logic [NumGroups-1:0][NumTilesPerGroup-1:0] tile_barrier;
  logic                                       barrier_done;
  // Tile participation mask for the cluster-level barrier, software-configured
  // via the HW_BARRIER_PARTICIPATION_MASK peripheral CSR (reset value: all tiles).
  logic [NumTiles-1:0]                        barrier_participation_mask;

  cachepool_cluster_barrier #(
    .NrTiles ( NumTiles )
  ) i_cluster_barrier (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .tile_barrier_i ( tile_barrier   ),
    .barrier_done_o ( barrier_done   ),
    .barrier_mask_i ( barrier_participation_mask )
  );

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

  // Per-group L2 refill TCDM mesh signals [NumGroupsX][NumGroupsY][direction 0..3]
  l2_noc_req_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_req_out;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_req_out_valid;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_req_out_ready;
  l2_noc_req_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_req_in;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_req_in_valid;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_req_in_ready;
  l2_noc_rsp_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_rsp_out;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_rsp_out_valid;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_rsp_out_ready;
  l2_noc_rsp_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_rsp_in;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_rsp_in_valid;
  logic        [NumGroupsX-1:0][NumGroupsY-1:0][3:0] l2_rsp_in_ready;

  assign error_o = |group_error;

  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_group_y
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_group_x
      // Flat group index: row-major (matches L1 mesh wiring which uses gx + gy*NumGroupsX)
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
        .axi_out_req_t            ( logic                    ),
        .axi_out_resp_t           ( logic                    ),
        .RegisterOffloadRsp       ( RegisterOffloadRsp       ),
        .RegisterCoreReq          ( RegisterCoreReq          ),
        .RegisterCoreRsp          ( RegisterCoreRsp          ),
        .RegisterTCDMCuts         ( RegisterTCDMCuts         ),
        .RegisterExt              ( RegisterExt              ),
        .XbarLatency              ( XbarLatency              ),
        .MaxMstTrans              ( MaxMstTrans              ),
        .MaxSlvTrans              ( MaxSlvTrans              ),
        .UseFoldedDataBanks       ( UseFoldedDataBanks       ),
        .FoldWayGroup             ( FoldWayGroup             ),
        .UseHashWaySelect         ( UseHashWaySelect         ),
        .UseForwardingBuffer      ( UseForwardingBuffer      )
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
        // L2 refill TCDM mesh (4 directions)
        .l2_req_o                 ( l2_req_out       [gx][gy]                       ),
        .l2_req_valid_o           ( l2_req_out_valid  [gx][gy]                      ),
        .l2_req_ready_i           ( l2_req_out_ready  [gx][gy]                      ),
        .l2_req_i                 ( l2_req_in         [gx][gy]                      ),
        .l2_req_valid_i           ( l2_req_in_valid   [gx][gy]                      ),
        .l2_req_ready_o           ( l2_req_in_ready   [gx][gy]                      ),
        .l2_rsp_o                 ( l2_rsp_out       [gx][gy]                       ),
        .l2_rsp_valid_o           ( l2_rsp_out_valid  [gx][gy]                      ),
        .l2_rsp_ready_i           ( l2_rsp_out_ready  [gx][gy]                      ),
        .l2_rsp_i                 ( l2_rsp_in         [gx][gy]                      ),
        .l2_rsp_valid_i           ( l2_rsp_in_valid   [gx][gy]                      ),
        .l2_rsp_ready_o           ( l2_rsp_in_ready   [gx][gy]                      ),
        .l2_id_i                  ( floo_cachepool_noc_pkg::id_t'(gx * NumGroupsY + gy)         ),
        .l2_route_table_i         ( floo_cachepool_noc_pkg::RoutingTables[gx * NumGroupsY + gy] ),
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
        .noc_rsp_ready_o          ( noc_rsp_in_ready [g]                                   ),
        // Direct-wire barrier
        .tile_barrier_o           ( tile_barrier     [g]                                   ),
        .barrier_done_i           ( barrier_done                                           )
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
      assign noc_req_in       [gx+1 + gy*NumGroupsX][3] = noc_req_out      [gx   + gy*NumGroupsX][1];
      assign noc_req_in_valid [gx+1 + gy*NumGroupsX][3] = noc_req_out_valid[gx   + gy*NumGroupsX][1];
      assign noc_req_out_ready[gx   + gy*NumGroupsX][1] = noc_req_in_ready [gx+1 + gy*NumGroupsX][3];
      assign noc_rsp_in       [gx+1 + gy*NumGroupsX][3] = noc_rsp_out      [gx   + gy*NumGroupsX][1];
      assign noc_rsp_in_valid [gx+1 + gy*NumGroupsX][3] = noc_rsp_out_valid[gx   + gy*NumGroupsX][1];
      assign noc_rsp_out_ready[gx   + gy*NumGroupsX][1] = noc_rsp_in_ready [gx+1 + gy*NumGroupsX][3];
      // West output of (gx+1,gy) → East input of (gx,gy)
      assign noc_req_in       [gx   + gy*NumGroupsX][1] = noc_req_out      [gx+1 + gy*NumGroupsX][3];
      assign noc_req_in_valid [gx   + gy*NumGroupsX][1] = noc_req_out_valid[gx+1 + gy*NumGroupsX][3];
      assign noc_req_out_ready[gx+1 + gy*NumGroupsX][3] = noc_req_in_ready [gx   + gy*NumGroupsX][1];
      assign noc_rsp_in       [gx   + gy*NumGroupsX][1] = noc_rsp_out      [gx+1 + gy*NumGroupsX][3];
      assign noc_rsp_in_valid [gx   + gy*NumGroupsX][1] = noc_rsp_out_valid[gx+1 + gy*NumGroupsX][3];
      assign noc_rsp_out_ready[gx+1 + gy*NumGroupsX][3] = noc_rsp_in_ready [gx   + gy*NumGroupsX][1];
    end
  end

  // North-South (vertical) interior connections
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_ns_conn
    for (genvar gy = 0; gy < NumGroupsY-1; gy++) begin : gen_ns_conn_y
      // North output of (gx,gy) (dir 0) → South input of (gx,gy+1) (dir 2)
      assign noc_req_in       [gx + (gy+1)*NumGroupsX][2] = noc_req_out      [gx +  gy   *NumGroupsX][0];
      assign noc_req_in_valid [gx + (gy+1)*NumGroupsX][2] = noc_req_out_valid[gx +  gy   *NumGroupsX][0];
      assign noc_req_out_ready[gx +  gy   *NumGroupsX][0] = noc_req_in_ready [gx + (gy+1)*NumGroupsX][2];
      assign noc_rsp_in       [gx + (gy+1)*NumGroupsX][2] = noc_rsp_out      [gx +  gy   *NumGroupsX][0];
      assign noc_rsp_in_valid [gx + (gy+1)*NumGroupsX][2] = noc_rsp_out_valid[gx +  gy   *NumGroupsX][0];
      assign noc_rsp_out_ready[gx +  gy   *NumGroupsX][0] = noc_rsp_in_ready [gx + (gy+1)*NumGroupsX][2];
      // South output of (gx,gy+1) (dir 2) → North input of (gx,gy) (dir 0)
      assign noc_req_in       [gx +  gy   *NumGroupsX][0] = noc_req_out      [gx + (gy+1)*NumGroupsX][2];
      assign noc_req_in_valid [gx +  gy   *NumGroupsX][0] = noc_req_out_valid[gx + (gy+1)*NumGroupsX][2];
      assign noc_req_out_ready[gx + (gy+1)*NumGroupsX][2] = noc_req_in_ready [gx +  gy   *NumGroupsX][0];
      assign noc_rsp_in       [gx +  gy   *NumGroupsX][0] = noc_rsp_out      [gx + (gy+1)*NumGroupsX][2];
      assign noc_rsp_in_valid [gx +  gy   *NumGroupsX][0] = noc_rsp_out_valid[gx + (gy+1)*NumGroupsX][2];
      assign noc_rsp_out_ready[gx + (gy+1)*NumGroupsX][2] = noc_rsp_in_ready [gx +  gy   *NumGroupsX][0];
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
`ifndef SYNTHESIS
    for (genvar p = 0; p < NumTilesPerGroup*NumNoCPortsPerTile; p++) begin : gen_west_chk
      always_ff @(posedge clk_i) begin
        if (rst_ni && noc_req_out_valid[gy*NumGroupsX][3][p])
          $error("[L1_MESH] REQ lost at West G(0,%0d) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) addr=%08x wen=%0b dst_tile=%0d",
            gy, p,
            noc_req_out[gy*NumGroupsX][3][p].hdr.src_id.x,
            noc_req_out[gy*NumGroupsX][3][p].hdr.src_id.y,
            noc_req_out[gy*NumGroupsX][3][p].hdr.src_tile_id,
            noc_req_out[gy*NumGroupsX][3][p].hdr.dst_id.x,
            noc_req_out[gy*NumGroupsX][3][p].hdr.dst_id.y,
            noc_req_out[gy*NumGroupsX][3][p].payload.addr,
            noc_req_out[gy*NumGroupsX][3][p].payload.write,
            noc_req_out[gy*NumGroupsX][3][p].payload.user.dst_tile_id);
        if (rst_ni && noc_rsp_out_valid[gy*NumGroupsX][3][p])
          $error("[L1_MESH] RSP lost at West G(0,%0d) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) data=%08x",
            gy, p,
            noc_rsp_out[gy*NumGroupsX][3][p].hdr.src_id.x,
            noc_rsp_out[gy*NumGroupsX][3][p].hdr.src_id.y,
            noc_rsp_out[gy*NumGroupsX][3][p].hdr.src_tile_id,
            noc_rsp_out[gy*NumGroupsX][3][p].hdr.dst_id.x,
            noc_rsp_out[gy*NumGroupsX][3][p].hdr.dst_id.y,
            noc_rsp_out[gy*NumGroupsX][3][p].payload.data);
      end
    end
`endif
  end

  // East boundary: gx=NumGroupsX-1 has no East neighbor (dir 1)
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_east_bnd
    assign noc_req_in       [(NumGroupsX-1) + gy*NumGroupsX][1] = '0;
    assign noc_req_in_valid [(NumGroupsX-1) + gy*NumGroupsX][1] = '0;
    assign noc_req_out_ready[(NumGroupsX-1) + gy*NumGroupsX][1] = '1;
    assign noc_rsp_in       [(NumGroupsX-1) + gy*NumGroupsX][1] = '0;
    assign noc_rsp_in_valid [(NumGroupsX-1) + gy*NumGroupsX][1] = '0;
    assign noc_rsp_out_ready[(NumGroupsX-1) + gy*NumGroupsX][1] = '1;
`ifndef SYNTHESIS
    for (genvar p = 0; p < NumTilesPerGroup*NumNoCPortsPerTile; p++) begin : gen_east_chk
      always_ff @(posedge clk_i) begin
        if (rst_ni && noc_req_out_valid[(NumGroupsX-1) + gy*NumGroupsX][1][p])
          $error("[L1_MESH] REQ lost at East G(%0d,%0d) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) addr=%08x wen=%0b dst_tile=%0d",
            NumGroupsX-1, gy, p,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.src_id.x,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.src_id.y,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.src_tile_id,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.dst_id.x,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.dst_id.y,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].payload.addr,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].payload.write,
            noc_req_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].payload.user.dst_tile_id);
        if (rst_ni && noc_rsp_out_valid[(NumGroupsX-1) + gy*NumGroupsX][1][p])
          $error("[L1_MESH] RSP lost at East G(%0d,%0d) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) data=%08x",
            NumGroupsX-1, gy, p,
            noc_rsp_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.src_id.x,
            noc_rsp_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.src_id.y,
            noc_rsp_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.src_tile_id,
            noc_rsp_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.dst_id.x,
            noc_rsp_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].hdr.dst_id.y,
            noc_rsp_out[(NumGroupsX-1) + gy*NumGroupsX][1][p].payload.data);
      end
    end
`endif
  end

  // South boundary: gy=0 has no South neighbor (dir 2)
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_south_bnd
    assign noc_req_in       [gx][2] = '0;
    assign noc_req_in_valid [gx][2] = '0;
    assign noc_req_out_ready[gx][2] = '1;
    assign noc_rsp_in       [gx][2] = '0;
    assign noc_rsp_in_valid [gx][2] = '0;
    assign noc_rsp_out_ready[gx][2] = '1;
`ifndef SYNTHESIS
    for (genvar p = 0; p < NumTilesPerGroup*NumNoCPortsPerTile; p++) begin : gen_south_chk
      always_ff @(posedge clk_i) begin
        if (rst_ni && noc_req_out_valid[gx][2][p])
          $error("[L1_MESH] REQ lost at South G(%0d,0) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) addr=%08x wen=%0b dst_tile=%0d",
            gx, p,
            noc_req_out[gx][2][p].hdr.src_id.x,
            noc_req_out[gx][2][p].hdr.src_id.y,
            noc_req_out[gx][2][p].hdr.src_tile_id,
            noc_req_out[gx][2][p].hdr.dst_id.x,
            noc_req_out[gx][2][p].hdr.dst_id.y,
            noc_req_out[gx][2][p].payload.addr,
            noc_req_out[gx][2][p].payload.write,
            noc_req_out[gx][2][p].payload.user.dst_tile_id);
        if (rst_ni && noc_rsp_out_valid[gx][2][p])
          $error("[L1_MESH] RSP lost at South G(%0d,0) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) data=%08x",
            gx, p,
            noc_rsp_out[gx][2][p].hdr.src_id.x,
            noc_rsp_out[gx][2][p].hdr.src_id.y,
            noc_rsp_out[gx][2][p].hdr.src_tile_id,
            noc_rsp_out[gx][2][p].hdr.dst_id.x,
            noc_rsp_out[gx][2][p].hdr.dst_id.y,
            noc_rsp_out[gx][2][p].payload.data);
      end
    end
`endif
  end

  // North boundary: gy=NumGroupsY-1 has no North neighbor (dir 0)
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_north_bnd
    assign noc_req_in       [gx + (NumGroupsY-1)*NumGroupsX][0] = '0;
    assign noc_req_in_valid [gx + (NumGroupsY-1)*NumGroupsX][0] = '0;
    assign noc_req_out_ready[gx + (NumGroupsY-1)*NumGroupsX][0] = '1;
    assign noc_rsp_in       [gx + (NumGroupsY-1)*NumGroupsX][0] = '0;
    assign noc_rsp_in_valid [gx + (NumGroupsY-1)*NumGroupsX][0] = '0;
    assign noc_rsp_out_ready[gx + (NumGroupsY-1)*NumGroupsX][0] = '1;
`ifndef SYNTHESIS
    for (genvar p = 0; p < NumTilesPerGroup*NumNoCPortsPerTile; p++) begin : gen_north_chk
      always_ff @(posedge clk_i) begin
        if (rst_ni && noc_req_out_valid[gx + (NumGroupsY-1)*NumGroupsX][0][p])
          $error("[L1_MESH] REQ lost at North G(%0d,%0d) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) addr=%08x wen=%0b dst_tile=%0d",
            gx, NumGroupsY-1, p,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.src_id.x,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.src_id.y,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.src_tile_id,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.dst_id.x,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.dst_id.y,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].payload.addr,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].payload.write,
            noc_req_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].payload.user.dst_tile_id);
        if (rst_ni && noc_rsp_out_valid[gx + (NumGroupsY-1)*NumGroupsX][0][p])
          $error("[L1_MESH] RSP lost at North G(%0d,%0d) p%0d | src=(%0d,%0d) t%0d dst=(%0d,%0d) data=%08x",
            gx, NumGroupsY-1, p,
            noc_rsp_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.src_id.x,
            noc_rsp_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.src_id.y,
            noc_rsp_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.src_tile_id,
            noc_rsp_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.dst_id.x,
            noc_rsp_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].hdr.dst_id.y,
            noc_rsp_out[gx + (NumGroupsY-1)*NumGroupsX][0][p].payload.data);
      end
    end
`endif
  end

  // -------------------------------------------------------
  // L2 Refill TCDM Mesh + HBM Edge Adapters
  // -------------------------------------------------------

  if (NumGroups > 1) begin : gen_l2_refill_mesh

    // --------------------------------------------------
    // L2 mesh interior cross-connections (valid/ready)
    // --------------------------------------------------

    // East-West connections
    for (genvar gx = 0; gx < NumGroupsX - 1; gx++) begin : gen_l2_ew
      for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_l2_ew_y
        // East(1) output of (gx,gy) → West(3) input of (gx+1,gy)
        assign l2_req_in       [gx+1][gy][3]  = l2_req_out        [gx]  [gy][1];
        assign l2_req_in_valid [gx+1][gy][3]  = l2_req_out_valid  [gx]  [gy][1];
        assign l2_req_out_ready[gx]  [gy][1]  = l2_req_in_ready   [gx+1][gy][3];
        assign l2_rsp_in       [gx+1][gy][3]  = l2_rsp_out        [gx]  [gy][1];
        assign l2_rsp_in_valid [gx+1][gy][3]  = l2_rsp_out_valid  [gx]  [gy][1];
        assign l2_rsp_out_ready[gx]  [gy][1]  = l2_rsp_in_ready   [gx+1][gy][3];
        // West(3) output of (gx+1,gy) → East(1) input of (gx,gy)
        assign l2_req_in       [gx]  [gy][1]  = l2_req_out        [gx+1][gy][3];
        assign l2_req_in_valid [gx]  [gy][1]  = l2_req_out_valid  [gx+1][gy][3];
        assign l2_req_out_ready[gx+1][gy][3]  = l2_req_in_ready   [gx]  [gy][1];
        assign l2_rsp_in       [gx]  [gy][1]  = l2_rsp_out        [gx+1][gy][3];
        assign l2_rsp_in_valid [gx]  [gy][1]  = l2_rsp_out_valid  [gx+1][gy][3];
        assign l2_rsp_out_ready[gx+1][gy][3]  = l2_rsp_in_ready   [gx]  [gy][1];
      end
    end

    // North-South connections
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_ns
      for (genvar gy = 0; gy < NumGroupsY - 1; gy++) begin : gen_l2_ns_y
        // North(0) output of (gx,gy) → South(2) input of (gx,gy+1)
        assign l2_req_in       [gx][gy+1][2]  = l2_req_out        [gx][gy]  [0];
        assign l2_req_in_valid [gx][gy+1][2]  = l2_req_out_valid  [gx][gy]  [0];
        assign l2_req_out_ready[gx][gy]  [0]  = l2_req_in_ready   [gx][gy+1][2];
        assign l2_rsp_in       [gx][gy+1][2]  = l2_rsp_out        [gx][gy]  [0];
        assign l2_rsp_in_valid [gx][gy+1][2]  = l2_rsp_out_valid  [gx][gy]  [0];
        assign l2_rsp_out_ready[gx][gy]  [0]  = l2_rsp_in_ready   [gx][gy+1][2];
        // South(2) output of (gx,gy+1) → North(0) input of (gx,gy)
        assign l2_req_in       [gx][gy]  [0]  = l2_req_out        [gx][gy+1][2];
        assign l2_req_in_valid [gx][gy]  [0]  = l2_req_out_valid  [gx][gy+1][2];
        assign l2_req_out_ready[gx][gy+1][2]  = l2_req_in_ready   [gx][gy]  [0];
        assign l2_rsp_in       [gx][gy]  [0]  = l2_rsp_out        [gx][gy+1][2];
        assign l2_rsp_in_valid [gx][gy]  [0]  = l2_rsp_out_valid  [gx][gy+1][2];
        assign l2_rsp_out_ready[gx][gy+1][2]  = l2_rsp_in_ready   [gx][gy]  [0];
      end
    end

    // --------------------------------------------------
    // Boundary tie-offs (North/South edges)
    // --------------------------------------------------

    // North boundary (gy=NumGroupsY-1, direction North=0)
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_north_bnd
      assign l2_req_in       [gx][NumGroupsY-1][0] = '0;
      assign l2_req_in_valid [gx][NumGroupsY-1][0] = 1'b0;
      assign l2_req_out_ready[gx][NumGroupsY-1][0] = 1'b1;
      assign l2_rsp_in       [gx][NumGroupsY-1][0] = '0;
      assign l2_rsp_in_valid [gx][NumGroupsY-1][0] = 1'b0;
      assign l2_rsp_out_ready[gx][NumGroupsY-1][0] = 1'b1;
    end

    // South boundary (gy=0, direction South=2)
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_south_bnd
      assign l2_req_in       [gx][0][2] = '0;
      assign l2_req_in_valid [gx][0][2] = 1'b0;
      assign l2_req_out_ready[gx][0][2] = 1'b1;
      assign l2_rsp_in       [gx][0][2] = '0;
      assign l2_rsp_in_valid [gx][0][2] = 1'b0;
      assign l2_rsp_out_ready[gx][0][2] = 1'b1;
    end

    // --------------------------------------------------
    // West HBM ejection points (HBM channels 0..NumGroupsY-1)
    // floo_tcdm_chimney (SbrPort, no router) at mesh edge:
    //   unpack req flit → reqrsp_to_axi → DRAM
    //   response → chimney packs flit with source route back to requester
    // HBM0: axi_demux splits DRAM from peripheral traffic.
    // --------------------------------------------------

    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_hbm_west
      localparam int unsigned HbmIdx = gy;
      localparam int unsigned HbmEndpointId = NumGroups + HbmIdx;

      // Chimney subordinate port ↔ REQRSP bundle bridge
      cache_trans_req_chan_t hbm_sbr_req;
      logic                 hbm_sbr_req_valid;
      logic                 hbm_sbr_req_ready;
      cache_trans_rsp_chan_t hbm_sbr_rsp;
      logic                 hbm_sbr_rsp_valid;
      logic                 hbm_sbr_rsp_ready;

      floo_tcdm_chimney #(
        .RouteCfg    ( floo_cachepool_noc_pkg::RouteCfg    ),
        .EnMgrPort   ( 1'b0                                ),
        .EnSbrPort   ( 1'b1                                ),
        .id_t        ( floo_cachepool_noc_pkg::id_t        ),
        .route_t     ( floo_cachepool_noc_pkg::route_t     ),
        .dst_t       ( floo_cachepool_noc_pkg::route_t     ),
        .hdr_t       ( l2_noc_hdr_t                        ),
        .req_chan_t  ( cache_trans_req_chan_t              ),
        .rsp_chan_t  ( cache_trans_rsp_chan_t              ),
        .floo_req_t  ( l2_noc_req_t                        ),
        .floo_rsp_t  ( l2_noc_rsp_t                        ),
        .addr_t      ( axi_addr_t                          ),
        .sam_rule_t  ( floo_cachepool_noc_pkg::sam_rule_t  ),
        .Sam         ( floo_cachepool_noc_pkg::Sam         )
      ) i_hbm_chimney (
        .clk_i            ( clk_i                                         ),
        .rst_ni           ( rst_ni                                        ),
        .test_enable_i    ( 1'b0                                          ),
        // Manager port: unused
        .mgr_req_i        ( '0                                            ),
        .mgr_req_valid_i  ( 1'b0                                          ),
        .mgr_req_ready_o  (                                               ),
        .mgr_rsp_o        (                                               ),
        .mgr_rsp_valid_o  (                                               ),
        .mgr_rsp_ready_i  ( 1'b0                                          ),
        // Subordinate port: drives reqrsp_to_axi
        .sbr_req_o        ( hbm_sbr_req                                   ),
        .sbr_req_valid_o  ( hbm_sbr_req_valid                             ),
        .sbr_req_ready_i  ( hbm_sbr_req_ready                             ),
        .sbr_rsp_i        ( hbm_sbr_rsp                                   ),
        .sbr_rsp_valid_i  ( hbm_sbr_rsp_valid                             ),
        .sbr_rsp_ready_o  ( hbm_sbr_rsp_ready                             ),
        .sbr_txn_id_i     ( hbm_sbr_rsp.user.l2_src_id                    ),
        // Routing
        .id_i             ( floo_cachepool_noc_pkg::id_t'(HbmEndpointId)        ),
        .route_table_i    ( floo_cachepool_noc_pkg::RoutingTables[HbmEndpointId]),
        // Request flit from mesh West(3) edge (no router)
        .floo_req_o       (                                               ),
        .floo_req_valid_o (                                               ),
        .floo_req_ready_i ( 1'b1                                          ),
        .floo_req_i       ( l2_req_out[0][gy][3]                          ),
        .floo_req_valid_i ( l2_req_out_valid[0][gy][3]                    ),
        .floo_req_ready_o ( l2_req_out_ready[0][gy][3]                    ),
        // Response flit into mesh West(3) edge
        .floo_rsp_o       ( l2_rsp_in[0][gy][3]                           ),
        .floo_rsp_valid_o ( l2_rsp_in_valid[0][gy][3]                     ),
        .floo_rsp_ready_i ( l2_rsp_in_ready[0][gy][3]                     ),
        .floo_rsp_i       ( '0                                            ),
        .floo_rsp_valid_i ( 1'b0                                          ),
        .floo_rsp_ready_o (                                               )
      );

      // Tie off: no requests injected from HBM, drain stray outgoing responses
      assign l2_req_in       [0][gy][3] = '0;
      assign l2_req_in_valid [0][gy][3] = 1'b0;
      assign l2_rsp_out_ready[0][gy][3] = 1'b1;

      // Pack chimney sbr signals into REQRSP bundle
      cache_trans_req_t  hbm_reqrsp_req;
      cache_trans_rsp_t  hbm_reqrsp_rsp;

      assign hbm_reqrsp_req = '{
        q:       hbm_sbr_req,
        q_valid: hbm_sbr_req_valid,
        p_ready: hbm_sbr_rsp_ready
      };
      assign hbm_sbr_req_ready = hbm_reqrsp_rsp.q_ready;
      assign hbm_sbr_rsp       = hbm_reqrsp_rsp.p;
      assign hbm_sbr_rsp_valid = hbm_reqrsp_rsp.p_valid;

      // HBM0: splits DRAM vs peripheral before AXI conversion. Uses
      // reqrsp_xbar rather than reqrsp_demux: the demux tracked every
      // dispatched request (regardless of target) in a single shared
      // in-order ID FIFO sized RespDepth, capping outstanding HBM0 refills
      // far below the windows available at the chimney/reqrsp_to_axi. The
      // xbar lets each downstream path track its own outstanding requests
      // independently. Reordering across the two paths is safe because
      // miss/request info lives in refill_user_t, not in arrival order.
      // Each path still has its own reqrsp_to_axi so the user-field FIFO
      // stays in-order per path and refill_user_t is preserved end-to-end.
      if (HbmIdx == 0) begin : gen_hbm0_demux

        // Address-based select: DRAM = port 0, Peripheral = port 1
        logic hbm0_reqrsp_sel;
        assign hbm0_reqrsp_sel = !((hbm_reqrsp_req.q.addr >= DramAddr) &&
                                    (hbm_reqrsp_req.q.addr <  DramAddr + DramPerChSize));

        cache_trans_req_t  [1:0] hbm0_demux_req;
        cache_trans_rsp_t  [1:0] hbm0_demux_rsp;

        cache_trans_req_chan_t [1:0] hbm0_xbar_mst_req;
        logic                   [1:0] hbm0_xbar_mst_req_valid;
        logic                   [1:0] hbm0_xbar_mst_req_ready;
        cache_trans_rsp_chan_t [1:0] hbm0_xbar_mst_rsp;
        logic                   [1:0] hbm0_xbar_mst_rsp_valid;
        logic                   [1:0] hbm0_xbar_mst_rsp_ready;

        logic                   hbm0_xbar_slv_req_ready;
        cache_trans_rsp_chan_t  hbm0_xbar_slv_rsp;
        logic                   hbm0_xbar_slv_rsp_valid;

        reqrsp_xbar #(
          .NumInp          ( 1                       ),
          .NumOut          ( 2                       ),
          .PipeReg         ( 1'b1                    ),
          .RspReg          ( 1'b1                    ),
          .tcdm_req_chan_t ( cache_trans_req_chan_t  ),
          .tcdm_rsp_chan_t ( cache_trans_rsp_chan_t  )
        ) i_hbm0_reqrsp_xbar (
          .clk_i            ( clk_i                       ),
          .rst_ni           ( rst_ni                      ),
          .slv_req_i        ( hbm_reqrsp_req.q            ),
          .slv_rr_i         ( '0                          ),
          .slv_req_valid_i  ( hbm_reqrsp_req.q_valid      ),
          .slv_req_ready_o  ( hbm0_xbar_slv_req_ready     ),
          .slv_rsp_o        ( hbm0_xbar_slv_rsp           ),
          .slv_rsp_valid_o  ( hbm0_xbar_slv_rsp_valid     ),
          .slv_rsp_ready_i  ( hbm_reqrsp_req.p_ready      ),
          .slv_sel_i        ( hbm0_reqrsp_sel             ),
          .slv_selected_o   (                             ),
          .mst_req_o        ( hbm0_xbar_mst_req           ),
          .mst_req_valid_o  ( hbm0_xbar_mst_req_valid     ),
          .mst_req_ready_i  ( hbm0_xbar_mst_req_ready     ),
          .mst_rsp_i        ( hbm0_xbar_mst_rsp           ),
          .mst_rr_i         ( '0                          ),
          .mst_rsp_valid_i  ( hbm0_xbar_mst_rsp_valid     ),
          .mst_rsp_ready_o  ( hbm0_xbar_mst_rsp_ready     ),
          .mst_sel_i        ( '0                          )
        );

        assign hbm_reqrsp_rsp = '{
          q_ready: hbm0_xbar_slv_req_ready,
          p:       hbm0_xbar_slv_rsp,
          p_valid: hbm0_xbar_slv_rsp_valid
        };

        for (genvar p = 0; p < 2; p++) begin : gen_hbm0_xbar_bundle
          assign hbm0_demux_req[p] = '{
            q:       hbm0_xbar_mst_req[p],
            q_valid: hbm0_xbar_mst_req_valid[p],
            p_ready: hbm0_xbar_mst_rsp_ready[p]
          };
          assign hbm0_xbar_mst_req_ready[p] = hbm0_demux_rsp[p].q_ready;
          assign hbm0_xbar_mst_rsp[p]       = hbm0_demux_rsp[p].p;
          assign hbm0_xbar_mst_rsp_valid[p] = hbm0_demux_rsp[p].p_valid;
        end

        // Port 0: DRAM — reqrsp_to_axi → axi_cut → TB
        axi_slv_cache_req_t  hbm0_dram_axi_req;
        axi_slv_cache_resp_t hbm0_dram_axi_rsp;

        reqrsp_to_axi #(
          .MaxTrans     ( L2RefillMaxTrans ),
          .ID           ( 0                     ),
          .EnBurst      ( 1                     ),
          .ShuffleId    ( 1                     ),
          .AxiIdWidth   ( WideIdWidthOut        ),
          .DataWidth    ( AxiDataWidth          ),
          .UserWidth    ( $bits(refill_user_t)  ),
          .AxiUserWidth ( AxiUserWidth          ),
          .reqrsp_req_t ( cache_trans_req_t     ),
          .reqrsp_rsp_t ( cache_trans_rsp_t     ),
          .axi_req_t    ( axi_slv_cache_req_t   ),
          .axi_rsp_t    ( axi_slv_cache_resp_t  )
        ) i_hbm0_dram_reqrsp_to_axi (
          .clk_i        ( clk_i              ),
          .rst_ni       ( rst_ni             ),
          .user_i       ( '0                 ),
          .reqrsp_req_i ( hbm0_demux_req[0]  ),
          .reqrsp_rsp_o ( hbm0_demux_rsp[0]  ),
          .axi_req_o    ( hbm0_dram_axi_req  ),
          .axi_rsp_i    ( hbm0_dram_axi_rsp  )
        );

        assign wide_axi_slv_req[0] = hbm0_dram_axi_req;
        assign hbm0_dram_axi_rsp   = wide_axi_slv_rsp[0];


        // Port 1: Non-DRAM — revert VA back to PA, then DW convert to 32b
        // All paths through the interconnect use scrambled (VA) addresses.
        // revertAddr recovers the physical address for the peripheral endpoint.
        cache_trans_req_t hbm0_peri_reqrsp_req;
        always_comb begin
          hbm0_peri_reqrsp_req        = hbm0_demux_req[1];
          hbm0_peri_reqrsp_req.q.addr = revertAddr(hbm0_demux_req[1].q.addr);
        end

        cache_trans_rsp_t hbm0_peri_reqrsp_rsp;
        assign hbm0_demux_rsp[1] = hbm0_peri_reqrsp_rsp;

        // W2N converter: 512b REQRSP → 32b REQRSP
        // Same user type (refill_user_t) on both sides.
        // We add a small 1-entry buffer with MSHR inside to reduce boot time
        reqrsp_w2n_converter #(
          .SlvDataWidth   ( AxiDataWidth              ),
          .MstDataWidth   ( 32                        ),
          .AddrWidth      ( AxiAddrWidth              ),
          .SlvUserWidth   ( $bits(refill_user_t)      ),
          .MstUserWidth   ( $bits(refill_user_t)      ),
          .MaxTrans       ( 4                         ),
          .EnRdBuf        ( 1'b1                      ),
          .CacheableBase  ( BootAddr                  ),
          .CacheableSize  ( 32'h1_0000                ),
          .slv_req_t      ( cache_trans_req_t         ),
          .slv_rsp_t      ( cache_trans_rsp_t         ),
          .mst_req_t      ( peri_narrow_req_t         ),
          .mst_rsp_t      ( peri_narrow_rsp_t         ),
          .slv_user_t     ( refill_user_t             )
        ) i_hbm0_peri_dw  (
          .clk_i          ( clk_i                     ),
          .rst_ni         ( rst_ni                    ),
          .slv_req_i      ( hbm0_peri_reqrsp_req      ),
          .slv_rsp_o      ( hbm0_peri_reqrsp_rsp      ),
          .mst_req_o      ( hbm0_peri_narrow_req      ),
          .mst_rsp_i      ( hbm0_peri_narrow_rsp      )
        );

      end else begin : gen_hbm_direct
        // Non-HBM0: single reqrsp_to_axi → DRAM
        axi_slv_cache_req_t  hbm_axi_req;
        axi_slv_cache_resp_t hbm_axi_rsp;

        reqrsp_to_axi #(
          .MaxTrans     ( L2RefillMaxTrans      ),
          .ID           ( 0                     ),
          .EnBurst      ( 1                     ),
          .ShuffleId    ( 1                     ),
          .AxiIdWidth   ( WideIdWidthOut        ),
          .DataWidth    ( AxiDataWidth          ),
          .UserWidth    ( $bits(refill_user_t)  ),
          .AxiUserWidth ( AxiUserWidth          ),
          .reqrsp_req_t ( cache_trans_req_t     ),
          .reqrsp_rsp_t ( cache_trans_rsp_t     ),
          .axi_req_t    ( axi_slv_cache_req_t   ),
          .axi_rsp_t    ( axi_slv_cache_resp_t  )
        ) i_hbm_reqrsp_to_axi (
          .clk_i        ( clk_i                 ),
          .rst_ni       ( rst_ni                ),
          .user_i       ( '0                    ),
          .reqrsp_req_i ( hbm_reqrsp_req        ),
          .reqrsp_rsp_o ( hbm_reqrsp_rsp        ),
          .axi_req_o    ( hbm_axi_req           ),
          .axi_rsp_i    ( hbm_axi_rsp           )
        );

        assign wide_axi_slv_req[HbmIdx] = hbm_axi_req;
        assign hbm_axi_rsp              = wide_axi_slv_rsp[HbmIdx];
      end
    end

    // --------------------------------------------------
    // East HBM ejection points (HBM channels NumGroupsY..2*NumGroupsY-1)
    // floo_tcdm_chimney (SbrPort, no router) at mesh edge.
    // --------------------------------------------------

    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_hbm_east
      localparam int unsigned HbmIdx = NumGroupsY + gy;
      localparam int unsigned HbmEndpointId = NumGroups + HbmIdx;

      // Chimney subordinate port ↔ REQRSP bundle bridge
      cache_trans_req_chan_t hbm_sbr_req;
      logic                  hbm_sbr_req_valid;
      logic                  hbm_sbr_req_ready;
      cache_trans_rsp_chan_t hbm_sbr_rsp;
      logic                  hbm_sbr_rsp_valid;
      logic                  hbm_sbr_rsp_ready;

      floo_tcdm_chimney #(
        .RouteCfg   ( floo_cachepool_noc_pkg::RouteCfg    ),
        .EnMgrPort  ( 1'b0                                ),
        .EnSbrPort  ( 1'b1                                ),
        .id_t       ( floo_cachepool_noc_pkg::id_t        ),
        .route_t    ( floo_cachepool_noc_pkg::route_t     ),
        .dst_t      ( floo_cachepool_noc_pkg::route_t     ),
        .hdr_t      ( l2_noc_hdr_t                        ),
        .req_chan_t ( cache_trans_req_chan_t              ),
        .rsp_chan_t ( cache_trans_rsp_chan_t              ),
        .floo_req_t ( l2_noc_req_t                        ),
        .floo_rsp_t ( l2_noc_rsp_t                        ),
        .addr_t     ( axi_addr_t                          ),
        .sam_rule_t ( floo_cachepool_noc_pkg::sam_rule_t  ),
        .Sam        ( floo_cachepool_noc_pkg::Sam         )
      ) i_hbm_chimney (
        .clk_i            ( clk_i                                          ),
        .rst_ni           ( rst_ni                                         ),
        .test_enable_i    ( 1'b0                                           ),
        // Manager port: unused
        .mgr_req_i        ( '0                                             ),
        .mgr_req_valid_i  ( 1'b0                                           ),
        .mgr_req_ready_o  (                                                ),
        .mgr_rsp_o        (                                                ),
        .mgr_rsp_valid_o  (                                                ),
        .mgr_rsp_ready_i  ( 1'b0                                           ),
        // Subordinate port: drives reqrsp_to_axi
        .sbr_req_o        ( hbm_sbr_req                                    ),
        .sbr_req_valid_o  ( hbm_sbr_req_valid                              ),
        .sbr_req_ready_i  ( hbm_sbr_req_ready                              ),
        .sbr_rsp_i        ( hbm_sbr_rsp                                    ),
        .sbr_rsp_valid_i  ( hbm_sbr_rsp_valid                              ),
        .sbr_rsp_ready_o  ( hbm_sbr_rsp_ready                              ),
        .sbr_txn_id_i     ( hbm_sbr_rsp.user.l2_src_id                     ),
        // Routing
        .id_i             ( floo_cachepool_noc_pkg::id_t'(HbmEndpointId)         ),
        .route_table_i    ( floo_cachepool_noc_pkg::RoutingTables[HbmEndpointId] ),
        // Request flit from mesh East(1) edge (no router)
        .floo_req_o       (                                                ),
        .floo_req_valid_o (                                                ),
        .floo_req_ready_i ( 1'b1                                           ),
        .floo_req_i       ( l2_req_out[NumGroupsX-1][gy][1]                ),
        .floo_req_valid_i ( l2_req_out_valid[NumGroupsX-1][gy][1]          ),
        .floo_req_ready_o ( l2_req_out_ready[NumGroupsX-1][gy][1]          ),
        // Response flit into mesh East(1) edge
        .floo_rsp_o       ( l2_rsp_in[NumGroupsX-1][gy][1]                 ),
        .floo_rsp_valid_o ( l2_rsp_in_valid[NumGroupsX-1][gy][1]           ),
        .floo_rsp_ready_i ( l2_rsp_in_ready[NumGroupsX-1][gy][1]           ),
        .floo_rsp_i       ( '0                                             ),
        .floo_rsp_valid_i ( 1'b0                                           ),
        .floo_rsp_ready_o (                                                )
      );

      // Tie off unused
      assign l2_req_in       [NumGroupsX-1][gy][1] = '0;
      assign l2_req_in_valid [NumGroupsX-1][gy][1] = 1'b0;
      assign l2_rsp_out_ready[NumGroupsX-1][gy][1] = 1'b1;

      // Pack chimney sbr signals into REQRSP bundle for reqrsp_to_axi
      cache_trans_req_t  hbm_reqrsp_req;
      cache_trans_rsp_t  hbm_reqrsp_rsp;

      assign hbm_reqrsp_req = '{
        q:       hbm_sbr_req,
        q_valid: hbm_sbr_req_valid,
        p_ready: hbm_sbr_rsp_ready
      };
      assign hbm_sbr_req_ready = hbm_reqrsp_rsp.q_ready;
      assign hbm_sbr_rsp       = hbm_reqrsp_rsp.p;
      assign hbm_sbr_rsp_valid = hbm_reqrsp_rsp.p_valid;

      // REQRSP → AXI conversion
      axi_slv_cache_req_t  hbm_axi_req;
      axi_slv_cache_resp_t hbm_axi_rsp;

      reqrsp_to_axi #(
        .MaxTrans     ( L2RefillMaxTrans ),
        .ID           ( 0                     ),
        .EnBurst      ( 1                     ),
        .ShuffleId    ( 1                     ),
        .AxiIdWidth   ( WideIdWidthOut        ),
        .DataWidth    ( AxiDataWidth          ),
        .UserWidth    ( $bits(refill_user_t)  ),
        .AxiUserWidth ( AxiUserWidth          ),
        .reqrsp_req_t ( cache_trans_req_t     ),
        .reqrsp_rsp_t ( cache_trans_rsp_t     ),
        .axi_req_t    ( axi_slv_cache_req_t   ),
        .axi_rsp_t    ( axi_slv_cache_resp_t  )
      ) i_hbm_reqrsp_to_axi (
        .clk_i        ( clk_i            ),
        .rst_ni       ( rst_ni           ),
        .user_i       ( '0               ),
        .reqrsp_req_i ( hbm_reqrsp_req   ),
        .reqrsp_rsp_o ( hbm_reqrsp_rsp   ),
        .axi_req_o    ( hbm_axi_req      ),
        .axi_rsp_i    ( hbm_axi_rsp      )
      );

      assign wide_axi_slv_req[HbmIdx] = hbm_axi_req;
      assign hbm_axi_rsp               = wide_axi_slv_rsp[HbmIdx];

    end

  end

  // --------------------------------------------------
  // AXI Cut: HBM → DRAM Output
  // --------------------------------------------------
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

  // --------------------------------------------------
  // Peripheral Fabric (REQRSP-based 2×3 xbar)
  // --------------------------------------------------
  //
  // Data path (all 32b REQRSP):
  //   Source [0]: HBM0 demux port 1 -> reqrsp_w2n_converter (512b-32b) -> pad src_id=0
  //   Source [1]: peri_ext_req_i (TB/SoC, already 32b REQRSP)          -> pad src_id=1
  //
  //   Target [0]: BootROM   -> reqrsp_to_reg -> bootrom
  //   Target [1]: CSR       -> reqrsp_to_reg -> cachepool_peripheral
  //   Target [2]: UART      -> reqrsp_to_axi -> axi_narrow_req_o
  //
  // Response routing: mst_sel_i = mst_rsp.user.src_id (1-bit, 0=NoC, 1=TB)

  localparam int unsigned PeriXbarNumSrc = 2;
  localparam int unsigned PeriXbarNumTgt = 3;

  typedef enum int unsigned {
    PeriTgtBootROM = 0,
    PeriTgtCSR     = 1,
    PeriTgtUART    = 2
  } peri_tgt_e;

  // Calculate the peripheral base address (needed for xbar rules).
  localparam logic [AxiAddrWidth-1:0] TCDMMask = ~(TCDMSize-1);
  addr_t tcdm_start_address, tcdm_end_address;
  assign tcdm_start_address = (cluster_base_addr_i & TCDMMask);
  assign tcdm_end_address   = (tcdm_start_address + TCDMSize) & TCDMMask;

  typedef logic [$clog2(PeriXbarNumTgt)-1:0] peri_tgt_sel_t;
  typedef logic                              peri_src_sel_t;

  function automatic peri_tgt_sel_t peri_addr_decode(input addr_t addr);
    if (addr >= BootAddr && addr < BootAddr + 32'h1_0000)
      return peri_tgt_sel_t'(PeriTgtBootROM);
    else if (addr >= UartAddr && addr < UartAddr + 32'h1_0000)
      return peri_tgt_sel_t'(PeriTgtUART);
    else
      return peri_tgt_sel_t'(PeriTgtCSR);
  endfunction

  // ---- Inline src_id packing: peri_narrow → peri_xbar (add 1-bit src_id) ----

  peri_xbar_req_chan_t [PeriXbarNumSrc-1:0] peri_xbar_src_req;
  logic                [PeriXbarNumSrc-1:0] peri_xbar_src_req_valid;
  logic                [PeriXbarNumSrc-1:0] peri_xbar_src_req_ready;
  peri_xbar_rsp_chan_t [PeriXbarNumSrc-1:0] peri_xbar_src_rsp;
  logic                [PeriXbarNumSrc-1:0] peri_xbar_src_rsp_valid;
  logic                [PeriXbarNumSrc-1:0] peri_xbar_src_rsp_ready;

  peri_xbar_req_chan_t [PeriXbarNumTgt-1:0] peri_xbar_tgt_req;
  logic                [PeriXbarNumTgt-1:0] peri_xbar_tgt_req_valid;
  logic                [PeriXbarNumTgt-1:0] peri_xbar_tgt_req_ready;
  peri_xbar_rsp_chan_t [PeriXbarNumTgt-1:0] peri_xbar_tgt_rsp;
  logic                [PeriXbarNumTgt-1:0] peri_xbar_tgt_rsp_valid;
  logic                [PeriXbarNumTgt-1:0] peri_xbar_tgt_rsp_ready;

  // Source [0]: HBM0 (src_id = 0)
  always_comb begin
    peri_xbar_src_req[0]       = '0;
    peri_xbar_src_req[0].addr  = hbm0_peri_narrow_req.q.addr;
    peri_xbar_src_req[0].write = hbm0_peri_narrow_req.q.write;
    peri_xbar_src_req[0].amo   = hbm0_peri_narrow_req.q.amo;
    peri_xbar_src_req[0].data  = hbm0_peri_narrow_req.q.data;
    peri_xbar_src_req[0].strb  = hbm0_peri_narrow_req.q.strb;
    peri_xbar_src_req[0].size  = hbm0_peri_narrow_req.q.size;
    peri_xbar_src_req[0].user  = '{src_id: 1'b0, refill: hbm0_peri_narrow_req.q.user};
  end
  assign peri_xbar_src_req_valid[0] = hbm0_peri_narrow_req.q_valid;
  assign peri_xbar_src_rsp_ready[0] = hbm0_peri_narrow_req.p_ready;

  assign hbm0_peri_narrow_rsp.q_ready = peri_xbar_src_req_ready[0];
  assign hbm0_peri_narrow_rsp.p.data  = peri_xbar_src_rsp[0].data;
  assign hbm0_peri_narrow_rsp.p.error = peri_xbar_src_rsp[0].error;
  assign hbm0_peri_narrow_rsp.p.write = peri_xbar_src_rsp[0].write;
  assign hbm0_peri_narrow_rsp.p.user  = peri_xbar_src_rsp[0].user.refill;
  assign hbm0_peri_narrow_rsp.p_valid = peri_xbar_src_rsp_valid[0];

  // Source [1]: TB/SoC external (src_id = 1)
  always_comb begin
    peri_xbar_src_req[1]       = '0;
    peri_xbar_src_req[1].addr  = peri_ext_req_i.q.addr;
    peri_xbar_src_req[1].write = peri_ext_req_i.q.write;
    peri_xbar_src_req[1].amo   = peri_ext_req_i.q.amo;
    peri_xbar_src_req[1].data  = peri_ext_req_i.q.data;
    peri_xbar_src_req[1].strb  = peri_ext_req_i.q.strb;
    peri_xbar_src_req[1].size  = peri_ext_req_i.q.size;
    peri_xbar_src_req[1].user  = '{src_id: 1'b1, refill: peri_ext_req_i.q.user};
  end
  assign peri_xbar_src_req_valid[1] = peri_ext_req_i.q_valid;
  assign peri_xbar_src_rsp_ready[1] = peri_ext_req_i.p_ready;

  assign peri_ext_rsp_o.q_ready = peri_xbar_src_req_ready[1];
  assign peri_ext_rsp_o.p.data  = peri_xbar_src_rsp[1].data;
  assign peri_ext_rsp_o.p.error = peri_xbar_src_rsp[1].error;
  assign peri_ext_rsp_o.p.write = peri_xbar_src_rsp[1].write;
  assign peri_ext_rsp_o.p.user  = peri_xbar_src_rsp[1].user.refill;
  assign peri_ext_rsp_o.p_valid = peri_xbar_src_rsp_valid[1];

  logic [NumTiles-1:0] use_barrier;
  // TODO: Connect to CSR
  //assign use_barrier = {NumTiles{1'b1}}; // for now all is set to 1
  logic [NumTiles-1:0] barrier_participation_mask;
  assign use_barrier = barrier_participation_mask;

  // ---- Address decode per source ----
  peri_tgt_sel_t [PeriXbarNumSrc-1:0] peri_slv_sel;
  assign peri_slv_sel[0] = peri_addr_decode(hbm0_peri_narrow_req.q.addr);
  assign peri_slv_sel[1] = peri_addr_decode(peri_ext_req_i.q.addr);

  // ---- Response routing per target: use src_id from user field ----
  peri_src_sel_t [PeriXbarNumTgt-1:0] peri_mst_sel;
  assign peri_mst_sel[0] = peri_xbar_tgt_rsp[0].user.src_id;
  assign peri_mst_sel[1] = peri_xbar_tgt_rsp[1].user.src_id;
  assign peri_mst_sel[2] = peri_xbar_tgt_rsp[2].user.src_id;

  // ---- 2×3 REQRSP Xbar ----
  reqrsp_xbar #(
    .NumInp          ( PeriXbarNumSrc       ),
    .NumOut          ( PeriXbarNumTgt       ),
    .PipeReg         ( 1'b1                 ),
    .RspReg          ( 1'b1                 ),
    .tcdm_req_chan_t ( peri_xbar_req_chan_t ),
    .tcdm_rsp_chan_t ( peri_xbar_rsp_chan_t )
  ) i_peri_xbar (
    .clk_i           ( clk_i                    ),
    .rst_ni          ( rst_ni                   ),
    .slv_req_i       ( peri_xbar_src_req        ),
    .slv_rr_i        ( '0                       ),
    .slv_req_valid_i ( peri_xbar_src_req_valid  ),
    .slv_req_ready_o ( peri_xbar_src_req_ready  ),
    .slv_rsp_o       ( peri_xbar_src_rsp        ),
    .slv_rsp_valid_o ( peri_xbar_src_rsp_valid  ),
    .slv_rsp_ready_i ( peri_xbar_src_rsp_ready  ),
    .slv_sel_i       ( peri_slv_sel             ),
    .slv_selected_o  ( /* unused */             ),
    .mst_req_o       ( peri_xbar_tgt_req        ),
    .mst_req_valid_o ( peri_xbar_tgt_req_valid  ),
    .mst_req_ready_i ( peri_xbar_tgt_req_ready  ),
    .mst_rsp_i       ( peri_xbar_tgt_rsp        ),
    .mst_rr_i        ( '0                       ),
    .mst_rsp_valid_i ( peri_xbar_tgt_rsp_valid  ),
    .mst_rsp_ready_o ( peri_xbar_tgt_rsp_ready  ),
    .mst_sel_i       ( peri_mst_sel             )
  );

  // ---- Target [0]: BootROM → reqrsp_to_reg → bootrom ----

  `REG_BUS_TYPEDEF_ALL(reg_bootrom, addr_t, narrow_data_t, narrow_strb_t)

  peri_xbar_req_t peri_bootrom_req;
  peri_xbar_rsp_t peri_bootrom_rsp;

  // Bundle xbar split channels into REQRSP struct
  assign peri_bootrom_req.q       = peri_xbar_tgt_req[PeriTgtBootROM];
  assign peri_bootrom_req.q_valid = peri_xbar_tgt_req_valid[PeriTgtBootROM];
  assign peri_bootrom_req.p_ready = peri_xbar_tgt_rsp_ready[PeriTgtBootROM];
  assign peri_xbar_tgt_req_ready[PeriTgtBootROM] = peri_bootrom_rsp.q_ready;
  assign peri_xbar_tgt_rsp[PeriTgtBootROM]       = peri_bootrom_rsp.p;
  assign peri_xbar_tgt_rsp_valid[PeriTgtBootROM] = peri_bootrom_rsp.p_valid;

  reg_bootrom_req_t bootrom_reg_req;
  reg_bootrom_rsp_t bootrom_reg_rsp;

  reqrsp_to_reg #(
    .AddrWidth    ( AxiAddrWidth              ),
    .DataWidth    ( 32                        ),
    .UserWidth    ( $bits(peri_xbar_user_t)   ),
    .FifoDepth    ( 2                         ),
    .ShiftResponse( 1'b0                      ),
    .user_t       ( peri_xbar_user_t          ),
    .reqrsp_req_t ( peri_xbar_req_t           ),
    .reqrsp_rsp_t ( peri_xbar_rsp_t           ),
    .reg_req_t    ( reg_bootrom_req_t         ),
    .reg_rsp_t    ( reg_bootrom_rsp_t         )
  ) i_reqrsp_to_reg_bootrom (
    .clk_i      ( clk_i            ),
    .rst_ni     ( rst_ni           ),
    .reqrsp_req_i ( peri_bootrom_req ),
    .reqrsp_rsp_o ( peri_bootrom_rsp ),
    .reg_req_o  ( bootrom_reg_req  ),
    .reg_rsp_i  ( bootrom_reg_rsp  )
  );

  bootrom #(
    .DataWidth ( 32          ),
    .AddrWidth ( AxiAddrWidth )
  ) i_bootrom (
    .clk_i   ( clk_i                           ),
    .req_i   ( bootrom_reg_req.valid           ),
    .addr_i  ( addr_t'(bootrom_reg_req.addr)   ),
    .rdata_o ( bootrom_reg_rsp.rdata           )
  );
  `FF(bootrom_reg_rsp.ready, bootrom_reg_req.valid, 1'b0)
  assign bootrom_reg_rsp.error = 1'b0;

  // ---- Target [1]: CSR → reqrsp_to_reg → cachepool_peripheral ----

  `REG_BUS_TYPEDEF_ALL(reg_csr, addr_t, narrow_data_t, narrow_strb_t)

  peri_xbar_req_t peri_csr_req;
  peri_xbar_rsp_t peri_csr_rsp;

  // Bundle xbar split channels into REQRSP struct
  assign peri_csr_req.q       = peri_xbar_tgt_req[PeriTgtCSR];
  assign peri_csr_req.q_valid = peri_xbar_tgt_req_valid[PeriTgtCSR];
  assign peri_csr_req.p_ready = peri_xbar_tgt_rsp_ready[PeriTgtCSR];
  assign peri_xbar_tgt_req_ready[PeriTgtCSR] = peri_csr_rsp.q_ready;
  assign peri_xbar_tgt_rsp[PeriTgtCSR]       = peri_csr_rsp.p;
  assign peri_xbar_tgt_rsp_valid[PeriTgtCSR] = peri_csr_rsp.p_valid;

  reg_csr_req_t reg_req;
  reg_csr_rsp_t reg_rsp;

  reqrsp_to_reg #(
    .AddrWidth    ( AxiAddrWidth              ),
    .DataWidth    ( 32                        ),
    .UserWidth    ( $bits(peri_xbar_user_t)   ),
    .FifoDepth    ( 2                         ),
    .ShiftResponse( 1'b0                      ),
    .user_t       ( peri_xbar_user_t          ),
    .reqrsp_req_t ( peri_xbar_req_t           ),
    .reqrsp_rsp_t ( peri_xbar_rsp_t           ),
    .reg_req_t    ( reg_csr_req_t             ),
    .reg_rsp_t    ( reg_csr_rsp_t             )
  ) i_reqrsp_to_reg_csr (
    .clk_i      ( clk_i      ),
    .rst_ni     ( rst_ni     ),
    .reqrsp_req_i ( peri_csr_req ),
    .reqrsp_rsp_o ( peri_csr_rsp ),
    .reg_req_o  ( reg_req    ),
    .reg_rsp_i  ( reg_rsp    )
  );

  cachepool_peripheral #(
    .AddrWidth     ( AxiAddrWidth    ),
    .SPMWidth      ( $clog2(L1NumSet)),
    .NumTiles      ( NumTiles        ),
    .reg_req_t     ( reg_csr_req_t   ),
    .reg_rsp_t     ( reg_csr_rsp_t   ),
    .cache_insn_t  ( cache_insn_t    )
  ) i_cachepool_cluster_peripheral (
    .clk_i                    ( clk_i                  ),
    .rst_ni                   ( rst_ni                 ),
    .eoc_o                    ( eoc_o                  ),
    .reg_req_i                ( reg_req                ),
    .reg_rsp_o                ( reg_rsp                ),
    .tcdm_start_address_i     ( tcdm_start_address     ),
    .tcdm_end_address_i       ( tcdm_end_address       ),
    .icache_prefetch_enable_o ( icache_prefetch_enable ),
    .cluster_hart_base_id_i   ( hart_base_id_i         ),
    .cluster_probe_o          ( cluster_probe_o        ),
    .dynamic_offset_o         ( dynamic_offset         ),
    .private_start_addr_o     ( private_start_addr     ),
    .l1d_spm_size_o           (                        ),
    .l1d_private_o            ( l1d_private            ),
    .l1d_insn_o               ( l1d_insn               ),
    .l1d_insn_valid_o         ( l1d_insn_valid         ),
    .l1d_insn_ready_i         ( l1d_insn_ready         ),
    .l1d_busy_o               ( l1d_busy               ),
    .barrier_participation_mask_o ( barrier_participation_mask )
  );

  // ---- Target [2]: UART → reqrsp_to_axi → axi_narrow_req_o ----

  peri_xbar_req_t peri_uart_req;
  peri_xbar_rsp_t peri_uart_rsp;

  // Bundle xbar split channels into REQRSP struct
  assign peri_uart_req.q       = peri_xbar_tgt_req[PeriTgtUART];
  assign peri_uart_req.q_valid = peri_xbar_tgt_req_valid[PeriTgtUART];
  assign peri_uart_req.p_ready = peri_xbar_tgt_rsp_ready[PeriTgtUART];
  assign peri_xbar_tgt_req_ready[PeriTgtUART] = peri_uart_rsp.q_ready;
  assign peri_xbar_tgt_rsp[PeriTgtUART]       = peri_uart_rsp.p;
  assign peri_xbar_tgt_rsp_valid[PeriTgtUART] = peri_uart_rsp.p_valid;

  reqrsp_to_axi #(
    .MaxTrans     ( 4                           ),
    .AxiIdWidth   ( SpatzAxiUartIdWidth         ),
    .DataWidth    ( 32                          ),
    .UserWidth    ( $bits(peri_xbar_user_t)     ),
    .AxiUserWidth ( AxiUserWidth                ),
    .reqrsp_req_t ( peri_xbar_req_t             ),
    .reqrsp_rsp_t ( peri_xbar_rsp_t             ),
    .axi_req_t    ( axi_uart_req_t              ),
    .axi_rsp_t    ( axi_uart_resp_t             )
  ) i_reqrsp_to_axi_uart (
    .clk_i        ( clk_i                       ),
    .rst_ni       ( rst_ni                      ),
    .user_i       ( '0                          ),
    .reqrsp_req_i ( peri_uart_req               ),
    .reqrsp_rsp_o ( peri_uart_rsp               ),
    .axi_req_o    ( axi_narrow_req_o            ),
    .axi_rsp_i    ( axi_narrow_resp_i           )
  );

endmodule
