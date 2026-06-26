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

  // Narrow-data types with chimney output ID (for DW downsizer master side).
  `AXI_TYPEDEF_ALL(axi_peri_dw, addr_t, id_cache_slv_t, axi_narrow_data_t, axi_narrow_strb_t, user_cache_t)

  // ----------------
  // Wire Definitions
  // ----------------
  // 1. AXI — post-chimney wide AXI (one per L2/HBM channel).
  axi_slv_cache_req_t  [ClusterWideOutAxiPorts-1:0] wide_axi_slv_req;
  axi_slv_cache_resp_t [ClusterWideOutAxiPorts-1:0] wide_axi_slv_rsp;

  // HBM0 peripheral demux port (module-scope; driven inside gen_hbm_west[0]).
  axi_slv_cache_req_t  hbm0_peri_req;
  axi_slv_cache_resp_t hbm0_peri_rsp;

  // 2. Peripherals
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

  // Direct-wire barrier: one bit per tile across all groups
  logic [NumGroups-1:0][NumTilesPerGroup-1:0] tile_barrier;
  logic                                       barrier_done;

  cachepool_cluster_barrier #(
    .NrTiles ( NumTiles )
  ) i_cluster_barrier (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .tile_barrier_i ( tile_barrier   ),
    .barrier_done_o ( barrier_done   ),
    // All tiles participate in the barrier (full barrier)
    .barrier_mask_i ( '1             )
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

  // Per-group L2 refill floo link arrays [NumGroupsX][NumGroupsY][West:North]
  import floo_cachepool_noc_pkg::floo_req_t;
  import floo_cachepool_noc_pkg::floo_rsp_t;
  floo_req_t [NumGroupsX-1:0][NumGroupsY-1:0][floo_pkg::West:floo_pkg::North] l2_floo_req_out;
  floo_req_t [NumGroupsX-1:0][NumGroupsY-1:0][floo_pkg::West:floo_pkg::North] l2_floo_req_in;
  floo_rsp_t [NumGroupsX-1:0][NumGroupsY-1:0][floo_pkg::West:floo_pkg::North] l2_floo_rsp_out;
  floo_rsp_t [NumGroupsX-1:0][NumGroupsY-1:0][floo_pkg::West:floo_pkg::North] l2_floo_rsp_in;

  assign error_o = |group_error;

  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_group_y
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_group_x
      // Flat group index: row-major (matches L1 mesh wiring which uses gx + gy*NumGroupsX)
      localparam int unsigned g = gy * NumGroupsX + gx;
      // Column-major index for floogen endpoint enumeration (GroupX0Y0, X0Y1, ...)
      localparam int unsigned g_floo = gx * NumGroupsY + gy;
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
        .axi_out_req_t            ( logic                    ),
        .axi_out_resp_t           ( logic                    ),
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
        // L2 refill floo mesh links (4 directions)
        .l2_floo_req_o            ( l2_floo_req_out[gx][gy]                         ),
        .l2_floo_rsp_o            ( l2_floo_rsp_out[gx][gy]                         ),
        .l2_floo_req_i            ( l2_floo_req_in [gx][gy]                         ),
        .l2_floo_rsp_i            ( l2_floo_rsp_in [gx][gy]                         ),
        .l2_floo_id_i             ( floo_cachepool_noc_pkg::id_t'(
                                      floo_cachepool_noc_pkg::GroupX0Y0 + g_floo)    ),
        .l2_floo_route_table_i    ( floo_cachepool_noc_pkg::RoutingTables[
                                      floo_cachepool_noc_pkg::GroupX0Y0 + g_floo]    ),
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
    assign noc_req_in      [(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_req_in_valid[(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_req_out_ready[(NumGroupsX-1) + gy*NumGroupsX][1] = '1;
    assign noc_rsp_in      [(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
    assign noc_rsp_in_valid[(NumGroupsX-1) + gy*NumGroupsX][1]  = '0;
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
    assign noc_req_in      [gx][2]  = '0;
    assign noc_req_in_valid[gx][2]  = '0;
    assign noc_req_out_ready[gx][2] = '1;
    assign noc_rsp_in      [gx][2]  = '0;
    assign noc_rsp_in_valid[gx][2]  = '0;
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
    assign noc_req_in      [gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_req_in_valid[gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_req_out_ready[gx + (NumGroupsY-1)*NumGroupsX][0] = '1;
    assign noc_rsp_in      [gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
    assign noc_rsp_in_valid[gx + (NumGroupsY-1)*NumGroupsX][0]  = '0;
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
  // L2 Refill Mesh + HBM Chimneys (peripheral via HBM0 demux)
  // -------------------------------------------------------

  if (NumGroups > 1) begin : gen_l2_refill_mesh

    // --------------------------------------------------
    // L2 mesh interior cross-connections (floo links)
    // --------------------------------------------------

    // East-West connections
    for (genvar gx = 0; gx < NumGroupsX - 1; gx++) begin : gen_l2_ew
      for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_l2_ew_y
        // East output of (gx,gy) → West input of (gx+1,gy)
        assign l2_floo_req_in[gx+1][gy][floo_pkg::West] = l2_floo_req_out[gx][gy][floo_pkg::East];
        assign l2_floo_rsp_in[gx+1][gy][floo_pkg::West] = l2_floo_rsp_out[gx][gy][floo_pkg::East];
        // West output of (gx+1,gy) → East input of (gx,gy)
        assign l2_floo_req_in[gx][gy][floo_pkg::East]   = l2_floo_req_out[gx+1][gy][floo_pkg::West];
        assign l2_floo_rsp_in[gx][gy][floo_pkg::East]   = l2_floo_rsp_out[gx+1][gy][floo_pkg::West];
      end
    end

    // North-South connections
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_ns
      for (genvar gy = 0; gy < NumGroupsY - 1; gy++) begin : gen_l2_ns_y
        // North output of (gx,gy) → South input of (gx,gy+1)
        assign l2_floo_req_in[gx][gy+1][floo_pkg::South] = l2_floo_req_out[gx][gy][floo_pkg::North];
        assign l2_floo_rsp_in[gx][gy+1][floo_pkg::South] = l2_floo_rsp_out[gx][gy][floo_pkg::North];
        // South output of (gx,gy+1) → North input of (gx,gy)
        assign l2_floo_req_in[gx][gy][floo_pkg::North]   = l2_floo_req_out[gx][gy+1][floo_pkg::South];
        assign l2_floo_rsp_in[gx][gy][floo_pkg::North]   = l2_floo_rsp_out[gx][gy+1][floo_pkg::South];
      end
    end

    // --------------------------------------------------
    // HBM subordinate chimneys at mesh boundaries
    // West HBMs: HBM[gy] at West port of (0, gy)
    // East HBMs: HBM[NumGroupsY+gy] at East port of (NumGroupsX-1, gy)
    // HBM0 also carries peripheral traffic (demuxed below chimney).
    // --------------------------------------------------

    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_hbm_west
      localparam int unsigned HbmIdx = gy;

      floo_req_t hbm_floo_req_in, hbm_floo_req_out;
      floo_rsp_t hbm_floo_rsp_in, hbm_floo_rsp_out;

      // Connect chimney to router (0, gy) West port
      assign l2_floo_req_in[0][gy][floo_pkg::West] = hbm_floo_req_out;
      assign l2_floo_rsp_in[0][gy][floo_pkg::West] = hbm_floo_rsp_out;
      assign hbm_floo_req_in = l2_floo_req_out[0][gy][floo_pkg::West];
      assign hbm_floo_rsp_in = l2_floo_rsp_out[0][gy][floo_pkg::West];

      // Chimney AXI output (intermediate for HBM0 demux, direct for others)
      axi_slv_cache_req_t  hbm_chimney_req;
      axi_slv_cache_resp_t hbm_chimney_rsp;

      floo_axi_chimney #(
        .AxiCfg       ( floo_cachepool_noc_pkg::AxiCfg                        ),
        // Subordinate-only: receives requests from mesh, outputs AXI to DRAM
        .ChimneyCfg   ( floo_pkg::set_ports(floo_pkg::ChimneyDefaultCfg,
                          1'b1, 1'b0)                                         ),
        .RouteCfg     ( floo_cachepool_noc_pkg::RouteCfg                      ),
        .AtopSupport  ( 1'b0                                                  ),
        .MaxAtomicTxns( 0                                                     ),
        .id_t         ( floo_cachepool_noc_pkg::id_t                          ),
        .rob_idx_t    ( floo_cachepool_noc_pkg::rob_idx_t                     ),
        .route_t      ( floo_cachepool_noc_pkg::route_t                       ),
        .dst_t        ( floo_cachepool_noc_pkg::route_t                       ),
        .hdr_t        ( floo_cachepool_noc_pkg::hdr_t                         ),
        .sam_rule_t   ( floo_cachepool_noc_pkg::sam_rule_t                    ),
        .Sam          ( floo_cachepool_noc_pkg::Sam                           ),
        .axi_in_req_t ( floo_cachepool_noc_pkg::axi_wide_in_req_t            ),
        .axi_in_rsp_t ( floo_cachepool_noc_pkg::axi_wide_in_rsp_t            ),
        .axi_out_req_t( axi_slv_cache_req_t                                  ),
        .axi_out_rsp_t( axi_slv_cache_resp_t                                 ),
        .floo_req_t   ( floo_cachepool_noc_pkg::floo_req_t                    ),
        .floo_rsp_t   ( floo_cachepool_noc_pkg::floo_rsp_t                    )
      ) i_hbm_chimney (
        .clk_i          ( clk_i                                               ),
        .rst_ni         ( rst_ni                                              ),
        .test_enable_i  ( 1'b0                                                ),
        .sram_cfg_i     ( '0                                                  ),
        .axi_in_req_i   ( '0                                                  ),
        .axi_in_rsp_o   (                                                     ),
        .axi_out_req_o  ( hbm_chimney_req                                    ),
        .axi_out_rsp_i  ( hbm_chimney_rsp                                    ),
        .id_i           ( floo_cachepool_noc_pkg::id_t'(
                            floo_cachepool_noc_pkg::Hbm0 + HbmIdx)            ),
        .route_table_i  ( floo_cachepool_noc_pkg::RoutingTables[
                            floo_cachepool_noc_pkg::Hbm0 + HbmIdx]            ),
        .floo_req_o     ( hbm_floo_req_out                                    ),
        .floo_rsp_o     ( hbm_floo_rsp_out                                    ),
        .floo_req_i     ( hbm_floo_req_in                                     ),
        .floo_rsp_i     ( hbm_floo_rsp_in                                     )
      );

      // HBM0: demux DRAM vs peripheral traffic
      if (HbmIdx == 0) begin : gen_hbm0_demux
        axi_slv_cache_req_t  [1:0] hbm0_demux_req;
        axi_slv_cache_resp_t [1:0] hbm0_demux_rsp;

        // Address decode: DRAM range → port 0, everything else → port 1
        logic hbm0_aw_sel, hbm0_ar_sel;
        assign hbm0_aw_sel = !((hbm_chimney_req.aw.addr >= DramAddr) &&
                                (hbm_chimney_req.aw.addr <  DramAddr + DramPerChSize));
        assign hbm0_ar_sel = !((hbm_chimney_req.ar.addr >= DramAddr) &&
                                (hbm_chimney_req.ar.addr <  DramAddr + DramPerChSize));

        axi_demux #(
          .AxiIdWidth  ( WideIdWidthOut              ),
          .AtopSupport ( 1'b0                        ),
          .aw_chan_t   ( axi_slv_cache_aw_chan_t      ),
          .w_chan_t    ( axi_slv_cache_w_chan_t        ),
          .b_chan_t    ( axi_slv_cache_b_chan_t        ),
          .ar_chan_t   ( axi_slv_cache_ar_chan_t       ),
          .r_chan_t    ( axi_slv_cache_r_chan_t        ),
          .axi_req_t   ( axi_slv_cache_req_t          ),
          .axi_resp_t  ( axi_slv_cache_resp_t         ),
          .NoMstPorts  ( 2                            ),
          .MaxTrans    ( 4                            )
        ) i_hbm0_demux (
          .clk_i           ( clk_i                    ),
          .rst_ni          ( rst_ni                   ),
          .test_i          ( 1'b0                     ),
          .slv_req_i       ( hbm_chimney_req          ),
          .slv_aw_select_i ( hbm0_aw_sel              ),
          .slv_ar_select_i ( hbm0_ar_sel              ),
          .slv_resp_o      ( hbm_chimney_rsp          ),
          .mst_reqs_o      ( hbm0_demux_req           ),
          .mst_resps_i     ( hbm0_demux_rsp           )
        );

        // Port 0: DRAM
        assign wide_axi_slv_req[0] = hbm0_demux_req[0];
        assign hbm0_demux_rsp[0]   = wide_axi_slv_rsp[0];

        // Port 1: Peripheral traffic (wired to module-scope hbm0_peri_*)
        assign hbm0_peri_req     = hbm0_demux_req[1];
        assign hbm0_demux_rsp[1] = hbm0_peri_rsp;

      end else begin : gen_hbm_direct
        // Other West HBMs: direct connection
        assign wide_axi_slv_req[HbmIdx] = hbm_chimney_req;
        assign hbm_chimney_rsp           = wide_axi_slv_rsp[HbmIdx];
      end
    end

    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_hbm_east
      localparam int unsigned HbmIdx = NumGroupsY + gy;

      floo_req_t hbm_floo_req_in, hbm_floo_req_out;
      floo_rsp_t hbm_floo_rsp_in, hbm_floo_rsp_out;

      // Connect chimney to router (NumGroupsX-1, gy) East port
      assign l2_floo_req_in[NumGroupsX-1][gy][floo_pkg::East] = hbm_floo_req_out;
      assign l2_floo_rsp_in[NumGroupsX-1][gy][floo_pkg::East] = hbm_floo_rsp_out;
      assign hbm_floo_req_in = l2_floo_req_out[NumGroupsX-1][gy][floo_pkg::East];
      assign hbm_floo_rsp_in = l2_floo_rsp_out[NumGroupsX-1][gy][floo_pkg::East];

      floo_axi_chimney #(
        .AxiCfg       ( floo_cachepool_noc_pkg::AxiCfg                        ),
        .ChimneyCfg   ( floo_pkg::set_ports(floo_pkg::ChimneyDefaultCfg,
                          1'b1, 1'b0)                                         ),
        .RouteCfg     ( floo_cachepool_noc_pkg::RouteCfg                      ),
        .AtopSupport  ( 1'b0                                                  ),
        .MaxAtomicTxns( 0                                                     ),
        .id_t         ( floo_cachepool_noc_pkg::id_t                          ),
        .rob_idx_t    ( floo_cachepool_noc_pkg::rob_idx_t                     ),
        .route_t      ( floo_cachepool_noc_pkg::route_t                       ),
        .dst_t        ( floo_cachepool_noc_pkg::route_t                       ),
        .hdr_t        ( floo_cachepool_noc_pkg::hdr_t                         ),
        .sam_rule_t   ( floo_cachepool_noc_pkg::sam_rule_t                    ),
        .Sam          ( floo_cachepool_noc_pkg::Sam                           ),
        .axi_in_req_t ( floo_cachepool_noc_pkg::axi_wide_in_req_t            ),
        .axi_in_rsp_t ( floo_cachepool_noc_pkg::axi_wide_in_rsp_t            ),
        .axi_out_req_t( axi_slv_cache_req_t                                  ),
        .axi_out_rsp_t( axi_slv_cache_resp_t                                 ),
        .floo_req_t   ( floo_cachepool_noc_pkg::floo_req_t                    ),
        .floo_rsp_t   ( floo_cachepool_noc_pkg::floo_rsp_t                    )
      ) i_hbm_chimney (
        .clk_i          ( clk_i                                               ),
        .rst_ni         ( rst_ni                                              ),
        .test_enable_i  ( 1'b0                                                ),
        .sram_cfg_i     ( '0                                                  ),
        .axi_in_req_i   ( '0                                                  ),
        .axi_in_rsp_o   (                                                     ),
        .axi_out_req_o  ( wide_axi_slv_req[HbmIdx]                           ),
        .axi_out_rsp_i  ( wide_axi_slv_rsp[HbmIdx]                           ),
        .id_i           ( floo_cachepool_noc_pkg::id_t'(
                            floo_cachepool_noc_pkg::Hbm0 + HbmIdx)            ),
        .route_table_i  ( floo_cachepool_noc_pkg::RoutingTables[
                            floo_cachepool_noc_pkg::Hbm0 + HbmIdx]            ),
        .floo_req_o     ( hbm_floo_req_out                                    ),
        .floo_rsp_o     ( hbm_floo_rsp_out                                    ),
        .floo_req_i     ( hbm_floo_req_in                                     ),
        .floo_rsp_i     ( hbm_floo_rsp_in                                     )
      );

    end

    // --------------------------------------------------
    // L2 mesh boundary tie-offs
    // --------------------------------------------------

    // North boundary (gy=NumGroupsY-1): no endpoint, tie off
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_north_bnd
      assign l2_floo_req_in[gx][NumGroupsY-1][floo_pkg::North] = '0;
      assign l2_floo_rsp_in[gx][NumGroupsY-1][floo_pkg::North] = '0;
    end

    // South boundary (gy=0): all tied off (no separate HostPeri endpoint)
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_south_bnd
      assign l2_floo_req_in[gx][0][floo_pkg::South] = '0;
      assign l2_floo_rsp_in[gx][0][floo_pkg::South] = '0;
    end

    // West boundary (gx=0): all connected to HBM chimneys (gen_hbm_west)
    // East boundary (gx=NumGroupsX-1): all connected to HBM chimneys (gen_hbm_east)
    // → no additional tie-offs needed for West/East

  end else begin : gen_l2_no_mesh
    // Single-group: no mesh. The wrapper's internal chimney+router directional
    // ports are unused. Tie them off.
    for (genvar d = floo_pkg::North; d <= floo_pkg::West; d++) begin : gen_l2_tieoff
      assign l2_floo_req_in[0][0][d] = '0;
      assign l2_floo_rsp_in[0][0][d] = '0;
    end
    // No HBM chimneys in single-group mode. Tie off wide AXI to DRAM.
    // TODO: For single-group bypass, connect group's L2 path directly to axi_cut
    // without going through the floo mesh.
    for (genvar ch = 0; ch < ClusterWideOutAxiPorts; ch++) begin : gen_l2_no_mesh_tieoff
      assign wide_axi_slv_req[ch] = '0;
    end
    // No HBM0 peripheral path in single-group mode.
    assign hbm0_peri_req = '0;
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
  // Peripheral Fabric
  // --------------------------------------------------
  //
  // Data path:
  //   HBM0 demux port 1 (512b, WideIdWidthOut ID)
  //     → axi_dw_converter (512b → 32b)
  //     → axi_id_serialize (WideIdWidthOut → CsrSerIdWidth=2)
  //     → 2×2 AXI xbar slave [0]
  //
  //   axi_in_req_i (TB/SoC, AxiIdWidthIn)
  //     → axi_id_serialize (AxiIdWidthIn → CsrSerIdWidth=2)
  //     → 2×2 AXI xbar slave [1]
  //
  //   Xbar master [0] → UART (axi_narrow_req_o)
  //   Xbar master [1] → barrier → axi_to_reg → cachepool_peripheral

  `REG_BUS_TYPEDEF_ALL(reg, narrow_addr_t, narrow_data_t, narrow_strb_t)

  reg_req_t reg_req;
  reg_rsp_t reg_rsp;

  // ---- HBM0 peripheral path: DW downsize (512 → 32) ----

  axi_peri_dw_req_t  peri_dw_req;
  axi_peri_dw_resp_t peri_dw_rsp;

  axi_dw_converter #(
    .AxiAddrWidth        ( AxiAddrWidth            ),
    .AxiIdWidth          ( WideIdWidthOut           ),
    .AxiMaxReads         ( 2                        ),
    .AxiSlvPortDataWidth ( AxiDataWidth             ),
    .AxiMstPortDataWidth ( SpatzAxiNarrowDataWidth  ),
    .ar_chan_t           ( axi_slv_cache_ar_chan_t   ),
    .aw_chan_t           ( axi_slv_cache_aw_chan_t   ),
    .b_chan_t            ( axi_slv_cache_b_chan_t    ),
    .slv_r_chan_t        ( axi_slv_cache_r_chan_t    ),
    .slv_w_chan_t        ( axi_slv_cache_w_chan_t    ),
    .axi_slv_req_t       ( axi_slv_cache_req_t      ),
    .axi_slv_resp_t      ( axi_slv_cache_resp_t     ),
    .mst_r_chan_t        ( axi_peri_dw_r_chan_t      ),
    .mst_w_chan_t        ( axi_peri_dw_w_chan_t      ),
    .axi_mst_req_t       ( axi_peri_dw_req_t        ),
    .axi_mst_resp_t      ( axi_peri_dw_resp_t       )
  ) i_peri_dw_downsize (
    .clk_i      ( clk_i              ),
    .rst_ni     ( rst_ni             ),
    .slv_req_i  ( hbm0_peri_req      ),
    .slv_resp_o ( hbm0_peri_rsp  ),
    .mst_req_o  ( peri_dw_req        ),
    .mst_resp_i ( peri_dw_rsp        )
  );

  // ---- HBM0 peripheral path: ID serialize (WideIdWidthOut → CsrSerIdWidth) ----

  axi_csr_ser_req_t  peri_hbm0_ser_req;
  axi_csr_ser_resp_t peri_hbm0_ser_rsp;

  axi_id_serialize #(
    .AxiSlvPortIdWidth      ( WideIdWidthOut          ),
    .AxiSlvPortMaxTxns      ( 2                       ),
    .AxiMstPortIdWidth      ( CsrSerIdWidth           ),
    .AxiMstPortMaxUniqIds   ( 1                       ),
    .AxiMstPortMaxTxnsPerId ( 2                       ),
    .AxiAddrWidth           ( AxiAddrWidth            ),
    .AxiDataWidth           ( SpatzAxiNarrowDataWidth ),
    .AxiUserWidth           ( AxiUserWidth            ),
    .AtopSupport            ( 1'b0                    ),
    .slv_req_t              ( axi_peri_dw_req_t       ),
    .slv_resp_t             ( axi_peri_dw_resp_t      ),
    .mst_req_t              ( axi_csr_ser_req_t       ),
    .mst_resp_t             ( axi_csr_ser_resp_t      ),
    .IdMapNumEntries        ( 1                       ),
    .IdMap                  ( '{'{32'd0, 32'd0}}      )
  ) i_peri_hbm0_id_serialize (
    .clk_i      ( clk_i               ),
    .rst_ni     ( rst_ni              ),
    .slv_req_i  ( peri_dw_req         ),
    .slv_resp_o ( peri_dw_rsp         ),
    .mst_req_o  ( peri_hbm0_ser_req   ),
    .mst_resp_i ( peri_hbm0_ser_rsp   )
  );

  // ---- TB/SoC axi_in: ID serialize (AxiIdWidthIn → CsrSerIdWidth) ----

  axi_csr_ser_req_t  peri_axi_in_ser_req;
  axi_csr_ser_resp_t peri_axi_in_ser_rsp;

  axi_id_serialize #(
    .AxiSlvPortIdWidth      ( AxiIdWidthIn            ),
    .AxiSlvPortMaxTxns      ( 2                       ),
    .AxiMstPortIdWidth      ( CsrSerIdWidth           ),
    .AxiMstPortMaxUniqIds   ( 1                       ),
    .AxiMstPortMaxTxnsPerId ( 2                       ),
    .AxiAddrWidth           ( AxiAddrWidth            ),
    .AxiDataWidth           ( SpatzAxiNarrowDataWidth ),
    .AxiUserWidth           ( AxiUserWidth            ),
    .AtopSupport            ( 1'b0                    ),
    .slv_req_t              ( axi_in_req_t            ),
    .slv_resp_t             ( axi_in_resp_t           ),
    .mst_req_t              ( axi_csr_ser_req_t       ),
    .mst_resp_t             ( axi_csr_ser_resp_t      ),
    .IdMapNumEntries        ( 1                       ),
    .IdMap                  ( '{'{32'd0, 32'd0}}      )
  ) i_peri_axi_in_id_serialize (
    .clk_i      ( clk_i                ),
    .rst_ni     ( rst_ni               ),
    .slv_req_i  ( axi_in_req_i         ),
    .slv_resp_o ( axi_in_resp_o        ),
    .mst_req_o  ( peri_axi_in_ser_req  ),
    .mst_resp_i ( peri_axi_in_ser_rsp  )
  );

  // ---- 2×2 Peripheral AXI Xbar ----
  // Slave [0]: HBM0 peripheral (serialized)
  // Slave [1]: TB/SoC axi_in (serialized)
  // Master [0]: UART
  // Master [1]: CSR/Peripheral registers

  localparam int unsigned PeriXbarNumSlv = 2;
  localparam int unsigned PeriXbarNumMst = 2;

  localparam int unsigned PeriXbarMstUart = 0;
  localparam int unsigned PeriXbarMstCsr  = 1;

  // Calculate the peripheral base address (needed for xbar rules and barrier).
  localparam logic [AxiAddrWidth-1:0] TCDMMask = ~(TCDMSize-1);
  addr_t tcdm_start_address, tcdm_end_address;
  assign tcdm_start_address = (cluster_base_addr_i & TCDMMask);
  assign tcdm_end_address   = (tcdm_start_address + TCDMSize) & TCDMMask;

  localparam axi_pkg::xbar_cfg_t PeriXbarCfg = '{
    NoSlvPorts        : PeriXbarNumSlv,
    NoMstPorts        : PeriXbarNumMst,
    MaxMstTrans       : 2,
    MaxSlvTrans       : 2,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::NO_LATENCY,
    AxiIdWidthSlvPorts: CsrSerIdWidth,
    AxiIdUsedSlvPorts : CsrSerIdWidth,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : SpatzAxiNarrowDataWidth,
    NoAddrRules       : 2,
    default           : '0
  };

  typedef axi_pkg::xbar_rule_32_t peri_xbar_rule_t;

  // UART and CSR get explicit rules; unmatched addresses get AXI DECERR.
  peri_xbar_rule_t [1:0] peri_xbar_addr_map;
  assign peri_xbar_addr_map = '{
    '{idx: PeriXbarMstUart, start_addr: UartAddr,
      end_addr: UartAddr + 32'h1_0000},
    '{idx: PeriXbarMstCsr,  start_addr: tcdm_end_address,
      end_addr: tcdm_end_address + ClusterPeriphSize * 1024}
  };

  axi_csr_ser_req_t  [PeriXbarNumSlv-1:0] peri_xbar_slv_req;
  axi_csr_ser_resp_t [PeriXbarNumSlv-1:0] peri_xbar_slv_rsp;
  axi_csr_slv_req_t  [PeriXbarNumMst-1:0] peri_xbar_mst_req;
  axi_csr_slv_resp_t [PeriXbarNumMst-1:0] peri_xbar_mst_rsp;

  assign peri_xbar_slv_req[0] = peri_hbm0_ser_req;
  assign peri_hbm0_ser_rsp    = peri_xbar_slv_rsp[0];
  assign peri_xbar_slv_req[1] = peri_axi_in_ser_req;
  assign peri_axi_in_ser_rsp  = peri_xbar_slv_rsp[1];

  axi_xbar #(
    .Cfg           ( PeriXbarCfg              ),
    .ATOPs         ( 0                        ),
    .slv_aw_chan_t ( axi_csr_ser_aw_chan_t     ),
    .mst_aw_chan_t ( axi_csr_slv_aw_chan_t     ),
    .w_chan_t      ( axi_csr_ser_w_chan_t      ),
    .slv_b_chan_t  ( axi_csr_ser_b_chan_t      ),
    .mst_b_chan_t  ( axi_csr_slv_b_chan_t      ),
    .slv_ar_chan_t ( axi_csr_ser_ar_chan_t     ),
    .mst_ar_chan_t ( axi_csr_slv_ar_chan_t     ),
    .slv_r_chan_t  ( axi_csr_ser_r_chan_t      ),
    .mst_r_chan_t  ( axi_csr_slv_r_chan_t      ),
    .slv_req_t     ( axi_csr_ser_req_t        ),
    .slv_resp_t    ( axi_csr_ser_resp_t       ),
    .mst_req_t     ( axi_csr_slv_req_t        ),
    .mst_resp_t    ( axi_csr_slv_resp_t       ),
    .rule_t        ( peri_xbar_rule_t         )
  ) i_peri_xbar (
    .clk_i                 ( clk_i                        ),
    .rst_ni                ( rst_ni                       ),
    .test_i                ( 1'b0                         ),
    .slv_ports_req_i       ( peri_xbar_slv_req             ),
    .slv_ports_resp_o      ( peri_xbar_slv_rsp             ),
    .mst_ports_req_o       ( peri_xbar_mst_req             ),
    .mst_ports_resp_i      ( peri_xbar_mst_rsp             ),
    .addr_map_i            ( peri_xbar_addr_map            ),
    .en_default_mst_port_i ( '0                            ),
    .default_mst_port_i    ( '0                            )
  );

  // ---- UART output (xbar master [0]) ----
  // axi_uart_req_t and axi_csr_slv_req_t have the same field widths
  // (CsrAxiSlvIdWidth = SpatzAxiUartIdWidth = CsrSerIdWidth + 1).
  assign axi_narrow_req_o     = axi_uart_req_t'(peri_xbar_mst_req[PeriXbarMstUart]);
  assign peri_xbar_mst_rsp[PeriXbarMstUart] = axi_csr_slv_resp_t'(axi_narrow_resp_i);

  // ---- CSR path (xbar master [1]) → axi_to_reg → peripheral ----
  // Barrier synchronization is handled by direct wires (tile_barrier / barrier_done),
  // so no cluster_barrier module is needed on the AXI path.

  axi_to_reg #(
    .ADDR_WIDTH         ( AxiAddrWidth            ),
    .DATA_WIDTH         ( SpatzAxiNarrowDataWidth  ),
    .AXI_MAX_WRITE_TXNS ( 1                        ),
    .AXI_MAX_READ_TXNS  ( 1                        ),
    .DECOUPLE_W         ( 0                        ),
    .ID_WIDTH           ( CsrAxiSlvIdWidth         ),
    .USER_WIDTH         ( AxiUserWidth             ),
    .axi_req_t          ( axi_csr_slv_req_t        ),
    .axi_rsp_t          ( axi_csr_slv_resp_t       ),
    .reg_req_t          ( reg_req_t                ),
    .reg_rsp_t          ( reg_rsp_t                )
  ) i_csr_axi_to_reg (
    .clk_i              ( clk_i                    ),
    .rst_ni             ( rst_ni                   ),
    .testmode_i         ( 1'b0                     ),
    .axi_req_i          ( peri_xbar_mst_req[PeriXbarMstCsr] ),
    .axi_rsp_o          ( peri_xbar_mst_rsp[PeriXbarMstCsr] ),
    .reg_req_o          ( reg_req                   ),
    .reg_rsp_i          ( reg_rsp                   )
  );

  cachepool_peripheral #(
    .AddrWidth     ( AxiAddrWidth    ),
    .SPMWidth      ( $clog2(L1NumSet)),
    .NumTiles      ( NumTiles        ),
    .reg_req_t     ( reg_req_t       ),
    .reg_rsp_t     ( reg_rsp_t       ),
    .cache_insn_t  ( cache_insn_t    )
  ) i_cachepool_cluster_peripheral (
    .clk_i                    ( clk_i                 ),
    .rst_ni                   ( rst_ni                ),
    .eoc_o                    ( eoc_o                 ),
    .reg_req_i                ( reg_req               ),
    .reg_rsp_o                ( reg_rsp               ),
    .tcdm_start_address_i     ( tcdm_start_address    ),
    .tcdm_end_address_i       ( tcdm_end_address      ),
    .icache_prefetch_enable_o ( icache_prefetch_enable ),
    .cluster_hart_base_id_i   ( hart_base_id_i        ),
    .cluster_probe_o          ( cluster_probe_o       ),
    .dynamic_offset_o         ( dynamic_offset        ),
    .private_start_addr_o     ( private_start_addr    ),
    .l1d_spm_size_o           (                       ),
    .l1d_private_o            ( l1d_private           ),
    .l1d_insn_o               ( l1d_insn              ),
    .l1d_insn_valid_o         ( l1d_insn_valid        ),
    .l1d_insn_ready_i         ( l1d_insn_ready        ),
    .l1d_busy_o               ( l1d_busy              )
  );

endmodule
