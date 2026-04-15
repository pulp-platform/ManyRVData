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

/// A single-tile cluster implementation for CachePool
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
    /// Size of DMA AXI buffer.
    parameter int                     unsigned               DMAAxiReqFifoDepth                 = 3,
    /// Size of DMA request fifo.
    parameter int                     unsigned               DMAReqFifoDepth                    = 3,
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
    /// Per-core enabling of the custom `Xdma` ISA extensions.
    parameter bit                              [NrCores-1:0] Xdma                               = '{default: '0},
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
    input  logic          [NrCores-1:0]           debug_req_i,
    /// End of Computing indicator to notify the host/tb
    output logic          [3:0]                   eoc_o,
    /// Machine external interrupt pending. Usually those interrupts come from a
    /// platform-level interrupt controller. This signal is assumed to be _async_.
    input  logic          [NrCores-1:0]           meip_i,
    /// Machine timer interrupt pending. Usually those interrupts come from a
    /// core-local interrupt controller such as a timer/RTC. This signal is
    /// assumed to be _async_.
    input  logic          [NrCores-1:0]           mtip_i,
    /// Core software interrupt pending. Usually those interrupts come from
    /// another core to facilitate inter-processor-interrupts. This signal is
    /// assumed to be _async_.
    input  logic          [NrCores-1:0]           msip_i,
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
  import snitch_icache_pkg::icache_events_t;

  // ---------
  // Constants
  // ---------
  /// Minimum width to hold the core number.
  localparam int unsigned CoreIDWidth     = cf_math_pkg::idx_width(NrCores);

  // Enlarge the address width for Spatz due to cache
  localparam int unsigned TCDMAddrWidth   = 32;

  // Core Request, SoC Request
  localparam int unsigned NrNarrowMasters = 2;

  localparam int unsigned WideIdWidthOut  = AxiIdWidthOut;
  localparam int unsigned WideIdWidthIn   = WideIdWidthOut - $clog2(NumClusterMst) - GroupMuxIdBits;

  // Pre-mux AXI ID width: per-group reqrsp_to_axi output.
  // The multi-group axi_mux adds GroupMuxIdBits on top to reach WideIdWidthOut.
  localparam int unsigned WideIdWidthPreMux = WideIdWidthOut - GroupMuxIdBits;

  // Cache XBar configuration struct
  localparam axi_pkg::xbar_cfg_t CacheXbarCfg = '{
    NoSlvPorts        : NumClusterMst*NumTiles,
    NoMstPorts        : ClusterWideOutAxiPorts,
    MaxMstTrans       : MaxMstTrans,
    MaxSlvTrans       : MaxSlvTrans,
    FallThrough       : 1'b0,
    LatencyMode       : XbarLatency,
    AxiIdWidthSlvPorts: WideIdWidthIn,
    AxiIdUsedSlvPorts : WideIdWidthIn,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiDataWidth,
    NoAddrRules       : ClusterWideOutAxiPorts - 1,
    default           : '0
  };

  // --------
  // Typedefs
  // --------
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [AxiDataWidth-1:0]      data_cache_t;
  typedef logic [AxiDataWidth/8-1:0]    strb_cache_t;
  typedef logic [WideIdWidthIn-1:0]     id_cache_mst_t;
  typedef logic [WideIdWidthOut-1:0]    id_cache_slv_t;
  typedef logic [AxiUserWidth-1:0]      user_cache_t;

  // Pre-mux (per-group) AXI types: narrower ID, widened by axi_mux.
  typedef logic [WideIdWidthPreMux-1:0] id_cache_premux_t;

  `AXI_TYPEDEF_ALL(axi_mst_cache, addr_t, id_cache_mst_t, data_cache_t, strb_cache_t, user_cache_t)
  // Post-mux AXI types (same as before — used for axi_cut and output).
  `AXI_TYPEDEF_ALL(axi_slv_cache, addr_t, id_cache_slv_t, data_cache_t, strb_cache_t, user_cache_t)
  // Pre-mux AXI types (per-group reqrsp_to_axi output, input to axi_mux).
  `AXI_TYPEDEF_ALL(axi_premux_cache, addr_t, id_cache_premux_t, data_cache_t, strb_cache_t, user_cache_t)

  `REG_BUS_TYPEDEF_ALL(reg_cache, addr_t, data_cache_t, strb_cache_t)

  typedef struct packed {
    int unsigned idx;
    addr_t start_addr;
    addr_t end_addr;
  } xbar_rule_t;

  `SNITCH_VM_TYPEDEF(AxiAddrWidth)

  // ----------------
  // Wire Definitions
  // ----------------
  // 1. AXI
  // Post-mux wide AXI (one per L2 channel, merged across groups).
  axi_slv_cache_req_t  [ClusterWideOutAxiPorts-1:0] wide_axi_slv_req;
  axi_slv_cache_resp_t [ClusterWideOutAxiPorts-1:0] wide_axi_slv_rsp;
  // Per-group pre-mux wide AXI (per group, per L2 channel).
  axi_premux_cache_req_t  [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] wide_axi_premux_req;
  axi_premux_cache_resp_t [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] wide_axi_premux_rsp;
  // Narrow AXI per tile (UART + Periph).
  axi_narrow_req_t     [NumTiles-1:0][1:0]          axi_out_req;
  axi_narrow_resp_t    [NumTiles-1:0][1:0]          axi_out_resp;

  // 3. Peripherals
  axi_addr_t                               private_start_addr;
  icache_events_t    [NrCores-1:0]         icache_events;
  logic                                    icache_prefetch_enable;
  logic              [NrCores-1:0]         cl_interrupt;
  logic [$clog2(L1AddrWidth)-1:0]          dynamic_offset;
  logic              [3:0]                 l1d_private;
  cache_insn_t                             l1d_insn;
  logic                                    l1d_insn_valid;
  logic              [NumTiles-1:0]        l1d_insn_ready;
  logic              [NumTiles-1:0]        l1d_busy;

  // Per-group error signals.
  logic              [NumGroups-1:0]       group_error;

  // ---------------
  // CachePool Group
  // ---------------

  // Per-group L2 reqrsp ports (one per L2 channel per group).
  l2_req_t [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] l2_req;
  l2_rsp_t [NumGroups-1:0][ClusterWideOutAxiPorts-1:0] l2_rsp;

  assign error_o = |group_error;

  for (genvar g = 0; g < NumGroups; g++) begin : gen_group
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
      .Xdma                     ( Xdma[g*NumCoreGroup +: NumCoreGroup] ),
      .DMAAxiReqFifoDepth       ( DMAAxiReqFifoDepth       ),
      .DMAReqFifoDepth          ( DMAReqFifoDepth          ),
      .RegisterOffloadRsp       ( RegisterOffloadRsp       ),
      .RegisterCoreReq          ( RegisterCoreReq          ),
      .RegisterCoreRsp          ( RegisterCoreRsp          ),
      .RegisterTCDMCuts         ( RegisterTCDMCuts         ),
      .RegisterExt              ( RegisterExt              ),
      .XbarLatency              ( XbarLatency              ),
      .MaxMstTrans              ( MaxMstTrans              ),
      .MaxSlvTrans              ( MaxSlvTrans              ),
      .UseFoldedDataBanks       ( UseFoldedDataBanks        ),
      .FoldWayGroup             ( FoldWayGroup              ),
      .UseHashWaySelect         ( UseHashWaySelect         ),
      .UseForwardingBuffer      ( UseForwardingBuffer       )
    ) i_group (
      .clk_i                    ( clk_i                                           ),
      .rst_ni                   ( rst_ni                                          ),
      .impl_i                   ( impl_i                                          ),
      .error_o                  ( group_error[g]                                  ),
      .debug_req_i              ( debug_req_i[g*NumCoreGroup +: NumCoreGroup]     ),
      .meip_i                   ( meip_i     [g*NumCoreGroup +: NumCoreGroup]     ),
      .mtip_i                   ( mtip_i     [g*NumCoreGroup +: NumCoreGroup]     ),
      .msip_i                   ( msip_i     [g*NumCoreGroup +: NumCoreGroup]     ),
      .hart_base_id_i           ( hart_base_id_i + 10'(g * NumCoreGroup)          ),
      .cluster_base_addr_i      ( cluster_base_addr_i                             ),
      .private_start_addr_i     ( private_start_addr                              ),
      .axi_narrow_req_o         ( axi_out_req [g*NumTilesPerGroup +: NumTilesPerGroup]  ),
      .axi_narrow_rsp_i         ( axi_out_resp[g*NumTilesPerGroup +: NumTilesPerGroup]  ),
      // DRAM refill reqrsp (post-xbar, one per L2 channel)
      .l2_req_o                 ( l2_req[g]                                       ),
      .l2_rsp_i                 ( l2_rsp[g]                                       ),
      // Peripherals
      .icache_events_o          ( icache_events[g*NumCoreGroup +: NumCoreGroup]   ),
      .icache_prefetch_enable_i ( icache_prefetch_enable                          ),
      .cl_interrupt_i           ( cl_interrupt [g*NumCoreGroup +: NumCoreGroup]   ),
      .dynamic_offset_i         ( dynamic_offset                                  ),
      .l1d_private_i            ( l1d_private                                     ),
      .l1d_insn_i               ( l1d_insn                                        ),
      .l1d_insn_valid_i         ( l1d_insn_valid                                  ),
      .l1d_insn_ready_o         ( l1d_insn_ready[g*NumTilesPerGroup +: NumTilesPerGroup]),
      .l1d_busy_i               ( l1d_busy      [g*NumTilesPerGroup +: NumTilesPerGroup])
    );
  end

  // -------------
  // To Main Memory: reqrsp_to_axi per group, then axi_mux across groups
  // -------------

  // Step 1: Per-group reqrsp_to_axi conversion.
  for (genvar g = 0; g < NumGroups; g++) begin : gen_per_group_l2
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

  // Step 2: Per-L2-channel axi_mux across groups.
  if (NumGroups > 1) begin : gen_l2_group_mux
    for (genvar ch = 0; ch < ClusterWideOutAxiPorts; ch++) begin : gen_l2_ch_mux
      // Collect per-group inputs for this channel.
      axi_premux_cache_req_t  [NumGroups-1:0] l2_mux_slv_req;
      axi_premux_cache_resp_t [NumGroups-1:0] l2_mux_slv_rsp;

      for (genvar g = 0; g < NumGroups; g++) begin : gen_l2_mux_connect
        assign l2_mux_slv_req[g] = wide_axi_premux_req[g][ch];
        assign wide_axi_premux_rsp[g][ch] = l2_mux_slv_rsp[g];
      end

      axi_mux #(
        .SlvAxiIDWidth ( WideIdWidthPreMux            ),
        .slv_aw_chan_t ( axi_premux_cache_aw_chan_t   ),
        .mst_aw_chan_t ( axi_slv_cache_aw_chan_t      ),
        .w_chan_t      ( axi_slv_cache_w_chan_t       ),
        .slv_b_chan_t  ( axi_premux_cache_b_chan_t    ),
        .mst_b_chan_t  ( axi_slv_cache_b_chan_t       ),
        .slv_ar_chan_t ( axi_premux_cache_ar_chan_t   ),
        .mst_ar_chan_t ( axi_slv_cache_ar_chan_t      ),
        .slv_r_chan_t  ( axi_premux_cache_r_chan_t    ),
        .mst_r_chan_t  ( axi_slv_cache_r_chan_t       ),
        .slv_req_t     ( axi_premux_cache_req_t       ),
        .slv_resp_t    ( axi_premux_cache_resp_t      ),
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

  // Spill register signals to cut the AXI feedback path
  axi_in_req_t     axi_in_req_reg;
  axi_in_resp_t    axi_in_resp_reg;

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
  //assign use_barrier = {NumTiles{1'b1}}; // for now all is set to 1
  logic [NumTiles-1:0] barrier_participation_mask;
  assign use_barrier = barrier_participation_mask;
  

  axi_cut #(
    .Bypass     (0                      ),
    .aw_chan_t  (spatz_axi_in_aw_chan_t ),
    .w_chan_t   (spatz_axi_in_w_chan_t  ),
    .b_chan_t   (spatz_axi_in_b_chan_t  ),
    .ar_chan_t  (spatz_axi_in_ar_chan_t ),
    .r_chan_t   (spatz_axi_in_r_chan_t  ),
    .axi_req_t  (spatz_axi_in_req_t     ),
    .axi_resp_t (spatz_axi_in_resp_t    )
  ) i_cut_ext_narrow_in (
    .clk_i      (clk_i                  ),
    .rst_ni     (rst_ni                 ),
    .slv_req_i  (axi_in_req_i           ),
    .slv_resp_o (axi_in_resp_o          ),
    .mst_req_o  (axi_in_req_reg         ),
    .mst_resp_i (axi_in_resp_reg        )
  );

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

  axi_mux #(
    .SlvAxiIDWidth ( CsrAxiMstIdWidth       ),
    .slv_aw_chan_t ( axi_csr_mst_aw_chan_t  ),
    .mst_aw_chan_t ( axi_csr_slv_aw_chan_t  ),
    .w_chan_t      ( axi_csr_slv_w_chan_t   ),
    .slv_b_chan_t  ( axi_csr_mst_b_chan_t   ),
    .mst_b_chan_t  ( axi_csr_slv_b_chan_t   ),
    .slv_ar_chan_t ( axi_csr_mst_ar_chan_t  ),
    .mst_ar_chan_t ( axi_csr_slv_ar_chan_t  ),
    .slv_r_chan_t  ( axi_csr_mst_r_chan_t   ),
    .mst_r_chan_t  ( axi_csr_slv_r_chan_t   ),
    .slv_req_t     ( axi_csr_mst_req_t      ),
    .slv_resp_t    ( axi_csr_mst_resp_t     ),
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
    .clk_i       ( clk_i        ),   // Clock
    .rst_ni      ( rst_ni       ),  // Asynchronous reset active low
    .test_i      ('0            ),  // Test Mode enable
    .slv_reqs_i  ( {axi_in_req_reg,  axi_core_csr_req}  ),
    .slv_resps_o ( {axi_in_resp_reg, axi_core_csr_rsp}  ),
    .mst_req_o   ( axi_csr_req  ),
    .mst_resp_i  ( axi_csr_rsp  )
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


  // Event counter increments for the TCDM.
  typedef struct packed {
    /// Number requests going in
    logic [$clog2(5):0] inc_accessed;
    /// Number of requests stalled due to congestion
    logic [$clog2(5):0] inc_congested;
  } tcdm_events_t;

  // Event counter increments for DMA.
  typedef struct packed {
    logic aw_stall, ar_stall, r_stall, w_stall,
    buf_w_stall, buf_r_stall;
    logic aw_valid, aw_ready, aw_done, aw_bw;
    logic ar_valid, ar_ready, ar_done, ar_bw;
    logic r_valid, r_ready, r_done, r_bw;
    logic w_valid, w_ready, w_done, w_bw;
    logic b_valid, b_ready, b_done;
    logic dma_busy;
    axi_pkg::len_t aw_len, ar_len;
    axi_pkg::size_t aw_size, ar_size;
    logic [$clog2(SpatzAxiNarrowDataWidth/8):0] num_bytes_written;
  } dma_events_t;

  cachepool_peripheral #(
    .AddrWidth     (AxiAddrWidth    ),
    .SPMWidth      ($clog2(L1NumSet)),
    .NumTiles      (NumTiles        ),
    .reg_req_t     (reg_req_t       ),
    .reg_rsp_t     (reg_rsp_t       ),
    .cache_insn_t  (cache_insn_t    ),
    .NrCores       (NrCores         )
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
    .cl_clint_o               (cl_interrupt          ),
    .cluster_hart_base_id_i   (hart_base_id_i        ),
    .cluster_probe_o          (cluster_probe_o       ),
    .dynamic_offset_o         (dynamic_offset        ),
    .private_start_addr_o     (private_start_addr    ),
    .l1d_spm_size_o           (                      ),
    .l1d_private_o            (l1d_private           ),
    .l1d_insn_o               (l1d_insn              ),
    .l1d_insn_valid_o         (l1d_insn_valid        ),
    .l1d_insn_ready_i         (l1d_insn_ready        ),
    .l1d_busy_o               (l1d_busy              ),
    .barrier_participation_mask_o (barrier_participation_mask)
  );

endmodule
