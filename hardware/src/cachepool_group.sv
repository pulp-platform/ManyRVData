// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "axi/typedef.svh"
`include "common_cells/registers.svh"
`include "register_interface/typedef.svh"

/// Group implementation for CachePool
module cachepool_group
  import cachepool_pkg::*;
  import spatz_pkg::*;
  import fpnew_pkg::fpu_implementation_t;
  import snitch_pma_pkg::snitch_pma_t;
  import snitch_icache_pkg::icache_l1_events_t;
  #(
    /// Width of physical address.
    parameter int unsigned                              AxiAddrWidth              = 48,
    /// Width of AXI port.
    parameter int unsigned                              AxiDataWidth              = 512,
    /// AXI: id width in.
    parameter int unsigned                              AxiIdWidthIn              = 2,
    /// AXI: id width out.
    parameter int unsigned                              AxiIdWidthOut             = 2,
    /// AXI: user width.
    parameter int unsigned                              AxiUserWidth              = 1,
    /// Address from which to fetch the first instructions.
    parameter logic                              [31:0] BootAddr                  = 32'h0,
    /// Address to indicate start of UART
    parameter logic                              [31:0] UartAddr                  = 32'h0,
    /// The total amount of cores.
    parameter int unsigned                              NrCores                   = 8,
    /// Data/TCDM memory depth per cut (in words).
    parameter int unsigned                              TCDMDepth                 = 1024,
    /// Cluster peripheral address region size (in kB).
    parameter int unsigned                              ClusterPeriphSize         = 64,
    /// Number of TCDM Banks.
    parameter int unsigned                              NrBanks                   = 2 * NrCores,
    /// Width of a single icache line.
    parameter     unsigned                              ICacheLineWidth           = 0,
    /// Number of icache lines per set.
    parameter int unsigned                              ICacheLineCount           = 0,
    /// Number of icache sets.
    parameter int unsigned                              ICacheSets                = 0,
    parameter snitch_pma_t                              SnitchPMACfg              = '{default: 0},
    /// # Core-global parameters
    /// FPU configuration.
    parameter fpu_implementation_t                      FPUImplementation         = fpu_implementation_t'(0),
    /// Spatz FPU/IPU Configuration
    parameter int unsigned                              NumSpatzFPUs              = 4,
    parameter int unsigned                              NumSpatzIPUs              = 1,
    /// # Per-core parameters
    /// Per-core integer outstanding loads
    parameter int unsigned                              NumIntOutstandingLoads    = 0,
    /// Per-core integer outstanding memory operations (load and stores)
    parameter int unsigned                              NumIntOutstandingMem      = 0,
    /// Per-core Spatz outstanding loads
    parameter int unsigned                              NumSpatzOutstandingLoads  = 0,
    /// ## Timing Tuning Parameters
    /// Insert Pipeline registers into off-loading path (response)
    parameter bit                                       RegisterOffloadRsp        = 1'b0,
    /// Insert Pipeline registers into data memory path (request)
    parameter bit                                       RegisterCoreReq           = 1'b0,
    /// Insert Pipeline registers into data memory path (response)
    parameter bit                                       RegisterCoreRsp           = 1'b0,
    /// Insert Pipeline registers after each memory cut
    parameter bit                                       RegisterTCDMCuts          = 1'b0,
    /// Decouple external AXI plug
    parameter bit                                       RegisterExt               = 1'b0,
    parameter axi_pkg::xbar_latency_e                   XbarLatency               = axi_pkg::CUT_ALL_PORTS,
    /// Outstanding transactions on the AXI network
    parameter int unsigned                              MaxMstTrans               = 4,
    parameter int unsigned                              MaxSlvTrans               = 4,
    /// # Interface
    /// AXI Ports
    parameter type                                      axi_in_req_t              = logic,
    parameter type                                      axi_in_resp_t             = logic,
    parameter type                                      axi_narrow_req_t          = logic,
    parameter type                                      axi_narrow_resp_t         = logic,
    parameter type                                      axi_out_req_t             = logic,
    parameter type                                      axi_out_resp_t            = logic,
    /// SRAM configuration
    parameter type                                      impl_in_t                 = logic,
    // Memory latency parameter. Most of the memories have a read latency of 1. In
    // case you have memory macros which are pipelined you want to adjust this
    // value here. This only applies to the TCDM. The instruction cache macros will break!
    // In case you are using the `RegisterTCDMCuts` feature this adds an
    // additional cycle latency, which is taken into account here.
    parameter int unsigned                              MemoryMacroLatency        = 1 + RegisterTCDMCuts,
    /// # SRAM Configuration rules needed: L1D Tag + L1D Data + L1D FIFO + L1I Tag + L1I Data
    /*** ATTENTION: `NrSramCfg` should be changed if `L1NumDataBank` and `L1NumTagBank` is changed ***/
    parameter int unsigned                              NrSramCfg                 = 1,
    /// Folded data bank configuration (0 = auto: min(4, L1AssoPerCtrl)).
    parameter bit                                       UseFoldedDataBanks        = 1'b1,
    parameter int unsigned                              FoldWayGroup              = 0,
    /// Use hash-based way selection (1 way per lookup, no LRU).
    parameter bit                                       UseHashWaySelect          = 1'b1,
    /// Enable the SRAM forwarding buffer (default on; requires UseHashWaySelect).
    parameter bit                                       UseForwardingBuffer       = 1'b1,

    localparam int unsigned                             TotRGPorts                = (NumRemoteGroupPortCore == 0) ? 0 :
                                                                                     NumTilesPerGroup*NumRemoteGroupPortCore*NrTCDMPortsPerCore-1,
    localparam int unsigned                             NumRemoteGroupPortTile    = (NumRemoteGroupPortCore == 0) ? 1 :
                                                                                     NumRemoteGroupPortCore * NrTCDMPortsPerCore
  ) (
    /// System clock.
    input  logic                                        clk_i,
    /// Asynchronous active high reset. This signal is assumed to be _async_.
    input  logic                                        rst_ni,
    /// Per-core debug request signal. Asserting this signals puts the
    /// corresponding core into debug mode. This signal is assumed to be _async_.
    input  logic                                        debug_req_i,
    /// Machine external interrupt pending. Usually those interrupts come from a
    /// platform-level interrupt controller. This signal is assumed to be _async_.
    input  logic                                        meip_i,
    /// Machine timer interrupt pending. Usually those interrupts come from a
    /// core-local interrupt controller such as a timer/RTC. This signal is
    /// assumed to be _async_.
    input  logic                                        mtip_i,
    /// Core software interrupt pending. Usually those interrupts come from
    /// another core to facilitate inter-processor-interrupts. This signal is
    /// assumed to be _async_.
    input  logic                                        msip_i,
    /// First hartid of the cluster. Cores of a cluster are monotonically
    /// increasing without a gap, i.e., a cluster with 8 cores and a
    /// `hart_base_id_i` of 5 get the hartids 5 - 12.
    input  logic                                  [9:0] hart_base_id_i,
    /// Globally-unique tile ID of the first tile in this group (= group_index * NumTilesPerGroup).
    input  logic                      [TileIDWidth-1:0] tile_base_id_i,
    /// Base address of cluster. TCDM and cluster peripheral location are derived from
    /// it. This signal is pseudo-static.
    input  axi_addr_t                                   cluster_base_addr_i,
    /// Partitioning address
    input  axi_addr_t                                   private_start_addr_i,
    /// L2 refill reqrsp port (single merged output: cache refill + iCache/peripheral)
    output l2_req_t                                     l2_req_o,
    input  l2_rsp_t                                     l2_rsp_i,
    /// This group's L2 refill mesh floo endpoint ID. Stamped into
    /// refill_user_t.l2_src_id on every outgoing L2 request so the HBM
    /// ejection chimney can route responses back without a local src_id
    /// FIFO (which assumed in-order HBM completion).
    input  floo_cachepool_noc_pkg::id_t                 l2_group_id_i,

    /// Peripheral signals
    output icache_l1_events_t             [NrCores-1:0] icache_events_o,
    input  logic                                        icache_prefetch_enable_i,
    input  logic                          [NrCores-1:0] cl_interrupt_i,
    input  logic             [$clog2(AxiAddrWidth)-1:0] dynamic_offset_i,
    input  logic              [$clog2(NumL1CtrlTile):0] l1d_private_i,
    input  cache_insn_t                                 l1d_insn_i,
    input  logic                                        l1d_insn_valid_i,
    output logic                 [NumTilesPerGroup-1:0] l1d_insn_ready_o,
    input  logic                 [NumTilesPerGroup-1:0] l1d_busy_i,

    /// Inter-group remote access ports (to other groups).
    /// Layout: [NumTilesPerGroup-1:0][NumRemoteGroupPortTile-1:0] flattened to
    /// [NumTilesPerGroup * NumRemoteGroupPortTile - 1 : 0].
    /// Per-tile flat index: j + r * NrTCDMPortsPerCore (j = interco instance,
    /// r = inter-group slot within that instance).
    /// NumRemoteGroupPortTile = NumRemoteGroupPortCore * NrTCDMPortsPerCore.
    /// Uses REQRSP-style types with built-in ready and remote_group_user_t.
    output remote_group_req_t            [TotRGPorts:0] remote_group_req_o,
    input  remote_group_rsp_t            [TotRGPorts:0] remote_group_rsp_i,
    /// Inter-group remote access ports (from other groups)
    input  remote_group_req_t            [TotRGPorts:0] remote_group_req_i,
    output remote_group_rsp_t            [TotRGPorts:0] remote_group_rsp_o,

    // Direct-wire barrier: one bit per tile
    output logic                 [NumTilesPerGroup-1:0] tile_barrier_o,
    input  logic                                        barrier_done_i,

    /// SRAM Configuration
    input  impl_in_t                    [NrSramCfg-1:0] impl_i,
    /// Indicate the program execution is error
    output logic                                        error_o
  );


  // ---------
  // Imports
  // ---------
  import snitch_pkg::*;

  // ---------
  // Constants
  // ---------
  // Per-group overrides of package-level constants that depend on NumTiles/NumCores.
  localparam int unsigned NumL1CacheCtrlLocal  = NrCores;

  localparam int unsigned WideIdWidthIn   = AxiIdWidthOut;


  // --------
  // Typedefs
  // --------
  typedef logic [AxiAddrWidth-1:0]      addr_t;
  typedef logic [AxiDataWidth-1:0]      data_cache_t;
  typedef logic [AxiDataWidth/8-1:0]    strb_cache_t;
  typedef logic [WideIdWidthIn-1:0]     id_cache_mst_t;
  typedef logic [AxiUserWidth-1:0]      user_cache_t;

  `AXI_TYPEDEF_ALL(axi_mst_cache, addr_t, id_cache_mst_t, data_cache_t, strb_cache_t, user_cache_t)

  typedef struct packed {
    int unsigned idx;
    addr_t start_addr;
    addr_t end_addr;
  } xbar_rule_t;

  // ---------------
  // CachePool Tile
  // ---------------

  logic [NumTilesPerGroup-1:0] error;
  assign error_o = |error;

  // Per-tile iCache AXI (single port, BootROM moved to cluster level)
  axi_mst_cache_req_t  [NumTilesPerGroup-1:0] axi_tile_mem_req;
  axi_mst_cache_resp_t [NumTilesPerGroup-1:0] axi_tile_mem_rsp;

  // Cache refill ports from tiles (NumL1CacheCtrlLocal = NumCores total)
  cache_trans_req_t [NumL1CacheCtrlLocal-1:0] cache_refill_req;
  cache_trans_rsp_t [NumL1CacheCtrlLocal-1:0] cache_refill_rsp;

  // Per-tile peripheral REQRSP (narrow 32b, from tile core mux)
  periph_req_t         [NumTilesPerGroup-1:0] tile_periph_req;
  periph_rsp_t         [NumTilesPerGroup-1:0] tile_periph_rsp;

  // L2 Group ICache AXI master output (from axi_hier_interco)
  axi_mst_cache_req_t  axi_l2icache_mst_req;
  axi_mst_cache_resp_t axi_l2icache_mst_rsp;
  // L2 Group ICache reqrsp output (to refill xbar port 0)
  cache_trans_req_t    cache_l2icache_req;
  cache_trans_rsp_t    cache_l2icache_rsp;
  // L2 Group ICache control (hardwired)
  ro_cache_ctrl_t      l2icache_ctrl;

  // Flat xbar input channels: NumClusterMst ports per tile (1 iCache + NumL1CtrlTile refill)
  cache_trans_req_chan_t [NumTilesPerGroup*NumClusterMst-1:0] tile_req_chan;
  cache_trans_rsp_chan_t [NumTilesPerGroup*NumClusterMst-1:0] tile_rsp_chan;
  logic                  [NumTilesPerGroup*NumClusterMst-1:0] tile_req_valid, tile_req_ready,
                                                              tile_rsp_valid, tile_rsp_ready;

  // Xbar output channel: single merged output (N:1 mux)
  cache_trans_req_chan_t l2_req_chan;
  cache_trans_rsp_chan_t l2_rsp_chan;
  logic                 l2_req_valid, l2_req_ready,
                        l2_rsp_valid, l2_rsp_ready;

  // Response demux selection: which xbar input port does the response target
  typedef logic [$clog2(NumClusterMst*NumTilesPerGroup)-1:0] l2_sel_t;
  l2_sel_t l2_sel;

  // ---------------------
  // L2 Group ICache: 4-to-1 AXI mux + read-only cache + ID remap
  // ---------------------
  always_comb begin
    l2icache_ctrl               = '0;
    l2icache_ctrl.enable        = 1'b1;
    l2icache_ctrl.flush_valid   = 1'b0;
    // Rule 0: DRAM range
    l2icache_ctrl.start_addr[0] = DramAddr;
    l2icache_ctrl.end_addr[0]   = DramAddr + DramSize;
    // Rule 1: BootROM range — routes through Cache path, not Bypass,
    // to avoid axi_mux MSB ID corruption in snitch_read_only_cache
    l2icache_ctrl.start_addr[1] = BootAddr;
    l2icache_ctrl.end_addr[1]   = BootAddr + 'h1000;
  end

  axi_hier_interco #(
    .NumSlvPorts    ( NumTilesPerGroup      ),
    .NumMstPorts    ( 1                     ),
    .Radix          ( NumTilesPerGroup      ),
    .EnableCache    ( 1                     ),
    .CacheLineWidth ( L2ICacheLineWidth     ),
    .CacheSizeByte  ( L2ICacheSizeByte      ),
    .CacheSets      ( L2ICacheSets          ),
    .AddrWidth      ( AxiAddrWidth          ),
    .DataWidth      ( AxiDataWidth          ),
    .SlvIdWidth     ( WideIdWidthIn         ),
    .MstIdWidth     ( WideIdWidthIn         ),
    .UserWidth      ( AxiUserWidth          ),
    .slv_req_t      ( axi_mst_cache_req_t   ),
    .slv_resp_t     ( axi_mst_cache_resp_t  ),
    .mst_req_t      ( axi_mst_cache_req_t   ),
    .mst_resp_t     ( axi_mst_cache_resp_t  )
  ) i_l2icache_interco (
    .clk_i           ( clk_i                ),
    .rst_ni          ( rst_ni               ),
    .test_i          ( 1'b0                 ),
    .ro_cache_ctrl_i ( l2icache_ctrl        ),
    .slv_req_i       ( axi_tile_mem_req     ),
    .slv_resp_o      ( axi_tile_mem_rsp     ),
    .mst_req_o       ( axi_l2icache_mst_req ),
    .mst_resp_i      ( axi_l2icache_mst_rsp )
  );

  // Convert L2 ICache AXI output to REQRSP for merging into refill xbar
  axi_to_reqrsp #(
    .axi_req_t            ( axi_mst_cache_req_t  ),
    .axi_rsp_t            ( axi_mst_cache_resp_t ),
    .AddrWidth            ( AxiAddrWidth         ),
    .DataWidth            ( AxiDataWidth         ),
    .UserWidth            ( $bits(refill_user_t) ),
    .IdWidth              ( WideIdWidthIn        ),
    .BufDepth             ( 0                    ),
    .EnUserIdPassthrough  ( 1'b1                 ),
    .reqrsp_req_t         ( cache_trans_req_t    ),
    .reqrsp_rsp_t         ( cache_trans_rsp_t    )
  ) i_l2icache_axi2reqrsp (
    .clk_i                ( clk_i                ),
    .rst_ni               ( rst_ni               ),
    .busy_o               (                      ),
    .axi_req_i            ( axi_l2icache_mst_req ),
    .axi_rsp_o            ( axi_l2icache_mst_rsp ),
    .reqrsp_req_o         ( cache_l2icache_req   ),
    .reqrsp_rsp_i         ( cache_l2icache_rsp   )
  );

  // ---------------------
  // Wiring: assemble flat xbar input from refill + peripheral + iCache paths
  // ---------------------
  // Port layout per tile (NumClusterMst = NumL1CtrlTile + 2):
  //   p = 0..NumL1CtrlTile-1  → refill (bank_id = p, set by tile)
  //   p = NumL1CtrlTile       → peripheral (bank_id = BankIdPeriph)
  //   p = NumL1CtrlTile+1     → iCache (bank_id = BankIdICache, only tile 0)
  always_comb begin
    for (int t = 0; t < NumTilesPerGroup; t++) begin
      for (int p = 0; p < NumClusterMst; p++) begin
        automatic int unsigned xbar_idx = t * NumClusterMst + p;

        if (p < NumL1CtrlTile) begin
          // Refill path: p maps directly to cache controller index
          automatic int unsigned refill_idx = t * NumL1CtrlTile + p;
          tile_req_chan  [xbar_idx]                  = cache_refill_req[refill_idx].q;
          tile_req_chan  [xbar_idx].addr             = scrambleAddr(cache_refill_req[refill_idx].q.addr);
          tile_req_valid [xbar_idx]                  = cache_refill_req[refill_idx].q_valid;
          cache_refill_rsp[refill_idx].q_ready       = tile_req_ready[xbar_idx];

          cache_refill_rsp[refill_idx].p             = tile_rsp_chan [xbar_idx];
          cache_refill_rsp[refill_idx].p_valid       = tile_rsp_valid[xbar_idx];
          tile_rsp_ready [xbar_idx]                  = cache_refill_req[refill_idx].p_ready;
          tile_req_chan  [xbar_idx].user.tile_id     = t;
          tile_req_chan  [xbar_idx].user.l2_src_id   = l2_group_id_i;

        end else if (p == BankIdPeriph) begin
          // Peripheral path: narrow REQRSP directly connected (data width mismatch — placeholder)
          tile_req_chan  [xbar_idx]                  = '0;
          tile_req_chan  [xbar_idx].addr             = scrambleAddr(tile_periph_req[t].q.addr);
          tile_req_chan  [xbar_idx].write            = tile_periph_req[t].q.write;
          tile_req_chan  [xbar_idx].amo              = tile_periph_req[t].q.amo;
          tile_req_chan  [xbar_idx].size             = tile_periph_req[t].q.size;
          tile_req_chan  [xbar_idx].data             = axi_wide_data_t'(tile_periph_req[t].q.data);
          tile_req_chan  [xbar_idx].strb             = axi_wide_strb_t'(tile_periph_req[t].q.strb);
          tile_req_chan  [xbar_idx].user.tile_id     = t;
          tile_req_chan  [xbar_idx].user.bank_id     = BankIdPeriph;
          tile_req_chan  [xbar_idx].user.l2_src_id   = l2_group_id_i;
          // Borrow the info field to carry req_id through the mesh
          tile_req_chan  [xbar_idx].user.info        = cache_info_t'(tile_periph_req[t].q.user.req_id);
          tile_req_valid [xbar_idx]                  = tile_periph_req[t].q_valid;
          tile_periph_rsp[t].q_ready                 = tile_req_ready[xbar_idx];

          tile_periph_rsp[t].p.data                  = tile_rsp_chan[xbar_idx].data[31:0];
          tile_periph_rsp[t].p.error                 = tile_rsp_chan[xbar_idx].error;
          tile_periph_rsp[t].p.write                 = tile_rsp_chan[xbar_idx].write;
          // Restore req_id from the info field; zero other tcdm_user fields
          tile_periph_rsp[t].p.user                  = '0;
          tile_periph_rsp[t].p.user.req_id           = reqid_t'(tile_rsp_chan[xbar_idx].user.info);
          tile_periph_rsp[t].p_valid                 = tile_rsp_valid[xbar_idx];
          tile_rsp_ready [xbar_idx]                  = tile_periph_req[t].p_ready;

        end else begin
          // iCache path: only tile 0 active
          if (t == 0) begin
            tile_req_chan  [xbar_idx]                = cache_l2icache_req.q;
            tile_req_chan  [xbar_idx].addr           = scrambleAddr(cache_l2icache_req.q.addr);
            tile_req_valid [xbar_idx]                = cache_l2icache_req.q_valid;
            cache_l2icache_rsp.q_ready               = tile_req_ready[xbar_idx];

            cache_l2icache_rsp.p                     = tile_rsp_chan [xbar_idx];
            cache_l2icache_rsp.p_valid               = tile_rsp_valid[xbar_idx];
            tile_rsp_ready [xbar_idx]                = cache_l2icache_req.p_ready;
            tile_req_chan  [xbar_idx].user.tile_id   = '0;
            tile_req_chan  [xbar_idx].user.bank_id   = BankIdICache;
            tile_req_chan  [xbar_idx].user.l2_src_id = l2_group_id_i;
            // axi_to_reqrsp with EnUserIdPassthrough packs the AXI ID into
            // the LSBs of the user field (spanning burst + info).  Move the
            // ID into info and zero burst so that reqrsp_to_axi (EnBurst+
            // ShuffleId) sees is_burst=0 → keeps ID=0 for iCache requests.
            tile_req_chan  [xbar_idx].user.info     = cache_info_t'(cache_l2icache_req.q.user);
            tile_req_chan  [xbar_idx].user.burst    = '0;
          end else begin
            tile_req_chan  [xbar_idx]  = '0;
            tile_req_valid [xbar_idx]  = 1'b0;
            tile_rsp_ready [xbar_idx]  = 1'b0;
          end
        end
      end
    end
  end

  // ---------------------
  // Refill xbar: N:1 mux (all requests go to single output)
  // No address decoder needed — the mesh chimney handles routing.
  // No burst protection needed — single output, no multi-channel response demux.
  // ---------------------
  reqrsp_xbar #(
    .NumInp          ( NumClusterMst*NumTilesPerGroup  ),
    .NumOut          ( 1                       ),
    .PipeReg         ( 1'b1                    ),
    .ExtReqPrio      ( 1'b0                    ),
    .ExtRspPrio      ( 1'b0                    ),
    .tcdm_req_chan_t ( cache_trans_req_chan_t  ),
    .tcdm_rsp_chan_t ( cache_trans_rsp_chan_t  )
  ) i_refill_xbar (
    .clk_i           ( clk_i          ),
    .rst_ni          ( rst_ni         ),
    .slv_req_i       ( tile_req_chan  ),
    .slv_req_valid_i ( tile_req_valid ),
    .slv_req_ready_o ( tile_req_ready ),
    .slv_rsp_o       ( tile_rsp_chan  ),
    .slv_rsp_valid_o ( tile_rsp_valid ),
    .slv_rsp_ready_i ( tile_rsp_ready ),
    .slv_sel_i       ( '{default: '0} ),
    .slv_rr_i        ( '0             ),
    .slv_selected_o  ( /* unused */   ),
    .mst_req_o       ( l2_req_chan    ),
    .mst_req_valid_o ( l2_req_valid   ),
    .mst_req_ready_i ( l2_req_ready   ),
    .mst_rsp_i       ( l2_rsp_chan    ),
    .mst_rr_i        ( '0             ),
    .mst_rsp_valid_i ( l2_rsp_valid   ),
    .mst_rsp_ready_o ( l2_rsp_ready   ),
    .mst_sel_i       ( l2_sel         )
  );

  // ---------------------
  // l2_req/rsp packing: bridge xbar channels <-> l2_req_t/l2_rsp_t port
  // ---------------------
  always_comb begin
    // Request: xbar -> group output port
    l2_req_o.q       = '{
      addr  : l2_req_chan.addr,
      write : l2_req_chan.write,
      amo   : l2_req_chan.amo,
      data  : l2_req_chan.data,
      strb  : l2_req_chan.strb,
      size  : l2_req_chan.size,
      default: '0
    };
    l2_req_o.q.user  = l2_req_chan.user;
    l2_req_o.q_valid = l2_req_valid;
    l2_req_ready     = l2_rsp_i.q_ready;

    // Response: group input port -> xbar
    l2_rsp_chan      = '{
      data  : l2_rsp_i.p.data,
      error : l2_rsp_i.p.error,
      write : l2_rsp_i.p.write,
      default: '0
    };
    l2_rsp_chan.user = l2_rsp_i.p.user;
    l2_rsp_valid     = l2_rsp_i.p_valid;
    l2_req_o.p_ready = l2_rsp_ready;

    // Response demux: which xbar input port does this response target?
    l2_sel           = l2_rsp_i.p.user.tile_id * NumClusterMst
                     + l2_rsp_i.p.user.bank_id;
  end


  // Tile remote access signals
  // In/Out relative to the tile (out--leave a tile; in--enter a tile)
  // Tile-side flat layout: index = j + r*NrTCDMPortsPerCore (j=xbar idx, r=remote slot within xbar)
  tcdm_req_t        [NumTilesPerGroup-1:0][NumRemotePortTile-1:0] tile_remote_out_req;
  tcdm_rsp_t        [NumTilesPerGroup-1:0][NumRemotePortTile-1:0] tile_remote_out_rsp;
  logic             [NumTilesPerGroup-1:0][NumRemotePortTile-1:0] tile_remote_in_ready, tile_remote_out_ready;

  tcdm_req_t        [NumTilesPerGroup-1:0][NumRemotePortTile-1:0] tile_remote_in_req;
  tcdm_rsp_t        [NumTilesPerGroup-1:0][NumRemotePortTile-1:0] tile_remote_in_rsp;

  // Xbar-side: NrTCDMPortsPerCore xbars, each with NumTilesPerGroup*NumRemotePortCore ports
  // Xbar port index = t*NumRemotePortCore + r
  tcdm_req_chan_t   [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_out_req_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_out_req_valid, tile_remote_out_req_ready;
  tcdm_rsp_chan_t   [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_out_rsp_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_out_rsp_valid, tile_remote_out_rsp_ready;

  tcdm_req_chan_t   [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_in_req_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_in_req_valid,  tile_remote_in_req_ready;
  tcdm_rsp_chan_t   [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_in_rsp_chan;
  logic             [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] tile_remote_in_rsp_valid,  tile_remote_in_rsp_ready;

  // Per-group override of package-level remote xbar selection width.
  // The package uses NumTiles (total), but the group's xbar is sized per-group.
  localparam int unsigned LocalRemoteXbarSelWidth = $clog2(NumTilesPerGroup * NumRemotePortCore);
  typedef logic [LocalRemoteXbarSelWidth-1:0] local_remote_xbar_sel_t;

  // Tile-side selection: narrow type, only carries tile_id
  remote_tile_sel_t [NumTilesPerGroup-1:0][NumRemotePortTile-1:0]                    remote_out_sel_tile;
  // Xbar-side selection: wider type, encodes tile_id*NumRemotePortCore + core_id%NumRemotePortCore
  local_remote_xbar_sel_t [NrTCDMPortsPerCore-1:0][NumTilesPerGroup*NumRemotePortCore-1:0] remote_out_sel_xbar, remote_in_sel_xbar;

  for (genvar t = 0; t < NumTilesPerGroup; t++) begin
    for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin
      for (genvar r = 0; r < NumRemotePortCore; r++) begin
        // tile flat index: j + r*NrTCDMPortsPerCore
        // xbar port index: t*NumRemotePortCore + r
        assign tile_remote_out_req_chan [j][t*NumRemotePortCore+r] = tile_remote_out_req[t][j+r*NrTCDMPortsPerCore].q;
        assign tile_remote_out_req_valid[j][t*NumRemotePortCore+r] = tile_remote_out_req[t][j+r*NrTCDMPortsPerCore].q_valid;
        assign tile_remote_out_rsp_ready[j][t*NumRemotePortCore+r] = tile_remote_in_ready[t][j+r*NrTCDMPortsPerCore];

        assign tile_remote_out_rsp[t][j+r*NrTCDMPortsPerCore].p       = tile_remote_out_rsp_chan [j][t*NumRemotePortCore+r];
        assign tile_remote_out_rsp[t][j+r*NrTCDMPortsPerCore].p_valid = tile_remote_out_rsp_valid[j][t*NumRemotePortCore+r];
        assign tile_remote_out_rsp[t][j+r*NrTCDMPortsPerCore].q_ready = tile_remote_out_req_ready[j][t*NumRemotePortCore+r];

        assign tile_remote_in_req[t][j+r*NrTCDMPortsPerCore].q       = tile_remote_in_req_chan [j][t*NumRemotePortCore+r];
        assign tile_remote_in_req[t][j+r*NrTCDMPortsPerCore].q_valid = tile_remote_in_req_valid[j][t*NumRemotePortCore+r];
        assign tile_remote_out_ready[t][j+r*NrTCDMPortsPerCore]      = tile_remote_in_rsp_ready[j][t*NumRemotePortCore+r];

        assign tile_remote_in_rsp_chan [j][t*NumRemotePortCore+r] = tile_remote_in_rsp[t][j+r*NrTCDMPortsPerCore].p;
        assign tile_remote_in_rsp_valid[j][t*NumRemotePortCore+r] = tile_remote_in_rsp[t][j+r*NrTCDMPortsPerCore].p_valid;
        assign tile_remote_in_req_ready[j][t*NumRemotePortCore+r] = tile_remote_in_rsp[t][j+r*NrTCDMPortsPerCore].q_ready;

        // Request selection: route to target tile's remote-in slot based on
        // SOURCE tile ID (mod NumRemotePortCore).  This is required for
        // response routing to be consistent: tcdm_cache_interco routes
        // responses out via (user.tile_id % NumRemotePortCore), so the
        // request must land in the destination's slot indexed by the same
        // value (the SOURCE tile id mod N).  If we used (target % N) here
        // instead, the request would arrive on slot (T%N) but the response
        // would leave on slot (S%N) — different xbar mst ports — and the
        // xbar's request/response pairing would break, dropping responses
        // and corrupting cache state at multi-tile configs where S%N != T%N.
        assign remote_out_sel_xbar[j][t*NumRemotePortCore+r] = local_remote_xbar_sel_t'(
            remote_out_sel_tile[t][j+r*NrTCDMPortsPerCore] * NumRemotePortCore
          + t % NumRemotePortCore);

        assign remote_in_sel_xbar[j][t*NumRemotePortCore+r] = local_remote_xbar_sel_t'(
            tile_remote_in_rsp_chan[j][t*NumRemotePortCore+r].user.tile_id * NumRemotePortCore
          + tile_remote_in_rsp_chan[j][t*NumRemotePortCore+r].user.core_id % NumRemotePortCore);
      end
    end
  end

  for (genvar t = 0; t < NumTilesPerGroup; t ++) begin : gen_tiles
    logic [9:0] hart_base_id;
    assign hart_base_id = hart_base_id_i + t * NumCoresTile;

    logic [TileIDWidth-1:0] tile_id;
    assign tile_id = tile_base_id_i + TileIDWidth'(t);

    if (NumRemoteGroupPortCore == 0) begin : gen_tile
      cachepool_tile #(
        .AxiAddrWidth             ( AxiAddrWidth             ),
        .AxiDataWidth             ( AxiDataWidth             ),
        .AxiIdWidthIn             ( AxiIdWidthIn             ),
        .AxiIdWidthOut            ( WideIdWidthIn            ),
        .AxiUserWidth             ( AxiUserWidth             ),
        .BootAddr                 ( BootAddr                 ),
        .UartAddr                 ( UartAddr                 ),
        .ClusterPeriphSize        ( ClusterPeriphSize        ),
        .NrCores                  ( NumCoresTile             ),
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
        .axi_narrow_req_t         ( axi_narrow_req_t         ),
        .axi_narrow_resp_t        ( axi_narrow_resp_t        ),
        .axi_out_req_t            ( axi_mst_cache_req_t      ),
        .axi_out_resp_t           ( axi_mst_cache_resp_t     ),
        .TileIDWidth              ( TileIDWidth              ),
        .NumRemoteGroupPortCore   ( NumRemoteGroupPortCore   ),
        .NumTilesPerGroup         ( NumTilesPerGroup         ),
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
      ) i_tile (
        .clk_i                    ( clk_i                                            ),
        .rst_ni                   ( rst_ni                                           ),
        .impl_i                   ( impl_i                                           ),
        .error_o                  ( error[t]                                         ),
        .debug_req_i              ( debug_req_i                                      ),
        .meip_i                   ( meip_i                                           ),
        .mtip_i                   ( mtip_i                                           ),
        .msip_i                   ( msip_i                                           ),
        .hart_base_id_i           ( hart_base_id                                     ),
        .cluster_base_addr_i      ( cluster_base_addr_i                              ),
        .tile_id_i                ( tile_id                                          ),
        .private_start_addr_i     ( private_start_addr_i                             ),
        // Remote Access Ports
        .remote_req_o             ( tile_remote_out_req  [t]                         ),
        .remote_req_dst_o         ( remote_out_sel_tile  [t]                         ),
        .remote_rsp_i             ( tile_remote_out_rsp  [t]                         ),
        .remote_rsp_ready_i       ( tile_remote_out_ready[t]                         ),
        .remote_req_i             ( tile_remote_in_req   [t]                         ),
        .remote_rsp_o             ( tile_remote_in_rsp   [t]                         ),
        .remote_rsp_ready_o       ( tile_remote_in_ready [t]                         ),
        // Inter-group Remote Access Ports (directly exposed to group I/O)
        .remote_group_req_o       (                                                  ),
        .remote_group_rsp_i       ( '0                                               ),
        .remote_group_req_i       ( '0                                               ),
        .remote_group_rsp_o       (                                                  ),
        // Cache Refill Ports (now internal, connected to group-level xbar)
        .cache_refill_req_o       ( cache_refill_req[t*NumL1CtrlTile+:NumL1CtrlTile] ),
        .cache_refill_rsp_i       ( cache_refill_rsp[t*NumL1CtrlTile+:NumL1CtrlTile] ),
        // Peripheral REQRSP (narrow, bypasses wide xbar)
        .periph_req_o             ( tile_periph_req [t]                              ),
        .periph_rsp_i             ( tile_periph_rsp [t]                              ),
        // iCache L2 (single wide AXI port, BootROM at cluster level)
        .axi_wide_req_o           ( axi_tile_mem_req[t]                              ),
        .axi_wide_rsp_i           ( axi_tile_mem_rsp[t]                              ),
        // Direct-wire barrier
        .barrier_o                ( tile_barrier_o  [t]                              ),
        .barrier_done_i           ( barrier_done_i                                   ),
        // Peripherals
        .icache_events_o          ( /* unused */                                     ),
        .icache_prefetch_enable_i ( icache_prefetch_enable_i                         ),
        .cl_interrupt_i           ( cl_interrupt_i  [t*NumCoresTile+:NumCoresTile]   ),
        .dynamic_offset_i         ( dynamic_offset_i                                 ),
        .l1d_insn_i               ( l1d_insn_i                                       ),
        .l1d_private_i            ( l1d_private_i                                    ),
        .l1d_insn_valid_i         ( l1d_insn_valid_i                                 ),
        .l1d_insn_ready_o         ( l1d_insn_ready_o[t]                              ),
        .l1d_busy_i               ( l1d_busy_i      [t]                              )
      );
    end else begin : gen_tile
      cachepool_tile #(
        .AxiAddrWidth             ( AxiAddrWidth             ),
        .AxiDataWidth             ( AxiDataWidth             ),
        .AxiIdWidthIn             ( AxiIdWidthIn             ),
        .AxiIdWidthOut            ( WideIdWidthIn            ),
        .AxiUserWidth             ( AxiUserWidth             ),
        .BootAddr                 ( BootAddr                 ),
        .UartAddr                 ( UartAddr                 ),
        .ClusterPeriphSize        ( ClusterPeriphSize        ),
        .NrCores                  ( NumCoresTile             ),
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
        .axi_narrow_req_t         ( axi_narrow_req_t         ),
        .axi_narrow_resp_t        ( axi_narrow_resp_t        ),
        .axi_out_req_t            ( axi_mst_cache_req_t      ),
        .axi_out_resp_t           ( axi_mst_cache_resp_t     ),
        .TileIDWidth              ( TileIDWidth              ),
        .NumRemoteGroupPortCore   ( NumRemoteGroupPortCore   ),
        .NumTilesPerGroup         ( NumTilesPerGroup         ),
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
      ) i_tile (
        .clk_i                    ( clk_i                                                       ),
        .rst_ni                   ( rst_ni                                                      ),
        .impl_i                   ( impl_i                                                      ),
        .error_o                  ( error[t]                                                    ),
        .debug_req_i              ( debug_req_i                                                 ),
        .meip_i                   ( meip_i                                                      ),
        .mtip_i                   ( mtip_i                                                      ),
        .msip_i                   ( msip_i                                                      ),
        .hart_base_id_i           ( hart_base_id                                                ),
        .cluster_base_addr_i      ( cluster_base_addr_i                                         ),
        .tile_id_i                ( tile_id                                                     ),
        .private_start_addr_i     ( private_start_addr_i                                        ),
        // Remote Access Ports
        .remote_req_o             ( tile_remote_out_req  [t]                                    ),
        .remote_req_dst_o         ( remote_out_sel_tile  [t]                                    ),
        .remote_rsp_i             ( tile_remote_out_rsp  [t]                                    ),
        .remote_rsp_ready_i       ( tile_remote_out_ready[t]                                    ),
        .remote_req_i             ( tile_remote_in_req   [t]                                    ),
        .remote_rsp_o             ( tile_remote_in_rsp   [t]                                    ),
        .remote_rsp_ready_o       ( tile_remote_in_ready [t]                                    ),
        // Inter-group Remote Access Ports (directly exposed to group I/O)
        .remote_group_req_o       ( remote_group_req_o      [t*NumRemoteGroupPortTile+:NumRemoteGroupPortTile]),
        .remote_group_rsp_i       ( remote_group_rsp_i      [t*NumRemoteGroupPortTile+:NumRemoteGroupPortTile]),
        .remote_group_req_i       ( remote_group_req_i      [t*NumRemoteGroupPortTile+:NumRemoteGroupPortTile]),
        .remote_group_rsp_o       ( remote_group_rsp_o      [t*NumRemoteGroupPortTile+:NumRemoteGroupPortTile]),
        // Cache Refill Ports (now internal, connected to group-level xbar)
        .cache_refill_req_o       ( cache_refill_req[t*NumL1CtrlTile+:NumL1CtrlTile]            ),
        .cache_refill_rsp_i       ( cache_refill_rsp[t*NumL1CtrlTile+:NumL1CtrlTile]            ),
        // Peripheral REQRSP (narrow, bypasses wide xbar)
        .periph_req_o             ( tile_periph_req  [t]                                        ),
        .periph_rsp_i             ( tile_periph_rsp  [t]                                        ),
        // iCache L2 (single wide AXI port, BootROM at cluster level)
        .axi_wide_req_o           ( axi_tile_mem_req[t]                                         ),
        .axi_wide_rsp_i           ( axi_tile_mem_rsp[t]                                         ),
        // Direct-wire barrier
        .barrier_o                ( tile_barrier_o    [t]                                       ),
        .barrier_done_i           ( barrier_done_i                                              ),
        // Peripherals
        .icache_events_o          ( /* unused */                                                ),
        .icache_prefetch_enable_i ( icache_prefetch_enable_i                                    ),
        .cl_interrupt_i           ( cl_interrupt_i    [t*NumCoresTile+:NumCoresTile]            ),
        .dynamic_offset_i         ( dynamic_offset_i                                            ),
        .l1d_insn_i               ( l1d_insn_i                                                  ),
        .l1d_private_i            ( l1d_private_i                                               ),
        .l1d_insn_valid_i         ( l1d_insn_valid_i                                            ),
        .l1d_insn_ready_o         ( l1d_insn_ready_o  [t]                                       ),
        .l1d_busy_i               ( l1d_busy_i        [t]                                       )
      );
    end
  end

  // ------------
  // Remote XBar
  // ------------

  for (genvar p = 0; p < NrTCDMPortsPerCore; p++) begin : gen_remote_tile_xbar
    // Decide which tile to go
    reqrsp_xbar #(
      .NumInp           (NumTilesPerGroup * NumRemotePortCore ),
      .NumOut           (NumTilesPerGroup * NumRemotePortCore ),
      .PipeReg          (1'b1                         ),
      .RspReg           (1'b1                         ),
      .ExtReqPrio       (1'b0                         ),
      .ExtRspPrio       (1'b0                         ),
      .tcdm_req_chan_t  (tcdm_req_chan_t              ),
      .tcdm_rsp_chan_t  (tcdm_rsp_chan_t              )
    ) i_tile_remote_xbar (
      .clk_i            (clk_i                        ),
      .rst_ni           (rst_ni                       ),
      .slv_req_i        (tile_remote_out_req_chan [p] ),
      .slv_req_valid_i  (tile_remote_out_req_valid[p] ),
      .slv_req_ready_o  (tile_remote_out_req_ready[p] ),
      .slv_rsp_o        (tile_remote_out_rsp_chan [p] ),
      .slv_rsp_valid_o  (tile_remote_out_rsp_valid[p] ),
      .slv_rsp_ready_i  (tile_remote_out_rsp_ready[p] ),
      .slv_sel_i        (remote_out_sel_xbar      [p] ),
      .slv_rr_i         ('0                           ),
      .slv_selected_o   (/*selection info in cid*/    ),
      .mst_req_o        (tile_remote_in_req_chan  [p] ),
      .mst_req_valid_o  (tile_remote_in_req_valid [p] ),
      .mst_req_ready_i  (tile_remote_in_req_ready [p] ),
      .mst_rsp_i        (tile_remote_in_rsp_chan  [p] ),
      .mst_rsp_valid_i  (tile_remote_in_rsp_valid [p] ),
      .mst_rsp_ready_o  (tile_remote_in_rsp_ready [p] ),
      .mst_rr_i         ('0                           ),
      .mst_sel_i        (remote_in_sel_xbar       [p] )
    );
  end

endmodule
