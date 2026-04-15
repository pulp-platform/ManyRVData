// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Description: Wrapper around cachepool_group that handles inter-group
// interconnection (mux/demux, flit packing, routers, receiving xbar).
//
// For now this is a pass-through wrapper with inter-group ports tied off,
// allowing the cluster to instantiate it in place of cachepool_group
// without functional change.  The inter-group logic will be added
// incrementally.
//
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

module cachepool_group_noc_wrapper
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
    parameter int                     unsigned               NrCores                            = 0,
    /// Data/TCDM memory depth per cut (in words).
    parameter int                     unsigned               TCDMDepth                          = 1024,
    /// Cluster peripheral address region size (in kB).
    parameter int                     unsigned               ClusterPeriphSize                  = 64,
    /// Number of TCDM Banks.
    parameter int                     unsigned               NrBanks                            = 2 * NrCores,
    /// Size of DMA AXI buffer.
    parameter int                     unsigned               DMAAxiReqFifoDepth                 = 3,
    /// Size of DMA request FIFO.
    parameter int                     unsigned               DMAReqFifoDepth                    = 3,
    /// Width of a single icache line.
    parameter int                     unsigned               ICacheLineWidth                    = 0,
    /// Number of icache lines per set.
    parameter int                     unsigned               ICacheLineCount                    = 0,
    /// Number of icache sets.
    parameter int                     unsigned               ICacheSets                         = 0,
    /// Per-core enabling of the custom `Xdma` ISA extensions.
    parameter bit                              [NrCores-1:0] Xdma                               = '{default: '0},
    /// FPU configuration.
    parameter fpu_implementation_t                           FPUImplementation                  = fpu_implementation_t'(0),
    /// Number of Spatz FPUs
    parameter int                     unsigned               NumSpatzFPUs                       = 1,
    /// Number of Spatz IPUs
    parameter int                     unsigned               NumSpatzIPUs                       = 1,
    /// Physical Memory Attributes Configuration
    parameter snitch_pma_t                                   SnitchPMACfg                       = '0,
    /// # Outstanding loads
    parameter int                     unsigned               NumIntOutstandingLoads             = 1,
    parameter int                     unsigned               NumIntOutstandingMem               = 4,
    parameter int                     unsigned               NumSpatzOutstandingLoads           = 4,
    /// Insert Pipeline registers into off-loading path (roles)
    parameter bit                                            RegisterOffloadRsp                 = 1,
    /// Insert Pipeline registers into data cache request path
    parameter bit                                            RegisterCoreReq                    = 0,
    /// Insert Pipeline registers into data cache response path
    parameter bit                                            RegisterCoreRsp                    = 0,
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
    // Memory latency parameter.
    parameter int                     unsigned               MemoryMacroLatency                 = 1 + RegisterTCDMCuts,
    /// # SRAM Configuration rules needed
    parameter int                     unsigned               NrSramCfg                          = 1
  ) (
    /// System clock.
    input  logic                                        clk_i,
    /// Asynchronous active high reset.
    input  logic                                        rst_ni,
    /// Per-core debug request signal.
    input  logic                          [NrCores-1:0] debug_req_i,
    /// Machine external interrupt pending.
    input  logic                          [NrCores-1:0] meip_i,
    /// Machine timer interrupt pending.
    input  logic                          [NrCores-1:0] mtip_i,
    /// Core software interrupt pending.
    input  logic                          [NrCores-1:0] msip_i,
    /// First hartid of the cluster.
    input  logic                                  [9:0] hart_base_id_i,
    /// Base address of cluster.
    input  axi_addr_t                                   cluster_base_addr_i,
    /// Partitioning address
    input  axi_addr_t                                   private_start_addr_i,
    /// AXI Narrow out-port (UART/Peripheral)
    output axi_narrow_req_t   [TileNarrowAxiPorts*NumTilesPerGroup-1:0] axi_narrow_req_o,
    input  axi_narrow_resp_t  [TileNarrowAxiPorts*NumTilesPerGroup-1:0] axi_narrow_rsp_i,
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
    output logic                         [NumTilesPerGroup-1:0] l1d_insn_ready_o,
    input  logic                         [NumTilesPerGroup-1:0] l1d_busy_i,
    /// SRAM Configuration
    input  impl_in_t                    [NrSramCfg-1:0] impl_i,
    /// Indicate the program execution is error
    output logic                                        error_o
  );


  // -------------------------------------------------------------------------
  // Inter-group remote signals
  // -------------------------------------------------------------------------
  // Total per-group inter-group port count.
  localparam int unsigned NumRemoteGroupPortTile  = (NumRemoteGroupPortCore == 0) ? 1
                                                    : NumRemoteGroupPortCore * NrTCDMPortsPerCore;
  localparam int unsigned NumRemoteGroupPortGroup = NumRemoteGroupPortTile * NumTilesPerGroup;

  remote_group_req_t [NumRemoteGroupPortGroup-1:0] remote_group_req_to_group;
  remote_group_rsp_t [NumRemoteGroupPortGroup-1:0] remote_group_rsp_from_group;
  remote_group_req_t [NumRemoteGroupPortGroup-1:0] remote_group_req_from_group;
  remote_group_rsp_t [NumRemoteGroupPortGroup-1:0] remote_group_rsp_to_group;

  // Tie off incoming inter-group requests: no traffic from other groups (for now).
  assign remote_group_req_to_group = '0;
  assign remote_group_rsp_to_group = '0;



  
  // -------------------------------------------------------------------------
  // Group instantiation
  // -------------------------------------------------------------------------
  cachepool_group #(
    .AxiAddrWidth             ( AxiAddrWidth             ),
    .AxiDataWidth             ( AxiDataWidth             ),
    .AxiIdWidthIn             ( AxiIdWidthIn             ),
    .AxiIdWidthOut            ( AxiIdWidthOut            ),
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
    .axi_out_req_t            ( axi_out_req_t            ),
    .axi_out_resp_t           ( axi_out_resp_t           ),
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
  ) i_group (
    .clk_i                    ( clk_i                    ),
    .rst_ni                   ( rst_ni                   ),
    .impl_i                   ( impl_i                   ),
    .error_o                  ( error_o                  ),
    .debug_req_i              ( debug_req_i              ),
    .meip_i                   ( meip_i                   ),
    .mtip_i                   ( mtip_i                   ),
    .msip_i                   ( msip_i                   ),
    .hart_base_id_i           ( hart_base_id_i           ),
    .cluster_base_addr_i      ( cluster_base_addr_i      ),
    .private_start_addr_i     ( private_start_addr_i     ),
    .axi_narrow_req_o         ( axi_narrow_req_o         ),
    .axi_narrow_rsp_i         ( axi_narrow_rsp_i         ),
    // DRAM refill reqrsp (post-xbar, one per L2 channel)
    .l2_req_o                 ( l2_req_o                 ),
    .l2_rsp_i                 ( l2_rsp_i                 ),
    // Inter-group remote ports (tied off for now)
    .remote_group_req_o       ( remote_group_req_from_group ),
    .remote_group_rsp_i       ( remote_group_rsp_to_group   ),
    .remote_group_req_i       ( remote_group_req_to_group   ),
    .remote_group_rsp_o       ( remote_group_rsp_from_group ),
    // Peripherals
    .icache_events_o          ( icache_events_o           ),
    .icache_prefetch_enable_i ( icache_prefetch_enable_i  ),
    .cl_interrupt_i           ( cl_interrupt_i            ),
    .dynamic_offset_i         ( dynamic_offset_i          ),
    .l1d_private_i            ( l1d_private_i             ),
    .l1d_insn_i               ( l1d_insn_i                ),
    .l1d_insn_valid_i         ( l1d_insn_valid_i          ),
    .l1d_insn_ready_o         ( l1d_insn_ready_o          ),
    .l1d_busy_i               ( l1d_busy_i                )
  );

endmodule
