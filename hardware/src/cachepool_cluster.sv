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
    /// Number of Core Complex (CC) slots in this cluster.
    parameter int                     unsigned               NumCC                              = 8,
    /// Data/TCDM memory depth per cut (in words).
    parameter int                     unsigned               TCDMDepth                          = 1024,
    /// Cluster peripheral address region size (in kB).
    parameter int                     unsigned               ClusterPeriphSize                  = 64,
    /// Number of TCDM Banks.
    parameter int                     unsigned               NrBanks                            = 2 * NumCC,
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
    /// Insert a register cut into off-loading path (request)
    parameter bit                                            RegisterOffloadReq                 = 1'b0,
    /// Insert Pipeline registers into data memory path (request)
    parameter bit                                            RegisterCoreReq                    = 1'b0,
    /// Insert Pipeline registers into data memory path (response)
    parameter bit                                            RegisterCoreRsp                    = 1'b0,
    /// Insert Pipeline registers after each memory cut
    parameter bit                                            RegisterTCDMCuts                   = 1'b0,
    /// Decouple external AXI plug
    parameter bit                                            RegisterExt                        = 1'b0,
    /// Insert a pipeline register on each group's cluster-facing barrier link
    parameter bit                                            RegisterBarrier                    = 1'b0,
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
    // TCDM read latency: 1 for most macros, adjust for pipelined macros (breaks the
    // instruction cache macros). `RegisterTCDMCuts` adds one cycle, accounted for here.
    parameter int                     unsigned               MemoryMacroLatency                 = 1 + RegisterTCDMCuts,
    /// # SRAM Configuration rules needed: L1D Tag + L1D Data + L1D FIFO + L1I Tag + L1I Data
    /*** ATTENTION: `NrSramCfg` should be changed if `L1NumDataBank` and `L1NumTagBank` is changed ***/
    parameter int                     unsigned               NrSramCfg                          = 1,
    /// Folded data bank configuration (0 = auto: min(4, L1AssoPerCtrl)).
    parameter bit                                            UseFoldedDataBanks                 = 1'b1,
    parameter int                     unsigned               FoldWayGroup                       = 0,
    parameter bit                                            UseHashWaySelect                   = 1'b1,
    /// Enable the SRAM forwarding buffer (default on; requires UseHashWaySelect).
    parameter bit                                            UseForwardingBuffer                = 1'b1,
    /// First hartid of the cluster; cores get hartids HartBaseId..HartBaseId+NumCC-1.
    parameter logic                   [9:0]                  HartBaseId                         = 10'h0
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

  // Narrow L2 mesh endpoint of the cluster peripheral, subordinate side: core accesses to the
  // CSRs and the UART.
  peri_noc_req_chan_t    peri_sbr_req;
  logic                  peri_sbr_req_valid;
  logic                  peri_sbr_req_ready;
  peri_narrow_rsp_chan_t peri_sbr_rsp;
  logic                  peri_sbr_rsp_valid;
  logic                  peri_sbr_rsp_ready;

  // 2. Peripherals
  logic         [NumTiles-1:0]                l1d_busy;

  // Configuration batch from the peripheral to the group configuration sender
  logic                                       cfg_start;
  group_cfg_reg_e                             cfg_reg;
  logic         [31:0]                        cfg_data;
  logic         [NumTiles-1:0]                cfg_tile_sel;
  logic                                       cfg_done;

  // Per-group error signals.
  logic         [NumGroups-1:0]               group_error;

  // Direct-wire barrier: one bit per group per slot, only for rounds that need the cluster.
  // Group-major; transposed to slot-major below for cachepool_cluster_barrier.
  logic  [NumGroups-1:0][NumBarrierSlots-1:0] group_barrier;
  logic  [NumBarrierSlots-1:0][NumGroups-1:0] group_barrier_slotmajor;
  // Broadcast to every group identically, same as the pre-multi-slot design.
  logic                 [NumBarrierSlots-1:0] barrier_done;
  // Per-slot group participation mask for the cluster-level barrier,
  // software-configured via the HW_BARRIER_PARTICIPATION_MASK peripheral
  // CSR (reset value: all groups).
  logic  [NumBarrierSlots-1:0][NumGroups-1:0] barrier_part_mask;

  always_comb begin : transpose_group_barrier
    for (int g = 0; g < NumGroups; g++) begin
      for (int s = 0; s < NumBarrierSlots; s++) begin
        group_barrier_slotmajor[s][g] = group_barrier[g][s];
      end
    end
  end

  cachepool_cluster_barrier #(
    .NrGroups ( NumGroups )
  ) i_cluster_barrier (
    .clk_i           ( clk_i                      ),
    .rst_ni          ( rst_ni                     ),
    .group_barrier_i ( group_barrier_slotmajor    ),
    .barrier_done_o  ( barrier_done               ),
    .barrier_mask_i  ( barrier_part_mask          )
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

  // Per-group narrow L2 mesh signals [NumGroupsX][NumGroupsY][direction 0..3]
  peri_noc_req_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_req_out;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_req_out_valid;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_req_out_ready;
  peri_noc_req_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_req_in;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_req_in_valid;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_req_in_ready;
  peri_noc_rsp_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_rsp_out;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_rsp_out_valid;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_rsp_out_ready;
  peri_noc_rsp_t [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_rsp_in;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_rsp_in_valid;
  logic          [NumGroupsX-1:0][NumGroupsY-1:0][3:0] peri_rsp_in_ready;

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
        .NumCC                    ( NumCoreGroup             ),
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
        .RegisterOffloadReq       ( RegisterOffloadReq       ),
        .RegisterCoreReq          ( RegisterCoreReq          ),
        .RegisterCoreRsp          ( RegisterCoreRsp          ),
        .RegisterTCDMCuts         ( RegisterTCDMCuts         ),
        .RegisterExt              ( RegisterExt              ),
        .RegisterBarrier          ( RegisterBarrier          ),
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
        .hart_base_id_i           ( HartBaseId + 10'(g * NumCoreGroup * NumScalarPerCC)         ),
        .tile_base_id_i           ( TileIDWidth'(g * NumTilesPerGroup)              ),
        .cluster_base_addr_i      ( cluster_base_addr_i                             ),
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
        // Narrow L2 mesh (4 directions)
        .peri_req_o               ( peri_req_out       [gx][gy]                     ),
        .peri_req_valid_o         ( peri_req_out_valid [gx][gy]                     ),
        .peri_req_ready_i         ( peri_req_out_ready [gx][gy]                     ),
        .peri_req_i               ( peri_req_in        [gx][gy]                     ),
        .peri_req_valid_i         ( peri_req_in_valid  [gx][gy]                     ),
        .peri_req_ready_o         ( peri_req_in_ready  [gx][gy]                     ),
        .peri_rsp_o               ( peri_rsp_out       [gx][gy]                     ),
        .peri_rsp_valid_o         ( peri_rsp_out_valid [gx][gy]                     ),
        .peri_rsp_ready_i         ( peri_rsp_out_ready [gx][gy]                     ),
        .peri_rsp_i               ( peri_rsp_in        [gx][gy]                     ),
        .peri_rsp_valid_i         ( peri_rsp_in_valid  [gx][gy]                     ),
        .peri_rsp_ready_o         ( peri_rsp_in_ready  [gx][gy]                     ),
        .l2_id_i                  ( floo_cachepool_noc_pkg::id_t'(gx * NumGroupsY + gy)         ),
        .l2_route_table_i         ( floo_cachepool_noc_pkg::RoutingTables[gx * NumGroupsY + gy] ),
        // Peripherals
        .icache_events_o          ( /* unused */                                    ),
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
        .group_barrier_o          ( group_barrier    [g]                                   ),
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
`ifndef TARGET_SYNTHESIS
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
`ifndef TARGET_SYNTHESIS
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
`ifndef TARGET_SYNTHESIS
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
`ifndef TARGET_SYNTHESIS
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

  // The group configuration registers are only reachable over the L2 mesh.
  `ASSERT_INIT(CheckMultiGroup, NumGroups > 1, "cachepool_cluster: NumGroups must be > 1")

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
    // Narrow L2 mesh: same interior links as the wide mesh
    // --------------------------------------------------

    for (genvar gx = 0; gx < NumGroupsX - 1; gx++) begin : gen_peri_ew
      for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_peri_ew_y
        // East(1) output of (gx,gy) <-> West(3) input of (gx+1,gy), both ways
        assign peri_req_in       [gx+1][gy][3] = peri_req_out       [gx]  [gy][1];
        assign peri_req_in_valid [gx+1][gy][3] = peri_req_out_valid [gx]  [gy][1];
        assign peri_req_out_ready[gx]  [gy][1] = peri_req_in_ready  [gx+1][gy][3];
        assign peri_rsp_in       [gx+1][gy][3] = peri_rsp_out       [gx]  [gy][1];
        assign peri_rsp_in_valid [gx+1][gy][3] = peri_rsp_out_valid [gx]  [gy][1];
        assign peri_rsp_out_ready[gx]  [gy][1] = peri_rsp_in_ready  [gx+1][gy][3];
        assign peri_req_in       [gx]  [gy][1] = peri_req_out       [gx+1][gy][3];
        assign peri_req_in_valid [gx]  [gy][1] = peri_req_out_valid [gx+1][gy][3];
        assign peri_req_out_ready[gx+1][gy][3] = peri_req_in_ready  [gx]  [gy][1];
        assign peri_rsp_in       [gx]  [gy][1] = peri_rsp_out       [gx+1][gy][3];
        assign peri_rsp_in_valid [gx]  [gy][1] = peri_rsp_out_valid [gx+1][gy][3];
        assign peri_rsp_out_ready[gx+1][gy][3] = peri_rsp_in_ready  [gx]  [gy][1];
      end
    end

    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_peri_ns
      for (genvar gy = 0; gy < NumGroupsY - 1; gy++) begin : gen_peri_ns_y
        // North(0) output of (gx,gy) <-> South(2) input of (gx,gy+1), both ways
        assign peri_req_in       [gx][gy+1][2] = peri_req_out       [gx][gy]  [0];
        assign peri_req_in_valid [gx][gy+1][2] = peri_req_out_valid [gx][gy]  [0];
        assign peri_req_out_ready[gx][gy]  [0] = peri_req_in_ready  [gx][gy+1][2];
        assign peri_rsp_in       [gx][gy+1][2] = peri_rsp_out       [gx][gy]  [0];
        assign peri_rsp_in_valid [gx][gy+1][2] = peri_rsp_out_valid [gx][gy]  [0];
        assign peri_rsp_out_ready[gx][gy]  [0] = peri_rsp_in_ready  [gx][gy+1][2];
        assign peri_req_in       [gx][gy]  [0] = peri_req_out       [gx][gy+1][2];
        assign peri_req_in_valid [gx][gy]  [0] = peri_req_out_valid [gx][gy+1][2];
        assign peri_req_out_ready[gx][gy+1][2] = peri_req_in_ready  [gx][gy]  [0];
        assign peri_rsp_in       [gx][gy]  [0] = peri_rsp_out       [gx][gy+1][2];
        assign peri_rsp_in_valid [gx][gy]  [0] = peri_rsp_out_valid [gx][gy+1][2];
        assign peri_rsp_out_ready[gx][gy+1][2] = peri_rsp_in_ready  [gx][gy]  [0];
      end
    end

    // Narrow mesh boundary: only the West port of group (0,0) has an endpoint (i_peri_chimney
    // below). Every other edge port is tied off and never sees a flit.
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_peri_bnd_x
      for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_peri_bnd_y
        for (genvar d = 0; d < 4; d++) begin : gen_peri_bnd_d
          localparam bit IsEdge = ((d == 0) && (gy == NumGroupsY - 1)) ||
                                  ((d == 1) && (gx == NumGroupsX - 1)) ||
                                  ((d == 2) && (gy == 0))              ||
                                  ((d == 3) && (gx == 0));
          localparam bit IsPeriPort = (d == 3) && (gx == 0) && (gy == 0);
          if (IsEdge && !IsPeriPort) begin : gen_tieoff
            assign peri_req_in       [gx][gy][d] = '0;
            assign peri_req_in_valid [gx][gy][d] = 1'b0;
            assign peri_req_out_ready[gx][gy][d] = 1'b1;
            assign peri_rsp_in       [gx][gy][d] = '0;
            assign peri_rsp_in_valid [gx][gy][d] = 1'b0;
            assign peri_rsp_out_ready[gx][gy][d] = 1'b1;
            `ASSERT(PeriEdgeNoReq, !peri_req_out_valid[gx][gy][d], clk_i, !rst_ni,
                "cachepool_cluster: narrow request lost at a mesh edge")
            `ASSERT(PeriEdgeNoRsp, !peri_rsp_out_valid[gx][gy][d], clk_i, !rst_ni,
                "cachepool_cluster: narrow response lost at a mesh edge")
          end
        end
      end
    end

    // --------------------------------------------------
    // North/South boundary: tied off (8ch) or hosts extra HBM chimneys for
    // more refill bandwidth (16ch). Assertion catches a mismatched mesh
    // shape/channel count.
    // --------------------------------------------------

    // NumHbmAllSides, HbmPerSide and L2PeriphChannel come from cachepool_pkg.
    localparam int unsigned NumHbmWestEast = 2 * NumGroupsY;
`ifndef TARGET_SYNTHESIS
    initial assert (NumL2Channel == NumHbmWestEast || NumL2Channel == NumHbmAllSides)
      else $fatal(1, "NumL2Channel must equal the West/East or all-sides chimney count.");
`endif

    // West/East same-ID placement (4ch/4g, else linear): remap channel ID <-> port so each
    // group reaches its own-ID channel in 1 hop. All-sides uses the side-contiguous scheme
    // below instead. SAM and address scrambling are unaffected either way.
    localparam bit L2SameIdPlacement = (NumL2Channel == NumGroups);
    // All-sides placement: one aligned block of HbmPerSide channels per edge (one controller IP,
    // in floorplan order). The side-contiguous IDs below assume a 4x4 mesh, so reject any other
    // mesh shape asking for all-sides chimneys rather than mis-wiring it.
`ifndef TARGET_SYNTHESIS
    initial assert (NumL2Channel != NumHbmAllSides || (NumGroupsX == 4 && NumGroupsY == 4))
      else $fatal(1, "All-sides HBM placement is only implemented for a 4x4 group mesh.");
`endif
    // West/East same-ID needs both columns on an edge, i.e. exactly 2 columns.
    // NumL2Channel == NumGroups == NumHbmWestEast already forces this, so the
    // check only guards against a future edit breaking that equality.
`ifndef TARGET_SYNTHESIS
    initial assert (!L2SameIdPlacement || NumL2Channel == NumHbmAllSides || NumGroupsX == 2)
      else $fatal(1, "West/East same-ID HBM placement requires a 2-column group mesh.");
`endif

    if (NumL2Channel == NumHbmWestEast) begin : gen_l2_north_south_tieoff
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
    end : gen_l2_north_south_tieoff

    // --------------------------------------------------
    // West HBM ejection points, one per mesh row: floo_tcdm_chimney (SbrPort, no router)
    // unpacks req flits -> reqrsp_to_axi -> DRAM and source-routes responses back.
    // HBM0 also serves the BootROM (reqrsp_xbar, see gen_hbm0_demux).
    // --------------------------------------------------

    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_hbm_west
      // All-sides: West owns HbmPerSide..2*HbmPerSide-1, bottom to top
      // (4x4: 4,5,6,7). Two-column same-ID keeps the group's own ID (2x2: 0,2).
      localparam int unsigned HbmIdx =
        (NumL2Channel == NumHbmAllSides) ? HbmPerSide + gy :
        !L2SameIdPlacement               ? gy              :
                                           gy * NumGroupsX;
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
        // Request flits on the mesh West(3) edge (no router). Without a manager port the
        // chimney injects nothing and drains stray responses.
        .floo_req_o       ( l2_req_in[0][gy][3]                           ),
        .floo_req_valid_o ( l2_req_in_valid[0][gy][3]                     ),
        .floo_req_ready_i ( l2_req_in_ready[0][gy][3]                     ),
        .floo_req_i       ( l2_req_out[0][gy][3]                          ),
        .floo_req_valid_i ( l2_req_out_valid[0][gy][3]                    ),
        .floo_req_ready_o ( l2_req_out_ready[0][gy][3]                    ),
        // Response flits on the mesh West(3) edge
        .floo_rsp_o       ( l2_rsp_in[0][gy][3]                           ),
        .floo_rsp_valid_o ( l2_rsp_in_valid[0][gy][3]                     ),
        .floo_rsp_ready_i ( l2_rsp_in_ready[0][gy][3]                     ),
        .floo_rsp_i       ( l2_rsp_out[0][gy][3]                          ),
        .floo_rsp_valid_i ( l2_rsp_out_valid[0][gy][3]                    ),
        .floo_rsp_ready_o ( l2_rsp_out_ready[0][gy][3]                    )
      );

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

      // HBM0: split DRAM vs BootROM with reqrsp_xbar, not reqrsp_demux, whose shared in-order
      // ID FIFO capped outstanding refills. Cross-path reordering is safe (miss info is in
      // refill_user_t).
      if (HbmIdx == L2PeriphChannel) begin : gen_hbm0_demux

        // Select DRAM = port 0, BootROM = port 1. The DRAM window is this chimney's channel slice
        // (channel L2PeriphChannel under all-sides placement); the interconnect carries scrambled
        // addresses, revertAddr recovers the physical one.
        localparam int unsigned HbmChBase = DramAddr + HbmIdx * DramPerChSize;
        addr_t hbm0_pa;
        logic  hbm0_reqrsp_sel;
        assign hbm0_pa         = revertAddr(hbm_reqrsp_req.q.addr);
        assign hbm0_reqrsp_sel = !((hbm_reqrsp_req.q.addr >= HbmChBase) &&
                                   (hbm_reqrsp_req.q.addr <  HbmChBase + DramPerChSize));

        // Everything outside the DRAM slice must be an iCache refill of the BootROM
        `ASSERT(Hbm0BootromOnly, (hbm_reqrsp_req.q_valid && hbm0_reqrsp_sel) |->
            ((hbm0_pa >= BootAddr) && (hbm0_pa < BootAddr + BootromSize)), clk_i, !rst_ni,
            $sformatf("cachepool_cluster: wide L2 access to unmapped address 0x%08x", hbm0_pa))

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

        assign wide_axi_slv_req[HbmIdx] = hbm0_dram_axi_req;
        assign hbm0_dram_axi_rsp        = wide_axi_slv_rsp[HbmIdx];

        // Port 1: BootROM, one full-width word per iCache line refill
        `REG_BUS_TYPEDEF_ALL(reg_bootrom, addr_t, data_cache_t, strb_cache_t)

        cache_trans_req_t   hbm0_bootrom_req;
        reg_bootrom_req_t   bootrom_reg_req;
        reg_bootrom_rsp_t   bootrom_reg_rsp;

        always_comb begin
          hbm0_bootrom_req        = hbm0_demux_req[1];
          hbm0_bootrom_req.q.addr = revertAddr(hbm0_demux_req[1].q.addr);
        end

        reqrsp_to_reg #(
          .AddrWidth     ( AxiAddrWidth          ),
          .DataWidth     ( AxiDataWidth          ),
          .UserWidth     ( $bits(refill_user_t)  ),
          .ShiftResponse ( 1'b0                  ),
          .user_t        ( refill_user_t         ),
          .reqrsp_req_t  ( cache_trans_req_t     ),
          .reqrsp_rsp_t  ( cache_trans_rsp_t     ),
          .reg_req_t     ( reg_bootrom_req_t     ),
          .reg_rsp_t     ( reg_bootrom_rsp_t     )
        ) i_reqrsp_to_reg_bootrom (
          .clk_i         ( clk_i                 ),
          .rst_ni        ( rst_ni                ),
          .reqrsp_req_i  ( hbm0_bootrom_req      ),
          .reqrsp_rsp_o  ( hbm0_demux_rsp[1]     ),
          .reg_req_o     ( bootrom_reg_req       ),
          .reg_rsp_i     ( bootrom_reg_rsp       )
        );

        bootrom #(
          .DataWidth ( AxiDataWidth ),
          .AddrWidth ( AxiAddrWidth )
        ) i_bootrom (
          .clk_i   ( clk_i                         ),
          .req_i   ( bootrom_reg_req.valid         ),
          .addr_i  ( addr_t'(bootrom_reg_req.addr) ),
          .rdata_o ( bootrom_reg_rsp.rdata         )
        );
        // The ROM registers its address: ready one cycle after each new address, so
        // back-to-back requests get a setup cycle each.
        `FF(bootrom_reg_rsp.ready, bootrom_reg_req.valid & ~bootrom_reg_rsp.ready, 1'b0)
        assign bootrom_reg_rsp.error = 1'b0;

        `ASSERT_INIT(CheckBootromWidth, BootromDataWidth == AxiDataWidth,
            "cachepool_cluster: bootrom_data_width must equal the L2 refill width")

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
    // Narrow L2 mesh endpoint of the cluster peripheral, West of group (0,0) with HBM0's ID and
    // routes. Subordinate port: core CSR/UART accesses; manager port: configuration batches,
    // one register write per group.
    // --------------------------------------------------

    peri_noc_req_chan_t    peri_mgr_req;
    logic                  peri_mgr_req_valid;
    logic                  peri_mgr_req_ready;
    peri_narrow_rsp_chan_t peri_mgr_rsp;
    logic                  peri_mgr_rsp_valid;
    logic                  peri_mgr_rsp_ready;

    // Requests carry this endpoint's ID so the groups route their responses back here.
    cachepool_group_cfg_sender #(
      .req_chan_t ( peri_noc_req_chan_t    ),
      .rsp_chan_t ( peri_narrow_rsp_chan_t ),
      .user_t     ( peri_narrow_user_t     ),
      .ReqUser    ( '{l2_src_id: floo_cachepool_noc_pkg::id_t'(PeriEndpointId), default: '0} )
    ) i_group_cfg_sender (
      .clk_i       ( clk_i              ),
      .rst_ni      ( rst_ni             ),
      .start_i     ( cfg_start          ),
      .reg_i       ( cfg_reg            ),
      .data_i      ( cfg_data           ),
      .tile_sel_i  ( cfg_tile_sel       ),
      .done_o      ( cfg_done           ),
      .req_o       ( peri_mgr_req       ),
      .req_valid_o ( peri_mgr_req_valid ),
      .req_ready_i ( peri_mgr_req_ready ),
      .rsp_i       ( peri_mgr_rsp       ),
      .rsp_valid_i ( peri_mgr_rsp_valid ),
      .rsp_ready_o ( peri_mgr_rsp_ready )
    );

    floo_tcdm_chimney #(
      .RouteCfg   ( PeriRouteCfg                        ),
      .EnMgrPort  ( 1'b1                                ),
      .EnSbrPort  ( 1'b1                                ),
      .id_t       ( floo_cachepool_noc_pkg::id_t        ),
      .route_t    ( floo_cachepool_noc_pkg::route_t     ),
      .dst_t      ( floo_cachepool_noc_pkg::route_t     ),
      .hdr_t      ( l2_noc_hdr_t                        ),
      .req_chan_t ( peri_noc_req_chan_t                 ),
      .rsp_chan_t ( peri_narrow_rsp_chan_t              ),
      .floo_req_t ( peri_noc_req_t                      ),
      .floo_rsp_t ( peri_noc_rsp_t                      ),
      .addr_t     ( axi_addr_t                          ),
      .sam_rule_t ( floo_cachepool_noc_pkg::sam_rule_t  ),
      .Sam        ( PeriSam                             )
    ) i_peri_chimney (
      .clk_i            ( clk_i                                                  ),
      .rst_ni           ( rst_ni                                                 ),
      .test_enable_i    ( 1'b0                                                   ),
      // Manager port: group configuration writes
      .mgr_req_i        ( peri_mgr_req                                           ),
      .mgr_req_valid_i  ( peri_mgr_req_valid                                     ),
      .mgr_req_ready_o  ( peri_mgr_req_ready                                     ),
      .mgr_rsp_o        ( peri_mgr_rsp                                           ),
      .mgr_rsp_valid_o  ( peri_mgr_rsp_valid                                     ),
      .mgr_rsp_ready_i  ( peri_mgr_rsp_ready                                     ),
      // Subordinate port: core accesses to the peripheral xbar
      .sbr_req_o        ( peri_sbr_req                                           ),
      .sbr_req_valid_o  ( peri_sbr_req_valid                                     ),
      .sbr_req_ready_i  ( peri_sbr_req_ready                                     ),
      .sbr_rsp_i        ( peri_sbr_rsp                                           ),
      .sbr_rsp_valid_i  ( peri_sbr_rsp_valid                                     ),
      .sbr_rsp_ready_o  ( peri_sbr_rsp_ready                                     ),
      .sbr_txn_id_i     ( peri_sbr_rsp.user.l2_src_id                            ),
      // Routing
      .id_i             ( floo_cachepool_noc_pkg::id_t'(PeriEndpointId)          ),
      .route_table_i    ( floo_cachepool_noc_pkg::RoutingTables[PeriEndpointId]  ),
      // Request flits on the narrow mesh West(3) edge of group (0,0)
      .floo_req_o       ( peri_req_in[0][0][3]                                   ),
      .floo_req_valid_o ( peri_req_in_valid[0][0][3]                             ),
      .floo_req_ready_i ( peri_req_in_ready[0][0][3]                             ),
      .floo_req_i       ( peri_req_out[0][0][3]                                  ),
      .floo_req_valid_i ( peri_req_out_valid[0][0][3]                            ),
      .floo_req_ready_o ( peri_req_out_ready[0][0][3]                            ),
      // Response flits on the narrow mesh West(3) edge of group (0,0)
      .floo_rsp_o       ( peri_rsp_in[0][0][3]                                   ),
      .floo_rsp_valid_o ( peri_rsp_in_valid[0][0][3]                             ),
      .floo_rsp_ready_i ( peri_rsp_in_ready[0][0][3]                             ),
      .floo_rsp_i       ( peri_rsp_out[0][0][3]                                  ),
      .floo_rsp_valid_i ( peri_rsp_out_valid[0][0][3]                            ),
      .floo_rsp_ready_o ( peri_rsp_out_ready[0][0][3]                            )
    );

    // --------------------------------------------------
    // East HBM ejection points (one per mesh row, channel ID per HbmIdx below)
    // floo_tcdm_chimney (SbrPort, no router) at mesh edge.
    // --------------------------------------------------

    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_hbm_east
      // All-sides: East owns 2*HbmPerSide..3*HbmPerSide-1, bottom to top
      // (4x4: 8,9,10,11). Two-column same-ID keeps the group's own ID (2x2: 1,3).
      localparam int unsigned HbmIdx =
        (NumL2Channel == NumHbmAllSides) ? 2 * HbmPerSide + gy          :
        !L2SameIdPlacement               ? NumGroupsY + gy              :
                                           gy * NumGroupsX + NumGroupsX - 1;
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
      assign hbm_axi_rsp              = wide_axi_slv_rsp[HbmIdx];

    end

    // --------------------------------------------------
    // North/South HBM ejection points (16ch only), mirroring gen_hbm_east
    // (no demux: L2PeriphChannel always lands in gen_hbm_west at gy=0).
    // --------------------------------------------------

    if (NumL2Channel == NumHbmAllSides) begin : gen_hbm_north_south

      for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_hbm_north
        // North owns the top aligned block, left to right
        // (gx 0,1,2,3 -> channel 12,13,14,15).
        localparam int unsigned HbmIdx = 3 * HbmPerSide + gx;
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
          // Request flit from mesh North(0) edge (no router)
          .floo_req_o       (                                                ),
          .floo_req_valid_o (                                                ),
          .floo_req_ready_i ( 1'b1                                           ),
          .floo_req_i       ( l2_req_out[gx][NumGroupsY-1][0]                ),
          .floo_req_valid_i ( l2_req_out_valid[gx][NumGroupsY-1][0]          ),
          .floo_req_ready_o ( l2_req_out_ready[gx][NumGroupsY-1][0]          ),
          // Response flit into mesh North(0) edge
          .floo_rsp_o       ( l2_rsp_in[gx][NumGroupsY-1][0]                 ),
          .floo_rsp_valid_o ( l2_rsp_in_valid[gx][NumGroupsY-1][0]           ),
          .floo_rsp_ready_i ( l2_rsp_in_ready[gx][NumGroupsY-1][0]           ),
          .floo_rsp_i       ( '0                                             ),
          .floo_rsp_valid_i ( 1'b0                                           ),
          .floo_rsp_ready_o (                                                )
        );

        // Tie off unused
        assign l2_req_in       [gx][NumGroupsY-1][0] = '0;
        assign l2_req_in_valid [gx][NumGroupsY-1][0] = 1'b0;
        assign l2_rsp_out_ready[gx][NumGroupsY-1][0] = 1'b1;

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
        assign hbm_axi_rsp              = wide_axi_slv_rsp[HbmIdx];

      end

      for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_hbm_south
        // South owns the bottom aligned block, left to right
        // (gx 0,1,2,3 -> channel 0,1,2,3).
        localparam int unsigned HbmIdx = gx;
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
          // Request flit from mesh South(2) edge (no router)
          .floo_req_o       (                                                ),
          .floo_req_valid_o (                                                ),
          .floo_req_ready_i ( 1'b1                                           ),
          .floo_req_i       ( l2_req_out[gx][0][2]                           ),
          .floo_req_valid_i ( l2_req_out_valid[gx][0][2]                     ),
          .floo_req_ready_o ( l2_req_out_ready[gx][0][2]                     ),
          // Response flit into mesh South(2) edge
          .floo_rsp_o       ( l2_rsp_in[gx][0][2]                            ),
          .floo_rsp_valid_o ( l2_rsp_in_valid[gx][0][2]                      ),
          .floo_rsp_ready_i ( l2_rsp_in_ready[gx][0][2]                      ),
          .floo_rsp_i       ( '0                                             ),
          .floo_rsp_valid_i ( 1'b0                                           ),
          .floo_rsp_ready_o (                                                )
        );

        // Tie off unused
        assign l2_req_in       [gx][0][2] = '0;
        assign l2_req_in_valid [gx][0][2] = 1'b0;
        assign l2_rsp_out_ready[gx][0][2] = 1'b1;

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
        assign hbm_axi_rsp              = wide_axi_slv_rsp[HbmIdx];

      end

    end : gen_hbm_north_south

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

  // style-waive: COMMENT_BLOCK: peripheral fabric data path diagram
  // --------------------------------------------------
  // Peripheral Fabric (REQRSP-based 2×2 xbar)
  // --------------------------------------------------
  //
  // Data path (all 32b REQRSP):
  //   Source [0]: narrow L2 mesh (i_peri_chimney subordinate port)   -> pad src_id=0
  //   Source [1]: peri_ext_req_i (TB/SoC, already 32b REQRSP)        -> pad src_id=1
  //
  //   Target [0]: CSR       -> reqrsp_to_reg -> cachepool_peripheral
  //   Target [1]: UART      -> reqrsp_to_axi -> axi_narrow_req_o
  //
  // The BootROM is not reachable here: it sits on the wide mesh (HBM0 demux port 1).
  //
  // Response routing: mst_sel_i = mst_rsp.user.src_id (1-bit, 0=NoC, 1=TB)

  localparam int unsigned PeriXbarNumSrc = 2;
  localparam int unsigned PeriXbarNumTgt = 2;

  typedef enum int unsigned {
    PeriTgtCSR     = 0,
    PeriTgtUART    = 1
  } peri_tgt_e;

  // Calculate the peripheral base address (needed for xbar rules).
  localparam logic [AxiAddrWidth-1:0] TCDMMask = ~(TCDMSize-1);
  addr_t tcdm_start_address, tcdm_end_address;
  assign tcdm_start_address = (cluster_base_addr_i & TCDMMask);
  assign tcdm_end_address   = (tcdm_start_address + TCDMSize) & TCDMMask;

  typedef logic [$clog2(PeriXbarNumTgt)-1:0] peri_tgt_sel_t;
  typedef logic                              peri_src_sel_t;

  // style-waive: AUTOMATIC: boundary checks
  function automatic peri_tgt_sel_t peri_addr_decode(input addr_t addr);
    if (addr >= UartAddr && addr < UartAddr + 32'h1_0000)
      return peri_tgt_sel_t'(PeriTgtUART);
    else
      return peri_tgt_sel_t'(PeriTgtCSR);
  endfunction

  // ---- Inline src_id packing: narrow mesh / peri_narrow → peri_xbar (add 1-bit src_id) ----

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

  // Source [0]: narrow L2 mesh (src_id = 0). The flit has no AMO field.
  always_comb begin
    peri_xbar_src_req[0]       = '0;
    peri_xbar_src_req[0].addr  = peri_sbr_req.addr;
    peri_xbar_src_req[0].write = peri_sbr_req.write;
    peri_xbar_src_req[0].amo   = reqrsp_pkg::AMONone;
    peri_xbar_src_req[0].data  = peri_sbr_req.data;
    peri_xbar_src_req[0].strb  = peri_sbr_req.strb;
    peri_xbar_src_req[0].size  = peri_sbr_req.size;
    peri_xbar_src_req[0].user  = '{src_id: 1'b0, narrow: peri_sbr_req.user};
  end
  assign peri_xbar_src_req_valid[0] = peri_sbr_req_valid;
  assign peri_xbar_src_rsp_ready[0] = peri_sbr_rsp_ready;

  assign peri_sbr_req_ready = peri_xbar_src_req_ready[0];
  assign peri_sbr_rsp       = '{
    data:  peri_xbar_src_rsp[0].data,
    error: peri_xbar_src_rsp[0].error,
    write: peri_xbar_src_rsp[0].write,
    user:  peri_xbar_src_rsp[0].user.narrow
  };
  assign peri_sbr_rsp_valid = peri_xbar_src_rsp_valid[0];

  // Source [1]: TB/SoC external (src_id = 1)
  always_comb begin
    peri_xbar_src_req[1]       = '0;
    peri_xbar_src_req[1].addr  = peri_ext_req_i.q.addr;
    peri_xbar_src_req[1].write = peri_ext_req_i.q.write;
    peri_xbar_src_req[1].amo   = peri_ext_req_i.q.amo;
    peri_xbar_src_req[1].data  = peri_ext_req_i.q.data;
    peri_xbar_src_req[1].strb  = peri_ext_req_i.q.strb;
    peri_xbar_src_req[1].size  = peri_ext_req_i.q.size;
    peri_xbar_src_req[1].user  = '{src_id: 1'b1, narrow: peri_ext_req_i.q.user};
  end
  assign peri_xbar_src_req_valid[1] = peri_ext_req_i.q_valid;
  assign peri_xbar_src_rsp_ready[1] = peri_ext_req_i.p_ready;

  assign peri_ext_rsp_o.q_ready = peri_xbar_src_req_ready[1];
  assign peri_ext_rsp_o.p.data  = peri_xbar_src_rsp[1].data;
  assign peri_ext_rsp_o.p.error = peri_xbar_src_rsp[1].error;
  assign peri_ext_rsp_o.p.write = peri_xbar_src_rsp[1].write;
  assign peri_ext_rsp_o.p.user  = peri_xbar_src_rsp[1].user.narrow;
  assign peri_ext_rsp_o.p_valid = peri_xbar_src_rsp_valid[1];

  // ---- Address decode per source ----
  peri_tgt_sel_t [PeriXbarNumSrc-1:0] peri_slv_sel;
  assign peri_slv_sel[0] = peri_addr_decode(peri_sbr_req.addr);
  assign peri_slv_sel[1] = peri_addr_decode(peri_ext_req_i.q.addr);

  // Core accesses only reach the CSRs and the UART; anything else is a software bug (stray
  // pointer) that would silently read 0 from the CSR target, so flag it with its source.
  `ifndef TARGET_SYNTHESIS
  logic peri_core_addr_ok;
  assign peri_core_addr_ok =
      ((peri_sbr_req.addr >= tcdm_end_address) &&
       (peri_sbr_req.addr <  tcdm_end_address + ClusterPeriphSize * 1024)) ||
      ((peri_sbr_req.addr >= UartAddr) &&
       (peri_sbr_req.addr <  UartAddr + 32'h1_0000));
  `ASSERT(PeriCoreAddrMapped, peri_sbr_req_valid |-> peri_core_addr_ok, clk_i, !rst_ni,
      $sformatf("cachepool_cluster: core access to unmapped address 0x%08x from L2 endpoint %0d tile %0d hart %0d",
                peri_sbr_req.addr, peri_sbr_req.user.l2_src_id, peri_sbr_req.user.tile_id,
                peri_sbr_req.user.hart_id))
  `ASSERT(PeriSingleWord, peri_sbr_req_valid |-> (peri_sbr_req.size <= reqrsp_pkg::size_t'(2)),
      clk_i, !rst_ni, "cachepool_cluster: peripheral access wider than 32 bits")
  `endif

  // ---- Response routing per target: use src_id from user field ----
  peri_src_sel_t [PeriXbarNumTgt-1:0] peri_mst_sel;
  assign peri_mst_sel[0] = peri_xbar_tgt_rsp[0].user.src_id;
  assign peri_mst_sel[1] = peri_xbar_tgt_rsp[1].user.src_id;

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

  // ---- Target [0]: CSR → reqrsp_to_reg → cachepool_peripheral ----

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
    .AddrWidth       ( AxiAddrWidth              ),
    .SPMWidth        ( $clog2(L1NumSet)          ),
    .NumTiles        ( NumTiles                  ),
    .NumGroups       ( NumGroups                 ),
    .NumBarrierSlots ( NumBarrierSlots           ),
    .PrivateWidth    ( L1PrivWidth               ),
    .reg_req_t       ( reg_csr_req_t             ),
    .reg_rsp_t       ( reg_csr_rsp_t             )
  ) i_cachepool_cluster_peripheral (
    .clk_i                    ( clk_i                  ),
    .rst_ni                   ( rst_ni                 ),
    .eoc_o                    ( eoc_o                  ),
    .reg_req_i                ( reg_req                ),
    .reg_rsp_o                ( reg_rsp                ),
    .tcdm_start_address_i     ( tcdm_start_address     ),
    .tcdm_end_address_i       ( tcdm_end_address       ),
    .cluster_hart_base_id_i   ( HartBaseId             ),
    .cluster_probe_o          ( cluster_probe_o        ),
    .l1d_spm_size_o           (                        ),
    .l1d_busy_o               ( l1d_busy               ),
    .cfg_start_o              ( cfg_start              ),
    .cfg_reg_o                ( cfg_reg                ),
    .cfg_data_o               ( cfg_data               ),
    .cfg_tile_sel_o           ( cfg_tile_sel           ),
    .cfg_done_i               ( cfg_done               ),
    .barrier_part_mask_o      ( barrier_part_mask      )
  );

  // ---- Target [1]: UART → reqrsp_to_axi → axi_narrow_req_o ----

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
