// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

package cachepool_pkg;
  import fpnew_pkg::*;
  import cf_math_pkg::idx_width;

  /*********************
   *  COMMON INCLUDES  *
   *********************/
  `include "axi/assign.svh"
  `include "axi/typedef.svh"
  `include "reqrsp_interface/assign.svh"
  `include "reqrsp_interface/typedef.svh"
  `include "tcdm_interface/assign.svh"
  `include "tcdm_interface/typedef.svh"

  /**************************************************************
   *  PARAMETERS
   *  Order: Core -> Tile -> Group -> Cluster -> TB/L2
   **************************************************************/

  //////////////////
  //   GLOBAL HW  //
  //////////////////
  localparam int unsigned NumCores        = `ifdef NUM_CORES  `NUM_CORES  `else 0 `endif;
  localparam int unsigned NumTiles        = `ifdef NUM_TILES  `NUM_TILES  `else 0 `endif;
  // TODO: not yet passed in through config, hardcode to 1
  localparam int unsigned NumGroups       = `ifdef NUM_GROUPS `NUM_GROUPS `else 1 `endif;
  localparam int unsigned NumL2Channel    = `ifdef L2_CHANNEL `L2_CHANNEL `else 0 `endif;

  ///////////////////
  //  CORE CONFIG  //
  ///////////////////
  localparam int unsigned SpatzDataWidth  = `ifdef DATA_WIDTH `DATA_WIDTH `else 0 `endif;
  localparam int unsigned BeWidth         = SpatzDataWidth / 8;
  localparam int unsigned ByteOffset      = $clog2(BeWidth);

  localparam int unsigned NFpu = `ifdef SPATZ_NUM_FPU `SPATZ_NUM_FPU `else 0 `endif;
  localparam int unsigned NIpu = `ifdef SPATZ_NUM_IPU `SPATZ_NUM_IPU `else 1 `endif;

  localparam int unsigned NumIntOutstandingLoads   = `ifdef SNITCH_MAX_TRANS `SNITCH_MAX_TRANS `else 0 `endif;
  localparam int unsigned NumIntOutstandingMem     = `ifdef SNITCH_MAX_TRANS `SNITCH_MAX_TRANS `else 0 `endif;
  localparam int unsigned NumSpatzOutstandingLoads = `ifdef SPATZ_MAX_TRANS  `SPATZ_MAX_TRANS `else 0 `endif;

  localparam int unsigned NumAxiMaxTrans           = 64;

  ///////////////////
  //  TILE CONFIG  //
  ///////////////////
  // How many cores for each tile?
  localparam int unsigned NumCoresTile        = NumCores / NumTiles;

  // How many remote ports for each tile per core's port?
  localparam int unsigned NumRemotePortCore   = `ifdef REMOTE_PORT_PER_CORE `REMOTE_PORT_PER_CORE `else 0 `endif;

  // How many cores within a tile? This is used to select the ports within a tile.
  localparam int unsigned LogNumCoresTile     = $clog2(NumCoresTile);

  // 4 ports from Spatz + 1 shared port from Snitch/FPU
  localparam int unsigned NrTCDMPortsPerCore  = 5;

  // How many remote ports for each tile in total?
  localparam int unsigned NumRemotePortTile   = NumRemotePortCore * NrTCDMPortsPerCore;

  ////////////////////
  //  GROUP CONFIG  //
  ////////////////////
  // How many tiles for each group?
  localparam int unsigned NumTilesPerGroup       = NumTiles / NumGroups;

  // How many cores for each group?
  localparam int unsigned NumCoreGroup           = NumCores / NumGroups;

  // How many remote group ports for each tile?
  localparam int unsigned NumRemoteGroupPortCore = `ifdef RG_PORT_PER_CORE `RG_PORT_PER_CORE `else 0 `endif;

  // Number of inter-group NoC router channels per tile (x in the 5-to-x concentration xbar).
  localparam int unsigned NumNoCPortsPerTile = `ifdef NOC_PORT_PER_TILE `NOC_PORT_PER_TILE `else 1 `endif;

  // Group mesh dimensions. NumGroupsY is derived; NumGroupsX must be set via config.
  localparam int unsigned NumGroupsX = `ifdef NUM_GROUPS_X `NUM_GROUPS_X `else 1 `endif;
  localparam int unsigned NumGroupsY = NumGroups / NumGroupsX;


  ////////////////////
  //  CLUSTER HW    //
  ////////////////////
  localparam int unsigned TCDMDepth       = 256;
  localparam int unsigned L1Depth         = `ifdef L1D_DEPTH `L1D_DEPTH `else 0 `endif;

  localparam int unsigned ICacheLineWidth = 128;
  localparam int unsigned ICacheLineCount = 128;
  localparam int unsigned ICacheSets      = 4;

  // Group-level L2 ICache (shared read-only cache, primarily for coalescing)
  localparam int unsigned L2ICacheLineWidth = 512;
  localparam int unsigned L2ICacheSets      = 4;
  localparam int unsigned L2ICacheSizeByte  = 8192;
  localparam int unsigned L2ICacheLineCount = L2ICacheSizeByte / (L2ICacheSets * L2ICacheLineWidth / 8);

  // Be careful on unsigned long int passed in from configuration.
  // Currently use fixed values.
  localparam int unsigned TCDMStartAddr   = 32'hBFFF_F800;
  localparam int unsigned TCDMSize        = 32'h800;

  // The short address for SPM
  localparam int unsigned SPMAddrWidth    = $clog2(TCDMSize);

  localparam int unsigned PeriStartAddr   = 32'hC000_0000;
  localparam int unsigned BootAddr        = 32'h1000;

  // UART Configuration
  localparam int unsigned UartAddr        = 32'hC001_0000;

  ///////////////////////
  //  CACHEPOOL L1 CFG  //
  ///////////////////////

  // Stack: 128*32/8 = 512 Byte per core
  localparam int unsigned SpmStackDepth       = `ifdef STACK_HW_DEPTH `STACK_HW_DEPTH `else 0 `endif;
  localparam int unsigned SpmStackSize        = `ifdef STACK_HW_SIZE `STACK_HW_SIZE `else 0 `endif;

  // Total Stack Size in Byte (shared in main memory + SpmStack)
  localparam int unsigned TotStackDepth       = `ifdef STACK_TOT_DEPTH `STACK_TOT_DEPTH `else 0 `endif;
  localparam int unsigned TotStackSize        = `ifdef STACK_TOT_SIZE `STACK_TOT_SIZE `else 0 `endif;

  // Address width of cache
  localparam int unsigned L1AddrWidth         = `ifdef ADDR_WIDTH `ADDR_WIDTH `else 0 `endif;
  // Cache line width
  localparam int unsigned L1LineWidth         = `ifdef L1D_CACHELINE_WIDTH `L1D_CACHELINE_WIDTH `else 0 `endif;
  // Coalescer window
  localparam int unsigned L1CoalFactor        = `ifdef L1D_COAL_WINDOW `L1D_COAL_WINDOW `else 0 `endif;
  // Number of ways per cache controller
  localparam int unsigned L1AssoPerCtrl       = `ifdef L1D_NUM_WAY `L1D_NUM_WAY `else 0 `endif;
  // Pseudo dual bank
  localparam int unsigned L1BankFactor        = 2;
  // Data width of tag bank
  localparam int unsigned L1TagDataWidth      = `ifdef L1D_TAG_DATA_WIDTH `L1D_TAG_DATA_WIDTH `else 0 `endif;
  // Number of L1 Banks per Tile
  localparam int unsigned NumBank             = `ifdef L1D_NUM_BANKS `L1D_NUM_BANKS `else 0 `endif;

  // NOTE: these are used by AXI/L2 as well, keep here but ordered as "cluster-level cache topology"
  localparam int unsigned NumL1CacheCtrl      = NumCores;
  localparam int unsigned NumL1CtrlTile       = NumL1CacheCtrl / NumTiles;

  // Number of data banks assigned to each cache controller
  localparam int unsigned NumDataBankPerCtrl  = (L1LineWidth / SpatzDataWidth) * L1AssoPerCtrl * L1BankFactor;
  // Number of tag banks assigned to each cache controller
  localparam int unsigned NumTagBankPerCtrl   = L1AssoPerCtrl * L1BankFactor;
  // Number of entries of L1 Cache (total number across multiple cache controllers)
  localparam int unsigned L1NumEntry          = NumBank * L1Depth * SpatzDataWidth / L1LineWidth;
  // Number of cache entries each cache way has
  localparam int unsigned L1CacheWayEntry     = L1NumEntry / L1AssoPerCtrl / NumL1CtrlTile;
  // Number of entries per cache controller
  localparam int unsigned L1NumEntryPerCtrl   = L1NumEntry / NumL1CtrlTile;
  // Number of cache sets each cache way has
  localparam int unsigned L1NumSet            = L1CacheWayEntry / L1BankFactor;

  // Core id width within a tile => tile ID will be calculated separatly
  localparam int unsigned CoreIDWidth         = idx_width(NumCoresTile);
  localparam int unsigned TileIDWidth         = idx_width(NumTiles);
  // Each bank inside a tile needs an unique id, plus two reserved for iCache and peripheral
  localparam int unsigned BankIDWidth         = idx_width(NumL1CtrlTile + 2);

  localparam int unsigned RefillDataWidth     = `ifdef REFILL_DATA_WIDTH `REFILL_DATA_WIDTH `else 0 `endif;
  localparam int unsigned RefillStrbWidth     = RefillDataWidth / 8;

  localparam int unsigned Burst_Enable        = (L1LineWidth > RefillDataWidth);

  //////////////////
  //  AXI CONFIG  //
  //////////////////
  // AXI requires different types after xbar/mux.
  // Keep all AXI related parameters and types together for easier management.

  /***** Basic Types and Width *****/
  // AXI Data Width
  localparam int unsigned SpatzAxiDataWidth       = `ifdef REFILL_DATA_WIDTH `REFILL_DATA_WIDTH `else 0 `endif;
  localparam int unsigned SpatzAxiStrbWidth       = SpatzAxiDataWidth / 8;
  localparam int unsigned SpatzAxiNarrowDataWidth = `ifdef DATA_WIDTH `DATA_WIDTH `else 0 `endif;
  localparam int unsigned SpatzAxiNarrowStrbWidth = SpatzAxiNarrowDataWidth / 8;
  // AXI Address Width
  localparam int unsigned SpatzAxiAddrWidth       = `ifdef ADDR_WIDTH `ADDR_WIDTH `else 0 `endif;
  // AXI User Width
  // The `+ $bits(floo_cachepool_noc_pkg::id_t)` term accounts for
  // refill_user_t.l2_src_id, whose width scales with NumEndpoints (groups +
  // HBM channels) rather than being a fixed constant across configs -- do
  // not fold this into the per-config axi_user_width define instead, that
  // was tried and breaks silently whenever NumEndpoints changes width.
  localparam int unsigned SpatzAxiUserWidth       = `ifdef AXI_USER_WIDTH `AXI_USER_WIDTH `else 0 `endif
                                                     + $clog2(NumTiles)
                                                     + $bits(floo_cachepool_noc_pkg::id_t);

  // -----------------------
  // AXI ID field structure
  // -----------------------
  // ClusterAxiIdWidth is composed of:
  //   [cluster_route_bits][tile_index_bits][tile_local_bits]
  // Per-tile xbar ports: NumL1CtrlTile refill + 1 peripheral + 1 iCache
  localparam int unsigned NumClusterMst           = 2 + NumL1CtrlTile;
  // Bank ID constants for the refill xbar response demux
  // Layout per tile: [0..NumL1CtrlTile-1] = refill, NumL1CtrlTile = peripheral, NumL1CtrlTile+1 = iCache
  localparam int unsigned BankIdPeriph             = NumL1CtrlTile;
  localparam int unsigned BankIdICache             = NumL1CtrlTile + 1;

  localparam int unsigned ClusterRouteIdWidth     = $clog2(NumClusterMst);

  /***** ID Width Topology (Tile -> Group -> Cluster) *****/
  // TileAxiIdWidth: base iCache/DMA AXI ID bits per tile before tile-index bits are added.
  // Determines how many outstanding refills the iCache can track (2^TileAxiIdWidth = 8).
  // This is the "tile_local_bits" field described above.
  localparam int unsigned TileAxiIdWidth          = 3;
  localparam int unsigned GroupAxiIdWidth         = TileAxiIdWidth + $clog2(NumTiles);
  localparam int unsigned ClusterAxiIdWidth       = GroupAxiIdWidth + ClusterRouteIdWidth;
  // Alias used by the Spatz-generated wrapper and testbench templates.
  localparam int unsigned SpatzAxiIdInWidth       = ClusterAxiIdWidth;

  // Tile wide xbar inputs (iCache only; peripheral bypasses the xbar)
  localparam int unsigned TileWideXbarInputs      = 1;
  localparam int unsigned TileWideXbarIdExtraBits = (TileWideXbarInputs > 1) ? $clog2(TileWideXbarInputs) : 0;

  // Tile-internal wide AXI ID width (passed to groups/tiles as AxiIdWidthOut).
  // Sized for the tile's wide xbar: iCache needs TileAxiIdWidth bits,
  // group-level BootROM mux needs $clog2(NumTilesPerGroup) bits on top,
  // and the tile xbar adds TileWideXbarIdExtraBits (0 with 1 master).
  localparam int unsigned GroupWideIdWidth        = TileAxiIdWidth + $clog2(NumTilesPerGroup) + TileWideXbarIdExtraBits;

  // Max outstanding transactions tracked by the L2 refill mesh's DRAM-facing
  // reqrsp_to_axi converters (HBM0 DRAM path, direct HBM paths). Sized for
  // the mesh's aggregate in-flight refill window, not per-core outstanding
  // loads -- deliberately decoupled from NumSpatzOutstandingLoads (that
  // bounds one core's own outstanding requests, whereas this bounds how many
  // requests from all cores/groups can be in flight at a single DRAM channel
  // at once). Chosen to match the previous NumSpatzOutstandingLoads*4 value.
  localparam int unsigned L2RefillMaxTrans        = 128;

  // Cluster-level AXI output ID width (chimney → DRAM).
  // With the FlooNoC mesh, reqrsp_to_axi generates fresh IDs with
  // $clog2(MaxTrans) bits. The chimney carries these through unchanged.
  // No multi-group mux → no extra bits needed.
  localparam int unsigned SpatzAxiIdOutWidth      = $clog2(L2RefillMaxTrans);

  // Cluster wrapper external output AXI ID width.
  // Equals SpatzAxiIdOutWidth (no compression needed), but kept as a
  // separate parameter for interface stability. Must track
  // SpatzAxiIdOutWidth: if narrower, the id_remap in cachepool_cluster_wrapper
  // (i_out_id_remap) would reintroduce the same ID-reuse collision problem
  // (right before DRAM) that widening SpatzAxiIdOutWidth was meant to fix.
  localparam int unsigned WrapperAxiIdOutWidth        = SpatzAxiIdOutWidth;
  // External narrow output AXI ID width for the UART port (cluster → SoC direction).
  // axi_id_remap in the wrapper compresses SpatzAxiUartIdWidth to this.
  localparam int unsigned WrapperAxiNarrowIdOutWidth  = 4;

  localparam int unsigned CsrAxiMstIdWidth        = ClusterAxiIdWidth;
  // ID width after per-master serialization (legacy, kept for barrier compatibility).
  localparam int unsigned CsrSerIdWidth           = 2;
  // CSR slave ID width: 2×2 peripheral xbar adds 1 bit to CsrSerIdWidth.
  // Both the HBM0 peripheral path (serialized) and TB axi_in path (serialized)
  // feed into the xbar at CsrSerIdWidth; output is CsrSerIdWidth + 1.
  localparam int unsigned CsrAxiSlvIdWidth        = CsrSerIdWidth + 1;

  // Narrow AXI ID width = ClusterAxiIdWidth (used for barrier types).
  localparam int unsigned SpatzAxiNarrowIdWidth   = ClusterAxiIdWidth;
  // UART ID width: same as CSR slave ID width (both are xbar master outputs).
  localparam int unsigned SpatzAxiUartIdWidth     = CsrSerIdWidth + 1;

  // BootROM is at cluster level (HBM0 peripheral path), no per-group BootROM ID width needed.

  /***** Tile Ports *****/
  // Each tile has:
  // 1) Wide AXI output: iCache L2 refill only (single port, no xbar)
  // 2) Narrow REQRSP output: peripheral traffic (UART, CSR, BootROM)
  // 3) Wide input bus for SoC control (enters via mesh)

  // Wide AXI Ports: iCache L2 output only (BootROM moved to cluster level)
  localparam int unsigned TileWideAxiPorts        = 1;


  // Wide Data Ports: 1 for each controller
  localparam int unsigned TileWideDataPorts   = NumL1CtrlTile;

  /***** Group Ports *****/
  // Wide AXI ports
  localparam int unsigned GroupWideAxiPorts   = TileWideAxiPorts * NumTiles;
  // Wide Data ports
  localparam int unsigned GroupWideDataPorts  = NumL1CtrlTile;

  // Correct selection width for remote xbar at group level
  localparam int unsigned RemoteXbarSelWidth = $clog2(NumTiles * NumRemotePortCore);

  /***** Cluster Ports *****/
  // Narrow AXI ports:
  //   In:  1 from SoC (enters mesh via HBM0 chimney input, upsized 32→512)
  //   Out: 1 to UART (exits HBM0 chimney output → demux → downsizer 512→32)
  localparam int unsigned ClusterNarrowInAxiPorts  = 1;
  localparam int unsigned ClusterNarrowOutAxiPorts = 1;
  // Wide AXI ports: one per HBM channel (HBM0 is shared with peripheral demux)
  localparam int unsigned ClusterWideOutAxiPorts   = NumL2Channel;


  //////////////////
  //   L2 / DRAM  //
  //////////////////
  // L2 Memory
  localparam int unsigned L2BankWidth    = `ifdef L2_BANK_WIDTH `L2_BANK_WIDTH `else 0 `endif;
  localparam int unsigned L2BankBeWidth  = L2BankWidth / 8;

  // Supported values (must match DRAMSys config names): DDR3, DDR4, LPDDR4, HBM2
  parameter string        DramType       = `ifdef DRAM_TYPE `DRAM_TYPE `else "DDR4" `endif;
  parameter  int unsigned DramBase       = 32'h8000_0000;

  // One more for UART?
  localparam int unsigned NumClusterSlv  = NumL2Channel;

  // DRAM Configuration
  localparam int unsigned DramAddr       = 32'h8000_0000;
  localparam int unsigned DramSize       = 32'h4000_0000; // 1GB
  localparam int unsigned DramPerChSize  = DramSize / NumL2Channel;

  // Currently set to 16 for now
  parameter int unsigned Interleave      = `ifdef L2_INTERLEAVE `L2_INTERLEAVE `else 0 `endif;

  /**************************************************************
   *  TYPES
   *  Order: Core -> Tile -> Group -> Cluster -> TB/L2
   **************************************************************/

  //////////////////
  //  CORE TYPES  //
  //////////////////
  typedef logic [$clog2(NumSpatzOutstandingLoads)-1:0]    reqid_t;

  //////////////////
  //  AXI TYPES   //
  //////////////////
  typedef logic [SpatzAxiDataWidth-1:0]         axi_wide_data_t;
  typedef logic [SpatzAxiStrbWidth-1:0]         axi_wide_strb_t;
  typedef logic [SpatzAxiNarrowDataWidth-1:0]   axi_narrow_data_t;
  typedef logic [SpatzAxiNarrowStrbWidth-1:0]   axi_narrow_strb_t;
  typedef logic [SpatzAxiAddrWidth-1:0]         axi_addr_t;
  typedef logic [SpatzAxiUserWidth-1:0]         axi_user_t;

  typedef logic [SpatzAxiIdInWidth-1:0]         axi_id_in_t;
  typedef logic [SpatzAxiIdOutWidth-1:0]        axi_id_out_t;

  typedef logic [SpatzAxiNarrowIdWidth-1:0]     axi_narrow_id_t;
  // legacy name; TODO: remove
  typedef logic [SpatzAxiNarrowIdWidth-1:0]     id_slv_t;

  typedef logic [SpatzAxiUartIdWidth-1:0]       axi_uart_id_t;

  typedef logic [CsrAxiMstIdWidth-1:0]          axi_id_csr_mst_t;
  typedef logic [CsrSerIdWidth-1:0]             axi_id_csr_ser_t;
  typedef logic [CsrAxiSlvIdWidth-1:0]          axi_id_csr_slv_t;

  typedef logic [WrapperAxiIdOutWidth-1:0]       axi_id_wrapper_out_t;
  typedef logic [WrapperAxiNarrowIdOutWidth-1:0] axi_id_wrapper_narrow_out_t;

  //////////////////
  //  TILE TYPES  //
  //////////////////
  typedef logic [TileIDWidth-1:0]               remote_tile_sel_t;

  // Tile-level wide AXI external port indices (group-facing)
  // Single port: iCache L2 output only (BootROM moved to cluster level)
  typedef enum integer {
    TileMem = 0
  } tile_wide_e;

  //////////////////////
  //  CACHE/L1 TYPES  //
  //////////////////////
  typedef logic [$clog2(L1CacheWayEntry)-1:0]             cache_ways_entry_ptr_t;
  typedef logic [$clog2(L1AssoPerCtrl)-1:0]               way_ptr_t;

  typedef logic [RefillDataWidth-1:0]                     refill_data_t;
  typedef logic [RefillStrbWidth-1:0]                     refill_strb_t;
  typedef logic [$clog2(L1LineWidth/RefillDataWidth)-1:0] burst_len_t;

  // Narrow TCDM channel (32b) for inter-tile and intra-tile connection
  typedef logic [31:0]                                    narrow_data_t;
  typedef logic [3 :0]                                    narrow_strb_t;
  typedef logic [L1AddrWidth-1:0]                         narrow_addr_t;
  typedef logic [SPMAddrWidth-1:0]                        spm_addr_t;

  typedef struct packed {
    logic        is_burst;
    burst_len_t  burst_len;
  } burst_req_t;

  // Cache flush/invalidation instruction issued by the peripheral flush controller.
  // insn encoding:
  //   2'b00 : flush private banks only
  //   2'b01 : flush shared  banks only
  //   2'b10 : flush all banks
  //   2'b11 : invalidate (init) all banks
  // tile_sel: one-hot mask over NumTiles. For insn != 2'b00 the peripheral
  //           sets tile_sel to '1 (all tiles) for consistency.
  typedef struct packed {
    logic [1:0]          insn;
    logic [NumTiles-1:0] tile_sel;
  } cache_insn_t;

  typedef struct packed {
    logic                  for_write_pend;
    cache_ways_entry_ptr_t depth;
    way_ptr_t              way;
  } cache_info_t;

  typedef struct packed {
    logic [CoreIDWidth-1:0] core_id;
    logic [TileIDWidth-1:0] tile_id;
    logic                   is_amo;
    reqid_t                 req_id;
    logic                   is_fpu;
  } tcdm_user_t;

  typedef struct packed {
    logic [BankIDWidth-1:0]      bank_id;
    logic [TileIDWidth-1:0]      tile_id;
    // L2 refill mesh source group (floo endpoint ID), stamped at request
    // formation and read back at the HBM ejection chimney to route the
    // response without a local src_id FIFO (which assumed in-order HBM
    // completion). Distinct from tile_id, which stays local to the group
    // and is used as a routing index for intra-group response delivery.
    // Placed above info/burst (not appended at the end) because the iCache
    // path's EnUserIdPassthrough workaround (cachepool_group.sv) truncates
    // this struct down to cache_info_t width and depends on info/burst
    // remaining the bottom (LSB) fields.
    floo_cachepool_noc_pkg::id_t l2_src_id;
    cache_info_t                 info;
    burst_req_t                  burst;
  } refill_user_t;

  ///////////////////
  //  GROUP TYPES  //
  ///////////////////

  typedef logic [RemoteXbarSelWidth-1:0]         remote_xbar_sel_t;
  typedef logic [$clog2(NrTCDMPortsPerCore)-1:0] portid_t;

  typedef struct packed {
    logic [CoreIDWidth-1:0]           core_id;
    logic [TileIDWidth-1:0]           tile_id;
    reqid_t                           req_id;
    logic                             is_fpu;
    portid_t                          port_id;
    logic [idx_width(NumGroupsX)-1:0] src_group_x;
    logic [idx_width(NumGroupsY)-1:0] src_group_y;
    // Globally-unique destination tile ID, set by tcdm_cache_interco for
    // inter-group requests.  Upper bits (above $clog2(NumTilesPerGroup)) are
    // the linear group index; lower bits are the local tile within the group.
    logic [TileIDWidth-1:0]           dst_tile_id;
  } remote_group_user_t;

  `REQRSP_TYPEDEF_ALL(remote_group, narrow_addr_t, narrow_data_t, narrow_strb_t, remote_group_user_t)

  // XY mesh coordinates for a group. port_id selects the eject port (always 0 for single-link).
  typedef struct packed {
    logic [idx_width(NumGroupsX)-1:0] x;
    logic [idx_width(NumGroupsY)-1:0] y;
    logic                             port_id;
  } group_xy_id_t;

  // Per-group tile index used by dispatch xbar selection.
  typedef logic [idx_width(NumTilesPerGroup)-1:0] group_tile_sel_t;

  // Routing header embedded in every inter-group NoC flit.
  typedef struct packed {
    logic [3:0]      collective_op;
    group_xy_id_t    src_id;
    group_xy_id_t    dst_id;
    group_tile_sel_t src_tile_id;
    portid_t         src_port_id;
    logic            last;
  } noc_group_hdr_t;

  // Inter-group NoC flit types (payload + routing header).
  typedef struct packed {
    remote_group_req_chan_t payload;
    noc_group_hdr_t         hdr;
  } noc_group_req_t;

  typedef struct packed {
    remote_group_rsp_chan_t payload;
    noc_group_hdr_t         hdr;
  } noc_group_rsp_t;

  //////////////////////////////
  //  L2 Refill Mesh Types    //
  //////////////////////////////
  // Types imported from floogen-generated floo_cachepool_noc_pkg:
  //   id_t    = logic[3:0]  — endpoint ID (GroupX0Y0..Hbm3, HostPeri)
  //   route_t = logic[8:0]  — packed source route (3 bits/hop, consumed LSB-first)
  // The header carries route_t as dst_id (for source routing) and id_t as src_id
  // (for return-path lookup). floo_tcdm_chimney uses SAM for address→id translation
  // and RoutingTables for id→route lookup.

  typedef struct packed {
    logic [3:0]                          collective_op;
    floo_cachepool_noc_pkg::id_t         src_id;
    floo_cachepool_noc_pkg::route_t      dst_id;
    logic                                last;
  } l2_noc_hdr_t;
  // l2_noc_req_t / l2_noc_rsp_t defined after REQRSP_TYPEDEF_ALL macros below.

  // Group ICache (L2 read-only cache control)
  // 2 rules: DRAM (cacheable) + BootROM (cacheable, avoids Bypass path)
  localparam int unsigned ROCacheNumAddrRules = 2;
  typedef struct packed {
    logic enable;
    logic flush_valid;
    axi_addr_t [ROCacheNumAddrRules-1:0] start_addr;
    axi_addr_t [ROCacheNumAddrRules-1:0] end_addr;
  } ro_cache_ctrl_t;


  /////////////////////
  //  CLUSTER TYPES  //
  /////////////////////
  typedef enum integer {
    L2Channel0  = 0,
    L2Channel1  = 1,
    L2Channel2  = 2,
    L2Channel3  = 3
  } cluster_slv_e;

  // Cache refill bus (at the interface of each cache controller)
  typedef struct packed {
    axi_addr_t      addr;
    cache_info_t    info;
    logic           write;
    refill_data_t   wdata;
    refill_strb_t   wstrb;
  } cache_refill_req_chan_t;

  typedef struct packed {
    logic           write;
    refill_data_t   data;
    cache_info_t    info;
  } cache_refill_rsp_chan_t;

  //////////////////
  //  L2 / DRAM   //
  //////////////////
  typedef struct packed {
    int                           dram_ctrl_id;
    logic [SpatzAxiAddrWidth-1:0] dram_ctrl_addr;
  } dram_ctrl_interleave_t;

  /**************************************************************
   *  MACROS (TYPEDEFS)
   *  Keep after base types are defined.
   **************************************************************/

  // REQRSP: L2 (wide AXI + refill_user)
  `REQRSP_TYPEDEF_ALL (l2, axi_addr_t, axi_wide_data_t, axi_wide_strb_t, refill_user_t)

  // REQRSP: cache transaction (same payload type as L2 in current code)
  `REQRSP_TYPEDEF_ALL (cache_trans, axi_addr_t, axi_wide_data_t, axi_wide_strb_t, refill_user_t)

  // L2 refill mesh flit types (payload = cache_trans channel + routing header)
  typedef struct packed {
    cache_trans_req_chan_t payload;
    l2_noc_hdr_t          hdr;
  } l2_noc_req_t;

  typedef struct packed {
    cache_trans_rsp_chan_t payload;
    l2_noc_hdr_t          hdr;
  } l2_noc_rsp_t;

  // REQRSP: peripheral path (narrow 32b, tcdm_user_t)
  `REQRSP_TYPEDEF_ALL (periph, axi_addr_t, narrow_data_t, narrow_strb_t, tcdm_user_t)

  // REQRSP: narrow 32b with refill_user_t (DW converter output, peripheral path)
  `REQRSP_TYPEDEF_ALL (peri_narrow, axi_addr_t, narrow_data_t, narrow_strb_t, refill_user_t)

  // Peripheral xbar user: refill_user_t + 1-bit source ID (0=NoC, 1=TB)
  typedef struct packed {
    logic          src_id;
    refill_user_t  refill;
  } peri_xbar_user_t;

  // REQRSP: peripheral xbar path (narrow 32b, peri_xbar_user_t)
  `REQRSP_TYPEDEF_ALL (peri_xbar, axi_addr_t, narrow_data_t, narrow_strb_t, peri_xbar_user_t)

  // TCDM req/rsp bus => core to L1
  `TCDM_TYPEDEF_ALL(tcdm, narrow_addr_t, narrow_data_t, narrow_strb_t, tcdm_user_t)
  `TCDM_TYPEDEF_ALL(spm,  spm_addr_t,    narrow_data_t, narrow_strb_t, tcdm_user_t)

  // AXI typedef bundles
  `AXI_TYPEDEF_ALL(spatz_axi_narrow,  axi_addr_t, axi_narrow_id_t,  axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_in,      axi_addr_t, axi_id_in_t,      axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_out,     axi_addr_t, axi_id_out_t,       axi_wide_data_t,   axi_wide_strb_t,   axi_user_t)
  // Wrapper-level external output type: ID from SpatzAxiIdOutWidth to WrapperAxiIdOutWidth.
  `AXI_TYPEDEF_ALL(spatz_axi_wrapper_out,         axi_addr_t, axi_id_wrapper_out_t,         axi_wide_data_t,   axi_wide_strb_t,   axi_user_t)
  // Wrapper-level external narrow output type: ID compressed from SpatzAxiUartIdWidth to WrapperAxiNarrowIdOutWidth.
  `AXI_TYPEDEF_ALL(spatz_axi_wrapper_narrow_out,  axi_addr_t, axi_id_wrapper_narrow_out_t,  axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)

  `AXI_TYPEDEF_ALL(axi_uart,          axi_addr_t, axi_uart_id_t,        axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(axi_csr_mst,       axi_addr_t, axi_id_csr_mst_t,     axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  // Serialized CSR type: 1-bit ID output of axi_id_serialize, fed into the CSR mux slave ports.
  `AXI_TYPEDEF_ALL(axi_csr_ser,       axi_addr_t, axi_id_csr_ser_t,     axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(axi_csr_slv,       axi_addr_t, axi_id_csr_slv_t,     axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  /**************************************************************
   *  FUNCTIONS
   *  Order: Core -> Tile -> Group -> Cluster -> TB/L2
   **************************************************************/

  ///////////////////
  //  CORE FUNCS   //
  ///////////////////
  localparam fpu_implementation_t FPUImplementation_Core = '{
    // FMA Block
    PipeRegs: '{
      // FP32      FP64      FP16      FP8       FP16A     FP8A
      '{ 1,        2,        1,        0,        1,        0},   // ADDMUL
      '{ 1,        1,        1,        1,        1,        1},   // DIVSQRT
      '{ 1,        1,        1,        1,        1,        1},   // NONCOMP
      '{ 2,        2,        2,        2,        2,        2},   // CONV
      '{ 4,        4,        4,        4,        4,        4}    // DOTP
    },
    UnitTypes: '{
      '{ MERGED,   MERGED,   MERGED,   MERGED,   MERGED,   MERGED   }, // FMA
      '{ DISABLED, DISABLED, DISABLED, DISABLED, DISABLED, DISABLED }, // DIVSQRT
      '{ PARALLEL, PARALLEL, PARALLEL, PARALLEL, PARALLEL, PARALLEL }, // NONCOMP
      '{ MERGED,   MERGED,   MERGED,   MERGED,   MERGED,   MERGED   }, // CONV
      '{ MERGED,   MERGED,   MERGED,   MERGED,   MERGED,   MERGED   }  // DOTP
    },
    PipeConfig:  BEFORE
  };

  //////////////////////
  //  CLUSTER FUNCS   //
  //////////////////////

  // PMA configuration (cached regions)
  function automatic snitch_pma_pkg::rule_t [snitch_pma_pkg::NrMaxRules-1:0] get_cached_regions();
    automatic snitch_pma_pkg::rule_t [snitch_pma_pkg::NrMaxRules-1:0] cached_regions;
    cached_regions = '{default: '0};
    cached_regions[0] = '{base: 32'h80000000, mask: 32'hfc000000};
    // Bootrom at 0x1000: make low 64KB cacheable for ICache
    cached_regions[1] = '{base: 32'h00000000, mask: 32'hffff0000};
    return cached_regions;
  endfunction

  localparam snitch_pma_pkg::snitch_pma_t SnitchPMACfg = '{
      NrCachedRegionRules: 2,
      CachedRegion:        get_cached_regions(),
      default:             0
  };

  //////////////////
  //  L2 / DRAM   //
  //////////////////

  // getHbmIdx / hbmIdxToXY removed — replaced by SAM-based address→ID
  // translation inside floo_tcdm_chimney (uses floo_cachepool_noc_pkg::Sam).

  /************* System Functions ************/
  function automatic dram_ctrl_interleave_t getDramCTRLInfo(axi_addr_t addr);
    automatic dram_ctrl_interleave_t res;
    localparam int unsigned ConstantBits  = $clog2(L2BankBeWidth * Interleave);
    localparam int unsigned ScrambleBits  = $clog2(NumL2Channel);
    localparam int unsigned ReminderBits  = SpatzAxiAddrWidth - ScrambleBits - ConstantBits;

    res.dram_ctrl_id    = addr[ConstantBits + ScrambleBits - 1 : ConstantBits];
    res.dram_ctrl_addr  = {addr[SpatzAxiAddrWidth-1 : SpatzAxiAddrWidth - ReminderBits],
                           {ScrambleBits{1'b0}},
                           addr[ConstantBits-1:0]};
    return res;
  endfunction

  function automatic axi_addr_t scrambleAddr(axi_addr_t addr);
    // IMPORTANT: This function will not work if size is smaller than `L2BankBeWidth * Interleave`
    automatic axi_addr_t res;
    if ((L2BankBeWidth * Interleave) < DramPerChSize) begin
      // Input address needs to move the dram_id bits to correct location for interleaving
      // [Reminder][InterChange][Scramble][Constant] => [Reminder][Scramble][InterChange][Constant]
      localparam int unsigned SizeOffsetBits  = $clog2(DramPerChSize);
      localparam int unsigned ConstantBits    = $clog2(L2BankBeWidth * Interleave);
      localparam int unsigned InterChangeBits = SizeOffsetBits - ConstantBits;
      localparam int unsigned ScrambleBits    = $clog2(NumL2Channel);
      localparam int unsigned ReminderBits    = SpatzAxiAddrWidth - ScrambleBits - SizeOffsetBits;

      res  = {addr[SpatzAxiAddrWidth              - 1 : SpatzAxiAddrWidth - ReminderBits],
              addr[ConstantBits + ScrambleBits    - 1 : ConstantBits                    ],
              addr[SizeOffsetBits + ScrambleBits  - 1 : ConstantBits + ScrambleBits     ],
              addr[ConstantBits                   - 1 : 0                               ]};

      return res;
    end else begin
      return addr;
    end
  endfunction

  function automatic axi_addr_t revertAddr(axi_addr_t addr);
    // IMPORTANT: This function will not work if size is smaller than `L2BankBeWidth * Interleave`
    // Revert the scrambled address back
    automatic axi_addr_t res;
    if ((L2BankBeWidth * Interleave) < DramPerChSize) begin
      // Input address needs to move the dram_id bits to correct location for interleaving
      // [Reminder][Scramble][InterChange][Constant] => [Reminder][InterChange][Scramble][Constant]
      localparam int unsigned SizeOffsetBits  = $clog2(DramPerChSize);
      localparam int unsigned ConstantBits    = $clog2(L2BankBeWidth * Interleave);
      localparam int unsigned InterChangeBits = SizeOffsetBits - ConstantBits;
      localparam int unsigned ScrambleBits    = $clog2(NumL2Channel);
      localparam int unsigned ReminderBits    = SpatzAxiAddrWidth - ScrambleBits - SizeOffsetBits;

      res  = {addr[SpatzAxiAddrWidth              - 1 : SpatzAxiAddrWidth - ReminderBits],
              addr[ConstantBits + InterChangeBits - 1 : ConstantBits                    ],
              addr[SizeOffsetBits + ScrambleBits  - 1 : SizeOffsetBits                  ],
              addr[ConstantBits                   - 1 : 0                               ]};

      return res;
    end else begin
      return addr;
    end
  endfunction

endpackage : cachepool_pkg
