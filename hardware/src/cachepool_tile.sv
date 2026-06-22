// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "axi/typedef.svh"
`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"
`include "reqrsp_interface/typedef.svh"
`include "snitch_vm/typedef.svh"
`include "hpdcache_typedef.svh"

/// Tile implementation for CachePool
module cachepool_tile
  import cachepool_pkg::*;
  import spatz_pkg::*;
  import hpdcache_pkg::*;
  import fpnew_pkg::fpu_implementation_t;
  import snitch_pma_pkg::snitch_pma_t;
  import snitch_icache_pkg::icache_l1_events_t;
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
    /// Tile ID Width
    parameter int                     unsigned               TileIDWidth                        = 0,
    /// Number of dedicated inter-group remote ports per xbar plane.
    /// When 0, no inter-group ports are generated (single-group mode).
    parameter int                     unsigned               NumRemoteGroupPortCore             = 0,
    /// Number of tiles within a single group (passed to interco for
    /// group-id extraction from the address).
    parameter int                     unsigned               NumTilesPerGroup                   = 0,
    /// # Per-core parameters
    /// Per-core integer outstanding loads
    parameter int                     unsigned               NumIntOutstandingLoads             = '0,
    /// Per-core integer outstanding memory operations (load and stores)
    parameter int                     unsigned               NumIntOutstandingMem               = '0,
    /// Per-core Spatz outstanding loads
    parameter int                     unsigned               NumSpatzOutstandingLoads           = '0,
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
    // [LP1] Strategy-B collapse: inter-group remote ports no longer fan out per
    // TCDM plane; the flat count drops to NumRemoteGroupPortCore * NumL2Plane.
    // localparam int                 unsigned               TotRGPorts                         = (NumRemoteGroupPortCore == 0) ? 0 : NumRemoteGroupPortCore*NrTCDMPortsPerCore-1
    localparam int                    unsigned               TotRGPorts                         = (NumRemoteGroupPortCore == 0) ? 0 : NumRemoteGroupPortCore*NumL2Plane-1
  ) (
    /// System clock.
    input  logic                                          clk_i,
    /// Asynchronous active high reset. This signal is assumed to be _async_.
    input  logic                                          rst_ni,
    /// Per-core debug request signal. Asserting this signals puts the
    /// corresponding core into debug mode. This signal is assumed to be _async_.
    input  logic                                          debug_req_i,
    /// Machine external interrupt pending. Usually those interrupts come from a
    /// platform-level interrupt controller. This signal is assumed to be _async_.
    input  logic                                          meip_i,
    /// Machine timer interrupt pending. Usually those interrupts come from a
    /// core-local interrupt controller such as a timer/RTC. This signal is
    /// assumed to be _async_.
    input  logic                                          mtip_i,
    /// Core software interrupt pending. Usually those interrupts come from
    /// another core to facilitate inter-processor-interrupts. This signal is
    /// assumed to be _async_.
    input  logic                                          msip_i,
    /// First hartid of the cluster. Cores of a cluster are monotonically
    /// increasing without a gap, i.e., a cluster with 8 cores and a
    /// `hart_base_id_i` of 5 get the hartids 5 - 12.
    input  logic              [9:0]                       hart_base_id_i,
    /// Base address of cluster. TCDM and cluster peripheral location are derived from
    /// it. This signal is pseudo-static.
    input  axi_addr_t                                     cluster_base_addr_i,
    /// Tile ID, internal ID, the base is always 0, in theory should not change during use
    input  remote_tile_sel_t                              tile_id_i,
    /// Partitioning address
    input  axi_addr_t                                     private_start_addr_i,
    /// AXI Narrow out-port (UART/Peripheral)
    output axi_narrow_req_t   [1:0]                       axi_out_req_o,
    input  axi_narrow_resp_t  [1:0]                       axi_out_resp_i,
    /// Cache Refill ports
    output cache_trans_req_t  [NumL1CtrlTile-1:0]         cache_refill_req_o,
    input  cache_trans_rsp_t  [NumL1CtrlTile-1:0]         cache_refill_rsp_i,
    /// Wide AXI ports to cluster level
    output axi_out_req_t      [TileNarrowAxiPorts-1:0]    axi_wide_req_o,
    input  axi_out_resp_t     [TileNarrowAxiPorts-1:0]    axi_wide_rsp_i,
    /// Remote Tile access ports (to remote tiles)
    // [LP1] Strategy-B collapse + Option-A width: the intra-group remote NoC is now
    // cacheline-wide (tcdm_cacheline_*) and the flat dimension collapses to
    // NumRemotePortTile = NumRemotePortCore * NumL2Plane (NumL2Plane = 1). Old
    // narrow ports commented out.
    // output tcdm_req_t         [NumRemotePortTile-1:0]     remote_req_o,
    // input  tcdm_rsp_t         [NumRemotePortTile-1:0]     remote_rsp_i,
    // input  tcdm_req_t         [NumRemotePortTile-1:0]     remote_req_i,
    // output tcdm_rsp_t         [NumRemotePortTile-1:0]     remote_rsp_o,
    output tcdm_cacheline_req_t [NumRemotePortTile-1:0]   remote_req_o,
    output remote_tile_sel_t  [NumRemotePortTile-1:0]     remote_req_dst_o,
    input  tcdm_cacheline_rsp_t [NumRemotePortTile-1:0]   remote_rsp_i,
    input  logic              [NumRemotePortTile-1:0]     remote_rsp_ready_i,
    /// Remote Tile access ports (from remote tiles)
    input  tcdm_cacheline_req_t [NumRemotePortTile-1:0]   remote_req_i,
    output tcdm_cacheline_rsp_t [NumRemotePortTile-1:0]   remote_rsp_o,
    output logic              [NumRemotePortTile-1:0]     remote_rsp_ready_o,
    /// Inter-group remote access ports (to other groups).
    /// Flat layout: flat index = j + r * NrTCDMPortsPerCore,
    /// where j is the interco instance and r is the inter-group remote slot.
    /// Total count: NumRemoteGroupPortCore * NrTCDMPortsPerCore.
    /// Uses REQRSP-style types with built-in ready and remote_group_user_t.
    output remote_group_req_t [TotRGPorts:0]              remote_group_req_o,
    input  remote_group_rsp_t [TotRGPorts:0]              remote_group_rsp_i,
    /// Inter-group remote access ports (from other groups)
    input  remote_group_req_t [TotRGPorts:0]              remote_group_req_i,
    output remote_group_rsp_t [TotRGPorts:0]              remote_group_rsp_o,
    /// Peripheral signals
    output icache_l1_events_t [NrCores-1:0]               icache_events_o,
    input  logic                                          icache_prefetch_enable_i,
    input  logic              [NrCores-1:0]               cl_interrupt_i,
    input  logic              [$clog2(AxiAddrWidth)-1:0]  dynamic_offset_i,
    input  cache_insn_t                                   l1d_insn_i,
    input  logic              [3:0]                       l1d_private_i,
    input  logic                                          l1d_insn_valid_i,
    output logic                                          l1d_insn_ready_o,
    input  logic                                          l1d_busy_i,



    /// SRAM Configuration Ports, usually not used.
    input  impl_in_t          [NrSramCfg-1:0]       impl_i,
    /// Indicate the program execution is error
    output logic                                    error_o
  );
  // ---------
  // Imports
  // ---------
  import snitch_pkg::*;

  // ---------
  // Constants
  // ---------
  // TODO: Should be imported from Memory-mapped Reg
  logic [2:0] num_private_cache;
  assign num_private_cache = l1d_private_i[2:0];

  /// Minimum width to hold the core number.
  // localparam int unsigned CoreIDWidth       = cf_math_pkg::idx_width(NrCores);
  localparam int unsigned TCDMMemAddrWidth  = $clog2(TCDMDepth);

  // Enlarge the address width for Spatz due to cache
  localparam int unsigned TCDMAddrWidth     = 32;
  localparam int unsigned BanksPerSuperBank = AxiDataWidth / DataWidth;
  localparam int unsigned NrSuperBanks      = NrBanks / BanksPerSuperBank;

  function automatic int unsigned get_tcdm_ports(int unsigned core);
    return spatz_pkg::N_FU + 1;
  endfunction

  function automatic int unsigned get_tcdm_port_offs(int unsigned core_idx);
    automatic int n = 0;
    for (int i = 0; i < core_idx; i++) n += get_tcdm_ports(i);
    return n;
  endfunction

  localparam int unsigned NrTCDMPortsCores            = get_tcdm_port_offs(NrCores);
  localparam int unsigned NumTCDMIn                   = NrTCDMPortsCores + 1;
  localparam logic        [AxiAddrWidth-1:0] TCDMMask = ~(TCDMSize-1);

  // Core Request, SoC Request
  localparam int unsigned NrNarrowMasters = 1;

  // Narrow AXI network parameters
  localparam int unsigned NarrowIdWidthIn  = AxiIdWidthIn;
  localparam int unsigned NarrowIdWidthOut = NarrowIdWidthIn + $clog2(NrNarrowMasters);
  localparam int unsigned NarrowDataWidth  = ELEN;
  localparam int unsigned NarrowUserWidth  = AxiUserWidth;

  // Peripherals, SoC Request, UART
  localparam int unsigned NrNarrowSlaves = 3;
  localparam int unsigned NrNarrowRules  = NrNarrowSlaves - 1;

  // Core Request, Instruction cache
  localparam int unsigned NrWideMasters  = 2;
  localparam int unsigned WideIdWidthOut = AxiIdWidthOut;
  localparam int unsigned WideIdWidthIn  = AxiIdWidthOut - $clog2(NrWideMasters);
  // Wide X-BAR configuration: Core Request, ICache
  localparam int unsigned NrWideSlaves   = 2;

  // AXI Configuration
  localparam axi_pkg::xbar_cfg_t ClusterXbarCfg = '{
    NoSlvPorts        : NrNarrowMasters,
    NoMstPorts        : NrNarrowSlaves,
    MaxMstTrans       : MaxMstTrans,
    MaxSlvTrans       : MaxSlvTrans,
    FallThrough       : 1'b0,
    LatencyMode       : XbarLatency,
    AxiIdWidthSlvPorts: NarrowIdWidthIn,
    AxiIdUsedSlvPorts : NarrowIdWidthIn,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : NarrowDataWidth,
    NoAddrRules       : NrNarrowRules,
    default           : '0
  };

  // DMA configuration struct
  localparam axi_pkg::xbar_cfg_t WideXbarCfg = '{
    NoSlvPorts        : NrWideMasters,
    NoMstPorts        : NrWideSlaves,
    MaxMstTrans       : MaxMstTrans,
    MaxSlvTrans       : MaxSlvTrans,
    FallThrough       : 1'b0,
    LatencyMode       : XbarLatency,
    AxiIdWidthSlvPorts: WideIdWidthIn,
    AxiIdUsedSlvPorts : WideIdWidthIn,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiDataWidth,
    NoAddrRules       : NrWideSlaves - 1,
    default           : '0
  };

  // --------
  // Typedefs
  // --------
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [NarrowDataWidth-1:0]   data_t;
  typedef logic [NarrowDataWidth/8-1:0] strb_t;
  typedef logic [L1TagDataWidth-1:0]    tag_data_t;
  typedef logic [AxiDataWidth-1:0]      data_wide_t;
  typedef logic [AxiDataWidth/8-1:0]    strb_wide_t;
  typedef logic [NarrowIdWidthIn-1:0]   id_mst_t;
  typedef logic [NarrowIdWidthOut-1:0]  id_slv_t;
  typedef logic [WideIdWidthIn-1:0]     id_wide_mst_t;
  typedef logic [WideIdWidthOut-1:0]    id_wide_slv_t;
  typedef logic [NarrowUserWidth-1:0]   user_t;
  typedef logic [AxiUserWidth-1:0]      user_wide_t;

  typedef logic [TCDMMemAddrWidth-1:0]  tcdm_mem_addr_t;
  typedef logic [TCDMAddrWidth-1:0]     tcdm_addr_t;

  typedef logic [$clog2(L1NumSet)-1:0] tcdm_bank_addr_t;

  ////////////////////////////////////////////
  // Private L1 (LP1) HPDcache config & types //
  ////////////////////////////////////////////
  // Per-core private L1 data cache (HPDcache, write-through, no coherence).
  // It coalesces the core's Spatz TCDM lanes; its mem interface is the
  // cacheline-wide downstream (l2_req) that feeds the shared L2 through the
  // collapsed tile interco. Config/types defined here and passed to
  // cachepool_l1_ctrl as parameters.

  // Spatz coalescer geometry
  localparam int unsigned NrLP1CoalInputs      = NrTCDMPortsPerCore - 1;          // Spatz lanes
  localparam int unsigned LP1ExtPorts          = NrLP1CoalInputs;
  localparam int unsigned LP1WordWidth         = 128;                             // HPDcache word width
  localparam int unsigned LP1NrBitsCoalOffset  = $clog2(LP1WordWidth/DataWidth);  // coalescer offset_t width
  localparam int unsigned LP1NumWordOffsetBits = $clog2(LP1WordWidth/DataWidth);  // tid word-offset field
  localparam int unsigned LP1CoalInfoWidth     = LP1ExtPorts + LP1ExtPorts*LP1NrBitsCoalOffset;
  localparam int unsigned LP1ReqIdWidth        = $clog2(NumSpatzOutstandingLoads);
  localparam int unsigned LP1TidWidth          = CoreIDWidth + TileIDWidth + LP1ReqIdWidth + 2 + LP1CoalInfoWidth; // +2: is_fpu, write; tile_id+core_id round-tripped
  localparam int unsigned LP1NrRequesters      = 2;                               // Snitch + Spatz(coalesced)

  localparam hpdcache_pkg::hpdcache_user_cfg_t HPDcacheUserCfg = '{
      nRequesters:        LP1NrRequesters,
      paWidth:            32,
      wordWidth:          LP1WordWidth,
      sets:               64,            // TODO: 32 sets => 8KB/core target (currently 16KB)
      ways:               4,
      clWords:            4,
      reqWords:           1,
      reqTransIdWidth:    LP1TidWidth + LP1NumWordOffsetBits,
      reqSrcIdWidth:      1,             // selects requester port (0 Spatz / 1 Snitch)
      victimSel:          hpdcache_pkg::HPDCACHE_VICTIM_PLRU,
      dataWaysPerRamWord: 1,
      dataSetsPerRam:     64,
      dataRamByteEnable:  1'b1,
      accessWords:        4,
      mshrSets:           8,
      mshrWays:           4,
      mshrWaysPerRamWord: 4,
      mshrSetsPerRam:     8,
      mshrRamByteEnable:  1'b1,
      mshrUseRegbank:     1'b1,
      cbufEntries:        2,
      refillCoreRspFeedthrough: 1'b1,
      refillFifoDepth:    2,
      wbufDirEntries:     4,
      wbufDataEntries:    4,
      wbufWords:          4,
      wbufTimecntWidth:   3,
      rtabEntries:        4,
      flushEntries:       2,
      flushFifoDepth:     2,
      memAddrWidth:       L1AddrWidth,
      memIdWidth:         LP1TidWidth,
      memDataWidth:       L1LineWidth,
      wtEn:               1'b1,          // write-through
      wbEn:               1'b0,
      lowLatency:         1'b1,
      eccEn:              1'b0,
      eccScrubberEn:      1'b0
  };
  localparam hpdcache_pkg::hpdcache_cfg_t HPDcacheCfg = hpdcacheBuildConfig(HPDcacheUserCfg);

  // The metadata type used to restore the information from req to rsp.
  // (extended with `amo` for the private-L1 datapath)
  typedef struct packed {
    tcdm_user_t       user;
    logic             write;
    hpdcache_req_op_t amo;
  } tcdm_meta_t;

  // HPDcache request-side typedefs
  typedef logic [HPDcacheCfg.tagWidth-1:0]                  hpdcache_tag_t;
  typedef logic [HPDcacheCfg.u.wordWidth-1:0]               hpdcache_data_word_t;
  typedef logic [HPDcacheCfg.u.wordWidth/8-1:0]             hpdcache_data_be_t;
  typedef logic [HPDcacheCfg.reqOffsetWidth-1:0]            hpdcache_req_offset_t;
  typedef hpdcache_data_word_t [HPDcacheCfg.u.reqWords-1:0] hpdcache_req_data_t;
  typedef hpdcache_data_be_t   [HPDcacheCfg.u.reqWords-1:0] hpdcache_req_be_t;
  typedef logic [HPDcacheCfg.u.reqSrcIdWidth-1:0]           hpdcache_req_sid_t;
  typedef logic [HPDcacheCfg.u.reqTransIdWidth-1:0]         hpdcache_req_tid_t;
  `HPDCACHE_TYPEDEF_REQ_T(hpdcache_req_t, hpdcache_req_offset_t, hpdcache_req_data_t,
                          hpdcache_req_be_t, hpdcache_req_sid_t, hpdcache_req_tid_t, hpdcache_tag_t);
  `HPDCACHE_TYPEDEF_RSP_T(hpdcache_rsp_t, hpdcache_req_data_t, hpdcache_req_sid_t, hpdcache_req_tid_t);
  typedef logic [HPDcacheCfg.u.wbufTimecntWidth-1:0]       hpdcache_wbuf_timecnt_t;

  // HPDcache memory-side typedefs (L1 -> L2 mem channels)
  typedef logic [HPDcacheCfg.u.memAddrWidth-1:0]           hpdcache_mem_addr_t;
  typedef logic [HPDcacheCfg.u.memIdWidth-1:0]             hpdcache_mem_id_t;
  typedef logic [HPDcacheCfg.u.memDataWidth-1:0]           hpdcache_mem_data_t;
  typedef logic [HPDcacheCfg.u.memDataWidth/8-1:0]         hpdcache_mem_be_t;
  `HPDCACHE_TYPEDEF_MEM_REQ_T(hpdcache_mem_req_t, hpdcache_mem_addr_t, hpdcache_mem_id_t);
  `HPDCACHE_TYPEDEF_MEM_RESP_R_T(hpdcache_mem_resp_r_t, hpdcache_mem_id_t, hpdcache_mem_data_t);
  `HPDCACHE_TYPEDEF_MEM_REQ_W_T(hpdcache_mem_req_w_t, hpdcache_mem_data_t, hpdcache_mem_be_t);
  `HPDCACHE_TYPEDEF_MEM_RESP_W_T(hpdcache_mem_resp_w_t, hpdcache_mem_id_t);

  // Spatz request coalescer types. downstream_info_t MUST match
  // par_coalescer_top's internal struct exactly:
  //   { down_id_t id; logic[ExtPorts] hitmap; offset_t[ExtPorts] ofsts;
  //     info_t[ExtPorts] infos; logic bypass_coalescer }
  // with down_id_t = logic, offset_t = logic[$clog2(Down/Up)-1:0], info_t = tcdm_meta_t.
  typedef logic [LP1NrBitsCoalOffset-1:0]  lp1_offset_t;
  typedef logic [LP1NumWordOffsetBits-1:0] word_offset_t;
  typedef struct packed {
    logic                          id;
    logic        [LP1ExtPorts-1:0] hitmap;
    lp1_offset_t [LP1ExtPorts-1:0] ofsts;
    tcdm_meta_t  [LP1ExtPorts-1:0] infos;
    logic                          bypass_coalescer;
  } downstream_info_t;

  // Regbus peripherals.
  `AXI_TYPEDEF_ALL(axi_mst, addr_t, id_mst_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(axi_slv, addr_t, id_slv_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(axi_mst_tile_wide, addr_t, id_wide_mst_t, data_wide_t, strb_wide_t, user_wide_t)
  `AXI_TYPEDEF_ALL(axi_slv_tile_wide, addr_t, id_wide_slv_t, data_wide_t, strb_wide_t, user_wide_t)

  `REQRSP_TYPEDEF_ALL(reqrsp, addr_t, data_t, strb_t, tcdm_user_t)

  typedef struct packed {
    int unsigned idx;
    addr_t start_addr;
    addr_t end_addr;
  } xbar_rule_t;

  typedef struct packed {
    acc_addr_e addr;
    logic [5:0] id;
    logic [31:0] data_op;
    data_t data_arga;
    data_t data_argb;
    addr_t data_argc;
  } acc_issue_req_t;

  typedef struct packed {
    logic accept;
    logic writeback;
    logic loadstore;
    logic exception;
    logic isfloat;
  } acc_issue_rsp_t;

  typedef struct packed {
    logic [5:0] id;
    logic error;
    data_t data;
  } acc_rsp_t;

  `SNITCH_VM_TYPEDEF(AxiAddrWidth)

  typedef struct packed {
    // Slow domain.
    logic flush_i_valid;
    addr_t inst_addr;
    logic inst_cacheable;
    logic inst_valid;
    // Fast domain.
    acc_issue_req_t acc_req;
    logic acc_qvalid;
    logic acc_pready;
    // Slow domain.
    logic [1:0] ptw_valid;
    va_t [1:0] ptw_va;
    pa_t [1:0] ptw_ppn;
  } hive_req_t;

  typedef struct packed {
    // Slow domain.
    logic flush_i_ready;
    logic [31:0] inst_data;
    logic inst_ready;
    logic inst_error;
    // Fast domain.
    logic acc_qready;
    acc_rsp_t acc_resp;
    logic acc_pvalid;
    // Slow domain.
    logic [1:0] ptw_ready;
    l0_pte_t [1:0] ptw_pte;
    logic [1:0] ptw_is_4mega;
  } hive_rsp_t;

  // -----------
  // Assignments
  // -----------
  // Calculate start and end address of TCDM based on the `cluster_base_addr_i`.
  addr_t tcdm_start_address, tcdm_end_address;
  assign tcdm_start_address = (cluster_base_addr_i & TCDMMask);
  assign tcdm_end_address   = (tcdm_start_address + TCDMSize) & TCDMMask;

  addr_t cluster_periph_start_address, cluster_periph_end_address;
  assign cluster_periph_start_address = tcdm_end_address;
  assign cluster_periph_end_address   = tcdm_end_address + ClusterPeriphSize * 1024;

  // ----------------
  // Wire Definitions
  // ----------------
  // 1. AXI
  axi_slv_req_t  [NrNarrowSlaves-1:0]  narrow_axi_slv_req;
  axi_slv_resp_t [NrNarrowSlaves-1:0]  narrow_axi_slv_rsp;
  axi_mst_req_t  [NrNarrowMasters-1:0] narrow_axi_mst_req;
  axi_mst_resp_t [NrNarrowMasters-1:0] narrow_axi_mst_rsp;

  // DMA AXI buses
  axi_mst_tile_wide_req_t  [NrWideMasters-1:0] wide_axi_mst_req;
  axi_mst_tile_wide_resp_t [NrWideMasters-1:0] wide_axi_mst_rsp;
  axi_slv_tile_wide_req_t  [NrWideSlaves-1 :0] wide_axi_slv_req;
  axi_slv_tile_wide_resp_t [NrWideSlaves-1 :0] wide_axi_slv_rsp;

  // 3. Memory Subsystem (Interconnect)
  tcdm_req_t [NrTCDMPortsCores-1:0] tcdm_req;
  tcdm_rsp_t [NrTCDMPortsCores-1:0] tcdm_rsp;

  core_events_t [NrCores-1:0] core_events;

  // snitch_icache_pkg::icache_events_t [NrCores-1:0] icache_events;

  // 4. Memory Subsystem (Core side).
  reqrsp_req_t [NrCores-1:0] core_req, filtered_core_req;
  reqrsp_rsp_t [NrCores-1:0] core_rsp, filtered_core_rsp;


  // 8. L1 D$
  tcdm_req_t  [NrTCDMPortsCores-1:0] unmerge_req;
  tcdm_rsp_t  [NrTCDMPortsCores-1:0] unmerge_rsp;

  // [LP1] cache_req/cache_rsp stay as the per-core *narrow* TCDM ports that feed
  // the private L1 (gen_lp1_cache_transpose). The interco mem-side collapses to a
  // single cacheline-wide plane per L2 controller (NumL2Plane = 1), so cache_xbar_*
  // lose the NrTCDMPortsPerCore dimension and become tcdm_cacheline_*.
  tcdm_req_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_req;
  tcdm_rsp_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_rsp;
  // tcdm_req_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_req, cache_xbar_req;
  // tcdm_rsp_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_rsp, cache_xbar_rsp;
  tcdm_cacheline_req_t [NumL1CtrlTile-1:0] cache_xbar_req;
  tcdm_cacheline_rsp_t [NumL1CtrlTile-1:0] cache_xbar_rsp;
  // Post-xbar gated copies.
  // cache_ctrl_req : xbar output with q_valid suppressed during flush.
  // cache_bank_rsp : raw response from the bank stage; q_ready is gated before
  //                  being returned to the interco as cache_xbar_rsp.
  // tcdm_req_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_ctrl_req;
  // tcdm_rsp_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_bank_rsp;
  tcdm_cacheline_req_t [NumL1CtrlTile-1:0] cache_ctrl_req;
  tcdm_cacheline_rsp_t [NumL1CtrlTile-1:0] cache_bank_rsp;

  // [LP1] Phase 1: AMOs are serviced inside the private L1 (HPDcache); the L2-side
  // spatz_cache_amo is bypassed (kept instantiated-but-unused below for phase 2).
  // cache_amo_* are therefore unused in the collapsed path.
  // tcdm_req_t  [NumL1CtrlTile-1:0] cache_amo_req;
  // tcdm_rsp_t  [NumL1CtrlTile-1:0] cache_amo_rsp;

  // ---- Private L1 (LP1) -> shared L1/L2 downstream (cacheline-wide) ----
  // One private L1 per core; its single mem-side downstream feeds the collapsed
  // tile interco towards the shared cache (named L1 in this file). lp1_l1_req_unique
  // tags a per-core id (core_id, req_id+=c) so the shared L1 round-trips it
  // (recovered in the LP1 ctrl as req_id - core_id).
  tcdm_cacheline_req_t [NumL1CtrlTile-1:0] lp1_l1_req, lp1_l1_req_unique;
  tcdm_cacheline_rsp_t [NumL1CtrlTile-1:0] lp1_l1_rsp;
  logic                [NumL1CtrlTile-1:0] lp1_l1_rsp_ready;

  tcdm_req_t  [NumLP1CacheCtrl-1:0][NrTCDMPortsPerCore-1:0] cache_req_transposed;
  tcdm_rsp_t  [NumLP1CacheCtrl-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_transposed;
  logic       [NumLP1CacheCtrl-1:0][NrTCDMPortsPerCore-1:0] lp1_cache_rsp_ready, lp1_cache_req_ready;

  // [LP1] Collapsed: one cacheline-wide port per L2 controller (was a 2-D
  // [NumL1CtrlTile][NrTCDMPortsPerCore] fan-in feeding the in-ctrl coalescer).
  // data/strb widen from DataWidth to the cacheline (the private L1 already
  // coalesced upstream; the L2-side coalescer in the insitu fork is removed).
  // logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_valid;
  // logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_ready;
  // tcdm_addr_t [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_addr;
  // tcdm_user_t [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_meta;
  // logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_write;
  // data_t      [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_data;
  // strb_t      [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_strb;
  // logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_valid;
  // logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_ready;
  // logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_write;
  // data_t      [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_data;
  // tcdm_user_t [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_meta;
  logic            [NumL1CtrlTile-1:0] cache_req_valid;
  logic            [NumL1CtrlTile-1:0] cache_req_ready;
  tcdm_addr_t      [NumL1CtrlTile-1:0] cache_req_addr;
  tcdm_user_t      [NumL1CtrlTile-1:0] cache_req_meta;
  logic            [NumL1CtrlTile-1:0] cache_req_write;
  cacheline_data_t [NumL1CtrlTile-1:0] cache_req_data;
  cacheline_strb_t [NumL1CtrlTile-1:0] cache_req_strb;

  logic            [NumL1CtrlTile-1:0] cache_rsp_valid;
  logic            [NumL1CtrlTile-1:0] cache_rsp_ready;
  logic            [NumL1CtrlTile-1:0] cache_rsp_write;
  cacheline_data_t [NumL1CtrlTile-1:0] cache_rsp_data;
  tcdm_user_t      [NumL1CtrlTile-1:0] cache_rsp_meta;

  logic            [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_req;
  logic            [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_we;
  tcdm_bank_addr_t [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_addr;
  tag_data_t       [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_wdata;
  logic            [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_be;
  tag_data_t       [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_rdata;

  // [LP1] Cacheline-granular L2 data banks: NumDataBankPerCtrl is now SetAssoc*BankFactor
  // banks, each holding a full cache line. req/we/addr/gnt stay 1-per-bank; wdata/rdata
  // widen to a cache line and be becomes a cacheline byte-mask.
  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_req;
  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_we;
  tcdm_bank_addr_t [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_addr;
  // data_t           [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_wdata;
  // logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0][DataWidth/8-1:0] l1_data_bank_be;
  // data_t           [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_rdata;
  cacheline_data_t [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_wdata;
  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0][L1LineWidth/8-1:0] l1_data_bank_be;
  cacheline_data_t [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_rdata;
  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_gnt;

  tcdm_bank_addr_t            cfg_spm_size;

  // TODO: Connect to stack overflow error
  assign error_o = 1'b0;


  // -------------
  // DMA Subsystem
  // -------------
  // Optionally decouple the external wide AXI master port.

  assign axi_wide_req_o[TileMem] = wide_axi_slv_req[SoCDMAOut];
  assign wide_axi_slv_rsp[SoCDMAOut] = axi_wide_rsp_i[TileMem];

  logic       [WideXbarCfg.NoSlvPorts-1:0][$clog2(WideXbarCfg.NoMstPorts)-1:0] dma_xbar_default_port;
  xbar_rule_t [WideXbarCfg.NoAddrRules-1:0]                                   dma_xbar_rule;

  assign dma_xbar_default_port = '{default: SoCDMAOut};
  assign dma_xbar_rule         = '{
    '{
      idx       : BootROM,
      start_addr: BootAddr,
      end_addr  : BootAddr + 'h1000
    }
  };

  localparam bit [WideXbarCfg.NoSlvPorts-1:0] DMAEnableDefaultMstPort = '1;
  axi_xbar #(
    .Cfg           (WideXbarCfg                ),
    .ATOPs         (0                          ),
    .slv_aw_chan_t (axi_mst_tile_wide_aw_chan_t),
    .mst_aw_chan_t (axi_slv_tile_wide_aw_chan_t),
    .w_chan_t      (axi_mst_tile_wide_w_chan_t ),
    .slv_b_chan_t  (axi_mst_tile_wide_b_chan_t ),
    .mst_b_chan_t  (axi_slv_tile_wide_b_chan_t ),
    .slv_ar_chan_t (axi_mst_tile_wide_ar_chan_t),
    .mst_ar_chan_t (axi_slv_tile_wide_ar_chan_t),
    .slv_r_chan_t  (axi_mst_tile_wide_r_chan_t ),
    .mst_r_chan_t  (axi_slv_tile_wide_r_chan_t ),
    .slv_req_t     (axi_mst_tile_wide_req_t    ),
    .slv_resp_t    (axi_mst_tile_wide_resp_t   ),
    .mst_req_t     (axi_slv_tile_wide_req_t    ),
    .mst_resp_t    (axi_slv_tile_wide_resp_t   ),
    .rule_t        (xbar_rule_t          )
  ) i_axi_wide_xbar (
    .clk_i                 (clk_i                  ),
    .rst_ni                (rst_ni                 ),
    .test_i                (1'b0                   ),
    .slv_ports_req_i       (wide_axi_mst_req       ),
    .slv_ports_resp_o      (wide_axi_mst_rsp       ),
    .mst_ports_req_o       (wide_axi_slv_req       ),
    .mst_ports_resp_i      (wide_axi_slv_rsp       ),
    .addr_map_i            (dma_xbar_rule          ),
    .en_default_mst_port_i (DMAEnableDefaultMstPort),
    .default_mst_port_i    (dma_xbar_default_port  )
  );


  logic  [NrTCDMPortsCores-1:0] unmerge_pready;
  // [LP1] cache_pready stays per-core narrow (LP1 core-side resp-ready, via the
  // transpose). cache_xbar_pready is the interco mem-side resp-ready: one per L2
  // controller now. cache_amo_pready unused in the collapsed (AMO-in-L1) path.
  // logic  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_pready, cache_xbar_pready;
  // logic  [NumL1CtrlTile-1:0] cache_amo_pready;
  logic  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_pready;
  logic  [NumL1CtrlTile-1:0] cache_xbar_pready;

  // ----------------------------------------------------------------------------
  // [LP1] Old core<->interco bridge, replaced by the per-core private L1.
  // The cores now drive their TCDM ports into cachepool_l1_ctrl (gen_lp1_cache);
  // the LP1 downstream (lp1_l1_req_unique) feeds the collapsed interco. The old
  // unmerge / cache_req reshape below is superseded and commented out.
  // ----------------------------------------------------------------------------
  always_comb begin : cache_flush_protection
    for (int j = 0; unsigned'(j) < NrTCDMPortsCores; j++) begin
      /***** REQ *****/
      unmerge_req[j].q       = tcdm_req[j].q;
      unmerge_req[j].q_valid = tcdm_req[j].q_valid;
      unmerge_pready[j]      = 1'b1;
  
      /***** RSP *****/
      tcdm_rsp[j].p       = unmerge_rsp[j].p;
      tcdm_rsp[j].p_valid = unmerge_rsp[j].p_valid;
      tcdm_rsp[j].q_ready = unmerge_rsp[j].q_ready;
    end
  
  end
  
  for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin
    for (genvar cb = 0; cb < NumL1CtrlTile; cb++) begin
      always_comb begin
        cache_req   [j][cb] = unmerge_req   [cb*NrTCDMPortsPerCore+j];
        cache_req   [j][cb].q.user.tile_id = tile_id_i;
        cache_pready[j][cb] = unmerge_pready[cb*NrTCDMPortsPerCore+j];
        unmerge_rsp [cb*NrTCDMPortsPerCore+j] = cache_rsp     [j][cb];
      end
  
    end
  end

  for (genvar i = 0; i < NumLP1CacheCtrl; i++) begin : gen_lp1_cache_transpose
    for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin : gen_lp1_cache_transpose_signals
      assign cache_req_transposed[i][j] = cache_req[j][i];

      assign cache_rsp[j][i].p_valid    = cache_rsp_transposed[i][j].p_valid;
      assign cache_rsp[j][i].p.data     = cache_rsp_transposed[i][j].p.data;
      assign cache_rsp[j][i].p.user     = cache_rsp_transposed[i][j].p.user;
      assign cache_rsp[j][i].p.write    = cache_rsp_transposed[i][j].p.write;
      
      assign cache_rsp[j][i].q_ready    = lp1_cache_req_ready[i][j];
      assign lp1_cache_rsp_ready[i][j]  = cache_pready[j][i];
    end
  end

  // ----------------------------------------------------------------------------
  // [LP1] Per-core private L1 data cache (HPDcache, write-through, no coherence).
  // Core side: the core's NrTCDMPortsPerCore TCDM ports (Spatz lanes [0..N-2] +
  // Snitch [N-1]). The LP1 coalesces/translates internally and exposes ONE
  // cacheline-wide downstream (lp1_l1_req / lp1_l1_rsp) to the shared L1/L2.
  // The core is always ready to accept responses (matches the legacy
  // unmerge_pready = 1'b1 convention), so core_rsp_ready_i is tied high.
  // ----------------------------------------------------------------------------
  for (genvar c = 0; c < NumLP1CacheCtrl; c++) begin : gen_lp1_cache
    cachepool_l1_ctrl #(
      .NrTCDMPortsPerCore   (NrTCDMPortsPerCore     ),
      .DataWidth            (DataWidth              ),
      .ByteWidth            (8                      ),
      .LP1NumWordOffsetBits (LP1NumWordOffsetBits   ),
      .LP1NrBitsCoalOffset  (LP1NrBitsCoalOffset    ),
      .HPDcacheCfg          (HPDcacheCfg            ),
      .wbuf_timecnt_t       (hpdcache_wbuf_timecnt_t),
      .l1_cache_req_t       (tcdm_req_t             ),
      .l1_cache_rsp_t       (tcdm_rsp_t             ),
      .tcdm_meta_t          (tcdm_meta_t            ),
      .downstream_info_t    (downstream_info_t      ),
      .word_offset_t        (word_offset_t          ),
      .l2_cache_req_t       (tcdm_cacheline_req_t   ),
      .l2_cache_rsp_t       (tcdm_cacheline_rsp_t   ),
      .hpdcache_tag_t        (hpdcache_tag_t        ),
      .hpdcache_data_word_t  (hpdcache_data_word_t  ),
      .hpdcache_data_be_t    (hpdcache_data_be_t    ),
      .hpdcache_req_offset_t (hpdcache_req_offset_t ),
      .hpdcache_req_data_t   (hpdcache_req_data_t   ),
      .hpdcache_req_be_t     (hpdcache_req_be_t     ),
      .hpdcache_req_sid_t    (hpdcache_req_sid_t    ),
      .hpdcache_req_tid_t    (hpdcache_req_tid_t    ),
      .hpdcache_req_t        (hpdcache_req_t        ),
      .hpdcache_rsp_t        (hpdcache_rsp_t        ),
      .hpdcache_mem_addr_t   (hpdcache_mem_addr_t   ),
      .hpdcache_mem_id_t     (hpdcache_mem_id_t     ),
      .hpdcache_mem_data_t   (hpdcache_mem_data_t   ),
      .hpdcache_mem_be_t     (hpdcache_mem_be_t     ),
      .hpdcache_mem_req_t    (hpdcache_mem_req_t    ),
      .hpdcache_mem_req_w_t  (hpdcache_mem_req_w_t  ),
      .hpdcache_mem_resp_r_t (hpdcache_mem_resp_r_t ),
      .hpdcache_mem_resp_w_t (hpdcache_mem_resp_w_t )
    ) i_lp1_cache (
      .clk_i            (clk_i        ),
      .rst_ni           (rst_ni       ),
      .wbuf_flush_i     (1'b0         ),

      // Core side (NrTCDMPortsPerCore narrow TCDM ports for this core)
      .core_req_i       (cache_req_transposed [c]),
      .core_rsp_o       (cache_rsp_transposed [c]),
      .core_req_ready_o (lp1_cache_req_ready  [c]),
      .core_rsp_ready_i (lp1_cache_rsp_ready  [c]),

      // Downstream (cacheline-wide) to shared L1/L2 via the interco
      .l2_req_o         (lp1_l1_req       [c]),
      .l2_rsp_i         (lp1_l1_rsp       [c]),
      .l2_rsp_ready_o   (lp1_l1_rsp_ready [c]),

      // Performance events: unconnected (perf counters unused for now)
      .evt_cache_write_miss_o   (),
      .evt_cache_read_miss_o    (),
      .evt_cache_dir_unc_err_o  (),
      .evt_cache_dir_cor_err_o  (),
      .evt_cache_dat_unc_err_o  (), 
      .evt_cache_dat_cor_err_o  (),
      .evt_scrub_complete_o     (), 
      .evt_uncached_req_o       (),
      .evt_cmo_req_o            (), 
      .evt_write_req_o          (),
      .evt_read_req_o           (), 
      .evt_prefetch_req_o       (),
      .evt_req_on_hold_o        (), 
      .evt_rtab_rollback_o      (),
      .evt_stall_refill_o       (), 
      .evt_stall_o              (),
      .wbuf_empty_o             (),

      // Configuration (static for now)
      .cfg_enable_i                        (1'b1),
      .cfg_wbuf_threshold_i                ('0  ),  // drain writes immediately (WT)
      .cfg_wbuf_reset_timecnt_on_write_i   (1'b0),
      .cfg_wbuf_sequential_waw_i           (1'b0),
      .cfg_wbuf_inhibit_write_coalescing_i (1'b0),
      .cfg_prefetch_updt_plru_i            (1'b0),
      .cfg_error_on_cacheable_amo_i        (1'b0),
      .cfg_rtab_single_entry_i             (1'b0),
      .cfg_default_wb_i                    (1'b0),  // write-through default
      .cfg_scrub_enable_i                  (1'b0),
      .cfg_scrub_period_i                  ('0  ),
      .cfg_scrub_restart_i                 (1'b0)
    );
  end

  // [LP1] Tag each private L1 downstream with a globally-unique id so the shared
  // L1/L2 can round-trip it. core_id selects the response path in the interco
  // (input port == core_id); tile_id marks this tile (for remote response
  // routing). req_id += core_id + tile_id offsets the HPDcache mem id so that
  // ids from different private caches (across cores AND remote tiles, which are
  // mutually agnostic) stay distinct towards the shared L2 (which keys on
  // req_id). The LP1 ctrl recovers the original via req_id - core_id - tile_id.
  for (genvar c = 0; c < NumLP1CacheCtrl; c++) begin : gen_lp1_l1_req_unique
    logic [CoreIDWidth-1:0] c_id;
    assign c_id = c[CoreIDWidth-1:0];
    always_comb begin
      lp1_l1_req_unique[c]                = lp1_l1_req[c];
      lp1_l1_req_unique[c].q.user.core_id = c_id;
      lp1_l1_req_unique[c].q.user.tile_id = tile_id_i;
      lp1_l1_req_unique[c].q.user.req_id  = lp1_l1_req[c].q.user.req_id + c_id + tile_id_i;
    end
  end

  // Used to determine the mapping policy between different cache banks.
  // Set through CSR
  logic [$clog2(AxiAddrWidth)-1:0] dynamic_offset;
  assign dynamic_offset = dynamic_offset_i;
  // One entry per flat remote port: flat index = j + r*NrTCDMPortsPerCore
  // where j is the xbar index and r is the remote slot within that xbar.
  logic [NumRemotePortTile-1:0] remote_out_pready, remote_in_pready;

  // Intra-group remote port wiring.
  // q_valid and q_ready for incoming requests are passed through without gating:
  // the after-xbar flush gate (cache_xbar_flush_gate) provides the authoritative
  // protection at the cache bank boundary and naturally back-pressures through
  // the interco to the remote sender.
  // response-ready (remote_in_pready) is still gated to prevent draining in-flight
  // completions during the flush window.

  // [LP1] cacheline-wide now; the single L2 plane means the flat index is just the
  // remote slot r (no j de-interleave, NumRemotePortTile == NumRemotePortCore).
  tcdm_cacheline_req_t [NumRemotePortTile-1:0] remote_req_gated;
  tcdm_cacheline_rsp_t [NumRemotePortTile-1:0] remote_rsp_xbar;

  always_comb begin : remote_flush_protection
    // for (int j = 0; j < NrTCDMPortsPerCore; j++) begin
    //   for (int r = 0; r < NumRemotePortCore; r++) begin
    //     automatic int unsigned flat = j + r * NrTCDMPortsPerCore;
    for (int r = 0; r < NumRemotePortTile; r++) begin
      remote_req_gated[r].q       = remote_req_i[r].q;
      remote_req_gated[r].q_valid = remote_req_i[r].q_valid;

      remote_rsp_o[r]             = remote_rsp_xbar[r];

      // Gate response-ready back to us: prevent draining completions
      // of requests that arrived just before the flush.
      remote_in_pready[r]         = remote_rsp_ready_i[r] && !l1d_busy_i;
    end
  end

  assign remote_rsp_ready_o = remote_out_pready;

  // -------------------------------------------------------------------------
  // Inter-group remote ports – type conversion and flush protection
  // -------------------------------------------------------------------------
  // External ports use REQRSP-style remote_group_req_t / remote_group_rsp_t
  // (with built-in ready and remote_group_user_t).
  // Internal interco uses TCDM-style tcdm_req_t / tcdm_rsp_t.
  // This section bridges the two and applies flush gating.
  //
  // Same flat layout as remote ports: flat = j + r * NrTCDMPortsPerCore.
  // Total count: NumRemoteGroupPortCore * NrTCDMPortsPerCore.

  // [LP1] Single L2 plane: count drops to NumRemoteGroupPortCore * NumL2Plane, and
  // the interco-side signals are cacheline-wide (Option A). The external ports
  // (remote_group_req_t) are already cacheline-wide via the pkg typedef.
  // localparam int unsigned NumRemoteGroupPortTile = NumRemoteGroupPortCore * NrTCDMPortsPerCore;
  localparam int unsigned NumRemoteGroupPortTile = NumRemoteGroupPortCore * NumL2Plane;

  // Internal TCDM-style (cacheline-wide) signals going to/from the interco.
  tcdm_cacheline_req_t [NumRemoteGroupPortTile-1:0] rg_interco_in_req;   // incoming requests to interco
  tcdm_cacheline_rsp_t [NumRemoteGroupPortTile-1:0] rg_interco_in_rsp;   // responses from interco (for incoming)
  logic                [NumRemoteGroupPortTile-1:0] rg_interco_in_pready; // response ready for incoming

  tcdm_cacheline_req_t [NumRemoteGroupPortTile-1:0] rg_interco_out_req;  // outgoing requests from interco
  tcdm_cacheline_rsp_t [NumRemoteGroupPortTile-1:0] rg_interco_out_rsp;  // responses returning (for outgoing)
  logic                [NumRemoteGroupPortTile-1:0] rg_interco_out_pready;// response ready for outgoing
  remote_tile_sel_t    [NumRemoteGroupPortTile-1:0] rg_interco_out_dst; // target tile from interco

  if (NumRemoteGroupPortCore > 0) begin : gen_remote_group_ports
    always_comb begin
      // [LP1] j now indexes the (single) L2 plane; flat de-interleave uses NumL2Plane.
      for (int j = 0; j < NumL2Plane; j++) begin
        for (int r = 0; r < NumRemoteGroupPortCore; r++) begin
          automatic int unsigned flat = j + r * NumL2Plane;

          // -----------------------------------------------------------
          // Incoming: REQRSP → TCDM conversion → interco
          // q_valid and q_ready are passed through without gating; the
          // after-xbar flush gate (cache_xbar_flush_gate) is the authoritative
          // protection point and naturally back-pressures through the interco.
          // -----------------------------------------------------------
          rg_interco_in_req[flat] = '{
            q: '{
              addr:  remote_group_req_i[flat].q.addr,
              write: remote_group_req_i[flat].q.write,
              data:  remote_group_req_i[flat].q.data,
              strb:  remote_group_req_i[flat].q.strb,
              amo:   remote_group_req_i[flat].q.amo,
              user: '{
                core_id: remote_group_req_i[flat].q.user.core_id,
                tile_id: remote_group_req_i[flat].q.user.tile_id,
                req_id:  remote_group_req_i[flat].q.user.req_id,
                is_fpu:  remote_group_req_i[flat].q.user.is_fpu,
                default: '0
              },
              default: '0
            },
            q_valid: remote_group_req_i[flat].q_valid,
            default: '0
          };

          // Interco response (TCDM) → REQRSP for remote_group_rsp_o.
          remote_group_rsp_o[flat] = '{
            p: '{
              data:  rg_interco_in_rsp[flat].p.data,
              write: rg_interco_in_rsp[flat].p.write,
              user: '{
                core_id: rg_interco_in_rsp[flat].p.user.core_id,
                tile_id: rg_interco_in_rsp[flat].p.user.tile_id,
                req_id:  rg_interco_in_rsp[flat].p.user.req_id,
                is_fpu:  rg_interco_in_rsp[flat].p.user.is_fpu,
                port_id: portid_t'(j),
                default: '0
              },
              default: '0
            },
            p_valid: rg_interco_in_rsp[flat].p_valid,
            q_ready: rg_interco_in_rsp[flat].q_ready,
            default: '0
          };

          // Response ready from the external port (REQRSP p_ready).
          rg_interco_in_pready[flat] = remote_group_req_i[flat].p_ready && !l1d_busy_i;

          // -----------------------------------------------------------
          // Outgoing: interco → flush gating → TCDM to REQRSP → output
          // -----------------------------------------------------------
          remote_group_req_o[flat] = '{
            q: '{
              addr:  rg_interco_out_req[flat].q.addr,
              write: rg_interco_out_req[flat].q.write,
              data:  rg_interco_out_req[flat].q.data,
              strb:  rg_interco_out_req[flat].q.strb,
              amo:   rg_interco_out_req[flat].q.amo,
              user: '{
                core_id:     rg_interco_out_req[flat].q.user.core_id,
                tile_id:     rg_interco_out_req[flat].q.user.tile_id,
                req_id:      rg_interco_out_req[flat].q.user.req_id,
                is_fpu:      rg_interco_out_req[flat].q.user.is_fpu,
                port_id:     portid_t'(j),
                dst_tile_id: rg_interco_out_dst[flat],
                default:     '0
              },
              default: '0
            },
            q_valid: rg_interco_out_req[flat].q_valid && !l1d_busy_i,
            p_ready: rg_interco_out_pready[flat] && !l1d_busy_i,
            default: '0
          };

          // Returning response (REQRSP) → TCDM for the interco.
          rg_interco_out_rsp[flat] = '{
            p: '{
              data:  remote_group_rsp_i[flat].p.data,
              write: remote_group_rsp_i[flat].p.write,
              user: '{
                core_id: remote_group_rsp_i[flat].p.user.core_id,
                tile_id: remote_group_rsp_i[flat].p.user.tile_id,
                req_id:  remote_group_rsp_i[flat].p.user.req_id,
                is_fpu:  remote_group_rsp_i[flat].p.user.is_fpu,
                default: '0
              },
              default: '0
            },
            p_valid: remote_group_rsp_i[flat].p_valid,
            q_ready: remote_group_rsp_i[flat].q_ready,
            default: '0
          };
        end
      end
    end
  end else begin : gen_remote_group_no_ports
    // No inter-group remote ports: tie off outputs.
    assign remote_group_rsp_o      = '0;
    assign remote_group_req_o      = '0;
    assign rg_interco_in_req       = '0;
    assign rg_interco_in_pready    = '0;
    assign rg_interco_out_rsp      = '0;
    assign rg_interco_out_pready   = '0;
    assign rg_interco_in_rsp       = '0;
    assign rg_interco_out_req      = '0;
    assign rg_interco_out_dst      = '0;
  end

  /// [LP1] Strategy-B collapse: the 5-plane (NrTCDMPortsPerCore) interco fan-out
  /// becomes a SINGLE cacheline-wide plane (NumL2Plane = 1). The core side is now
  /// the per-core private-L1 downstreams (lp1_l1_req_unique), and the mem side
  /// drives one cacheline port per L2 controller (cache_xbar_*, no plane index).
  /// Remote/inter-group slots are de-interleaved by NumL2Plane (so flat = r).
  for (genvar j = 0; j < NumL2Plane; j++) begin : gen_cache_xbar
    // Collect the NumRemotePortCore remote slots for this plane.
    tcdm_cacheline_req_t [NumRemotePortCore-1:0] xbar_remote_req_gated;
    tcdm_cacheline_rsp_t [NumRemotePortCore-1:0] xbar_remote_rsp_xbar;
    logic                [NumRemotePortCore-1:0] xbar_remote_in_pready;
    logic                [NumRemotePortCore-1:0] xbar_remote_out_pready;
    tcdm_cacheline_rsp_t [NumRemotePortCore-1:0] xbar_remote_rsp_i;
    remote_tile_sel_t    [NumRemotePortCore-1:0] xbar_remote_req_dst;
    tcdm_cacheline_req_t [NumRemotePortCore-1:0] xbar_remote_req_o;

    for (genvar r = 0; r < NumRemotePortCore; r++) begin : gen_remote_slice
      localparam int unsigned flat = j + r * NumL2Plane;
      assign xbar_remote_req_gated [r]  = remote_req_gated      [flat];
      assign xbar_remote_in_pready [r]  = remote_in_pready      [flat];
      assign xbar_remote_rsp_i     [r]  = remote_rsp_i          [flat];
      assign remote_rsp_xbar       [flat] = xbar_remote_rsp_xbar  [r];
      assign remote_out_pready     [flat] = xbar_remote_out_pready[r];
      assign remote_req_dst_o      [flat] = xbar_remote_req_dst   [r];
      assign remote_req_o          [flat] = xbar_remote_req_o     [r];
    end

    // Collect the NumRemoteGroupPortCore inter-group remote slots for this xbar (same flat layout).
    // When NumRemoteGroupPortCore == 0, no inter-group remote signals exist and the interco is
    // instantiated without inter-group remote ports (backward-compatible).
    if (NumRemoteGroupPortCore > 0) begin : gen_remote_group_slice
      tcdm_cacheline_req_t [NumRemoteGroupPortCore-1:0] xbar_remote_group_in_req;
      tcdm_cacheline_rsp_t [NumRemoteGroupPortCore-1:0] xbar_remote_group_in_rsp;
      logic                [NumRemoteGroupPortCore-1:0] xbar_remote_group_in_pready;
      tcdm_cacheline_req_t [NumRemoteGroupPortCore-1:0] xbar_remote_group_out_req;
      tcdm_cacheline_rsp_t [NumRemoteGroupPortCore-1:0] xbar_remote_group_out_rsp;
      logic                [NumRemoteGroupPortCore-1:0] xbar_remote_group_out_pready;
      remote_tile_sel_t    [NumRemoteGroupPortCore-1:0] xbar_remote_group_out_dst;

      for (genvar r = 0; r < NumRemoteGroupPortCore; r++) begin : gen_remote_group_slice_r
        localparam int unsigned flat = j + r * NumL2Plane;
        // Incoming: from conversion/flush → interco input
        assign xbar_remote_group_in_req    [r]    = rg_interco_in_req    [flat];
        assign xbar_remote_group_in_pready [r]    = rg_interco_in_pready [flat];
        assign rg_interco_in_rsp           [flat] = xbar_remote_group_in_rsp [r];
        // Outgoing: interco output → conversion/flush
        assign rg_interco_out_req          [flat] = xbar_remote_group_out_req [r];
        assign rg_interco_out_dst          [flat] = xbar_remote_group_out_dst [r];
        assign xbar_remote_group_out_rsp   [r]    = rg_interco_out_rsp   [flat];
        assign rg_interco_out_pready       [flat] = xbar_remote_group_out_pready[r];
      end

      // tcdm_cache_interco #(
      //   .NumTiles              (NumTiles          ),
      //   .NumCores              (NrCores           ),
      //   .NumCache              (NumL1CtrlTile     ),
      //   .NumTotCache           (NumL1CacheCtrl    ),
      //   .NumRemotePort         (NumRemotePortCore ),
      //   .NumRemoteGroupPort    (NumRemoteGroupPortCore    ),
      //   .NumTilesPerGroup      (NumTilesPerGroup  ),
      //   .AddrWidth             (TCDMAddrWidth     ),
      //   .TileIDWidth           (TileIDWidth       ),
      //   .tcdm_req_t            (tcdm_req_t        ),
      //   .tcdm_rsp_t            (tcdm_rsp_t        ),
      //   .tcdm_req_chan_t       (tcdm_req_chan_t   ),
      //   .tcdm_rsp_chan_t       (tcdm_rsp_chan_t   )
      // ) i_cache_xbar (
      //   .clk_i                ( clk_i                                              ),
      //   .rst_ni               ( rst_ni                                             ),
      //   .tile_id_i            ( tile_id_i                                          ),
      //   .dynamic_offset_i     ( dynamic_offset                                     ),
      //   .private_start_addr_i ( private_start_addr_i                               ),
      //   .num_private_cache_i  ( num_private_cache                                  ),
      //   .core_req_i           ({xbar_remote_group_in_req,     xbar_remote_req_gated,  cache_req        [j]}),
      //   .core_rsp_ready_i     ({xbar_remote_group_in_pready,  xbar_remote_in_pready,  cache_pready     [j]}),
      //   .core_rsp_o           ({xbar_remote_group_in_rsp,     xbar_remote_rsp_xbar,   cache_rsp        [j]}),
      //   .tile_sel_o           ( xbar_remote_req_dst                                                        ),
      //   .remote_group_sel_o   ( xbar_remote_group_out_dst                                                  ),
      //   .mem_req_o            ({xbar_remote_group_out_req,    xbar_remote_req_o,      cache_xbar_req   [j]}),
      //   .mem_rsp_ready_o      ({xbar_remote_group_out_pready, xbar_remote_out_pready, cache_xbar_pready[j]}),
      //   .mem_rsp_i            ({xbar_remote_group_out_rsp,    xbar_remote_rsp_i,      cache_xbar_rsp   [j]})
      // );

      // [LP1] New collapsed, cacheline-wide interco for the single L2 plane.
      // Core side  : the NumL1CtrlTile per-core private-L1 downstreams
      //              (lp1_l1_req_unique), already coalesced & id-tagged.
      // Mem side   : one cacheline port per L2 controller (cache_xbar_*), no
      //              plane index (NumL2Plane = 1).
      // Routing math is identical to before (width-agnostic, Option A); only the
      // data/strb width and the port multiplicity change.
      tcdm_cache_interco #(
        .NumTiles              (NumTiles                  ),
        .NumCores              (NrCores                   ),
        .NumCache              (NumL1CtrlTile             ),
        .NumTotCache           (NumL1CacheCtrl            ),
        .NumRemotePort         (NumRemotePortCore         ),
        .NumRemoteGroupPort    (NumRemoteGroupPortCore    ),
        .NumTilesPerGroup      (NumTilesPerGroup          ),
        .AddrWidth             (TCDMAddrWidth             ),
        .TileIDWidth           (TileIDWidth               ),
        .tcdm_req_t            (tcdm_cacheline_req_t      ),
        .tcdm_rsp_t            (tcdm_cacheline_rsp_t      ),
        .tcdm_req_chan_t       (tcdm_cacheline_req_chan_t ),
        .tcdm_rsp_chan_t       (tcdm_cacheline_rsp_chan_t )
      ) i_cache_xbar (
        .clk_i                ( clk_i                                                                  ),
        .rst_ni               ( rst_ni                                                                 ),
        .tile_id_i            ( tile_id_i                                                              ),
        .dynamic_offset_i     ( dynamic_offset                                                         ),
        .private_start_addr_i ( private_start_addr_i                                                   ),
        .num_private_cache_i  ( num_private_cache                                                      ),
        .core_req_i           ({xbar_remote_group_in_req,     xbar_remote_req_gated,  lp1_l1_req_unique}),
        .core_rsp_ready_i     ({xbar_remote_group_in_pready,  xbar_remote_in_pready,  lp1_l1_rsp_ready }),
        .core_rsp_o           ({xbar_remote_group_in_rsp,     xbar_remote_rsp_xbar,   lp1_l1_rsp       }),
        .tile_sel_o           ( xbar_remote_req_dst                                                    ),
        .remote_group_sel_o   ( xbar_remote_group_out_dst                                              ),
        .mem_req_o            ({xbar_remote_group_out_req,    xbar_remote_req_o,      cache_xbar_req   }),
        .mem_rsp_ready_o      ({xbar_remote_group_out_pready, xbar_remote_out_pready, cache_xbar_pready}),
        .mem_rsp_i            ({xbar_remote_group_out_rsp,    xbar_remote_rsp_i,      cache_xbar_rsp   })
      );
    end else begin : gen_no_remote_group
      // No inter-group remote ports: instantiate interco without inter-group remote ports (backward-compatible).
      // [LP1] Collapsed, cacheline-wide variant. Old narrow/5-plane instance below.
      // tcdm_cache_interco #(
      //   .NumTiles              (NumTiles          ),
      //   .NumCores              (NrCores           ),
      //   .NumCache              (NumL1CtrlTile     ),
      //   .NumTotCache           (NumL1CacheCtrl    ),
      //   .NumRemotePort         (NumRemotePortCore ),
      //   .AddrWidth             (TCDMAddrWidth     ),
      //   .TileIDWidth           (TileIDWidth       ),
      //   .tcdm_req_t            (tcdm_req_t        ),
      //   .tcdm_rsp_t            (tcdm_rsp_t        ),
      //   .tcdm_req_chan_t       (tcdm_req_chan_t   ),
      //   .tcdm_rsp_chan_t       (tcdm_rsp_chan_t   )
      // ) i_cache_xbar (
      //   .clk_i                ( clk_i                                         ),
      //   .rst_ni               ( rst_ni                                        ),
      //   .tile_id_i            ( tile_id_i                                     ),
      //   .dynamic_offset_i     ( dynamic_offset                                ),
      //   .private_start_addr_i ( private_start_addr_i                          ),
      //   .num_private_cache_i  ( num_private_cache                             ),
      //   .core_req_i           ({xbar_remote_req_gated,  cache_req        [j]} ),
      //   .core_rsp_ready_i     ({xbar_remote_in_pready,  cache_pready     [j]} ),
      //   .core_rsp_o           ({xbar_remote_rsp_xbar,   cache_rsp        [j]} ),
      //   .tile_sel_o           ( xbar_remote_req_dst                           ),
      //   .remote_group_sel_o   (                                               ),
      //   .mem_req_o            ({xbar_remote_req_o,       cache_xbar_req   [j]}),
      //   .mem_rsp_ready_o      ({xbar_remote_out_pready,  cache_xbar_pready[j]}),
      //   .mem_rsp_i            ({xbar_remote_rsp_i,       cache_xbar_rsp   [j]})
      // );
      tcdm_cache_interco #(
        .NumTiles              (NumTiles                  ),
        .NumCores              (NrCores                   ),
        .NumCache              (NumL1CtrlTile             ),
        .NumTotCache           (NumL1CacheCtrl            ),
        .NumRemotePort         (NumRemotePortCore         ),
        .AddrWidth             (TCDMAddrWidth             ),
        .TileIDWidth           (TileIDWidth               ),
        .tcdm_req_t            (tcdm_cacheline_req_t      ),
        .tcdm_rsp_t            (tcdm_cacheline_rsp_t      ),
        .tcdm_req_chan_t       (tcdm_cacheline_req_chan_t ),
        .tcdm_rsp_chan_t       (tcdm_cacheline_rsp_chan_t )
      ) i_cache_xbar (
        .clk_i                ( clk_i                                            ),
        .rst_ni               ( rst_ni                                           ),
        .tile_id_i            ( tile_id_i                                        ),
        .dynamic_offset_i     ( dynamic_offset                                   ),
        .private_start_addr_i ( private_start_addr_i                             ),
        .num_private_cache_i  ( num_private_cache                                ),
        .core_req_i           ({xbar_remote_req_gated,  lp1_l1_req_unique}       ),
        .core_rsp_ready_i     ({xbar_remote_in_pready,  lp1_l1_rsp_ready }       ),
        .core_rsp_o           ({xbar_remote_rsp_xbar,   lp1_l1_rsp       }       ),
        .tile_sel_o           ( xbar_remote_req_dst                              ),
        .remote_group_sel_o   (                                                  ),
        .mem_req_o            ({xbar_remote_req_o,       cache_xbar_req   }       ),
        .mem_rsp_ready_o      ({xbar_remote_out_pready,  cache_xbar_pready}       ),
        .mem_rsp_i            ({xbar_remote_rsp_i,       cache_xbar_rsp   }       )
      );
    end
  end

  for (genvar cb = 0; cb < NumL1CtrlTile; cb++) begin : gen_cache_connect
    // Only Snitch will send out amo requests
    // Ports from Spatz can bypass this module

    // [LP1] OLD per-plane AMO + spill structure. Superseded by the single
    // cacheline-wide spill path below: the private L1 already coalesced the
    // Spatz lanes and handles AMOs (phase 1), so there is one cacheline port per
    // L2 controller and the L2-side spatz_cache_amo is bypassed. Kept for ref.
    /*
    for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin : gen_cache_amo_connect
      if (j == NrTCDMPortsPerCore-1) begin : gen_amo
        spatz_cache_amo #(
          .DataWidth        ( DataWidth        ),
          .CoreIDWidth      ( CoreIDWidth      ),
          .tcdm_req_t       ( tcdm_req_t       ),
          .tcdm_rsp_t       ( tcdm_rsp_t       ),
          .tcdm_req_chan_t  ( tcdm_req_chan_t  ),
          .tcdm_rsp_chan_t  ( tcdm_rsp_chan_t  ),
          .tcdm_user_t      ( tcdm_user_t      )
        ) i_cache_amo (
          .clk_i            (clk_i                    ),
          .rst_ni           (rst_ni                   ),
          .core_req_i       (cache_ctrl_req   [j][cb] ),
          .core_rsp_ready_i (cache_xbar_pready[j][cb] ),
          .core_rsp_o       (cache_bank_rsp   [j][cb] ),
          .mem_req_o        (cache_amo_req    [cb]    ),
          .mem_rsp_ready_o  (cache_amo_pready [cb]    ),
          .mem_rsp_i        (cache_amo_rsp    [cb]    )
        );

        tcdm_req_t cache_req_reg;
        tcdm_rsp_t cache_rsp_reg;

        spill_register #(
          .T      ( tcdm_req_chan_t ),
          .Bypass ( 1'b0            )
        ) i_spill_reg_cache_req (
          .clk_i                                   ,
          .rst_ni  ( rst_ni                       ),
          .valid_i ( cache_amo_req[cb].q_valid    ),
          .ready_o ( cache_amo_rsp[cb].q_ready    ),
          .data_i  ( cache_amo_req[cb].q          ),
          .valid_o ( cache_req_reg.q_valid        ),
          .ready_i ( cache_rsp_reg.q_ready        ),
          .data_o  ( cache_req_reg.q              )
        );

        spill_register #(
          .T      ( tcdm_rsp_chan_t ),
          .Bypass ( 1'b1            )
        ) i_spill_reg_cache_rsp (
          .clk_i   ( clk_i                       ),
          .rst_ni  ( rst_ni                      ),
          .valid_i ( cache_rsp_reg.p_valid       ),
          .ready_o ( cache_rsp_ready [cb][j]     ),
          .data_i  ( cache_rsp_reg.p             ),
          .valid_o ( cache_amo_rsp   [cb].p_valid),
          .ready_i ( cache_amo_pready[cb]        ),
          .data_o  ( cache_amo_rsp   [cb].p      )
        );

        assign cache_req_valid[cb][j] = cache_req_reg.q_valid;
        assign cache_req_addr [cb][j] = cache_req_reg.q.addr;
        assign cache_req_meta [cb][j] = cache_req_reg.q.user;
        assign cache_req_write[cb][j] = cache_req_reg.q.write;
        assign cache_req_data [cb][j] = cache_req_reg.q.data;
        assign cache_req_strb [cb][j] = cache_req_reg.q.strb;

        assign cache_rsp_reg.p_valid = cache_rsp_valid[cb][j];
        assign cache_rsp_reg.q_ready = cache_req_ready[cb][j];
        assign cache_rsp_reg.p.data  = cache_rsp_data [cb][j];
        assign cache_rsp_reg.p.user  = cache_rsp_meta [cb][j];

        assign cache_rsp_reg.p.write = cache_rsp_write[cb][j];

      end else begin : gen_no_amo
        // Spill registers to cut the L1 xbar → coalescer critical path,
        // matching the timing budget of the Snitch AMO path above.
        tcdm_req_t cache_req_reg;
        tcdm_rsp_t cache_rsp_reg;

        spill_register #(
          .T      ( tcdm_req_chan_t ),
          .Bypass ( 1'b0            )
        ) i_spill_reg_cache_req (
          .clk_i                                         ,
          .rst_ni  ( rst_ni                             ),
          .valid_i ( cache_ctrl_req[j][cb].q_valid      ),
          .ready_o ( cache_bank_rsp[j][cb].q_ready      ),
          .data_i  ( cache_ctrl_req[j][cb].q            ),
          .valid_o ( cache_req_reg.q_valid              ),
          .ready_i ( cache_rsp_reg.q_ready              ),
          .data_o  ( cache_req_reg.q                    )
        );

        spill_register #(
          .T      ( tcdm_rsp_chan_t ),
          .Bypass ( 1'b1            )
        ) i_spill_reg_cache_rsp (
          .clk_i   ( clk_i                             ),
          .rst_ni  ( rst_ni                            ),
          .valid_i ( cache_rsp_reg.p_valid             ),
          .ready_o ( cache_rsp_ready[cb][j]            ),
          .data_i  ( cache_rsp_reg.p                   ),
          .valid_o ( cache_bank_rsp[j][cb].p_valid     ),
          .ready_i ( cache_xbar_pready[j][cb]          ),
          .data_o  ( cache_bank_rsp[j][cb].p           )
        );

        assign cache_req_valid[cb][j] = cache_req_reg.q_valid;
        assign cache_req_addr [cb][j] = cache_req_reg.q.addr;
        assign cache_req_meta [cb][j] = cache_req_reg.q.user;
        assign cache_req_write[cb][j] = cache_req_reg.q.write;
        assign cache_req_data [cb][j] = cache_req_reg.q.data;
        assign cache_req_strb [cb][j] = cache_req_reg.q.strb;

        assign cache_rsp_reg.p_valid = cache_rsp_valid[cb][j];
        assign cache_rsp_reg.q_ready = cache_req_ready[cb][j];
        assign cache_rsp_reg.p.data  = cache_rsp_data [cb][j];
        assign cache_rsp_reg.p.user  = cache_rsp_meta [cb][j];
        assign cache_rsp_reg.p.write = cache_rsp_write[cb][j];

      end
    end
    */

    // [LP1] Single cacheline port per L2 controller. A spill register cuts the
    // interco -> bank critical path (matching the old timing budget). AMOs are
    // serviced upstream in the private L1, so spatz_cache_amo is bypassed here.
    tcdm_cacheline_req_t cache_req_reg;
    tcdm_cacheline_rsp_t cache_rsp_reg;

    spill_register #(
      .T      ( tcdm_cacheline_req_chan_t ),
      .Bypass ( 1'b0                      )
    ) i_spill_reg_cache_req (
      .clk_i                                     ,
      .rst_ni  ( rst_ni                         ),
      .valid_i ( cache_ctrl_req[cb].q_valid     ),
      .ready_o ( cache_bank_rsp[cb].q_ready     ),
      .data_i  ( cache_ctrl_req[cb].q           ),
      .valid_o ( cache_req_reg.q_valid          ),
      .ready_i ( cache_rsp_reg.q_ready          ),
      .data_o  ( cache_req_reg.q                )
    );

    spill_register #(
      .T      ( tcdm_cacheline_rsp_chan_t ),
      .Bypass ( 1'b1                      )
    ) i_spill_reg_cache_rsp (
      .clk_i   ( clk_i                       ),
      .rst_ni  ( rst_ni                      ),
      .valid_i ( cache_rsp_reg.p_valid       ),
      .ready_o ( cache_rsp_ready  [cb]       ),
      .data_i  ( cache_rsp_reg.p             ),
      .valid_o ( cache_bank_rsp   [cb].p_valid),
      .ready_i ( cache_xbar_pready[cb]       ),
      .data_o  ( cache_bank_rsp   [cb].p     )
    );

    assign cache_req_valid[cb] = cache_req_reg.q_valid;
    assign cache_req_addr [cb] = cache_req_reg.q.addr;
    assign cache_req_meta [cb] = cache_req_reg.q.user;
    assign cache_req_write[cb] = cache_req_reg.q.write;
    assign cache_req_data [cb] = cache_req_reg.q.data;
    assign cache_req_strb [cb] = cache_req_reg.q.strb;

    assign cache_rsp_reg.p_valid = cache_rsp_valid[cb];
    assign cache_rsp_reg.q_ready = cache_req_ready[cb];
    assign cache_rsp_reg.p.data  = cache_rsp_data [cb];
    assign cache_rsp_reg.p.user  = cache_rsp_meta [cb];
    assign cache_rsp_reg.p.write = cache_rsp_write[cb];
  end

  // Post-xbar flush gate (applied uniformly across all ports).
  // Suppresses q_valid going into the bank so no new cache accesses are processed
  // while a flush is in progress, and gates q_ready going back to the interco so the
  // xbar cannot dequeue a buffered request that is already sitting at its output.
  always_comb begin : cache_xbar_flush_gate
    // [LP1] One cacheline port per L2 controller (the NrTCDMPortsPerCore plane
    // dimension is gone).
    for (int cb = 0; cb < NumL1CtrlTile; cb++) begin
      cache_ctrl_req[cb]         = cache_xbar_req[cb];
      cache_ctrl_req[cb].q_valid = cache_xbar_req[cb].q_valid && !l1d_busy_i;
      cache_xbar_rsp[cb]         = cache_bank_rsp[cb];
      cache_xbar_rsp[cb].q_ready = cache_bank_rsp[cb].q_ready && !l1d_busy_i;
    end
  end

  // Refill address inverse rotation parameters.
  // Must mirror the bits_to_rotate table in tcdm_cache_interco gen_scramble:
  //   All-private or half-half private banks (cb < NumL1CtrlTile/2):
  //     N = CacheBankBits
  //   All-shared  or half-half shared  banks (cb >= NumL1CtrlTile/2):
  //     N = CacheBankBits + TileBits
  localparam int unsigned RefillCacheBankBits = $clog2(NumL1CtrlTile);
  localparam int unsigned RefillTileBits      = $clog2(NumL1CacheCtrl / NumL1CtrlTile);
  localparam int unsigned RefillRotWidth      = $clog2(RefillCacheBankBits + RefillTileBits + 1) + 1;

  localparam NumWordPerLine = L1LineWidth / DataWidth;
  localparam int unsigned WordBytes = DataWidth / 8;
`ifndef TARGET_SYNTHESIS
  initial begin
    $display("Cache Configuration:");
    $display("  NumCtrl        : %0d", NumL1CtrlTile);
    $display("  LineWidth      : %0d", L1LineWidth);
    $display("  NumWordPerLine : %0d", NumWordPerLine);
    $display("  NumSet         : %0d", L1NumSet);
    $display("  AssoPerCtrl    : %0d", L1AssoPerCtrl);
    $display("  BankFactor     : %0d", L1BankFactor);
    $display("  NumTagBankPerCtrl : %0d", NumTagBankPerCtrl);
    $display("  NumDataBankPerCtrl: %0d", NumDataBankPerCtrl);
    $display("  CoalFactor     : %0d", L1CoalFactor);
    $display("  RefillDataWidth: %0d", RefillDataWidth);
    $display("  DynamicOffset  : %0d", dynamic_offset);
  end
`endif

  // CL-offset mask: bits below dynamic_offset, verbatim in both directions.
  logic [SpatzAxiAddrWidth-1:0] bitmask_lo;
  assign bitmask_lo = (SpatzAxiAddrWidth'(1) << dynamic_offset) - 1;

  cache_refill_req_chan_t [NumL1CtrlTile-1 : 0] cache_refill_req;
  burst_req_t             [NumL1CtrlTile-1 : 0] cache_refill_burst;
  logic                   [NumL1CtrlTile-1 : 0] cache_refill_req_valid, cache_refill_req_ready;
  cache_refill_rsp_chan_t [NumL1CtrlTile-1 : 0] cache_refill_rsp;
  logic                   [NumL1CtrlTile-1 : 0] cache_refill_rsp_valid, cache_refill_rsp_ready;

  // -------------------------------------------------------------------------
  // Tile-level flush tracking
  // -------------------------------------------------------------------------
  //
  // flush_pending_q : set when this tile accepts an instruction, cleared when
  //                   all targeted controllers complete (cache_flush_q == 0).
  //                   Prevents accepting a second instruction mid-flush.
  //
  // cache_flush_q[cb] : per-controller pending bit.  Set when ctrl_sync_valid
  //                     is asserted to controller cb; cleared on ctrl_sync_ready.
  //
  // ctrl_sync_valid[cb] : per-controller valid, gated by partition membership.
  // ctrl_sync_insn[cb]  : per-controller insn encoding (translated to 2-bit
  //                       controller encoding: flush->2'b00, init->2'b11).
  // ctrl_sync_ready[cb] : wired back from cache controller.
  //
  // l1d_insn_ready_o : one-cycle pulse to peripheral when flush_pending_q
  //                    is asserted and cache_flush_d has just reached zero.
  //                    Using cache_flush_d (not _q) avoids the one-cycle delay
  //                    that _q would introduce.  No combinational loop exists
  //                    because l1d_insn_ready_o feeds only the peripheral lock
  //                    register, which has no same-cycle path back into the tile.

  // Determine whether this tile should act on the incoming instruction.
  // Private flush (insn==00): only if our tile_id bit is set in tile_sel.
  // All other modes: always act.
  logic tile_insn_active;
  always_comb begin : gen_tile_active
    if (l1d_insn_i.insn == 2'b00)
      tile_insn_active = l1d_insn_i.tile_sel[tile_id_i];
    else
      tile_insn_active = 1'b1;
  end

  // Per-controller signals driven by the flush tracking logic.
  logic [NumL1CtrlTile-1:0]       ctrl_sync_valid;
  logic [NumL1CtrlTile-1:0][1:0]  ctrl_sync_insn;
  logic [NumL1CtrlTile-1:0]       ctrl_sync_ready;

  logic [NumL1CtrlTile-1:0]       cache_flush_d, cache_flush_q;
  logic                           flush_pending_d, flush_pending_q;

  // Determine which controllers to activate based on insn partition field.
  //   insn==00 (private) : cb < num_private_cache
  //   insn==01 (shared)  : cb >= num_private_cache
  //   insn==10 or 11     : all controllers
  always_comb begin : gen_ctrl_valid
    for (int cb = 0; cb < NumL1CtrlTile; cb++) begin
      ctrl_sync_valid[cb] = 1'b0;
      ctrl_sync_insn[cb]  = 2'b00; // default: flush encoding for controller

      if (l1d_insn_valid_i && tile_insn_active && !flush_pending_q) begin
        case (l1d_insn_i.insn)
          2'b00: begin // flush private
            ctrl_sync_valid[cb] = (cb < int'(num_private_cache));
          end
          2'b01: begin // flush shared
            ctrl_sync_valid[cb] = (cb >= int'(num_private_cache));
          end
          2'b10: begin // flush all
            ctrl_sync_valid[cb] = 1'b1;
          end
          2'b11: begin // invalidate all
            ctrl_sync_valid[cb] = 1'b1;
            ctrl_sync_insn[cb]  = 2'b11;
          end
          default: ctrl_sync_valid[cb] = 1'b0;
        endcase
      end
    end
  end

  // Flush pending and per-controller tracking (combinational next-state).
  always_comb begin : gen_flush_next
    cache_flush_d   = cache_flush_q;
    flush_pending_d = flush_pending_q;

    // Set bits for controllers being activated this cycle.
    for (int cb = 0; cb < NumL1CtrlTile; cb++) begin
      if (ctrl_sync_valid[cb])
        cache_flush_d[cb] = 1'b1;
      // Clear bit when controller returns ready (one-cycle pulse).
      if (ctrl_sync_ready[cb])
        cache_flush_d[cb] = 1'b0;
    end

    // Raise flush_pending when accepting a new instruction.
    if (l1d_insn_valid_i && tile_insn_active && !flush_pending_q)
      flush_pending_d = 1'b1;

    // Clear flush_pending once all controllers have finished.
    if (flush_pending_q && (cache_flush_d == '0))
      flush_pending_d = 1'b0;
  end

  `FF(cache_flush_q,   cache_flush_d,   '0, clk_i, rst_ni)
  `FF(flush_pending_q, flush_pending_d, '0, clk_i, rst_ni)

  // One-cycle ready pulse to the peripheral when flush completes.
  assign l1d_insn_ready_o = flush_pending_q && (cache_flush_d == '0);

  for (genvar cb = 0; cb < NumL1CtrlTile; cb++) begin: gen_l1_cache_ctrl
    // cachepool_cache_ctrl #(
    //   // Core
    //   .NumPorts         (NrTCDMPortsPerCore ),
    //   .CoalExtFactor    (L1CoalFactor       ),
    //   .AddrWidth        (L1AddrWidth        ),
    //   .WordWidth        (DataWidth          ),
    //   .ByteWidth        (8                  ),
    //   .TagWidth         (L1TagDataWidth     ),
    //   // Cache
    //   .NumCacheEntry    (L1NumEntryPerCtrl  ),
    //   .CacheLineWidth   (L1LineWidth        ),
    //   .SetAssociativity (L1AssoPerCtrl      ),
    //   .BankFactor       (L1BankFactor       ),
    //   // .LogDebug         (0                  ),
    //   .RefillDataWidth  (RefillDataWidth    ),
    //   // Type
    //   .core_meta_t      (tcdm_user_t        ),
    //   .impl_in_t        (impl_in_t          ),
    //   .refill_req_t     (cache_refill_req_chan_t),
    //   .refill_rsp_t     (cache_refill_rsp_chan_t),
    //   .burst_req_t      (burst_req_t        )
    // ) i_l1_controller (
    //   .clk_i                 (clk_i                          ),
    //   .rst_ni                (rst_ni                         ),
    //   .impl_i                ('0                             ),
    //   // Sync Control
    //   .cache_sync_valid_i    (ctrl_sync_valid[cb]            ),
    //   .cache_sync_ready_o    (ctrl_sync_ready[cb]            ),
    //   .cache_sync_insn_i     (ctrl_sync_insn[cb]             ),
    //   // SPM Size
    //   // The calculation of spm region in cache is different
    //   // than other modules (needs to times 2)
    //   // Currently assume full cache
    //   .bank_depth_for_SPM_i  ('0                             ),
    //   // Request
    //   .core_req_valid_i      (cache_req_valid[cb]            ),
    //   .core_req_ready_o      (cache_req_ready[cb]            ),
    //   .core_req_addr_i       (cache_req_addr [cb]            ),
    //   .core_req_meta_i       (cache_req_meta [cb]            ),
    //   .core_req_write_i      (cache_req_write[cb]            ),
    //   .core_req_wdata_i      (cache_req_data [cb]            ),
    //   .core_req_wstrb_i      (cache_req_strb [cb]            ),
    //   // Response
    //   .core_resp_valid_o     (cache_rsp_valid[cb]            ),
    //   .core_resp_ready_i     (cache_rsp_ready[cb]            ),
    //   .core_resp_write_o     (cache_rsp_write[cb]            ),
    //   .core_resp_data_o      (cache_rsp_data [cb]            ),
    //   .core_resp_meta_o      (cache_rsp_meta [cb]            ),
    //   // TCDM Refill
    //   .refill_req_o          (cache_refill_req      [cb]     ),
    //   .refill_burst_o        (cache_refill_burst    [cb]     ),
    //   .refill_req_valid_o    (cache_refill_req_valid[cb]     ),
    //   .refill_req_ready_i    (cache_refill_req_ready[cb]     ),
    //   .refill_rsp_i          (cache_refill_rsp      [cb]     ),
    //   .refill_rsp_valid_i    (cache_refill_rsp_valid[cb]     ),
    //   .refill_rsp_ready_o    (cache_refill_rsp_ready[cb]     ),
    //   // Tag Banks
    //   .tcdm_tag_bank_req_o   (l1_tag_bank_req  [cb]          ),
    //   .tcdm_tag_bank_we_o    (l1_tag_bank_we   [cb]          ),
    //   .tcdm_tag_bank_addr_o  (l1_tag_bank_addr [cb]          ),
    //   .tcdm_tag_bank_wdata_o (l1_tag_bank_wdata[cb]          ),
    //   .tcdm_tag_bank_be_o    (l1_tag_bank_be   [cb]          ),
    //   .tcdm_tag_bank_rdata_i (l1_tag_bank_rdata[cb]          ),
    //   // Data Banks
    //   .tcdm_data_bank_req_o  (l1_data_bank_req  [cb]         ),
    //   .tcdm_data_bank_we_o   (l1_data_bank_we   [cb]         ),
    //   .tcdm_data_bank_addr_o (l1_data_bank_addr [cb]         ),
    //   .tcdm_data_bank_wdata_o(l1_data_bank_wdata[cb]         ),
    //   .tcdm_data_bank_be_o   (l1_data_bank_be   [cb]         ),
    //   .tcdm_data_bank_rdata_i(l1_data_bank_rdata[cb]         ),
    //   .tcdm_data_bank_gnt_i  (l1_data_bank_gnt  [cb]         )
    // );

    // [LP1] New shared-cache (L2) controller: ONE cacheline-wide core port.
    // The private L1 already coalesced the Spatz lanes upstream, so the L2-side
    // coalescer (i_par_coalescer_for_spatz) is removed in the insitu fork and
    // CoalExtFactor collapses to 1, WordWidth widens to the full cache line.
    // The fork's core_req_*/core_resp_* interface must present this single
    // cacheline port (the tile drives the scalar cache_req_*/cache_rsp_* below).
    cachepool_cache_ctrl #(
      // Core
      .NumPorts         (1                  ),
      .CoalExtFactor    (1                  ),
      .AddrWidth        (L1AddrWidth        ),
      .WordWidth        (L1LineWidth        ),
      .ByteWidth        (8                  ),
      .TagWidth         (L1TagDataWidth     ),
      // Cache
      .NumCacheEntry    (L1NumEntryPerCtrl  ),
      .CacheLineWidth   (L1LineWidth        ),
      .SetAssociativity (L1AssoPerCtrl      ),
      .BankFactor       (L1BankFactor       ),
      // .LogDebug         (0                  ),
      .RefillDataWidth  (RefillDataWidth    ),
      // Type
      .core_meta_t      (tcdm_user_t        ),
      .impl_in_t        (impl_in_t          ),
      .refill_req_t     (cache_refill_req_chan_t),
      .refill_rsp_t     (cache_refill_rsp_chan_t),
      .burst_req_t      (burst_req_t        )
    ) i_l1_controller (
      .clk_i                 (clk_i                          ),
      .rst_ni                (rst_ni                         ),
      .impl_i                ('0                             ),
      // Sync Control
      .cache_sync_valid_i    (ctrl_sync_valid[cb]            ),
      .cache_sync_ready_o    (ctrl_sync_ready[cb]            ),
      .cache_sync_insn_i     (ctrl_sync_insn[cb]             ),
      // SPM Size
      // The calculation of spm region in cache is different
      // than other modules (needs to times 2)
      // Currently assume full cache
      .bank_depth_for_SPM_i  ('0                             ),
      // Request (single cacheline port)
      .core_req_valid_i      (cache_req_valid[cb]            ),
      .core_req_ready_o      (cache_req_ready[cb]            ),
      .core_req_addr_i       (cache_req_addr [cb]            ),
      .core_req_meta_i       (cache_req_meta [cb]            ),
      .core_req_write_i      (cache_req_write[cb]            ),
      .core_req_wdata_i      (cache_req_data [cb]            ),
      .core_req_wstrb_i      (cache_req_strb [cb]            ),
      // Response
      .core_resp_valid_o     (cache_rsp_valid[cb]            ),
      .core_resp_ready_i     (cache_rsp_ready[cb]            ),
      .core_resp_write_o     (cache_rsp_write[cb]            ),
      .core_resp_data_o      (cache_rsp_data [cb]            ),
      .core_resp_meta_o      (cache_rsp_meta [cb]            ),
      // TCDM Refill
      .refill_req_o          (cache_refill_req      [cb]     ),
      .refill_burst_o        (cache_refill_burst    [cb]     ),
      .refill_req_valid_o    (cache_refill_req_valid[cb]     ),
      .refill_req_ready_i    (cache_refill_req_ready[cb]     ),
      .refill_rsp_i          (cache_refill_rsp      [cb]     ),
      .refill_rsp_valid_i    (cache_refill_rsp_valid[cb]     ),
      .refill_rsp_ready_o    (cache_refill_rsp_ready[cb]     ),
      // Tag Banks
      .tcdm_tag_bank_req_o   (l1_tag_bank_req  [cb]          ),
      .tcdm_tag_bank_we_o    (l1_tag_bank_we   [cb]          ),
      .tcdm_tag_bank_addr_o  (l1_tag_bank_addr [cb]          ),
      .tcdm_tag_bank_wdata_o (l1_tag_bank_wdata[cb]          ),
      .tcdm_tag_bank_be_o    (l1_tag_bank_be   [cb]          ),
      .tcdm_tag_bank_rdata_i (l1_tag_bank_rdata[cb]          ),
      // Data Banks
      .tcdm_data_bank_req_o  (l1_data_bank_req  [cb]         ),
      .tcdm_data_bank_we_o   (l1_data_bank_we   [cb]         ),
      .tcdm_data_bank_addr_o (l1_data_bank_addr [cb]         ),
      .tcdm_data_bank_wdata_o(l1_data_bank_wdata[cb]         ),
      .tcdm_data_bank_be_o   (l1_data_bank_be   [cb]         ),
      .tcdm_data_bank_rdata_i(l1_data_bank_rdata[cb]         ),
      .tcdm_data_bank_gnt_i  (l1_data_bank_gnt  [cb]         )
    );

    // Inverse rotation for the refill address.
    //
    // The cache controller stores a *rotated* address: routing bits (BankSel
    // and, for shared banks, TileID) were moved to the MSB by the forward
    // rotation in tcdm_cache_interco so the cache sees a dense index space.
    // Before issuing the refill to the NoC we must undo that rotation to
    // recover the original address.
    //
    // Forward rotation recap (N = bits_to_rotate):
    //   rotated = lower | (upper << offset) | (rot_field << (AddrWidth - N))
    //
    // Inverse:
    //   lower     = addr_rot & ((1 << offset) - 1)   // CL offset, verbatim
    //   rot_field = addr_rot >> (AddrWidth - N)       // routing bits at top
    //   upper     = (addr_rot >> offset)              // tag+index (no top bits)
    //             & ((1 << (AddrWidth-offset-N)) - 1)
    //   original  = lower | (rot_field << offset) | (upper << (offset + N))
    //
    // N per bank mirrors tcdm_cache_interco gen_scramble:
    //   Private banks (cb < num_private_cache):
    //     N = RefillCacheBankBits
    //   Shared banks (cb >= num_private_cache):
    //     N = RefillCacheBankBits + RefillTileBits
    //
    // cb is a genvar constant → static per-bank elaboration, but the
    // boundary (num_private_cache) is a registered runtime signal.

    logic [RefillRotWidth-1:0] refill_bits_to_rotate;

    always_comb begin : refill_rot_sel
      if (num_private_cache == '0) begin
        // All-shared: every bank is shared.
        refill_bits_to_rotate = RefillRotWidth'(RefillCacheBankBits + RefillTileBits);
      end else if (num_private_cache == 3'(NumL1CtrlTile)) begin
        // All-private: every bank is private.
        refill_bits_to_rotate = RefillRotWidth'(RefillCacheBankBits);
      end else begin
        // Mixed: use num_private_cache boundary, mirroring gen_scramble in
        // tcdm_cache_interco.  Banks [0..num_private_cache-1] are private,
        // banks [num_private_cache..NumL1CtrlTile-1] are shared.
        if (cb < int'(num_private_cache))
          refill_bits_to_rotate = RefillRotWidth'(RefillCacheBankBits);
        else
          refill_bits_to_rotate = RefillRotWidth'(RefillCacheBankBits + RefillTileBits);
      end
    end

    always_comb begin : bank_addr_scramble
      cache_refill_req_o[cb].q = '{
        addr : cache_refill_req[cb].addr,
        write: cache_refill_req[cb].write,
        data : cache_refill_req[cb].wdata,
        strb : cache_refill_req[cb].wstrb,
        size : $clog2(RefillDataWidth/8),
        amo  : reqrsp_pkg::AMONone,
        default : '0
      };

      // ID 0 reserved for bypass cache
      cache_refill_req_o[cb].q.user = '{
        // The first bit is reserved for iCache identifier
        bank_id : cb + 1,
        info    : cache_refill_req[cb].info,
        burst   : cache_refill_burst[cb],
        default : '0
      };
      cache_refill_req_o[cb].q_valid = cache_refill_req_valid[cb];
      cache_refill_req_o[cb].p_ready = cache_refill_rsp_ready[cb];

      cache_refill_rsp[cb] = '{
        data  : cache_refill_rsp_i[cb].p.data,
        write : cache_refill_rsp_i[cb].p.write,
        info  : cache_refill_rsp_i[cb].p.user.info,
        default   :'0
      };
      cache_refill_rsp_valid[cb] = cache_refill_rsp_i[cb].p_valid;
      cache_refill_req_ready[cb] = cache_refill_rsp_i[cb].q_ready;

      // Inverse rotation: recover original address from the rotated form.
      begin
        logic [SpatzAxiAddrWidth-1:0] addr_rot, lower, rot_field, upper;
        addr_rot  = cache_refill_req[cb].addr;

        lower     = addr_rot & bitmask_lo;

        rot_field = addr_rot >> (SpatzAxiAddrWidth - refill_bits_to_rotate);

        upper     = (addr_rot >> dynamic_offset)
                  & ((SpatzAxiAddrWidth'(1) << (SpatzAxiAddrWidth
                                                - dynamic_offset
                                                - refill_bits_to_rotate)) - 1);

        cache_refill_req_o[cb].q.addr = lower
                                      | (rot_field << dynamic_offset)
                                      | (upper     << (dynamic_offset
                                                       + refill_bits_to_rotate));
      end
    end

    for (genvar j = 0; j < NumTagBankPerCtrl; j++) begin
      tc_sram_impl #(
        .NumWords  (L1CacheWayEntry/L1BankFactor),
        .DataWidth ($bits(tag_data_t)           ),
        .ByteWidth ($bits(tag_data_t)           ),
        .NumPorts  (1                           ),
        .Latency   (1                           ),
        .SimInit   ("zeros"                     ),
        .impl_in_t (impl_in_t                   )
      ) i_meta_bank (
        .clk_i  (clk_i                   ),
        .rst_ni (rst_ni                  ),
        .impl_i ('0                      ),
        .impl_o (/* unused */             ),
        .req_i  (l1_tag_bank_req  [cb][j]),
        .we_i   (l1_tag_bank_we   [cb][j]),
        .addr_i (l1_tag_bank_addr [cb][j]),
        .wdata_i(l1_tag_bank_wdata[cb][j]),
        .be_i   (l1_tag_bank_be   [cb][j]),
        .rdata_o(l1_tag_bank_rdata[cb][j])
      );
    end

    // [LP1] Cacheline-granular: each bank is directly one cacheline-wide SRAM
    // (NumDataBankPerCtrl == SetAssoc*BankFactor now), matching the L2 ctrl's
    // per-bank cacheline ports. The old NumWordPerLine grouping (which packed
    // narrow per-word entries into a cacheline SRAM) is no longer needed.
    for (genvar bank = 0; bank < NumDataBankPerCtrl; bank++) begin : gen_l1_data_banks
      tc_sram_impl #(
        .NumWords   (L1CacheWayEntry/L1BankFactor),
        .DataWidth  (L1LineWidth),
        .ByteWidth  (8          ),
        .NumPorts   (1          ),
        .Latency    (1          ),
        .SimInit    ("zeros"    )
      ) i_data_bank (
        .clk_i  (clk_i                       ),
        .rst_ni (rst_ni                      ),
        .impl_i ('0                          ),
        .impl_o (/* unused */                 ),
        .req_i  ( l1_data_bank_req  [cb][bank]  ),
        .we_i   ( l1_data_bank_we   [cb][bank]  ),
        .addr_i ( l1_data_bank_addr [cb][bank]  ),
        .wdata_i( l1_data_bank_wdata[cb][bank]  ),  // full cache line
        .be_i   ( l1_data_bank_be   [cb][bank]  ),  // cacheline byte-mask
        .rdata_o( l1_data_bank_rdata[cb][bank]  )
      );

      assign l1_data_bank_gnt[cb][bank] = 1'b1;
    end

    // TODO: Should we use a single large bank or multiple narrow ones?
    // for (genvar bank = 0; bank < (NumDataBankPerCtrl/NumWordPerLine);
    //      bank++) begin : gen_l1_data_banks
    //   localparam int unsigned BaseIdx = bank * NumWordPerLine;
    //   logic [NumWordPerLine*WordBytes-1:0] bank_be;

    //   for (genvar w = 0; w < NumWordPerLine; w++) begin : gen_bank_be
    //     assign bank_be[w*WordBytes +: WordBytes] = l1_data_bank_be[cb][BaseIdx + w];
    //   end

    //   tc_sram_impl #(
    //     .NumWords   (L1CacheWayEntry/L1BankFactor),
    //     .DataWidth  (L1LineWidth),
    //     .ByteWidth  (8          ),
    //     .NumPorts   (1          ),
    //     .Latency    (1          ),
    //     .SimInit    ("zeros"    )
    //   ) i_data_bank (
    //     .clk_i  (clk_i                       ),
    //     .rst_ni (rst_ni                      ),
    //     .impl_i ('0                          ),
    //     .impl_o (/* unused */                 ),
    //     .req_i  ( l1_data_bank_req  [cb][BaseIdx]  ),
    //     .we_i   ( l1_data_bank_we   [cb][BaseIdx]  ),
    //     .addr_i ( l1_data_bank_addr [cb][BaseIdx]  ),
    //     .wdata_i( l1_data_bank_wdata[cb][BaseIdx+:NumWordPerLine]),
    //     .be_i   ( bank_be ),
    //     .rdata_o( l1_data_bank_rdata[cb][BaseIdx+:NumWordPerLine])
    //   );

    //   assign l1_data_bank_gnt[cb][BaseIdx+:NumWordPerLine] = {NumWordPerLine{1'b1}};
    // end

    // for (genvar j = 0; j < NumDataBankPerCtrl; j++) begin : gen_l1_data_banks
    //   tc_sram_impl #(
    //     .NumWords   (L1CacheWayEntry/L1BankFactor),
    //     .DataWidth  (DataWidth),
    //     .ByteWidth  (DataWidth),
    //     .NumPorts   (1),
    //     .Latency    (1),
    //     .SimInit    ("zeros")
    //   ) i_data_bank (
    //     .clk_i  (clk_i                    ),
    //     .rst_ni (rst_ni                   ),
    //     .impl_i ('0                       ),
    //     .impl_o (/* unused */              ),
    //     .req_i  (l1_data_bank_req  [cb][j]),
    //     .we_i   (l1_data_bank_we   [cb][j]),
    //     .addr_i (l1_data_bank_addr [cb][j]),
    //     .wdata_i(l1_data_bank_wdata[cb][j]),
    //     .be_i   (l1_data_bank_be   [cb][j]),
    //     .rdata_o(l1_data_bank_rdata[cb][j])
    //   );

    //   assign l1_data_bank_gnt[cb][j] = 1'b1;
    // end
  end

  hive_req_t [NrCores-1:0] hive_req;
  hive_rsp_t [NrCores-1:0] hive_rsp;

  for (genvar i = 0; i < NrCores; i++) begin : gen_core
    localparam int unsigned TcdmPorts     = get_tcdm_ports(i);
    localparam int unsigned TcdmPortsOffs = get_tcdm_port_offs(i);

    interrupts_t irq;

    sync #(.STAGES (2))
    i_sync_debug (.clk_i, .rst_ni, .serial_i (debug_req_i), .serial_o (irq.debug));
    sync #(.STAGES (2))
    i_sync_meip (.clk_i, .rst_ni, .serial_i (meip_i), .serial_o (irq.meip));
    sync #(.STAGES (2))
    i_sync_mtip (.clk_i, .rst_ni, .serial_i (mtip_i), .serial_o (irq.mtip));
    sync #(.STAGES (2))
    i_sync_msip (.clk_i, .rst_ni, .serial_i (msip_i), .serial_o (irq.msip));
    assign irq.mcip = cl_interrupt_i[i];

    tcdm_req_t [TcdmPorts-1:0] tcdm_req_wo_user;

    logic [31:0] hart_id;
    assign hart_id = hart_base_id_i + i;

    cachepool_cc #(
      .BootAddr                (BootAddr                   ),
      .UartAddr                (UartAddr                   ),
      .RVE                     (1'b0                       ),
      .RVF                     (RVF                        ),
      .RVD                     (RVD                        ),
      .RVV                     (RVV                        ),
      .AddrWidth               (AxiAddrWidth               ),
      .DataWidth               (NarrowDataWidth            ),
      .UserWidth               (AxiUserWidth               ),
      .SnitchPMACfg            (SnitchPMACfg               ),
      .dreq_t                  (reqrsp_req_t               ),
      .drsp_t                  (reqrsp_rsp_t               ),
      .dreq_chan_t             (reqrsp_req_chan_t          ),
      .drsp_chan_t             (reqrsp_rsp_chan_t          ),
      .tcdm_req_t              (tcdm_req_t                 ),
      .tcdm_user_t             (tcdm_user_t                ),
      .tcdm_req_chan_t         (tcdm_req_chan_t            ),
      .tcdm_rsp_t              (tcdm_rsp_t                 ),
      .tcdm_rsp_chan_t         (tcdm_rsp_chan_t            ),
      .axi_req_t               (axi_mst_tile_wide_req_t    ),
      .axi_ar_chan_t           (axi_mst_tile_wide_ar_chan_t),
      .axi_aw_chan_t           (axi_mst_tile_wide_aw_chan_t),
      .axi_rsp_t               (axi_mst_tile_wide_resp_t   ),
      .hive_req_t              (hive_req_t                 ),
      .hive_rsp_t              (hive_rsp_t                 ),
      .acc_issue_req_t         (acc_issue_req_t            ),
      .acc_issue_rsp_t         (acc_issue_rsp_t            ),
      .acc_rsp_t               (acc_rsp_t                  ),
      .XDivSqrt                (1'b0                       ),
      .XF16                    (1'b1                       ),
      .XF16ALT                 (1'b0                       ),
      .XF8                     (1'b1                       ),
      .XF8ALT                  (1'b0                       ),
      .IsoCrossing             (1'b0                       ),
      .NumIntOutstandingLoads  (NumIntOutstandingLoads     ),
      .NumIntOutstandingMem    (NumIntOutstandingMem       ),
      .NumSpatzOutstandingLoads(NumSpatzOutstandingLoads   ),
      .FPUImplementation       (FPUImplementation          ),
      .SpmStackDepth           (SpmStackDepth              ),
      .RegisterOffloadRsp      (RegisterOffloadRsp         ),
      .RegisterCoreReq         (RegisterCoreReq            ),
      .RegisterCoreRsp         (RegisterCoreRsp            ),
      .NumSpatzFPUs            (NumSpatzFPUs               ),
      .NumSpatzIPUs            (NumSpatzIPUs               ),
      .TCDMAddrWidth           (SPMAddrWidth               )
    ) i_cachepool_cc (
      .clk_i            (clk_i                               ),
      .rst_ni           (rst_ni                              ),
      .testmode_i       (1'b0                                ),
      .hart_id_i        (hart_id                             ),
      .hive_req_o       (hive_req[i]                         ),
      .hive_rsp_i       (hive_rsp[i]                         ),
      .irq_i            (irq                                 ),
      .data_req_o       (core_req[i]                         ),
      .data_rsp_i       (core_rsp[i]                         ),
      .tcdm_req_o       (tcdm_req_wo_user                    ),
      .tcdm_rsp_i       (tcdm_rsp[TcdmPortsOffs +: TcdmPorts]),
      .core_events_o    (core_events[i]                      ),
      .tcdm_addr_base_i (tcdm_start_address                  )
    );
    for (genvar j = 0; j < TcdmPorts; j++) begin : gen_tcdm_user
      always_comb begin
        tcdm_req[TcdmPortsOffs+j].q              = tcdm_req_wo_user[j].q;
        tcdm_req[TcdmPortsOffs+j].q.user.core_id = i[CoreIDWidth-1:0];
        tcdm_req[TcdmPortsOffs+j].q_valid        = tcdm_req_wo_user[j].q_valid;
      end
    end
  end

  // ----------------
  // Instruction Cache
  // ----------------

  addr_t [NrCores-1:0]       inst_addr;
  logic  [NrCores-1:0]       inst_cacheable;
  logic  [NrCores-1:0][31:0] inst_data;
  logic  [NrCores-1:0]       inst_valid;
  logic  [NrCores-1:0]       inst_ready;
  logic  [NrCores-1:0]       inst_error;
  logic  [NrCores-1:0]       flush_valid;
  logic  [NrCores-1:0]       flush_ready;

  for (genvar i = 0; i < NrCores; i++) begin : gen_unpack_icache
    assign inst_addr[i]      = hive_req[i].inst_addr;
    assign inst_cacheable[i] = hive_req[i].inst_cacheable;
    assign inst_valid[i]     = hive_req[i].inst_valid;
    assign flush_valid[i]    = hive_req[i].flush_i_valid;
    assign hive_rsp[i]       = '{
      inst_data    : inst_data[i],
      inst_ready   : inst_ready[i],
      inst_error   : inst_error[i],
      flush_i_ready: flush_ready[i],
      default      : '0
    };
  end

  snitch_icache #(
    .NR_FETCH_PORTS     ( NrCores                                            ),
    .L0_LINE_COUNT      ( 8                                                  ),
    .LINE_WIDTH         ( ICacheLineWidth                                    ),
    .LINE_COUNT         ( ICacheLineCount                                    ),
    .WAY_COUNT          ( ICacheSets                                         ),
    .FETCH_AW           ( AxiAddrWidth                                       ),
    .FETCH_DW           ( 32                                                 ),
    .FILL_AW            ( AxiAddrWidth                                       ),
    .FILL_DW            ( AxiDataWidth                                       ),
    .EARLY_LATCH        ( 0                                                  ),
    .L0_EARLY_TAG_WIDTH ( snitch_pkg::PAGE_SHIFT - $clog2(ICacheLineWidth/8) ),
    .ISO_CROSSING       ( 1'b1                                               ),
    .axi_req_t          ( axi_mst_tile_wide_req_t                            ),
    .axi_rsp_t          ( axi_mst_tile_wide_resp_t                           ),
    .sram_cfg_data_t    ( impl_in_t                                          ),
    .sram_cfg_tag_t     ( impl_in_t                                          )
  ) i_snitch_icache (
    .clk_i                ( clk_i                    ),
    .clk_d2_i             ( clk_i                    ),
    .rst_ni               ( rst_ni                   ),
    .enable_prefetching_i ( icache_prefetch_enable_i ),
    .enable_branch_pred_i ( '0                       ),
    .icache_l0_events_o   (                          ),
    .icache_l1_events_o   (                          ),
    .flush_valid_i        ( flush_valid              ),
    .flush_ready_o        ( flush_ready              ),
    .inst_addr_i          ( inst_addr                ),
    .inst_cacheable_i     ( inst_cacheable           ),
    .inst_data_o          ( inst_data                ),
    .inst_valid_i         ( inst_valid               ),
    .inst_ready_o         ( inst_ready               ),
    .inst_error_o         ( inst_error               ),
    .sram_cfg_tag_i       ( '0                       ),
    .sram_cfg_data_i      ( '0                       ),
    .sram_cfg_out_data_o  (),
    .sram_cfg_out_tag_o   (),
    .axi_req_o            ( wide_axi_mst_req[ICache] ),
    .axi_rsp_i            ( wide_axi_mst_rsp[ICache] )
  );

  // --------
  // Cores SoC
  // --------

  // First-level barrier for CachePool system
  cachepool_tile_barrier #(
    .AddrWidth (AxiAddrWidth ),
    .NrPorts   (NrCores      ),
    .dreq_t    (reqrsp_req_t ),
    .drsp_t    (reqrsp_rsp_t ),
    .user_t    (tcdm_user_t  )
  ) i_cachepool_tile_barrier (
    .clk_i                          (clk_i                       ),
    .rst_ni                         (rst_ni                      ),
    .in_req_i                       (core_req                    ),
    .in_rsp_o                       (core_rsp                    ),
    .out_req_o                      (filtered_core_req           ),
    .out_rsp_i                      (filtered_core_rsp           ),
    .cluster_periph_start_address_i (cluster_periph_start_address)
  );

  reqrsp_req_t core_to_axi_req;
  reqrsp_rsp_t core_to_axi_rsp;
  user_t       cluster_user;
  // Atomic ID, needs to be unique ID of cluster
  // cluster_id + HartIdOffset + 1 (because 0 is for non-atomic masters)
  assign cluster_user = (hart_base_id_i / NrCores) + (hart_base_id_i % NrCores) + 1'b1;

  reqrsp_mux #(
    .NrPorts   (NrCores           ),
    .AddrWidth (AxiAddrWidth      ),
    .DataWidth (NarrowDataWidth   ),
    .UserWidth ($bits(tcdm_user_t)),
    .req_t     (reqrsp_req_t      ),
    .rsp_t     (reqrsp_rsp_t      ),
    .RespDepth (2                 )
  ) i_reqrsp_mux_core (
    .clk_i     (clk_i            ),
    .rst_ni    (rst_ni           ),
    .slv_req_i (filtered_core_req),
    .slv_rsp_o (filtered_core_rsp),
    .mst_req_o (core_to_axi_req  ),
    .mst_rsp_i (core_to_axi_rsp  ),
    .idx_o     (/*unused*/       )
  );

  reqrsp_to_axi #(
    .DataWidth    (NarrowDataWidth    ),
    .AxiUserWidth (NarrowUserWidth    ),
    .UserWidth    ($bits(tcdm_user_t) ),
    .ID           ( 1 ),
    .reqrsp_req_t (reqrsp_req_t       ),
    .reqrsp_rsp_t (reqrsp_rsp_t       ),
    .axi_req_t    (axi_mst_req_t      ),
    .axi_rsp_t    (axi_mst_resp_t     )
  ) i_reqrsp_to_axi_core (
    .clk_i        (clk_i                      ),
    .rst_ni       (rst_ni                     ),
    .user_i       (cluster_user               ),
    .reqrsp_req_i (core_to_axi_req            ),
    .reqrsp_rsp_o (core_to_axi_rsp            ),
    .axi_req_o    (narrow_axi_mst_req[CoreReq]),
    .axi_rsp_i    (narrow_axi_mst_rsp[CoreReq])
  );

  xbar_rule_t [NrNarrowRules-1:0] cluster_xbar_rules;

  assign cluster_xbar_rules = '{
    '{
      idx       : ClusterPeripherals,
      start_addr: cluster_periph_start_address,
      end_addr  : cluster_periph_end_address
    },
    '{
      idx       : UART,
      start_addr: UartAddr,
      end_addr  : UartAddr + 32'h1000
    }
  };

  localparam bit   [ClusterXbarCfg.NoSlvPorts-1:0]                                                        ClusterEnableDefaultMstPort = '1;
  localparam logic [ClusterXbarCfg.NoSlvPorts-1:0][cf_math_pkg::idx_width(ClusterXbarCfg.NoMstPorts)-1:0] ClusterXbarDefaultPort      = '{default: SoC};

  axi_xbar #(
    .Cfg           (ClusterXbarCfg   ),
    .slv_aw_chan_t (axi_mst_aw_chan_t),
    .mst_aw_chan_t (axi_slv_aw_chan_t),
    .w_chan_t      (axi_mst_w_chan_t ),
    .slv_b_chan_t  (axi_mst_b_chan_t ),
    .mst_b_chan_t  (axi_slv_b_chan_t ),
    .slv_ar_chan_t (axi_mst_ar_chan_t),
    .mst_ar_chan_t (axi_slv_ar_chan_t),
    .slv_r_chan_t  (axi_mst_r_chan_t ),
    .mst_r_chan_t  (axi_slv_r_chan_t ),
    .slv_req_t     (axi_mst_req_t    ),
    .slv_resp_t    (axi_mst_resp_t   ),
    .mst_req_t     (axi_slv_req_t    ),
    .mst_resp_t    (axi_slv_resp_t   ),
    .rule_t        (xbar_rule_t      )
  ) i_axi_narrow_xbar (
    .clk_i                 (clk_i                      ),
    .rst_ni                (rst_ni                     ),
    .test_i                (1'b0                       ),
    .slv_ports_req_i       (narrow_axi_mst_req         ),
    .slv_ports_resp_o      (narrow_axi_mst_rsp         ),
    .mst_ports_req_o       (narrow_axi_slv_req         ),
    .mst_ports_resp_i      (narrow_axi_slv_rsp         ),
    .addr_map_i            (cluster_xbar_rules         ),
    .en_default_mst_port_i (ClusterEnableDefaultMstPort),
    .default_mst_port_i    (ClusterXbarDefaultPort     )
  );

  // 3. BootROM
  assign axi_wide_req_o[TileBootROM] = wide_axi_slv_req[BootROM];
  assign wide_axi_slv_rsp[BootROM] = axi_wide_rsp_i[TileBootROM];

  // 4. UART
  assign axi_out_req_o[0] = narrow_axi_slv_req[UART];
  assign narrow_axi_slv_rsp[UART] = axi_out_resp_i[0];

  assign axi_out_req_o[1] = narrow_axi_slv_req[ClusterPeripherals];
  assign narrow_axi_slv_rsp[ClusterPeripherals] = axi_out_resp_i[1];


  // Upsize the narrow SoC connection
  `AXI_TYPEDEF_ALL(axi_mst_core_narrow, addr_t, id_wide_mst_t, data_t, strb_t, user_t)
  axi_mst_core_narrow_req_t  narrow_axi_slv_req_soc;
  axi_mst_core_narrow_resp_t narrow_axi_slv_resp_soc;

  axi_iw_converter #(
    .AxiAddrWidth          (AxiAddrWidth             ),
    .AxiDataWidth          (NarrowDataWidth          ),
    .AxiUserWidth          (AxiUserWidth             ),
    .AxiSlvPortIdWidth     (NarrowIdWidthOut         ),
    .AxiSlvPortMaxUniqIds  (1                        ),
    .AxiSlvPortMaxTxnsPerId(1                        ),
    .AxiSlvPortMaxTxns     (1                        ),
    .AxiMstPortIdWidth     (WideIdWidthIn            ),
    .AxiMstPortMaxUniqIds  (1                        ),
    .AxiMstPortMaxTxnsPerId(1                        ),
    .slv_req_t             (axi_slv_req_t            ),
    .slv_resp_t            (axi_slv_resp_t           ),
    .mst_req_t             (axi_mst_core_narrow_req_t ),
    .mst_resp_t            (axi_mst_core_narrow_resp_t)
  ) i_soc_port_iw_convert (
    .clk_i      (clk_i                   ),
    .rst_ni     (rst_ni                  ),
    .slv_req_i  (narrow_axi_slv_req[SoC] ),
    .slv_resp_o (narrow_axi_slv_rsp[SoC] ),
    .mst_req_o  (narrow_axi_slv_req_soc  ),
    .mst_resp_i (narrow_axi_slv_resp_soc )
  );

  // TODO: Do we need this data path?
  // core will never use it as wide destination is only BootRom and main memory
  axi_dw_converter #(
    .AxiAddrWidth       (AxiAddrWidth               ),
    .AxiIdWidth         (WideIdWidthIn              ),
    .AxiMaxReads        (2                          ),
    .AxiSlvPortDataWidth(NarrowDataWidth            ),
    .AxiMstPortDataWidth(AxiDataWidth               ),
    .ar_chan_t          (axi_mst_tile_wide_ar_chan_t),
    .aw_chan_t          (axi_mst_tile_wide_aw_chan_t),
    .b_chan_t           (axi_mst_tile_wide_b_chan_t ),
    .slv_r_chan_t       (axi_mst_core_narrow_r_chan_t),
    .slv_w_chan_t       (axi_mst_core_narrow_b_chan_t),
    .axi_slv_req_t      (axi_mst_core_narrow_req_t   ),
    .axi_slv_resp_t     (axi_mst_core_narrow_resp_t  ),
    .mst_r_chan_t       (axi_mst_tile_wide_r_chan_t ),
    .mst_w_chan_t       (axi_mst_tile_wide_w_chan_t ),
    .axi_mst_req_t      (axi_mst_tile_wide_req_t    ),
    .axi_mst_resp_t     (axi_mst_tile_wide_resp_t   )
  ) i_soc_port_dw_upsize (
    .clk_i      (clk_i                        ),
    .rst_ni     (rst_ni                       ),
    .slv_req_i  (narrow_axi_slv_req_soc       ),
    .slv_resp_o (narrow_axi_slv_resp_soc      ),
    .mst_req_o  (wide_axi_mst_req[CoreReqWide]),
    .mst_resp_i (wide_axi_mst_rsp[CoreReqWide])
  );

  // -------------
  // Sanity Checks
  // -------------
  // Check that the cluster base address aligns to the TCDMSize.
  `ASSERT(ClusterBaseAddrAlign, ((TCDMSize - 1) & cluster_base_addr_i) == 0)

endmodule
