// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Description: Wrapper around cachepool_group that handles inter-group
// interconnection: master-side concentration xbar, flit packing, floo_router
// instances (req + rsp), and a slave-side dispatch xbar.
//
// Author: Diyou Shen <dishen@iis.ee.ethz.ch>


`include "axi/typedef.svh"

module cachepool_group_noc_wrapper
  import cachepool_pkg::*;
  import floo_pkg::*;
  import spatz_pkg::*;
  import fpnew_pkg::fpu_implementation_t;
  import snitch_pma_pkg::snitch_pma_t;
  import snitch_icache_pkg::icache_l1_events_t;
  #(
    parameter int                     unsigned               AxiAddrWidth                       = 48,
    parameter int                     unsigned               AxiDataWidth                       = 512,
    parameter int                     unsigned               AxiIdWidthIn                       = 2,
    parameter int                     unsigned               AxiIdWidthOut                      = 2,
    parameter int                     unsigned               AxiUserWidth                       = 1,
    parameter logic                            [31:0]        BootAddr                           = 32'h0,
    parameter logic                            [31:0]        UartAddr                           = 32'h0,
    parameter int                     unsigned               NrCores                            = 0,
    parameter int                     unsigned               TCDMDepth                          = 1024,
    parameter int                     unsigned               ClusterPeriphSize                  = 64,
    parameter int                     unsigned               NrBanks                            = 2 * NrCores,
    parameter int                     unsigned               ICacheLineWidth                    = 0,
    parameter int                     unsigned               ICacheLineCount                    = 0,
    parameter int                     unsigned               ICacheSets                         = 0,
    parameter fpu_implementation_t                           FPUImplementation                  = fpu_implementation_t'(0),
    parameter int                     unsigned               NumSpatzFPUs                       = 1,
    parameter int                     unsigned               NumSpatzIPUs                       = 1,
    parameter snitch_pma_t                                   SnitchPMACfg                       = '0,
    parameter int                     unsigned               NumIntOutstandingLoads             = 1,
    parameter int                     unsigned               NumIntOutstandingMem               = 4,
    parameter int                     unsigned               NumSpatzOutstandingLoads           = 4,
    parameter bit                                            RegisterOffloadRsp                 = 1,
    parameter bit                                            RegisterCoreReq                    = 0,
    parameter bit                                            RegisterCoreRsp                    = 0,
    parameter bit                                            RegisterTCDMCuts                   = 1'b0,
    parameter bit                                            RegisterExt                        = 1'b0,
    parameter axi_pkg::xbar_latency_e                        XbarLatency                        = axi_pkg::CUT_ALL_PORTS,
    parameter int                     unsigned               MaxMstTrans                        = 4,
    parameter int                     unsigned               MaxSlvTrans                        = 4,
    parameter type                                           axi_in_req_t                       = logic,
    parameter type                                           axi_in_resp_t                      = logic,
    parameter type                                           axi_out_req_t                      = logic,
    parameter type                                           axi_out_resp_t                     = logic,
    parameter type                                           impl_in_t                          = logic,
    parameter int                     unsigned               MemoryMacroLatency                 = 1 + RegisterTCDMCuts,
    parameter int                     unsigned               NrSramCfg                          = 1
  ) (
    input  logic                                                          clk_i,
    input  logic                                                          rst_ni,
    input  logic                                                          debug_req_i,
    input  logic                                                          meip_i,
    input  logic                                                          mtip_i,
    input  logic                                                          msip_i,
    input  logic              [9:0]                                       hart_base_id_i,
    input  logic              [TileIDWidth-1:0]                           tile_base_id_i,
    input  axi_addr_t                                                     cluster_base_addr_i,
    input  axi_addr_t                                                     private_start_addr_i,
    // L2 refill FlooNoC links: 4 mesh directions (North=0, East=1, South=2, West=3)
    output floo_cachepool_noc_pkg::floo_req_t [floo_pkg::West:floo_pkg::North] l2_floo_req_o,
    output floo_cachepool_noc_pkg::floo_rsp_t [floo_pkg::West:floo_pkg::North] l2_floo_rsp_o,
    input  floo_cachepool_noc_pkg::floo_req_t [floo_pkg::West:floo_pkg::North] l2_floo_req_i,
    input  floo_cachepool_noc_pkg::floo_rsp_t [floo_pkg::West:floo_pkg::North] l2_floo_rsp_i,
    // Chimney ID and routing table for the L2 refill mesh
    input  floo_cachepool_noc_pkg::id_t                                   l2_floo_id_i,
    input  floo_cachepool_noc_pkg::route_t [floo_pkg::floo_iomsb(
             floo_cachepool_noc_pkg::RouteCfg.NumRoutes):0]               l2_floo_route_table_i,
    output icache_l1_events_t [NrCores-1:0]                               icache_events_o,
    input  logic                                                          icache_prefetch_enable_i,
    input  logic              [NrCores-1:0]                               cl_interrupt_i,
    input  logic              [$clog2(AxiAddrWidth)-1:0]                  dynamic_offset_i,
    input  logic              [$clog2(NumL1CtrlTile):0]                   l1d_private_i,
    input  cache_insn_t                                                   l1d_insn_i,
    input  logic                                                          l1d_insn_valid_i,
    output logic              [NumTilesPerGroup-1:0]                      l1d_insn_ready_o,
    input  logic              [NumTilesPerGroup-1:0]                      l1d_busy_i,
    input  impl_in_t          [NrSramCfg-1:0]                             impl_i,
    output logic                                                          error_o,
    // XY coordinates of this group in the inter-group mesh
    input  group_xy_id_t                                                  group_xy_id_i,
    // Inter-group req mesh: 4 directions (N=0,E=1,S=2,W=3)
    //   dim1: direction, dim2: tile*NumNoCPortsPerTile+channel
    output noc_group_req_t [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_o,
    output logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_valid_o,
    input  logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_ready_i,
    input  noc_group_req_t [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_i,
    input  logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_valid_i,
    output logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_req_ready_o,
    // Inter-group rsp mesh
    output noc_group_rsp_t [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_o,
    output logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_valid_o,
    input  logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_ready_i,
    input  noc_group_rsp_t [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_i,
    input  logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_valid_i,
    output logic           [3:0][NumTilesPerGroup*NumNoCPortsPerTile-1:0] noc_rsp_ready_o,
    // Direct-wire barrier: one bit per tile in this group
    output logic           [NumTilesPerGroup-1:0]                         tile_barrier_o,
    input  logic                                                          barrier_done_i
  );


  // -------------------------------------------------------------------------
  // Localparams
  // -------------------------------------------------------------------------
  localparam int unsigned NumRemoteGroupPortTile  = (NumRemoteGroupPortCore == 0) ? 1
                                                    : NumRemoteGroupPortCore * NrTCDMPortsPerCore;
  localparam int unsigned NumRemoteGroupPortGroup = NumRemoteGroupPortTile * NumTilesPerGroup;
  localparam int unsigned NumNoCPortsGroup        = NumNoCPortsPerTile * NumTilesPerGroup;
  localparam int unsigned SlvXbarSelW             = (NumRemoteGroupPortGroup > 1) ? $clog2(NumRemoteGroupPortGroup) : 1;
  localparam int unsigned MstXbarSelW             = (NumNoCPortsGroup > 1) ? $clog2(NumNoCPortsGroup) : 1;

  // -- Struct / xbar field widths (always >= 1 to avoid zero-width ports) ------
  localparam int unsigned NocCacheBankBits  = $clog2(NrBanks);
  localparam int unsigned NocAddrTileWidth  = (NumTilesPerGroup > 1) ? $clog2(NumTilesPerGroup) : 1;
  // -- Actual bit counts inside dst_tile_id (can be 0 when that dimension = 1) -
  // Flat group_id = gy * NumGroupsX + gx  (row-major, set in cachepool_cluster.sv).
  // dst_tile_id layout: [ group_y (NocGroupBitsY) | group_x (NocGroupBitsX) | local_tile (NocGroupOffset) ]
  // Lower group bits are X, upper group bits are Y.
  localparam int unsigned NocGroupOffset    = $clog2(NumTilesPerGroup);
  localparam int unsigned NocGroupBitsX     = (NumGroupsX > 1) ? $clog2(NumGroupsX) : 0;
  localparam int unsigned NocGroupBitsY     = (NumGroupsY > 1) ? $clog2(NumGroupsY) : 0;


  // -------------------------------------------------------------------------
  // AXI types for L2 mux slave ports
  // ID width = AxiIdWidthOut (matches group internal axi_mst_cache types)
  // Master types come from floo_cachepool_noc_pkg (InIdWidth = AxiIdWidthOut + 1)
  // -------------------------------------------------------------------------
  typedef logic [AxiAddrWidth-1:0]          l2_addr_t;
  typedef logic [AxiIdWidthOut-1:0]         l2_mux_slv_id_t;
  typedef logic [AxiDataWidth-1:0]          l2_data_t;
  typedef logic [AxiDataWidth/8-1:0]        l2_strb_t;
  typedef logic [AxiUserWidth-1:0]          l2_user_t;

  `AXI_TYPEDEF_ALL(l2_axi_mux_slv, l2_addr_t, l2_mux_slv_id_t, l2_data_t, l2_strb_t, l2_user_t)

  // -------------------------------------------------------------------------
  // Group ↔ wrapper boundary signals
  // -------------------------------------------------------------------------
  remote_group_req_t [NumRemoteGroupPortGroup-1:0] remote_group_req_to_group;
  remote_group_rsp_t [NumRemoteGroupPortGroup-1:0] remote_group_rsp_from_group;
  remote_group_req_t [NumRemoteGroupPortGroup-1:0] remote_group_req_from_group;
  remote_group_rsp_t [NumRemoteGroupPortGroup-1:0] remote_group_rsp_to_group;


  // -------------------------------------------------------------------------
  // Mesh signals [tile][ch][dir=3:0] and transposition to/from ports
  // -------------------------------------------------------------------------
  noc_group_req_t [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] req_mesh_out;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] req_mesh_out_valid;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] req_mesh_out_ready;
  noc_group_req_t [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] req_mesh_in;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] req_mesh_in_valid;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] req_mesh_in_ready;

  noc_group_rsp_t [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] rsp_mesh_out;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] rsp_mesh_out_valid;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] rsp_mesh_out_ready;
  noc_group_rsp_t [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] rsp_mesh_in;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] rsp_mesh_in_valid;
  logic           [NumTilesPerGroup-1:0][NumNoCPortsPerTile-1:0][3:0] rsp_mesh_in_ready;

  for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_mesh_trans_t
    for (genvar n = 0; n < NumNoCPortsPerTile; n++) begin : gen_mesh_trans_n
      for (genvar d = 0; d < 4; d++) begin : gen_mesh_trans_d
        // Mute the channel when not valid for debugging
        assign noc_req_o[d][t*NumNoCPortsPerTile+n]        = req_mesh_out_valid[t][n][d] ? req_mesh_out[t][n][d] : '0;
        assign noc_req_valid_o[d][t*NumNoCPortsPerTile+n]  = req_mesh_out_valid[t][n][d];
        assign req_mesh_out_ready[t][n][d]                 = noc_req_ready_i[d][t*NumNoCPortsPerTile+n];
        assign req_mesh_in[t][n][d]                        = noc_req_i[d][t*NumNoCPortsPerTile+n];
        assign req_mesh_in_valid[t][n][d]                  = noc_req_valid_i[d][t*NumNoCPortsPerTile+n];
        assign noc_req_ready_o[d][t*NumNoCPortsPerTile+n]  = req_mesh_in_ready[t][n][d];

        assign noc_rsp_o[d][t*NumNoCPortsPerTile+n]        = rsp_mesh_out_valid[t][n][d] ? rsp_mesh_out[t][n][d] : '0;
        assign noc_rsp_valid_o[d][t*NumNoCPortsPerTile+n]  = rsp_mesh_out_valid[t][n][d];
        assign rsp_mesh_out_ready[t][n][d]                 = noc_rsp_ready_i[d][t*NumNoCPortsPerTile+n];
        assign rsp_mesh_in[t][n][d]                        = noc_rsp_i[d][t*NumNoCPortsPerTile+n];
        assign rsp_mesh_in_valid[t][n][d]                  = noc_rsp_valid_i[d][t*NumNoCPortsPerTile+n];
        assign noc_rsp_ready_o[d][t*NumNoCPortsPerTile+n]  = rsp_mesh_in_ready[t][n][d];
      end
    end
  end


  if (NumRemoteGroupPortCore > 0) begin : gen_noc

    // -----------------------------------------------------------------------
    // Router inject/eject signals (flat 1D index noc_port = t*NumNoCPortsPerTile+n)
    // -----------------------------------------------------------------------
    noc_group_req_t [NumNoCPortsGroup-1:0] packed_req;
    logic           [NumNoCPortsGroup-1:0] packed_req_valid;
    logic           [NumNoCPortsGroup-1:0] packed_req_ready;

    noc_group_req_t [NumNoCPortsGroup-1:0] eject_req;
    logic           [NumNoCPortsGroup-1:0] eject_req_valid;
    logic           [NumNoCPortsGroup-1:0] eject_req_ready;

    noc_group_rsp_t [NumNoCPortsGroup-1:0] inject_rsp;
    logic           [NumNoCPortsGroup-1:0] inject_rsp_valid;
    logic           [NumNoCPortsGroup-1:0] inject_rsp_ready;

    noc_group_rsp_t [NumNoCPortsGroup-1:0] eject_rsp;
    logic           [NumNoCPortsGroup-1:0] eject_rsp_valid;
    logic           [NumNoCPortsGroup-1:0] eject_rsp_ready;

    // Master xbar output (one concentrated req/rsp channel per tile/channel)
    remote_group_req_chan_t [NumNoCPortsGroup-1:0] mst_xbar_req;
    logic                   [NumNoCPortsGroup-1:0] mst_xbar_req_valid;
    logic                   [NumNoCPortsGroup-1:0] mst_xbar_req_ready;

    // Slave xbar signals
    noc_group_req_t [NumRemoteGroupPortGroup-1:0] slv_xbar_mst_req;
    logic           [NumRemoteGroupPortGroup-1:0] slv_xbar_mst_req_valid;
    logic           [NumRemoteGroupPortGroup-1:0] slv_xbar_mst_req_ready;
    noc_group_rsp_t [NumRemoteGroupPortGroup-1:0] slv_xbar_mst_rsp;
    logic           [NumRemoteGroupPortGroup-1:0] slv_xbar_mst_rsp_valid;
    logic           [NumRemoteGroupPortGroup-1:0] slv_xbar_mst_rsp_ready;
    noc_group_rsp_t [NumNoCPortsGroup-1:0] slv_xbar_slv_rsp;
    logic           [NumNoCPortsGroup-1:0] slv_xbar_slv_rsp_valid;
    logic           [NumNoCPortsGroup-1:0] slv_xbar_slv_rsp_ready;

    logic [NumNoCPortsGroup-1:0][SlvXbarSelW-1:0]        slv_xbar_slv_sel;
    logic [NumRemoteGroupPortGroup-1:0][MstXbarSelW-1:0] slv_xbar_mst_sel;


    // -----------------------------------------------------------------------
    // Master-side per-tile concentration xbar + flit packing
    // -----------------------------------------------------------------------
    for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_mst_t

      remote_group_req_chan_t [NumRemoteGroupPortTile-1:0] mst_slv_req;
      logic                   [NumRemoteGroupPortTile-1:0] mst_slv_req_valid;
      logic                   [NumRemoteGroupPortTile-1:0] mst_slv_req_ready;
      remote_group_rsp_chan_t [NumRemoteGroupPortTile-1:0] mst_slv_rsp;
      logic                   [NumRemoteGroupPortTile-1:0] mst_slv_rsp_valid;
      logic                   [NumRemoteGroupPortTile-1:0] mst_slv_rsp_ready;
      remote_group_rsp_chan_t [NumNoCPortsPerTile-1:0]     eject_rsp_payload;
      portid_t                [NumNoCPortsPerTile-1:0]     mst_xbar_mst_sel;
      portid_t                [NumNoCPortsPerTile-1:0]     mst_xbar_slv_selected;

      for (genvar p = 0; p < NumRemoteGroupPortTile; p++) begin : gen_mst_port_p
        assign mst_slv_req[p]       = remote_group_req_from_group[t*NumRemoteGroupPortTile+p].q;
        assign mst_slv_req_valid[p] = remote_group_req_from_group[t*NumRemoteGroupPortTile+p].q_valid;
        assign remote_group_rsp_to_group[t*NumRemoteGroupPortTile+p].q_ready = mst_slv_req_ready[p];
        assign remote_group_rsp_to_group[t*NumRemoteGroupPortTile+p].p       = mst_slv_rsp[p];
        assign remote_group_rsp_to_group[t*NumRemoteGroupPortTile+p].p_valid = mst_slv_rsp_valid[p];
        assign mst_slv_rsp_ready[p] =
          remote_group_req_from_group[t*NumRemoteGroupPortTile+p].p_ready;
      end

      for (genvar n = 0; n < NumNoCPortsPerTile; n++) begin : gen_mst_eject_n
        localparam int unsigned noc_port = t * NumNoCPortsPerTile + n;
        assign eject_rsp_payload[n]  = eject_rsp[noc_port].payload;
        assign mst_xbar_mst_sel[n]   = eject_rsp[noc_port].hdr.src_port_id;
      end

      // Static port-to-NoC-channel mapping: each flat port p has xbar index
      // j = p % NrTCDMPortsPerCore, and is steered to NoC channel j % NumNoCPortsPerTile.
      // Spatz ports (j=0..NrTCDMPortsPerCore-2) divide evenly across channels;
      // Snitch (j=NrTCDMPortsPerCore-1) maps by the same modulo.
      localparam int unsigned NocMstSelWidth = (NumNoCPortsPerTile > 1)
                                               ? $clog2(NumNoCPortsPerTile) : 1;
      logic [NumRemoteGroupPortTile-1:0][NocMstSelWidth-1:0] noc_mst_sel;
      for (genvar p = 0; p < NumRemoteGroupPortTile; p++) begin : gen_noc_mst_sel
        assign noc_mst_sel[p] = NocMstSelWidth'((p % NrTCDMPortsPerCore) % NumNoCPortsPerTile);
      end

      reqrsp_xbar #(
        .NumInp          ( NumRemoteGroupPortTile   ),
        .NumOut          ( NumNoCPortsPerTile       ),
        .tcdm_req_chan_t ( remote_group_req_chan_t  ),
        .tcdm_rsp_chan_t ( remote_group_rsp_chan_t  )
      ) i_noc_mst_xbar (
        .clk_i,
        .rst_ni,
        .slv_req_i       ( mst_slv_req                                ),
        .slv_rr_i        ( '0                                         ),
        .slv_req_valid_i ( mst_slv_req_valid                          ),
        .slv_req_ready_o ( mst_slv_req_ready                          ),
        .slv_rsp_o       ( mst_slv_rsp                                ),
        .slv_rsp_valid_o ( mst_slv_rsp_valid                          ),
        .slv_rsp_ready_i ( mst_slv_rsp_ready                          ),
        .slv_sel_i       ( noc_mst_sel                                ),
        .slv_selected_o  ( mst_xbar_slv_selected                      ),
        .mst_req_o       ( mst_xbar_req[t*NumNoCPortsPerTile +:
                                        NumNoCPortsPerTile]           ),
        .mst_req_valid_o ( mst_xbar_req_valid[t*NumNoCPortsPerTile +:
                                              NumNoCPortsPerTile]     ),
        .mst_req_ready_i ( mst_xbar_req_ready[t*NumNoCPortsPerTile +:
                                              NumNoCPortsPerTile]     ),
        .mst_rsp_i       ( eject_rsp_payload                          ),
        .mst_rr_i        ( '0                                         ),
        .mst_rsp_valid_i ( eject_rsp_valid[t*NumNoCPortsPerTile +:
                                           NumNoCPortsPerTile]        ),
        .mst_rsp_ready_o ( eject_rsp_ready[t*NumNoCPortsPerTile +:
                                           NumNoCPortsPerTile]        ),
        .mst_sel_i       ( mst_xbar_mst_sel                           )
      );

      for (genvar n = 0; n < NumNoCPortsPerTile; n++) begin : gen_pack_n
        localparam int unsigned noc_port = t * NumNoCPortsPerTile + n;
        assign packed_req[noc_port].hdr.collective_op   = '0;
        assign packed_req[noc_port].hdr.src_id          = group_xy_id_i;
        // Flat group_id = gy * NumGroupsX + gx (row-major), so in the
        // dst_tile_id bit field the lower group bits are X and the upper are Y:
        //   dst_tile_id = [ gy (NocGroupBitsY) | gx (NocGroupBitsX) | local_tile ]
        if (NumGroupsX > 1) begin : gen_dst_x
          assign packed_req[noc_port].hdr.dst_id.x =
            mst_xbar_req[noc_port].user.dst_tile_id[NocGroupOffset +: NocGroupBitsX];
        end else begin : gen_dst_x
          assign packed_req[noc_port].hdr.dst_id.x = '0;
        end
        if (NumGroupsY > 1) begin : gen_dst_y
          assign packed_req[noc_port].hdr.dst_id.y =
            mst_xbar_req[noc_port].user.dst_tile_id[(NocGroupOffset + NocGroupBitsX) +: NocGroupBitsY];
        end else begin : gen_dst_y
          assign packed_req[noc_port].hdr.dst_id.y = '0;
        end
        assign packed_req[noc_port].hdr.dst_id.port_id  = '0;
        assign packed_req[noc_port].hdr.src_tile_id     = group_tile_sel_t'(t);
        assign packed_req[noc_port].hdr.src_port_id     = mst_xbar_slv_selected[n];
        assign packed_req[noc_port].hdr.last            = 1'b1;
        assign packed_req[noc_port].payload             = mst_xbar_req[noc_port];
        assign packed_req_valid[noc_port]               = mst_xbar_req_valid[noc_port];
        assign mst_xbar_req_ready[noc_port]             = packed_req_ready[noc_port];

      end

    end : gen_mst_t


    // -----------------------------------------------------------------------
    // Per-tile per-channel req floo_router
    // -----------------------------------------------------------------------
    for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_req_router_t
      for (genvar n = 0; n < NumNoCPortsPerTile; n++) begin : gen_req_router_n
        localparam int unsigned noc_port = t * NumNoCPortsPerTile + n;
        floo_router #(
          .NumRoutes       ( 5                    ),
          .NumVirtChannels ( 1                    ),
          .NumPhysChannels ( 1                    ),
          .InFifoDepth     ( 2                    ),
          .OutFifoDepth    ( 0                    ),
          .RouteAlgo       ( XYRouting            ),
          .IdWidth         ( $bits(group_xy_id_t) ),
          .id_t            ( group_xy_id_t        ),
          .NumAddrRules    ( 1                    ),
          .addr_rule_t     ( logic                ),
          .flit_t          ( noc_group_req_t      ),
          .hdr_t           ( noc_group_hdr_t      )
        ) i_req_router (
          .clk_i,
          .rst_ni,
          .test_enable_i  ( 1'b0                            ),
          .xy_id_i        ( group_xy_id_i                   ),
          .id_route_map_i ( '0                              ),
          .valid_i        ( {packed_req_valid[noc_port],
                             req_mesh_in_valid[t][n][3:0]}  ),
          .ready_o        ( {packed_req_ready[noc_port],
                             req_mesh_in_ready[t][n][3:0]}  ),
          .data_i         ( {packed_req[noc_port],
                             req_mesh_in[t][n][3:0]}        ),
          .credit_o       (                                 ),
          .valid_o        ( {eject_req_valid[noc_port],
                             req_mesh_out_valid[t][n][3:0]} ),
          .ready_i        ( {eject_req_ready[noc_port],
                             req_mesh_out_ready[t][n][3:0]} ),
          .data_o         ( {eject_req[noc_port],
                             req_mesh_out[t][n][3:0]}       ),
          .credit_i       ( '1                              ),
          .offload_req_o  (                                 ),
          .offload_rsp_i  ( '0                              )
        );
      end
    end


    // -----------------------------------------------------------------------
    // Per-tile per-channel rsp floo_router
    // -----------------------------------------------------------------------
    for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_rsp_router_t
      for (genvar n = 0; n < NumNoCPortsPerTile; n++) begin : gen_rsp_router_n
        localparam int unsigned noc_port = t * NumNoCPortsPerTile + n;
        floo_router #(
          .NumRoutes       ( 5                    ),
          .NumVirtChannels ( 1                    ),
          .NumPhysChannels ( 1                    ),
          .InFifoDepth     ( 2                    ),
          .OutFifoDepth    ( 0                    ),
          .RouteAlgo       ( XYRouting            ),
          .IdWidth         ( $bits(group_xy_id_t) ),
          .id_t            ( group_xy_id_t        ),
          .NumAddrRules    ( 1                    ),
          .addr_rule_t     ( logic                ),
          .flit_t          ( noc_group_rsp_t      ),
          .hdr_t           ( noc_group_hdr_t      )
        ) i_rsp_router (
          .clk_i,
          .rst_ni,
          .test_enable_i  ( 1'b0                            ),
          .xy_id_i        ( group_xy_id_i                   ),
          .id_route_map_i ( '0                              ),
          .valid_i        ( {inject_rsp_valid[noc_port],
                             rsp_mesh_in_valid[t][n][3:0]}  ),
          .ready_o        ( {inject_rsp_ready[noc_port],
                             rsp_mesh_in_ready[t][n][3:0]}  ),
          .data_i         ( {inject_rsp[noc_port],
                             rsp_mesh_in[t][n][3:0]}        ),
          .credit_o       (                                 ),
          .valid_o        ( {eject_rsp_valid[noc_port],
                             rsp_mesh_out_valid[t][n][3:0]} ),
          .ready_i        ( {eject_rsp_ready[noc_port],
                             rsp_mesh_out_ready[t][n][3:0]} ),
          .data_o         ( {eject_rsp[noc_port],
                             rsp_mesh_out[t][n][3:0]}       ),
          .credit_i       ( '1                              ),
          .offload_req_o  (                                 ),
          .offload_rsp_i  ( '0                              )
        );
      end
    end


    // -----------------------------------------------------------------------
    // Slave xbar selection signals + inject_rsp ↔ slv_xbar_slv_rsp
    // -----------------------------------------------------------------------
    for (genvar noc_port = 0; noc_port < NumNoCPortsGroup; noc_port++) begin : gen_slv_sel
      assign slv_xbar_slv_sel[noc_port] = (NumTilesPerGroup == 1)
        ? SlvXbarSelW'(eject_req[noc_port].hdr.src_port_id)
        : SlvXbarSelW'(eject_req[noc_port].payload.addr[(dynamic_offset_i + NocCacheBankBits) +: NocAddrTileWidth]
                     * NumRemoteGroupPortTile
                     + eject_req[noc_port].hdr.src_port_id);

    end

    assign inject_rsp             = slv_xbar_slv_rsp;
    assign inject_rsp_valid       = slv_xbar_slv_rsp_valid;
    assign slv_xbar_slv_rsp_ready = inject_rsp_ready;


    // -----------------------------------------------------------------------
    // Slave-side group-wide dispatch xbar
    // -----------------------------------------------------------------------
    reqrsp_xbar #(
      .NumInp          ( NumNoCPortsGroup       ),
      .NumOut          ( NumRemoteGroupPortGroup),
      .tcdm_req_chan_t ( noc_group_req_t        ),
      .tcdm_rsp_chan_t ( noc_group_rsp_t        )
    ) i_noc_slv_xbar (
      .clk_i,
      .rst_ni,
      .slv_req_i       ( eject_req              ),
      .slv_rr_i        ( '0                     ),
      .slv_req_valid_i ( eject_req_valid        ),
      .slv_req_ready_o ( eject_req_ready        ),
      .slv_rsp_o       ( slv_xbar_slv_rsp       ),
      .slv_rsp_valid_o ( slv_xbar_slv_rsp_valid ),
      .slv_rsp_ready_i ( slv_xbar_slv_rsp_ready ),
      .slv_sel_i       ( slv_xbar_slv_sel       ),
      .slv_selected_o  (                        ),
      .mst_req_o       ( slv_xbar_mst_req       ),
      .mst_req_valid_o ( slv_xbar_mst_req_valid ),
      .mst_req_ready_i ( slv_xbar_mst_req_ready ),
      .mst_rsp_i       ( slv_xbar_mst_rsp       ),
      .mst_rr_i        ( '0                     ),
      .mst_rsp_valid_i ( slv_xbar_mst_rsp_valid ),
      .mst_rsp_ready_o ( slv_xbar_mst_rsp_ready ),
      .mst_sel_i       ( slv_xbar_mst_sel       )
    );


    // -----------------------------------------------------------------------
    // Slave delivery: unpack xbar output → group slave ports + rsp packing
    // -----------------------------------------------------------------------
    for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_slv_deliver_t
      for (genvar p = 0; p < NumRemoteGroupPortTile; p++) begin : gen_slv_deliver_p
        localparam int unsigned port = t * NumRemoteGroupPortTile + p;

        // Placeholder response routing: route response back via the NoC channel
        // of the same tile (t). Correct cross-tile response routing is deferred.
        assign slv_xbar_mst_sel[port] = MstXbarSelW'(t * NumNoCPortsPerTile);

        always_comb begin : proc_req_unpack
          remote_group_req_to_group[port].q                  = slv_xbar_mst_req[port].payload;
          remote_group_req_to_group[port].q.user.src_group_x =
            slv_xbar_mst_req[port].hdr.src_id.x;
          remote_group_req_to_group[port].q.user.src_group_y =
            slv_xbar_mst_req[port].hdr.src_id.y;
        end

        assign remote_group_req_to_group[port].q_valid    = slv_xbar_mst_req_valid[port];
        assign slv_xbar_mst_req_ready[port]               =
          remote_group_rsp_from_group[port].q_ready;
        assign remote_group_req_to_group[port].p_ready    = slv_xbar_mst_rsp_ready[port];


        assign slv_xbar_mst_rsp[port].payload             =
          remote_group_rsp_from_group[port].p;
        assign slv_xbar_mst_rsp[port].hdr.collective_op   = '0;
        assign slv_xbar_mst_rsp[port].hdr.src_id          = group_xy_id_i;
        // Row-major: lower group bits are X, upper are Y
        if (NumGroupsX > 1) begin : gen_rsp_dst_x
          assign slv_xbar_mst_rsp[port].hdr.dst_id.x      =
            remote_group_rsp_from_group[port].p.user.tile_id[NocGroupOffset +: NocGroupBitsX];
        end else begin : gen_rsp_dst_x
          assign slv_xbar_mst_rsp[port].hdr.dst_id.x      = '0;
        end
        if (NumGroupsY > 1) begin : gen_rsp_dst_y
          assign slv_xbar_mst_rsp[port].hdr.dst_id.y      =
            remote_group_rsp_from_group[port].p.user.tile_id[(NocGroupOffset + NocGroupBitsX) +: NocGroupBitsY];
        end else begin : gen_rsp_dst_y
          assign slv_xbar_mst_rsp[port].hdr.dst_id.y      = '0;
        end
        assign slv_xbar_mst_rsp[port].hdr.dst_id.port_id  = '0;
        assign slv_xbar_mst_rsp[port].hdr.src_tile_id     = group_tile_sel_t'(t);
        assign slv_xbar_mst_rsp[port].hdr.src_port_id     = remote_group_rsp_from_group[port].p.user.port_id;
        assign slv_xbar_mst_rsp[port].hdr.last            = 1'b1;
        assign slv_xbar_mst_rsp_valid[port]               =
          remote_group_rsp_from_group[port].p_valid;
      end
    end


  end else begin : gen_noc_disabled

    assign remote_group_req_to_group = '0;
    assign remote_group_rsp_to_group = '0;
    assign req_mesh_out              = '0;
    assign req_mesh_out_valid        = '0;
    assign req_mesh_in_ready         = '0;
    assign rsp_mesh_out              = '0;
    assign rsp_mesh_out_valid        = '0;
    assign rsp_mesh_in_ready         = '0;

  end


  // -------------------------------------------------------------------------
  // L2 path: reqrsp_to_axi + axi_mux(2:1) → floo_axi_chimney → floo_axi_router
  // -------------------------------------------------------------------------
  // Two AXI streams merged before the chimney:
  //   [0] refill traffic: group l2_req/rsp → reqrsp_to_axi
  //   [1] ICache/peripheral traffic: group l2_axi_req/rsp (stays AXI)
  // The axi_mux adds 1 ID bit ($clog2(2)), so chimney InIdWidth = SlvIdWidth + 1.

  // Internal L2 reqrsp between group and reqrsp_to_axi
  l2_req_t l2_group_req;
  l2_rsp_t l2_group_rsp;

  // Internal L2 AXI from group (ICache/peripheral bypass)
  l2_axi_mux_slv_req_t  l2_group_axi_req;
  l2_axi_mux_slv_resp_t  l2_group_axi_rsp;

  // AXI mux slave-side wires (6-bit ID, before mux prepends 1 bit)
  l2_axi_mux_slv_req_t  [1:0] l2_mux_slv_req;
  l2_axi_mux_slv_resp_t  [1:0] l2_mux_slv_rsp;

  // Chimney AXI wires (InIdWidth bit ID, after mux)
  floo_cachepool_noc_pkg::axi_wide_in_req_t l2_chimney_axi_req;
  floo_cachepool_noc_pkg::axi_wide_in_rsp_t l2_chimney_axi_rsp;

  // Router ↔ chimney floo links [Eject:North]
  floo_cachepool_noc_pkg::floo_req_t [floo_pkg::Eject:floo_pkg::North] l2_router_req_in;
  floo_cachepool_noc_pkg::floo_req_t [floo_pkg::Eject:floo_pkg::North] l2_router_req_out;
  floo_cachepool_noc_pkg::floo_rsp_t [floo_pkg::Eject:floo_pkg::North] l2_router_rsp_in;
  floo_cachepool_noc_pkg::floo_rsp_t [floo_pkg::Eject:floo_pkg::North] l2_router_rsp_out;

  // reqrsp_to_axi: convert l2 refill reqrsp to AXI (mux slave [0])
  reqrsp_to_axi #(
    .MaxTrans           ( NumSpatzOutstandingLoads * 2  ),
    .ID                 ( '0                            ),
    .EnBurst            ( 1                             ),
    .ShuffleId          ( 1                             ),
    .UserWidth          ( $bits(refill_user_t)          ),
    .ReqUserFallThrough ( 1'b0                          ),
    .DataWidth          ( AxiDataWidth                  ),
    .AxiUserWidth       ( AxiUserWidth                  ),
    .reqrsp_req_t       ( l2_req_t                      ),
    .reqrsp_rsp_t       ( l2_rsp_t                      ),
    .axi_req_t          ( l2_axi_mux_slv_req_t          ),
    .axi_rsp_t          ( l2_axi_mux_slv_resp_t         )
  ) i_l2_reqrsp2axi (
    .clk_i              ( clk_i                         ),
    .rst_ni             ( rst_ni                        ),
    .user_i             ( l2_group_req.q.user           ),
    .reqrsp_req_i       ( l2_group_req                  ),
    .reqrsp_rsp_o       ( l2_group_rsp                  ),
    .axi_req_o          ( l2_mux_slv_req[0]             ),
    .axi_rsp_i          ( l2_mux_slv_rsp[0]             )
  );

  // ICache/peripheral AXI from group (mux slave [1])
  // Scramble DRAM addresses so they match the refill path's scrambled layout.
  // Peripheral/bootrom addresses are left unscrambled — the top 2 address bits
  // are preserved by scrambleAddr, so scrambled DRAM (10xx) never overlaps
  // with peripheral (11xx) or low (00xx) ranges.
  always_comb begin
    l2_mux_slv_req[1] = l2_group_axi_req;
    if (l2_group_axi_req.ar.addr >= DramAddr &&
        l2_group_axi_req.ar.addr <  DramAddr + DramSize)
      l2_mux_slv_req[1].ar.addr = scrambleAddr(l2_group_axi_req.ar.addr);
    if (l2_group_axi_req.aw.addr >= DramAddr &&
        l2_group_axi_req.aw.addr <  DramAddr + DramSize)
      l2_mux_slv_req[1].aw.addr = scrambleAddr(l2_group_axi_req.aw.addr);
  end
  assign l2_group_axi_rsp = l2_mux_slv_rsp[1];

  // 2:1 AXI mux: merges refill and ICache/peripheral streams before chimney
  axi_mux #(
    .SlvAxiIDWidth ( AxiIdWidthOut                                        ),
    .slv_aw_chan_t ( l2_axi_mux_slv_aw_chan_t                             ),
    .mst_aw_chan_t ( floo_cachepool_noc_pkg::axi_wide_in_aw_chan_t        ),
    .w_chan_t      ( l2_axi_mux_slv_w_chan_t                              ),
    .slv_b_chan_t  ( l2_axi_mux_slv_b_chan_t                              ),
    .mst_b_chan_t  ( floo_cachepool_noc_pkg::axi_wide_in_b_chan_t         ),
    .slv_ar_chan_t ( l2_axi_mux_slv_ar_chan_t                             ),
    .mst_ar_chan_t ( floo_cachepool_noc_pkg::axi_wide_in_ar_chan_t        ),
    .slv_r_chan_t  ( l2_axi_mux_slv_r_chan_t                              ),
    .mst_r_chan_t  ( floo_cachepool_noc_pkg::axi_wide_in_r_chan_t         ),
    .slv_req_t     ( l2_axi_mux_slv_req_t                                 ),
    .slv_resp_t    ( l2_axi_mux_slv_resp_t                                ),
    .mst_req_t     ( floo_cachepool_noc_pkg::axi_wide_in_req_t            ),
    .mst_resp_t    ( floo_cachepool_noc_pkg::axi_wide_in_rsp_t            ),
    .NoSlvPorts    ( 2                                                    ),
    .MaxWTrans     ( 4                                                    )
  ) i_l2_axi_mux (
    .clk_i       ( clk_i              ),
    .rst_ni      ( rst_ni             ),
    .test_i      ( 1'b0               ),
    .slv_reqs_i  ( l2_mux_slv_req     ),
    .slv_resps_o ( l2_mux_slv_rsp     ),
    .mst_req_o   ( l2_chimney_axi_req ),
    .mst_resp_i  ( l2_chimney_axi_rsp )
  );


  // Manager-only chimney: injects merged L2 traffic into mesh
  floo_axi_chimney #(
    .AxiCfg       ( floo_cachepool_noc_pkg::AxiCfg                        ),
    .ChimneyCfg   ( floo_pkg::set_ports(floo_pkg::ChimneyDefaultCfg,
                      1'b0, 1'b1)                                         ),
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
    .axi_in_req_t ( floo_cachepool_noc_pkg::axi_wide_in_req_t             ),
    .axi_in_rsp_t ( floo_cachepool_noc_pkg::axi_wide_in_rsp_t             ),
    .axi_out_req_t( floo_cachepool_noc_pkg::axi_wide_out_req_t            ),
    .axi_out_rsp_t( floo_cachepool_noc_pkg::axi_wide_out_rsp_t            ),
    .floo_req_t   ( floo_cachepool_noc_pkg::floo_req_t                    ),
    .floo_rsp_t   ( floo_cachepool_noc_pkg::floo_rsp_t                    )
  ) i_l2_chimney (
    .clk_i          ( clk_i                                               ),
    .rst_ni         ( rst_ni                                              ),
    .test_enable_i  ( 1'b0                                                ),
    .sram_cfg_i     ( '0                                                  ),
    .axi_in_req_i   ( l2_chimney_axi_req                                  ),
    .axi_in_rsp_o   ( l2_chimney_axi_rsp                                  ),
    .axi_out_req_o  (                                                     ),
    .axi_out_rsp_i  ( '0                                                  ),
    .id_i           ( l2_floo_id_i                                        ),
    .route_table_i  ( l2_floo_route_table_i                               ),
    // Chimney connects to router Eject port
    .floo_req_o     ( l2_router_req_in [floo_pkg::Eject]                  ),
    .floo_rsp_o     ( l2_router_rsp_in [floo_pkg::Eject]                  ),
    .floo_req_i     ( l2_router_req_out[floo_pkg::Eject]                  ),
    .floo_rsp_i     ( l2_router_rsp_out[floo_pkg::Eject]                  )
  );

  // L2 refill mesh router (source-routing, 5 ports: N/E/S/W/Eject)
  floo_axi_router #(
    .AxiCfg       ( floo_cachepool_noc_pkg::AxiCfg                        ),
    .RouteAlgo    ( floo_cachepool_noc_pkg::RouteCfg.RouteAlgo            ),
    .NumRoutes    ( 5                                                     ),
    .InFifoDepth  ( 2                                                     ),
    .OutFifoDepth ( 2                                                     ),
    .id_t         ( floo_cachepool_noc_pkg::id_t                          ),
    .hdr_t        ( floo_cachepool_noc_pkg::hdr_t                         ),
    .floo_req_t   ( floo_cachepool_noc_pkg::floo_req_t                    ),
    .floo_rsp_t   ( floo_cachepool_noc_pkg::floo_rsp_t                    )
  ) i_l2_router (
    .clk_i          ( clk_i                                               ),
    .rst_ni         ( rst_ni                                              ),
    .test_enable_i  ( 1'b0                                                ),
    .id_i           ( '0                                                  ),
    .id_route_map_i ( '0                                                  ),
    .floo_req_i     ( l2_router_req_in                                    ),
    .floo_rsp_i     ( l2_router_rsp_in                                    ),
    .floo_req_o     ( l2_router_req_out                                   ),
    .floo_rsp_o     ( l2_router_rsp_out                                   )
  );

  // Expose [West:North] router ports to cluster for mesh wiring
  assign l2_floo_req_o = l2_router_req_out[floo_pkg::West:floo_pkg::North];
  assign l2_floo_rsp_o = l2_router_rsp_out[floo_pkg::West:floo_pkg::North];
  assign l2_router_req_in[floo_pkg::West:floo_pkg::North] = l2_floo_req_i;
  assign l2_router_rsp_in[floo_pkg::West:floo_pkg::North] = l2_floo_rsp_i;

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
    .axi_out_req_t            ( axi_out_req_t            ),
    .axi_out_resp_t           ( axi_out_resp_t           ),
    .l2_axi_req_t             ( l2_axi_mux_slv_req_t     ),
    .l2_axi_rsp_t             ( l2_axi_mux_slv_resp_t    ),
    .RegisterOffloadRsp       ( RegisterOffloadRsp       ),
    .RegisterCoreReq          ( RegisterCoreReq          ),
    .RegisterCoreRsp          ( RegisterCoreRsp          ),
    .RegisterTCDMCuts         ( RegisterTCDMCuts         ),
    .RegisterExt              ( RegisterExt              ),
    .XbarLatency              ( XbarLatency              ),
    .MaxMstTrans              ( MaxMstTrans              ),
    .MaxSlvTrans              ( MaxSlvTrans              )
  ) i_group (
    .clk_i,
    .rst_ni,
    .impl_i                   ( impl_i                   ),
    .error_o                  ( error_o                  ),
    .debug_req_i              ( debug_req_i              ),
    .meip_i                   ( meip_i                   ),
    .mtip_i                   ( mtip_i                   ),
    .msip_i                   ( msip_i                   ),
    .hart_base_id_i           ( hart_base_id_i           ),
    .tile_base_id_i           ( tile_base_id_i           ),
    .cluster_base_addr_i      ( cluster_base_addr_i      ),
    .private_start_addr_i     ( private_start_addr_i     ),
    .l2_req_o                 ( l2_group_req              ),
    .l2_rsp_i                 ( l2_group_rsp              ),
    .l2_axi_req_o             ( l2_group_axi_req          ),
    .l2_axi_rsp_i             ( l2_group_axi_rsp          ),
    .remote_group_req_o       ( remote_group_req_from_group ),
    .remote_group_rsp_i       ( remote_group_rsp_to_group   ),
    .remote_group_req_i       ( remote_group_req_to_group   ),
    .remote_group_rsp_o       ( remote_group_rsp_from_group ),
    .tile_barrier_o           ( tile_barrier_o             ),
    .barrier_done_i           ( barrier_done_i             ),
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
