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

/// Tile implementation for CachePool
module cachepool_tile
  import cachepool_pkg::*;
  import spatz_pkg::*;
  import fpnew_pkg::fpu_implementation_t;
  import snitch_pma_pkg::snitch_pma_t;
  import snitch_icache_pkg::icache_events_t;
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
    /// Folded data bank configuration (0 = auto: min(4, L1AssoPerCtrl)).
    parameter bit                                            UseFoldedDataBanks               = 1'b1,
    parameter int                     unsigned               FoldWayGroup                     = 0,
    /// Use hash-based way selection (1 way per lookup, no LRU).
    parameter bit                                            UseHashWaySelect                 = 1'b0
  ) (
    /// System clock.
    input  logic                                    clk_i,
    /// Asynchronous active high reset. This signal is assumed to be _async_.
    input  logic                                    rst_ni,
    /// Per-core debug request signal. Asserting this signals puts the
    /// corresponding core into debug mode. This signal is assumed to be _async_.
    input  logic              [NrCores-1:0]         debug_req_i,
    /// End of Computing indicator to notify the host/tb
    // output logic                                    eoc_o,
    /// Machine external interrupt pending. Usually those interrupts come from a
    /// platform-level interrupt controller. This signal is assumed to be _async_.
    input  logic              [NrCores-1:0]         meip_i,
    /// Machine timer interrupt pending. Usually those interrupts come from a
    /// core-local interrupt controller such as a timer/RTC. This signal is
    /// assumed to be _async_.
    input  logic              [NrCores-1:0]         mtip_i,
    /// Core software interrupt pending. Usually those interrupts come from
    /// another core to facilitate inter-processor-interrupts. This signal is
    /// assumed to be _async_.
    input  logic              [NrCores-1:0]         msip_i,
    /// First hartid of the cluster. Cores of a cluster are monotonically
    /// increasing without a gap, i.e., a cluster with 8 cores and a
    /// `hart_base_id_i` of 5 get the hartids 5 - 12.
    input  logic              [9:0]                 hart_base_id_i,
    /// Base address of cluster. TCDM and cluster peripheral location are derived from
    /// it. This signal is pseudo-static.
    input  logic              [AxiAddrWidth-1:0]    cluster_base_addr_i,
    /// AXI Narrow out-port (UART/Peripheral)
    output axi_narrow_req_t   [1:0]                 axi_out_req_o,
    input  axi_narrow_resp_t  [1:0]                 axi_out_resp_i,
    /// Cache Refill ports
    output cache_trans_req_t  [NumL1CtrlTile-1:0]   cache_refill_req_o,
    input  cache_trans_rsp_t  [NumL1CtrlTile-1:0]   cache_refill_rsp_i,
    /// Wide AXI ports to cluster level
    output axi_out_req_t      [TileNarrowAxiPorts-1:0]  axi_wide_req_o,
    input  axi_out_resp_t     [TileNarrowAxiPorts-1:0]  axi_wide_rsp_i,
    /// Remote Tile access ports (to remote tiles)
    output tcdm_req_t         [NrTCDMPortsPerCore*NumRemotePortTile-1:0] remote_req_o,
    output remote_tile_sel_t  [NrTCDMPortsPerCore*NumRemotePortTile-1:0] remote_req_dst_o,
    input  tcdm_rsp_t         [NrTCDMPortsPerCore*NumRemotePortTile-1:0] remote_rsp_i,
    /// Remote Tile access ports (from remote tiles)
    input  tcdm_req_t         [NrTCDMPortsPerCore*NumRemotePortTile-1:0] remote_req_i,
    output tcdm_rsp_t         [NrTCDMPortsPerCore*NumRemotePortTile-1:0] remote_rsp_o,
    /// Peripheral signals
    output icache_events_t    [NrCores-1:0]         icache_events_o,
    input  logic                                    icache_prefetch_enable_i,
    input  logic              [NrCores-1:0]         cl_interrupt_i,
    input  logic [$clog2(AxiAddrWidth)-1:0]         dynamic_offset_i,
    input  logic              [1:0]                 l1d_insn_i,
    input  logic                                    l1d_insn_valid_i,
    output logic              [NumL1CtrlTile-1:0]   l1d_insn_ready_o,
    input  logic              [NumL1CtrlTile-1:0]   l1d_busy_i,



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

  // The metadata type used to restore the information from req to rsp
  typedef struct packed {
    tcdm_user_t user;
    logic       write;
  } tcdm_meta_t;

  // Regbus peripherals.
  `AXI_TYPEDEF_ALL(axi_mst, addr_t, id_mst_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(axi_slv, addr_t, id_slv_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(axi_mst_tile_wide, addr_t, id_wide_mst_t, data_wide_t, strb_wide_t, user_wide_t)
  `AXI_TYPEDEF_ALL(axi_slv_tile_wide, addr_t, id_wide_slv_t, data_wide_t, strb_wide_t, user_wide_t)

  `REQRSP_TYPEDEF_ALL(reqrsp, addr_t, data_t, strb_t, tcdm_user_t)

  `MEM_TYPEDEF_ALL(mem, tcdm_mem_addr_t, data_t, strb_t, tcdm_user_t)

  `REG_BUS_TYPEDEF_ALL(reg, addr_t, data_t, strb_t)


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

  snitch_icache_pkg::icache_events_t [NrCores-1:0] icache_events;

  // 4. Memory Subsystem (Core side).
  reqrsp_req_t [NrCores-1:0] core_req, filtered_core_req;
  reqrsp_rsp_t [NrCores-1:0] core_rsp, filtered_core_rsp;


  // 8. L1 D$
  tcdm_req_t  [NrTCDMPortsCores-1:0] unmerge_req;
  tcdm_rsp_t  [NrTCDMPortsCores-1:0] unmerge_rsp;

  tcdm_req_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_req, cache_xbar_req;
  tcdm_rsp_t  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_rsp, cache_xbar_rsp;

  tcdm_req_t  [NumL1CtrlTile-1:0] cache_amo_req;
  tcdm_rsp_t  [NumL1CtrlTile-1:0] cache_amo_rsp;


  logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_valid;
  logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_ready;
  tcdm_addr_t [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_addr;
  tcdm_user_t [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_meta;
  logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_write;
  data_t      [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_data;
  strb_t      [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_req_strb;

  logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_valid;
  logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_ready;
  logic       [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_write;
  data_t      [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_data;
  tcdm_user_t [NumL1CtrlTile-1:0][NrTCDMPortsPerCore-1:0] cache_rsp_meta;

  logic            [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_req;
  logic            [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_we;
  tcdm_bank_addr_t [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_addr;
  tag_data_t       [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_wdata;
  logic            [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_be;
  tag_data_t       [NumL1CtrlTile-1:0][NumTagBankPerCtrl-1:0] l1_tag_bank_rdata;

  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_req;
  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_we;
  tcdm_bank_addr_t [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_addr;
  data_t           [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_wdata;
  logic            [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0][DataWidth/8-1:0] l1_data_bank_be;
  data_t           [NumL1CtrlTile-1:0][NumDataBankPerCtrl-1:0] l1_data_bank_rdata;
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
  logic  [NrTCDMPortsPerCore-1:0][NumL1CtrlTile-1:0] cache_pready, cache_xbar_pready;
  logic  [NumL1CtrlTile-1:0] cache_amo_pready;

  always_comb begin : cache_flush_protection
    for (int j = 0; unsigned'(j) < NrTCDMPortsCores; j++) begin
      /***** REQ *****/
      // Wire to Cache outputs
      unmerge_req[j].q       = tcdm_req[j].q;
      // invalidate the request when cache is busy
      unmerge_req[j].q_valid = tcdm_req[j].q_valid && !(|l1d_busy_i);
      unmerge_pready[j]      = 1'b1;

      /***** RSP *****/
      tcdm_rsp[j].p       = unmerge_rsp[j].p;
      tcdm_rsp[j].p_valid = unmerge_rsp[j].p_valid;
      tcdm_rsp[j].q_ready = unmerge_rsp[j].q_ready && !(|l1d_busy_i);
    end

  end

  for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin
    for (genvar cb = 0; cb < NumL1CtrlTile; cb++) begin
      assign cache_req   [j][cb] = unmerge_req   [cb*NrTCDMPortsPerCore+j];
      assign cache_pready[j][cb] = unmerge_pready[cb*NrTCDMPortsPerCore+j];
      assign unmerge_rsp [cb*NrTCDMPortsPerCore+j] = cache_rsp     [j][cb];
    end

    // for (genvar rt = 0; rt < NumRemotePortTile; rt++) begin
    //   assign cache_req[j][rt+NumL1CtrlTile] = remote_req_i[j*NrTCDMPortsPerCore+rt];
    //   assign remote_rsp_o[j*NrTCDMPortsPerCore+rt] = cache_rsp [j][rt+NumL1CtrlTile];
    // end
  end

  // Connecting the remote ports
  // if (NumRemotePort > 0) begin
  //   for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin

  //   end
  // end

  // Used to determine the mapping policy between different cache banks.
  // Set through CSR
  logic [$clog2(TCDMAddrWidth)-1:0] dynamic_offset;
  assign dynamic_offset = dynamic_offset_i;

  logic [NrTCDMPortsPerCore-1:0] remote_pready;

  /// Wire requests after strb handling to the cache controller
  for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin : gen_cache_xbar
    tcdm_cache_interco #(
      .NumTiles              (NumTiles          ),
      .NumCores              (NrCores           ),
      .NumCache              (NumL1CtrlTile    ),
      .NumRemotePort         (NumRemotePortTile ),
      .AddrWidth             (TCDMAddrWidth     ),
      .tcdm_req_t            (tcdm_req_t        ),
      .tcdm_rsp_t            (tcdm_rsp_t        ),
      .tcdm_req_chan_t       (tcdm_req_chan_t   ),
      .tcdm_rsp_chan_t       (tcdm_rsp_chan_t   )
    ) i_cache_xbar (
      .clk_i            (clk_i                  ),
      .rst_ni           (rst_ni                 ),
      .tile_id_i        (1'b0                   ),
      .dynamic_offset_i (dynamic_offset         ),
      .core_req_i       ({remote_req_i[j], cache_req        [j]}),
      .core_rsp_ready_i ({1'b1,            cache_pready     [j]}),
      .core_rsp_o       ({remote_rsp_o[j], cache_rsp        [j]}),
      .mem_req_o        ({remote_req_o[j], cache_xbar_req   [j]}),
      .mem_rsp_ready_o  ({remote_pready[j],cache_xbar_pready[j]}),
      .mem_rsp_i        ({remote_rsp_i[j], cache_xbar_rsp   [j]})
    );
  end

  for (genvar cb = 0; cb < NumL1CtrlTile; cb++) begin : gen_cache_connect
    // Only Snitch will send out amo requests
    // Ports from Spatz can bypass this module

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
          .core_req_i       (cache_xbar_req   [j][cb] ),
          .core_rsp_ready_i (cache_xbar_pready[j][cb] ),
          .core_rsp_o       (cache_xbar_rsp   [j][cb] ),
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
        // Bypass AMO and registers
        assign cache_req_valid[cb][j] = cache_xbar_req   [j][cb].q_valid;
        assign cache_rsp_ready[cb][j] = cache_xbar_pready[j][cb];
        assign cache_req_addr [cb][j] = cache_xbar_req   [j][cb].q.addr;
        assign cache_req_meta [cb][j] = cache_xbar_req   [j][cb].q.user;
        assign cache_req_write[cb][j] = cache_xbar_req   [j][cb].q.write;
        assign cache_req_data [cb][j] = cache_xbar_req   [j][cb].q.data;
        assign cache_req_strb [cb][j] = cache_xbar_req   [j][cb].q.strb;

        assign cache_xbar_rsp[j][cb].q_ready = cache_req_ready[cb][j];
        assign cache_xbar_rsp[j][cb].p_valid = cache_rsp_valid[cb][j];
        assign cache_xbar_rsp[j][cb].p.data  = cache_rsp_data [cb][j];
        assign cache_xbar_rsp[j][cb].p.user  = cache_rsp_meta [cb][j];

        assign cache_xbar_rsp[j][cb].p.write = cache_rsp_write[cb][j];

      end
    end
  end

  // For address scrambling
  localparam NumSelBits = $clog2(NumL1CtrlTile);
  localparam NumWordPerLine = L1LineWidth / DataWidth;
  localparam int unsigned WordBytes = DataWidth / 8;
  localparam bit          UseSkewedFolded = UseFoldedDataBanks && (L1AssoPerCtrl > 1);
  localparam int unsigned DefaultFoldWayGroup = (L1AssoPerCtrl >= 4) ? 4 : 2;
  localparam int unsigned EffectiveFoldWayGroup = UseSkewedFolded ?
      ((FoldWayGroup == 0) ? DefaultFoldWayGroup : FoldWayGroup) :
      L1AssoPerCtrl;
  localparam int unsigned NumWayGroups = L1AssoPerCtrl / EffectiveFoldWayGroup;
  localparam int unsigned PartSplit = UseSkewedFolded ? EffectiveFoldWayGroup : 1;
  localparam int unsigned NumDataBankPerWay = NumDataBankPerCtrl / L1AssoPerCtrl;
  localparam int unsigned WordsPerPart = NumWordPerLine / PartSplit;
  localparam int unsigned NumDataBankPerWayGrouped = NumDataBankPerWay / WordsPerPart;
  localparam int unsigned BankDataWidth = DataWidth * WordsPerPart;
  localparam int unsigned BankByteCount = BankDataWidth / 8;
  localparam int unsigned FoldedDataDepth = (L1CacheWayEntry / L1BankFactor) * PartSplit;
  // Folded mode already shrinks request window to part-width; keep coalescer in
  // equal-window mode to avoid response lane remap corner cases.
  localparam int unsigned EffectiveCoalFactor = UseSkewedFolded ? 1 : L1CoalFactor;
  initial begin
    $display("Cache Configuration:");
    $display("  NumCtrl        : %0d", NumL1CtrlTile);
    $display("  LineWidth      : %0d", L1LineWidth);
    $display("  NumWordPerLine : %0d", NumWordPerLine);
    $display("  NumSet         : %0d", L1NumSet);
    $display("  AssoPerCtrl    : %0d", L1AssoPerCtrl);
    $display("  BankFactor     : %0d", L1BankFactor);
    $display("  PartSplit      : %0d", PartSplit);
    $display("  BankDataWidth  : %0d", BankDataWidth);
    $display("  NumTagBankPerCtrl : %0d", NumTagBankPerCtrl);
    $display("  NumDataBankPerCtrl: %0d", NumDataBankPerCtrl);
    $display("  CoalFactor     : %0d", EffectiveCoalFactor);
    $display("  RefillDataWidth: %0d", RefillDataWidth);
    $display("  DynamicOffset  : %0d", dynamic_offset);
  end
  logic [SpatzAxiAddrWidth-1:0] bitmask_up, bitmask_lo;
  assign bitmask_lo = (1 << dynamic_offset) - 1;
  // We will keep AddrWidth - Offset - log2(CacheBanks) bits in the upper half, and add back the NumSelBits bits
  assign bitmask_up = ((1 << (SpatzAxiAddrWidth - dynamic_offset - NumSelBits)) - 1) << (dynamic_offset);

  cache_refill_req_chan_t [NumL1CtrlTile-1 : 0] cache_refill_req;
  burst_req_t             [NumL1CtrlTile-1 : 0] cache_refill_burst;
  logic                   [NumL1CtrlTile-1 : 0] cache_refill_req_valid, cache_refill_req_ready;
  cache_refill_rsp_chan_t [NumL1CtrlTile-1 : 0] cache_refill_rsp;
  logic                   [NumL1CtrlTile-1 : 0] cache_refill_rsp_valid, cache_refill_rsp_ready;

  for (genvar cb = 0; cb < NumL1CtrlTile; cb++) begin: gen_l1_cache_ctrl
    cachepool_cache_ctrl #(
      // Core
      .NumPorts         (NrTCDMPortsPerCore ),
      .CoalExtFactor    (EffectiveCoalFactor),
      .AddrWidth        (L1AddrWidth        ),
      .WordWidth        (DataWidth          ),
      .ByteWidth        (8                  ),
      .TagWidth         (L1TagDataWidth     ),
      // Cache
      .NumCacheEntry    (L1NumEntryPerCtrl  ),
      .CacheLineWidth   (L1LineWidth        ),
      .SetAssociativity (L1AssoPerCtrl      ),
      .DataPartSplit    (PartSplit          ),
      .UseHashWaySelect (UseHashWaySelect   ),
      .BankFactor       (L1BankFactor       ),
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
      .cache_sync_valid_i    (l1d_insn_valid_i               ),
      .cache_sync_ready_o    (l1d_insn_ready_o[cb]           ),
      .cache_sync_insn_i     (l1d_insn_i                     ),
      // SPM Size
      // The calculation of spm region in cache is different
      // than other modules (needs to times 2)
      // Currently assume full cache
      .bank_depth_for_SPM_i  ('0                             ),
      // Request
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

    always_comb begin : bank_addr_scramble
      // TODO: use info and cb to calculate ID correctly
      cache_refill_req_o[cb].q = '{
        addr : cache_refill_req[cb].addr,
        write: cache_refill_req[cb].write,
        data : cache_refill_req[cb].wdata,
        strb : cache_refill_req[cb].wstrb,
        // We always want full size from cache
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


      // Pass the lower bits first
      cache_refill_req_o[cb].q.addr  =   cache_refill_req[cb].addr & bitmask_lo;
      // Shift the upper part to its location
      cache_refill_req_o[cb].q.addr |= ((cache_refill_req[cb].addr & bitmask_up) << NumSelBits);
      // Add back the removed cache bank ID
      cache_refill_req_o[cb].q.addr |= (cb << dynamic_offset);

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
        .impl_o (/* unsed */             ),
        .req_i  (l1_tag_bank_req  [cb][j]),
        .we_i   (l1_tag_bank_we   [cb][j]),
        .addr_i (l1_tag_bank_addr [cb][j]),
        .wdata_i(l1_tag_bank_wdata[cb][j]),
        .be_i   (l1_tag_bank_be   [cb][j]),
        .rdata_o(l1_tag_bank_rdata[cb][j])
      );
    end

    if (UseSkewedFolded) begin : gen_folded_data_banks
      // Skewed folded banks: keep W*B macros, narrow width, deeper depth, and skew (way, part) -> column.
      typedef logic [$clog2(FoldedDataDepth)-1:0] folded_bank_addr_t;

      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0]            bank_req;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0]            bank_we;
      folded_bank_addr_t   [L1AssoPerCtrl-1:0][L1BankFactor-1:0]            bank_addr;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][BankDataWidth-1:0] bank_wdata;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][BankByteCount-1:0] bank_be;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][BankDataWidth-1:0] bank_rdata;

      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0] part_req;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0] part_we;
      folded_bank_addr_t   [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0] part_addr;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0][BankDataWidth-1:0] part_wdata;
      logic                [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0][BankByteCount-1:0] part_be;

      for (genvar group = 0; group < NumWayGroups; group++) begin : gen_skew_groups
        for (genvar way = 0; way < EffectiveFoldWayGroup; way++) begin : gen_skew_ways
          localparam int unsigned WayIdx = group * EffectiveFoldWayGroup + way;
          for (genvar part = 0; part < PartSplit; part++) begin : gen_skew_parts
            localparam int unsigned ColIdx = group * EffectiveFoldWayGroup + ((way + part) % EffectiveFoldWayGroup);
            for (genvar bank_sel = 0; bank_sel < L1BankFactor; bank_sel++) begin : gen_skew_banks
              localparam int unsigned BankBase = bank_sel * NumWordPerLine + part * WordsPerPart;
              assign part_req[ColIdx][bank_sel][part] =
                  |l1_data_bank_req[cb][WayIdx * NumDataBankPerWay + BankBase +: WordsPerPart];
              assign part_we[ColIdx][bank_sel][part] =
                  |l1_data_bank_we [cb][WayIdx * NumDataBankPerWay + BankBase +: WordsPerPart];
              assign part_addr[ColIdx][bank_sel][part] =
                  folded_bank_addr_t'((l1_data_bank_addr[cb][WayIdx * NumDataBankPerWay + BankBase] * PartSplit) + part);

              for (genvar w = 0; w < WordsPerPart; w++) begin : gen_part_words
                localparam int unsigned FlatIdx = WayIdx * NumDataBankPerWay + BankBase + w;
                assign part_wdata[ColIdx][bank_sel][part][w*DataWidth +: DataWidth] =
                    l1_data_bank_wdata[cb][FlatIdx];
                assign part_be[ColIdx][bank_sel][part][w*(DataWidth/8) +: (DataWidth/8)] =
                    l1_data_bank_be[cb][FlatIdx];
                assign l1_data_bank_rdata[cb][FlatIdx] =
                    bank_rdata[ColIdx][bank_sel][w*DataWidth +: DataWidth];
                assign l1_data_bank_gnt[cb][FlatIdx] = 1'b1;
              end
            end
          end
        end
      end

      always_comb begin : select_skewed_part
        for (int col = 0; col < L1AssoPerCtrl; col++) begin
          for (int bank_sel = 0; bank_sel < L1BankFactor; bank_sel++) begin
            automatic logic sel_found;
            automatic int unsigned sel_part_idx;

            bank_req[col][bank_sel] = 1'b0;
            bank_we[col][bank_sel] = 1'b0;
            bank_addr[col][bank_sel] = '0;
            bank_wdata[col][bank_sel] = '0;
            bank_be[col][bank_sel] = '0;

            sel_found = 1'b0;
            sel_part_idx = 0;
            for (int part = 0; part < PartSplit; part++) begin
              if (part_we[col][bank_sel][part] && !sel_found) begin
                sel_found = 1'b1;
                sel_part_idx = part;
              end
            end
            if (!sel_found) begin
              for (int part = 0; part < PartSplit; part++) begin
                if (part_req[col][bank_sel][part] && !sel_found) begin
                  sel_found = 1'b1;
                  sel_part_idx = part;
                end
              end
            end

            if (sel_found) begin
              bank_req[col][bank_sel] = 1'b1;
              bank_we[col][bank_sel] = part_we[col][bank_sel][sel_part_idx];
              bank_addr[col][bank_sel] = part_addr[col][bank_sel][sel_part_idx];
              bank_wdata[col][bank_sel] = part_wdata[col][bank_sel][sel_part_idx];
              bank_be[col][bank_sel] = part_be[col][bank_sel][sel_part_idx];
            end
          end
        end
      end

      for (genvar col = 0; col < L1AssoPerCtrl; col++) begin : gen_skew_cols
        for (genvar bank_sel = 0; bank_sel < L1BankFactor; bank_sel++) begin : gen_skew_col_banks
          tc_sram_impl #(
            .NumWords  (FoldedDataDepth),
            .DataWidth (BankDataWidth),
            .ByteWidth (8),
            .NumPorts  (1),
            .Latency   (1),
            .SimInit   ("zeros")
          ) i_data_bank (
            .clk_i  (clk_i      ),
            .rst_ni (rst_ni     ),
            .impl_i ('0         ),
            .impl_o (/* unused */),
            .req_i  (bank_req[col][bank_sel]),
            .we_i   (bank_we[col][bank_sel]),
            .addr_i (bank_addr[col][bank_sel]),
            .wdata_i(bank_wdata[col][bank_sel]),
            .be_i   (bank_be[col][bank_sel]),
            .rdata_o(bank_rdata[col][bank_sel])
          );
        end
      end
    end else begin : gen_unfolded_data_banks
      // Unfolded banks: each SRAM stores a full cacheline per way/bank factor.
      for (genvar bank = 0; bank < NumDataBankPerWayGrouped; bank++) begin : gen_l1_data_banks
        for (genvar way = 0; way < L1AssoPerCtrl; way++) begin : gen_way_banks
          logic                  bank_req;
          logic                  bank_we;
          tcdm_bank_addr_t       bank_addr;
          logic [BankDataWidth-1:0] bank_wdata;
          logic [BankByteCount-1:0] bank_be;
          logic [BankDataWidth-1:0] bank_rdata;

          assign bank_req = |l1_data_bank_req[cb][way*NumDataBankPerWay + bank*WordsPerPart +: WordsPerPart];
          assign bank_we  = |l1_data_bank_we [cb][way*NumDataBankPerWay + bank*WordsPerPart +: WordsPerPart];
          assign bank_addr = l1_data_bank_addr[cb][way*NumDataBankPerWay + bank*WordsPerPart];

          for (genvar g = 0; g < WordsPerPart; g++) begin : gen_group_words
            localparam int unsigned FlatIdx = way * NumDataBankPerWay + bank * WordsPerPart + g;
            assign bank_wdata[g*DataWidth +: DataWidth] = l1_data_bank_wdata[cb][FlatIdx];
            assign bank_be[g*(DataWidth/8) +: (DataWidth/8)] = l1_data_bank_be[cb][FlatIdx];
            assign l1_data_bank_rdata[cb][FlatIdx] = bank_rdata[g*DataWidth +: DataWidth];
            assign l1_data_bank_gnt[cb][FlatIdx] = 1'b1;
          end

          tc_sram_impl #(
            .NumWords  (L1CacheWayEntry/L1BankFactor),
            .DataWidth (BankDataWidth),
            .ByteWidth (8),
            .NumPorts  (1),
            .Latency   (1),
            .SimInit   ("zeros")
          ) i_data_bank (
            .clk_i  (clk_i      ),
            .rst_ni (rst_ni     ),
            .impl_i ('0         ),
            .impl_o (/* unused */),
            .req_i  (bank_req   ),
            .we_i   (bank_we    ),
            .addr_i (bank_addr  ),
            .wdata_i(bank_wdata ),
            .be_i   (bank_be    ),
            .rdata_o(bank_rdata )
          );
        end
      end
    end
  end

  hive_req_t [NrCores-1:0] hive_req;
  hive_rsp_t [NrCores-1:0] hive_rsp;

  for (genvar i = 0; i < NrCores; i++) begin : gen_core
    localparam int unsigned TcdmPorts     = get_tcdm_ports(i);
    localparam int unsigned TcdmPortsOffs = get_tcdm_port_offs(i);

    interrupts_t irq;

    sync #(.STAGES (2))
    i_sync_debug (.clk_i, .rst_ni, .serial_i (debug_req_i[i]), .serial_o (irq.debug));
    sync #(.STAGES (2))
    i_sync_meip (.clk_i, .rst_ni, .serial_i (meip_i[i]), .serial_o (irq.meip));
    sync #(.STAGES (2))
    i_sync_mtip (.clk_i, .rst_ni, .serial_i (mtip_i[i]), .serial_o (irq.mtip));
    sync #(.STAGES (2))
    i_sync_msip (.clk_i, .rst_ni, .serial_i (msip_i[i]), .serial_o (irq.msip));
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
      .Xdma                    (Xdma[i]                    ),
      .AddrWidth               (AxiAddrWidth               ),
      .DataWidth               (NarrowDataWidth            ),
      .UserWidth               (AxiUserWidth               ),
      .DMADataWidth            (AxiDataWidth               ),
      .DMAIdWidth              (AxiIdWidthIn               ),
      .SnitchPMACfg            (SnitchPMACfg               ),
      .DMAAxiReqFifoDepth      (DMAAxiReqFifoDepth         ),
      .DMAReqFifoDepth         (DMAReqFifoDepth            ),
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
    .SET_COUNT          ( ICacheSets                                         ),
    .FETCH_AW           ( AxiAddrWidth                                       ),
    .FETCH_DW           ( 32                                                 ),
    .FILL_AW            ( AxiAddrWidth                                       ),
    .FILL_DW            ( AxiDataWidth                                       ),
    .EARLY_LATCH        ( 0                                                  ),
    .L0_EARLY_TAG_WIDTH ( snitch_pkg::PAGE_SHIFT - $clog2(ICacheLineWidth/8) ),
    .ISO_CROSSING       ( 1'b0                                               ),
    .axi_req_t          ( axi_mst_tile_wide_req_t                            ),
    .axi_rsp_t          ( axi_mst_tile_wide_resp_t                           ),
    .sram_cfg_data_t    ( impl_in_t                                          ),
    .sram_cfg_tag_t     ( impl_in_t                                          )
  ) i_snitch_icache (
    .clk_i                ( clk_i                    ),
    .clk_d2_i             ( clk_i                    ),
    .rst_ni               ( rst_ni                   ),
    .enable_prefetching_i ( icache_prefetch_enable_i ),
    .icache_events_o      ( icache_events_o          ),
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
    // .WriteRspEn   ( 1'b0 ),
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
  // Sanity check the parameters. Not every configuration makes sense.
  `ASSERT_INIT(CheckSuperBankSanity, NrBanks >= BanksPerSuperBank);
  `ASSERT_INIT(CheckSuperBankFactor, (NrBanks % BanksPerSuperBank) == 0);
  `ASSERT_INIT(CheckFoldWayGroup, (EffectiveFoldWayGroup > 0) &&
    ((L1AssoPerCtrl % EffectiveFoldWayGroup) == 0));
  `ASSERT_INIT(CheckLineSplit, (NumWordPerLine % PartSplit) == 0);
  // Check that the cluster base address aligns to the TCDMSize.
  `ASSERT(ClusterBaseAddrAlign, ((TCDMSize - 1) & cluster_base_addr_i) == 0)
  // Make sure we only have one DMA in the system.
  `ASSERT_INIT(NumberDMA, $onehot0(Xdma))

endmodule
