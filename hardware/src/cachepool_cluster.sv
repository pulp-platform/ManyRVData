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
    parameter fpu_implementation_t                           FPUImplementation        [NrCores] = '{default: fpu_implementation_t'(0)},
    /// Spatz FPU/IPU Configuration
    parameter int                     unsigned               NumSpatzFPUs                       = 4,
    parameter int                     unsigned               NumSpatzIPUs                       = 1,
    /// Per-core enabling of the custom `Xdma` ISA extensions.
    parameter bit                              [NrCores-1:0] Xdma                               = '{default: '0},
    /// # Per-core parameters
    /// Per-core integer outstanding loads
    parameter int                     unsigned               NumIntOutstandingLoads   [NrCores] = '{default: '0},
    /// Per-core integer outstanding memory operations (load and stores)
    parameter int                     unsigned               NumIntOutstandingMem     [NrCores] = '{default: '0},
    /// Per-core Spatz outstanding loads
    parameter int                     unsigned               NumSpatzOutstandingLoads [NrCores] = '{default: '0},
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
    input  logic          [NrCores-1:0]           debug_req_i,
    /// End of Computing indicator to notify the host/tb
    output logic                                  eoc_o,
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
    output logic          [NumTiles-1:0]          cluster_probe_o,
    /// AXI Core cluster in-port.
    input  axi_in_req_t   [NumTiles-1:0]          axi_in_req_i,
    output axi_in_resp_t  [NumTiles-1:0]          axi_in_resp_o,
    /// AXI Narrow out-port (UART)
    output axi_narrow_req_t                       axi_narrow_req_o,
    input  axi_narrow_resp_t                      axi_narrow_resp_i,
    /// AXI Core cluster out-port to core.
    output axi_out_req_t  [NumClusterSlv-1:0]  axi_out_req_o,
    input  axi_out_resp_t [NumClusterSlv-1:0]  axi_out_resp_i,
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
  localparam int unsigned WideIdWidthIn   = WideIdWidthOut - $clog2(NumClusterMst);

  // Cache XBar configuration struct
  localparam axi_pkg::xbar_cfg_t CacheXbarCfg = '{
    NoSlvPorts        : NumClusterMst*NumTiles,
    NoMstPorts        : NumClusterSlv,
    MaxMstTrans       : MaxMstTrans,
    MaxSlvTrans       : MaxSlvTrans,
    FallThrough       : 1'b0,
    LatencyMode       : XbarLatency,
    AxiIdWidthSlvPorts: WideIdWidthIn,
    AxiIdUsedSlvPorts : WideIdWidthIn,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiDataWidth,
    NoAddrRules       : NumClusterSlv - 1,
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

  `AXI_TYPEDEF_ALL(axi_mst_cache, addr_t, id_cache_mst_t, data_cache_t, strb_cache_t, user_cache_t)
  `AXI_TYPEDEF_ALL(axi_slv_cache, addr_t, id_cache_slv_t, data_cache_t, strb_cache_t, user_cache_t)

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
  axi_mst_cache_req_t  [NumTiles*NumTileWideAxi  -1 :0] axi_tile_req;
  axi_mst_cache_resp_t [NumTiles*NumTileWideAxi  -1 :0] axi_tile_rsp;
  axi_slv_cache_req_t  [NumTiles*NumClusterSlv-1 :0] wide_axi_slv_req;
  axi_slv_cache_resp_t [NumTiles*NumClusterSlv-1 :0] wide_axi_slv_rsp;
  axi_narrow_req_t     [NumTiles-1 :0]                  axi_out_req;
  axi_narrow_resp_t    [NumTiles-1 :0]                  axi_out_resp;

  // 2. BootROM
  reg_cache_req_t bootrom_reg_req;
  reg_cache_rsp_t bootrom_reg_rsp;

  // ---------------
  // CachePool Tile
  // ---------------

  logic [NumTiles-1:0] error, eoc;
  assign error_o = |error;
  assign eoc_o   = |eoc;

  cache_trans_req_t [NumTiles*NumL1CacheCtrl-1:0] cache_refill_req;
  cache_trans_rsp_t [NumTiles*NumL1CacheCtrl-1:0] cache_refill_rsp;

  cache_trans_req_t [NumTiles-1               :0] cache_core_req;
  cache_trans_rsp_t [NumTiles-1               :0] cache_core_rsp;

  cache_trans_req_chan_t [NumTiles*NumClusterMst-1 :0] tile_req_chan;
  cache_trans_rsp_chan_t [NumTiles*NumClusterMst-1 :0] tile_rsp_chan;
  logic                  [NumTiles*NumClusterMst-1 :0] tile_req_valid, tile_req_ready, tile_rsp_valid, tile_rsp_ready;

  l2_req_t               [NumClusterSlv-1 :0] l2_req;
  l2_rsp_t               [NumClusterSlv-1 :0] l2_rsp;

  cache_trans_req_chan_t [NumClusterSlv-1 :0] l2_req_chan;
  cache_trans_rsp_chan_t [NumClusterSlv-1 :0] l2_rsp_chan;
  logic                  [NumClusterSlv-1 :0] l2_req_valid,   l2_req_ready  , l2_rsp_valid,   l2_rsp_ready  ;

  typedef logic [$clog2(NumClusterMst*NumTiles)-1:0] l2_sel_t;
  typedef logic [$clog2(NumClusterSlv)-1         :0] tile_sel_t;

  // Which l2 we want to select for each req
  tile_sel_t [NumTiles*NumClusterMst-1 :0]           tile_sel;
  // Which tile we selected for each req
  l2_sel_t   [NumClusterSlv-1:0]                     tile_selected;
  // which tile we want to select for each rsp
  l2_sel_t   [NumClusterSlv-1:0]                     l2_sel;

  for (genvar t = 0; t < NumTiles; t ++) begin : gen_tiles
    cachepool_tile #(
      .AxiAddrWidth             ( AxiAddrWidth             ),
      .AxiDataWidth             ( AxiDataWidth             ),
      .AxiIdWidthIn             ( AxiIdWidthIn             ),
      .AxiIdWidthOut            ( WideIdWidthIn            ),
      .AxiUserWidth             ( AxiUserWidth             ),
      .BootAddr                 ( BootAddr                 ),
      .UartAddr                 ( UartAddr                 ),
      .ClusterPeriphSize        ( ClusterPeriphSize        ),
      .NrCores                  ( NrCores                  ),
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
      .clk_i                    ( clk_i                    ),
      .rst_ni                   ( rst_ni                   ),
      .eoc_o                    ( eoc[t]                   ),
      .impl_i                   ( impl_i                   ),
      .error_o                  ( error[t]                 ),
      .debug_req_i              ( debug_req_i              ),
      .meip_i                   ( meip_i                   ),
      .mtip_i                   ( mtip_i                   ),
      .msip_i                   ( msip_i                   ),
      .hart_base_id_i           ( hart_base_id_i           ),
      .cluster_base_addr_i      ( cluster_base_addr_i      ),
      .tile_probe_o             ( cluster_probe_o[t]       ),
      .axi_in_req_i             ( axi_in_req_i [t]         ),
      .axi_in_resp_o            ( axi_in_resp_o[t]         ),
      .axi_out_req_o            ( axi_out_req[t]           ),
      .axi_out_resp_i           ( axi_out_resp[t]          ),
      // Cache Refill Ports
      .cache_refill_req_o       ( cache_refill_req[t*NumL1CacheCtrl+:NumL1CacheCtrl]),
      .cache_refill_rsp_i       ( cache_refill_rsp[t*NumL1CacheCtrl+:NumL1CacheCtrl]),
      .axi_wide_req_o           ( axi_tile_req [t*NumTileWideAxi+:NumTileWideAxi] ),
      .axi_wide_rsp_i           ( axi_tile_rsp [t*NumTileWideAxi+:NumTileWideAxi] )
    );

    axi_to_reqrsp #(
      .axi_req_t    (axi_mst_cache_req_t        ),
      .axi_rsp_t    (axi_mst_cache_resp_t       ),
      .AddrWidth    (AxiAddrWidth               ),
      .DataWidth    (AxiDataWidth               ),
      .UserWidth    ($bits(refill_user_t)       ),
      .IdWidth      (AxiIdWidthIn               ),
      .BufDepth     (NumSpatzOutstandingLoads[0]),
      .reqrsp_req_t (cache_trans_req_t          ),
      .reqrsp_rsp_t (cache_trans_rsp_t          )
    ) i_axi2reqrsp  (
      .clk_i        (clk_i                                  ),
      .rst_ni       (rst_ni                                 ),
      .busy_o       (                                       ),
      .axi_req_i    (axi_tile_req [t*NumTileWideAxi+TileMem]),
      .axi_rsp_o    (axi_tile_rsp [t*NumTileWideAxi+TileMem]),
      .reqrsp_req_o (cache_core_req[t]                      ),
      .reqrsp_rsp_i (cache_core_rsp[t]                      )
    );
  end

  for (genvar t = 0; t < NumTiles; t++) begin
    // Cache Bypass requests
    always_comb begin
      tile_req_chan [t*NumTiles]      = cache_core_req[t].q;
      // Scrmable address
      tile_req_chan [t*NumTiles].addr = scrambleAddr(cache_core_req[t].q.addr);
      tile_req_valid[t*NumTiles]      = cache_core_req[t].q_valid;
      cache_core_rsp[t].q_ready       = tile_req_ready[t*NumTiles];

      cache_core_rsp[t].p             = tile_rsp_chan [t*NumTiles];
      cache_core_rsp[t].p_valid       = tile_rsp_valid[t*NumTiles];
      tile_rsp_ready[t*NumTiles]      = cache_core_req[t].p_ready;

      // Normal Cache requests
      for (int p = 0; p < NumL1CacheCtrl; p++) begin
        tile_req_chan [t*NumTiles+p+1]         = cache_refill_req[t*NumTiles+p].q;
        // Scramble address
        tile_req_chan [t*NumTiles+p+1].addr    = scrambleAddr(cache_refill_req[t*NumTiles+p].q.addr);
        tile_req_valid[t*NumTiles+p+1]         = cache_refill_req[t*NumTiles+p].q_valid;
        cache_refill_rsp[t*NumTiles+p].q_ready = tile_req_ready[t*NumTiles+p+1];

        cache_refill_rsp[t*NumTiles+p].p       = tile_rsp_chan [t*NumTiles+p+1];
        cache_refill_rsp[t*NumTiles+p].p_valid = tile_rsp_valid[t*NumTiles+p+1];
        tile_rsp_ready[t*NumTiles+p+1]         = cache_refill_req[t*NumTiles+p].p_ready;
      end
    end
  end

  typedef struct packed {
    int unsigned idx;
    logic [AxiAddrWidth-1:0] base;
    logic [AxiAddrWidth-1:0] mask;
  } reqrsp_rule_t;

  reqrsp_rule_t [NumClusterSlv-2:0] xbar_rule;

  for (genvar i = 0; i < NumClusterSlv-1; i ++) begin
    assign xbar_rule[i] = '{
      idx  : i,
      base : DramAddr + DramPerChSize * i,
      mask : ({AxiAddrWidth{1'b1}} << $clog2(DramPerChSize))
    };
  end

  logic [$clog2(NumClusterSlv)-1:0] default_idx;
  assign default_idx = (NumClusterSlv-1);

  for (genvar inp = 0; inp < NumClusterMst*NumTiles; inp ++) begin : gen_xbar_sel
    addr_decode_napot #(
      .NoIndices (NumClusterSlv   ),
      .NoRules   (NumClusterSlv-1      ),
      .addr_t    (axi_addr_t    ),
      .rule_t    (reqrsp_rule_t )
    ) i_snitch_decode_napot (
      .addr_i           (tile_req_chan[inp].addr),
      .addr_map_i       (xbar_rule              ),
      .idx_o            (tile_sel[inp]          ),
      .dec_valid_o      (/* Unused */           ),
      .dec_error_o      (/* Unused */           ),
      .en_default_idx_i (1'b1                   ),
      .default_idx_i    (default_idx            )
    );
  end

  reqrsp_xbar #(
    .NumInp           (NumClusterMst*NumTiles ),
    .NumOut           (NumClusterSlv          ),
    .PipeReg          (1'b1             ),
    .tcdm_req_chan_t  (cache_trans_req_chan_t  ),
    .tcdm_rsp_chan_t  (cache_trans_rsp_chan_t  )
  ) i_cluster_xbar (
    .clk_i            (clk_i            ),
    .rst_ni           (rst_ni           ),
    .slv_req_i        (tile_req_chan    ),
    .slv_req_valid_i  (tile_req_valid   ),
    .slv_req_ready_o  (tile_req_ready   ),
    .slv_rsp_o        (tile_rsp_chan    ),
    .slv_rsp_valid_o  (tile_rsp_valid   ),
    .slv_rsp_ready_i  (tile_rsp_ready   ),
    .slv_sel_i        (tile_sel         ),
    .slv_selected_o   (tile_selected    ),
    .mst_req_o        (l2_req_chan      ),
    .mst_req_valid_o  (l2_req_valid     ),
    .mst_req_ready_i  (l2_req_ready     ),
    .mst_rsp_i        (l2_rsp_chan      ),
    .mst_rsp_valid_i  (l2_rsp_valid     ),
    .mst_rsp_ready_o  (l2_rsp_ready     ),
    .mst_sel_i        (l2_sel           )
  );

  for (genvar ch = 0; ch < NumClusterSlv; ch++) begin
    // To L2 Channels
    always_comb begin
      l2_req[ch].q       = '{
        addr : l2_req_chan[ch].addr,
        write: l2_req_chan[ch].write,
        amo  : l2_req_chan[ch].amo,
        data : l2_req_chan[ch].data,
        strb : l2_req_chan[ch].strb,
        size : l2_req_chan[ch].size,
        default: '0
      };
      l2_req[ch].q.user  = '{
        bank_id: l2_req_chan[ch].user.bank_id,
        info:    l2_req_chan[ch].user.info,
        default: '0
      };
      l2_req[ch].q_valid = l2_req_valid[ch] ;
      l2_req_ready[ch]   = l2_rsp[ch].q_ready;

      l2_rsp_chan [ch]   = '{
        data : l2_rsp[ch].p.data,
        error: l2_rsp[ch].p.error,
        write: l2_rsp[ch].p.write,
        default: '0
      };
      l2_rsp_chan [ch].user = '{
        bank_id: l2_rsp[ch].p.user.bank_id,
        info   : l2_rsp[ch].p.user.info,
        default: '0
      };
      l2_rsp_valid[ch]   = l2_rsp[ch].p_valid;
      l2_req[ch].p_ready = l2_rsp_ready[ch];
      l2_sel[ch]         = l2_rsp[ch].p.user.bank_id;
    end
  end

  for (genvar ch = 0; ch < NumClusterSlv; ch ++) begin : gen_output_axi
    reqrsp_to_axi #(
      .MaxTrans           (NumSpatzOutstandingLoads[0]),
      .ID                 (ch                         ),
      .ShuffleId          (0                          ),
      .UserWidth          ($bits(l2_user_t)           ),
      .ReqUserFallThrough (1'b0                       ),
      .DataWidth          (AxiDataWidth               ),
      .AxiUserWidth       (AxiUserWidth               ),
      .reqrsp_req_t       (l2_req_t                   ),
      .reqrsp_rsp_t       (l2_rsp_t                   ),
      .axi_req_t          (axi_slv_cache_req_t        ),
      .axi_rsp_t          (axi_slv_cache_resp_t       )
    ) i_reqrsp2axi  (
      .clk_i        (clk_i                ),
      .rst_ni       (rst_ni               ),
      .user_i       ('0                   ),
      .reqrsp_req_i (l2_req[ch]           ),
      .reqrsp_rsp_o (l2_rsp[ch]           ),
      .axi_req_o    (wide_axi_slv_req[ch] ),
      .axi_rsp_i    (wide_axi_slv_rsp[ch] )
    );
  end

  // TODO: Add AXI MUX and assign ID correctly here
  assign axi_narrow_req_o = axi_out_req[0];
  assign axi_out_resp[0] = axi_narrow_resp_i;

  // -------------
  // DMA Subsystem
  // -------------
  // Optionally decouple the external wide AXI master port.
  for (genvar port = 0; port < NumClusterSlv; port ++) begin : gen_axi_out_cut
    axi_cut #(
      .Bypass     (0               ),
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

  // TODO: Add MUX for multi-Tile
  // BootROM
  axi_to_reg #(
    .ADDR_WIDTH         (AxiAddrWidth        ),
    .DATA_WIDTH         (AxiDataWidth        ),
    .AXI_MAX_WRITE_TXNS (1                   ),
    .AXI_MAX_READ_TXNS  (1                   ),
    .DECOUPLE_W         (0                   ),
    .ID_WIDTH           (WideIdWidthIn       ),
    .USER_WIDTH         (AxiUserWidth        ),
    .axi_req_t          (axi_mst_cache_req_t ),
    .axi_rsp_t          (axi_mst_cache_resp_t),
    .reg_req_t          (reg_cache_req_t     ),
    .reg_rsp_t          (reg_cache_rsp_t     )
  ) i_axi_to_reg_bootrom (
    .clk_i      (clk_i                    ),
    .rst_ni     (rst_ni                   ),
    .testmode_i (1'b0                     ),
    .axi_req_i  (axi_tile_req[TileBootROM]),
    .axi_rsp_o  (axi_tile_rsp[TileBootROM]),
    .reg_req_o  (bootrom_reg_req          ),
    .reg_rsp_i  (bootrom_reg_rsp          )
  );

  bootrom i_bootrom (
    .clk_i  (clk_i                        ),
    .req_i  (bootrom_reg_req.valid        ),
    .addr_i (addr_t'(bootrom_reg_req.addr)),
    .rdata_o(bootrom_reg_rsp.rdata        )
  );
  `FF(bootrom_reg_rsp.ready, bootrom_reg_req.valid, 1'b0)
  assign bootrom_reg_rsp.error = 1'b0;

endmodule
