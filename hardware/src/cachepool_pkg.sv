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

  localparam int unsigned NumAxiMaxTrans           = 32;

  ///////////////////
  //  TILE CONFIG  //
  ///////////////////
  // How many cores for each tile?
  localparam int unsigned NumCoresTile      = NumCores / NumTiles;

  // How many remote ports for each tile? Currently needs to be 0 or 1.
  // localparam int unsigned NumRemotePortTile = `ifdef NumRemotePortTile `NumRemotePortTile `else 0 `endif;
  localparam int unsigned NumRemotePortTile = 1;

  // How many cores within a tile? This is used to select the ports within a tile.
  localparam int unsigned LogNumCoresTile   = $clog2(NumCoresTile);

  localparam int unsigned NrTCDMPortsPerCore = 5;

  ////////////////////
  //  CLUSTER HW    //
  ////////////////////
  localparam int unsigned TCDMDepth       = 256;
  localparam int unsigned L1Depth         = `ifdef L1D_DEPTH `L1D_DEPTH `else 0 `endif;

  localparam int unsigned ICacheLineWidth = 128;
  localparam int unsigned ICacheLineCount = 128;
  localparam int unsigned ICacheSets      = 4;

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
  // Each bank inside a tile needs an unique id, plus one reserved for icache
  localparam int unsigned BankIDWidth         = idx_width(NumL1CtrlTile + 1);

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
  localparam int unsigned SpatzAxiUserWidth       = `ifdef AXI_USER_WIDTH `AXI_USER_WIDTH `else 0 `endif + $clog2(NumTiles);

  // -----------------------
  // AXI ID field structure
  // -----------------------
  // ClusterAxiIdWidth is composed of:
  //   [cluster_route_bits][tile_index_bits][tile_local_bits]
  localparam int unsigned NumClusterMst           = 1 + NumL1CtrlTile;

  localparam int unsigned ClusterRouteIdWidth     = $clog2(NumClusterMst);

  /***** ID Width Topology (Tile -> Group -> Cluster) *****/
  localparam int unsigned TileAxiIdWidth          = 3;
  localparam int unsigned GroupAxiIdWidth         = TileAxiIdWidth + $clog2(NumTiles);
  localparam int unsigned ClusterAxiIdWidth       = GroupAxiIdWidth + ClusterRouteIdWidth;

  // legacy naming
  localparam int unsigned SpatzAxiIdInWidth       = ClusterAxiIdWidth;
  // localparam int unsigned SpatzAxiIdInWidth       = TileAxiIdWidth;
  localparam int unsigned SpatzAxiIdOutWidth      = ClusterAxiIdWidth + 1;

  // Fixed AXI ID width for IWC
  localparam int unsigned IwcAxiIdOutWidth        = SpatzAxiIdOutWidth + 1;

  localparam int unsigned CsrAxiMstIdWidth        = ClusterAxiIdWidth;
  localparam int unsigned CsrAxiSlvIdWidth        = ClusterAxiIdWidth + $clog2(NumTiles+1);

  // Base ID width 6, plus tile mux => adding clog(tile)
  localparam int unsigned SpatzAxiNarrowIdWidth   = 6 + $clog2(NumTiles);
  // UART ID width, with an extra xbar
  localparam int unsigned SpatzAxiUartIdWidth     = SpatzAxiNarrowIdWidth + $clog2(NumTiles);

  /***** Tile Ports *****/
  // We have three sets of AXI ports for each tile:
  // 1) Wide   output bus for BootRom & L2 (from ICache)
  // 2) Narrow output bus for UART/Periph
  // 3) Narrow input  bus for SoC control

  // Narrow AXI Ports: 1 UART + 1 Periph
  localparam int unsigned TileNarrowAxiPorts      = 2;

  // Wide AXI Ports: 1 BootROM + 1 Data (I$)
  localparam int unsigned TileWideAxiPorts        = 2;
  localparam int unsigned TileWideXbarInputs      = 2; // iCache + narrow2wide
  localparam int unsigned TileWideXbarIdExtraBits = $clog2(TileWideXbarInputs); // = 1


  // Wide Data Ports: 1 for each controller
  localparam int unsigned TileWideDataPorts   = NumL1CtrlTile;

  /***** Group Ports *****/
  // Narrow AXI ports
  localparam int unsigned GroupNarrowAxiPorts = TileNarrowAxiPorts * NumTiles;
  // Wide AXI ports
  localparam int unsigned GroupWideAxiPorts   = TileWideAxiPorts * NumTiles;
  // Wide Data ports
  localparam int unsigned GroupWideDataPorts  = NumL1CtrlTile;

  /***** Cluster Ports *****/
  // Narrow AXI ports: 1 In from SoC, 1 Out to UART
  localparam int unsigned ClusterNarrowInAxiPorts  = 1;
  localparam int unsigned ClusterNarrowOutAxiPorts = 1;
  // Wide AXI ports: X to DRAM (X=4 for now)
  localparam int unsigned ClusterWideOutAxiPorts   = NumL2Channel;

  // TODO: multi-tile support
  // One more from the Snitch core

  //////////////////
  //   L2 / DRAM  //
  //////////////////
  // L2 Memory
  localparam int unsigned L2BankWidth    = `ifdef L2_BANK_WIDTH `L2_BANK_WIDTH `else 0 `endif;
  localparam int unsigned L2BankBeWidth  = L2BankWidth / 8;

  parameter               DramType       = "DDR4"; // "DDR4", "DDR3", "HBM2", "LPDDR4"
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
  typedef logic [CsrAxiSlvIdWidth-1:0]          axi_id_csr_slv_t;

  typedef logic [IwcAxiIdOutWidth-1:0]          axi_id_out_iwc_t;

  //////////////////
  //  TILE TYPES  //
  //////////////////
  typedef logic [TileIDWidth-1:0]               remote_tile_sel_t;

  // Naming the port for easier connection
  typedef enum integer {
    TilePeriph  = 0,
    TileUart    = 1
  } tile_narrow_e;

  // Naming the port for easier connection
  typedef enum integer {
    TileBootROM = 0,
    TileMem     = 1
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
    logic [BankIDWidth-1:0] bank_id;
    logic [TileIDWidth-1:0] tile_id;
    cache_info_t            info;
    burst_req_t             burst;
  } refill_user_t;

  /////////////////////
  //  CLUSTER TYPES  //
  /////////////////////
  typedef enum integer {
    ClusterUart   = 0,
    ClusterPeriph = 1
  } cluster_narrow_e;

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

  // TCDM req/rsp bus => core to L1
  `TCDM_TYPEDEF_ALL(tcdm, narrow_addr_t, narrow_data_t, narrow_strb_t, tcdm_user_t)
  `TCDM_TYPEDEF_ALL(spm,  spm_addr_t,    narrow_data_t, narrow_strb_t, tcdm_user_t)

  // AXI typedef bundles
  `AXI_TYPEDEF_ALL(spatz_axi_narrow,  axi_addr_t, axi_narrow_id_t,  axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_in,      axi_addr_t, axi_id_in_t,      axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_out,     axi_addr_t, axi_id_out_t,     axi_wide_data_t,   axi_wide_strb_t,   axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_iwc_out, axi_addr_t, axi_id_out_iwc_t, axi_wide_data_t,   axi_wide_strb_t,   axi_user_t)

  `AXI_TYPEDEF_ALL(axi_uart,          axi_addr_t, axi_uart_id_t,    axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(axi_csr_mst,       axi_addr_t, axi_id_csr_mst_t, axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(axi_csr_slv,       axi_addr_t, axi_id_csr_slv_t, axi_narrow_data_t, axi_narrow_strb_t, axi_user_t)

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
    return cached_regions;
  endfunction

  localparam snitch_pma_pkg::snitch_pma_t SnitchPMACfg = '{
      NrCachedRegionRules: 1,
      CachedRegion:        get_cached_regions(),
      default:             0
  };

  //////////////////
  //  L2 / DRAM   //
  //////////////////

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
