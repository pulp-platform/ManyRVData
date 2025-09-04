// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

package cachepool_pkg;
  import fpnew_pkg::*;

  /*********************
   *  TILE PARAMETERS  *
   *********************/

  `include "axi/assign.svh"
  `include "axi/typedef.svh"
  `include "reqrsp_interface/assign.svh"
  `include "reqrsp_interface/typedef.svh"

  localparam int unsigned NumTiles = `ifdef NUM_TILES `NUM_TILES `else 0 `endif;

  ///////////
  //  AXI  //
  ///////////

  // AXI Data Width
  localparam int unsigned SpatzAxiDataWidth       = `ifdef REFILL_DATA_WIDTH `REFILL_DATA_WIDTH `else 0 `endif;
  localparam int unsigned SpatzAxiStrbWidth       = SpatzAxiDataWidth / 8;
  localparam int unsigned SpatzAxiNarrowDataWidth = `ifdef DATA_WIDTH `DATA_WIDTH `else 0 `endif;
  // AXI Address Width
  localparam int unsigned SpatzAxiAddrWidth       = `ifdef ADDR_WIDTH `ADDR_WIDTH `else 0 `endif;
  // AXI ID Width
  localparam int unsigned SpatzAxiIdInWidth       = 6;
  localparam int unsigned SpatzAxiIdOutWidth      = 7;

  // FIXED AxiIdOutWidth
  // Add 3 because of cache controller (second-level xbar, 4 cache, 1 old port)
  localparam int unsigned IwcAxiIdOutWidth        = 3 + $clog2(4) + 3;

  // AXI User Width
  localparam int unsigned SpatzAxiUserWidth       = `ifdef AXI_USER_WIDTH `AXI_USER_WIDTH `else 0 `endif;

  typedef logic [SpatzAxiDataWidth-1:0]  axi_data_t;
  typedef logic [SpatzAxiStrbWidth-1:0]  axi_strb_t;
  typedef logic [SpatzAxiAddrWidth-1:0]  axi_addr_t;
  typedef logic [SpatzAxiIdInWidth-1:0]  axi_id_in_t;
  typedef logic [SpatzAxiIdOutWidth-1:0] axi_id_out_t;
  typedef logic [SpatzAxiUserWidth-1:0]  axi_user_t;

  // --------
  // Typedefs
  // --------

  typedef logic [6:0]  id_slv_t;

  // Regbus peripherals.
  `AXI_TYPEDEF_ALL(spatz_axi_narrow, axi_addr_t, id_slv_t, logic [SpatzAxiNarrowDataWidth-1:0], logic [(SpatzAxiNarrowDataWidth/8)-1:0], axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_in, axi_addr_t, axi_id_in_t, logic [SpatzAxiNarrowDataWidth-1:0], logic [(SpatzAxiNarrowDataWidth/8)-1:0], axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_out, axi_addr_t, axi_id_out_t, axi_data_t, axi_strb_t, axi_user_t)

  typedef logic [IwcAxiIdOutWidth-1:0] axi_id_out_iwc_t;

  `AXI_TYPEDEF_ALL(spatz_axi_iwc_out, axi_addr_t, axi_id_out_iwc_t, axi_data_t, axi_strb_t, axi_user_t)

  ////////////////////
  //  Spatz Cluster //
  ////////////////////

  localparam int unsigned NumCores        = `ifdef NUM_CORES `NUM_CORES `else 0 `endif;
  // TODO: read from CFG
  localparam int unsigned NumBank         = `ifdef L1D_NUM_BANKS `L1D_NUM_BANKS `else 0 `endif;
  localparam int unsigned TCDMDepth       = 256;
  localparam int unsigned L1Depth         = `ifdef L1D_DEPTH `L1D_DEPTH `else 0 `endif;

  localparam int unsigned SpatzDataWidth  = `ifdef DATA_WIDTH `DATA_WIDTH `else 0 `endif;
  localparam int unsigned BeWidth         = SpatzDataWidth / 8;
  localparam int unsigned ByteOffset      = $clog2(BeWidth);

  localparam int unsigned ICacheLineWidth = 128;
  localparam int unsigned ICacheLineCount = 128;
  localparam int unsigned ICacheSets      = 4;

  // Be careful on unsigned long int passed in from configuration
  // Currently use fixed values
  localparam int unsigned TCDMStartAddr   = 32'hBFFF_F800;
  localparam int unsigned TCDMSize        = 32'h800;

  localparam int unsigned PeriStartAddr   = 32'hC000_0000;

  localparam int unsigned BootAddr        = 32'h1000;

  // UART Configuration
  localparam int unsigned UartAddr        = 32'hC001_0000;

  function automatic snitch_pma_pkg::rule_t [snitch_pma_pkg::NrMaxRules-1:0] get_cached_regions();
    automatic snitch_pma_pkg::rule_t [snitch_pma_pkg::NrMaxRules-1:0] cached_regions;
    cached_regions = '{default: '0};
    cached_regions[0] = '{base: 32'h80000000, mask: 32'hfc000000};
    return cached_regions;
  endfunction

  localparam snitch_pma_pkg::snitch_pma_t SnitchPMACfg = '{
      NrCachedRegionRules: 1,
      CachedRegion: get_cached_regions(),
      default: 0
  };

  /////////////////
  //  Spatz Core //
  /////////////////

  localparam int unsigned NFpu          = `ifdef SPATZ_NUM_FPU `SPATZ_NUM_FPU `else 0 `endif;
  localparam int unsigned NIpu          = `ifdef SPATZ_NUM_IPU `SPATZ_NUM_IPU `else 1 `endif;

  localparam int unsigned NumIntOutstandingLoads   [NumCores] = '{default: `ifdef SNITCH_MAX_TRANS `SNITCH_MAX_TRANS `else 0 `endif};
  localparam int unsigned NumIntOutstandingMem     [NumCores] = '{default: `ifdef SNITCH_MAX_TRANS `SNITCH_MAX_TRANS `else 0 `endif};
  localparam int unsigned NumSpatzOutstandingLoads [NumCores] = '{default: `ifdef SPATZ_MAX_TRANS `SPATZ_MAX_TRANS `else 0 `endif};

  localparam int unsigned NumAxiMaxTrans                      = 32;

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

  localparam fpu_implementation_t FPUImplementation [NumCores] = '{default: FPUImplementation_Core};

  ////////////////////
  //  CachePool L1  //
  ////////////////////

  // Stack: 128*32/8 = 512 Byte per core
  localparam int unsigned SpmStackDepth       = `ifdef STACK_HW_DEPTH `STACK_HW_DEPTH `else 0 `endif;
  localparam int unsigned SpmStackSize        = `ifdef STACK_HW_SIZE `STACK_HW_SIZE `else 0 `endif;

  // Total Stack Size in Byte (Shared in main memory + SpmStack)
  localparam int unsigned TotStackDepth       = `ifdef STACK_TOT_DEPTH `STACK_TOT_DEPTH `else 0 `endif;
  localparam int unsigned TotStackSize        = `ifdef STACK_TOT_SIZE `STACK_TOT_SIZE `else 0 `endif;

  // Address width of cache
  localparam int unsigned L1AddrWidth         = `ifdef ADDR_WIDTH `ADDR_WIDTH `else 0 `endif;
  // Cache lane width
  localparam int unsigned L1LineWidth         = `ifdef L1D_CACHELINE_WIDTH `L1D_CACHELINE_WIDTH `else 0 `endif;
  // Coalecser window
  localparam int unsigned L1CoalFactor        = `ifdef L1D_COAL_WINDOW `L1D_COAL_WINDOW `else 0 `endif;
  // Number of cache controller (now is fixde to NrCores (if we change it, we need to change the controller axi output id width too)
  localparam int unsigned NumL1CacheCtrl      = `ifdef NUM_CORES_PER_TILE `NUM_CORES_PER_TILE `else 0 `endif;
  // Number of ways per cache controller
  localparam int unsigned L1AssoPerCtrl       = `ifdef L1D_NUM_WAY `L1D_NUM_WAY `else 0 `endif;
  // Pesudo dual bank
  localparam int unsigned L1BankFactor        = 2;
  // DataWidth of Tag bank
  localparam int unsigned L1TagDataWidth      = `ifdef L1D_TAG_DATA_WIDTH `L1D_TAG_DATA_WIDTH `else 0 `endif;

  // Number of data banks assigned to each cache controller
  localparam int unsigned NumDataBankPerCtrl  = (L1LineWidth / SpatzDataWidth) * L1AssoPerCtrl * L1BankFactor;
  // Number of tag banks assigned to each cache controller
  localparam int unsigned NumTagBankPerCtrl   = L1AssoPerCtrl * L1BankFactor;
  // Number of entrys of L1 Cache (total number across multiple cache controllers)
  localparam int unsigned L1NumEntry          = NumBank * L1Depth * SpatzDataWidth / L1LineWidth;
  // Number of cache entries each cache way has
  localparam int unsigned L1CacheWayEntry     = L1NumEntry / L1AssoPerCtrl / NumL1CacheCtrl;
  // Number of entries per cache controller
  localparam int unsigned L1NumEntryPerCtrl   = L1NumEntry / NumL1CacheCtrl;
  // Number of cache sets each cache way has
  localparam int unsigned L1NumSet            = L1CacheWayEntry / L1BankFactor;

  localparam int unsigned CoreIDWidth         = cf_math_pkg::idx_width(NumCores);
  localparam int unsigned BankIDWidth         = cf_math_pkg::idx_width(NumL1CacheCtrl);

  localparam int unsigned RefillDataWidth     = `ifdef REFILL_DATA_WIDTH `REFILL_DATA_WIDTH `else 0 `endif;
  localparam int unsigned RefillStrbWidth     = RefillDataWidth / 8;

  localparam int unsigned Burst_Enable        = (L1LineWidth > RefillDataWidth);

  typedef logic [$clog2(NumSpatzOutstandingLoads[0])-1:0] reqid_t;

  typedef logic [$clog2(L1CacheWayEntry)-1:0] cache_ways_entry_ptr_t;
  typedef logic [$clog2(L1AssoPerCtrl)-1:0]   way_ptr_t;

  typedef logic [RefillDataWidth-1:0]                     refill_data_t;
  typedef logic [RefillStrbWidth-1:0]                     refill_strb_t;
  typedef logic [$clog2(L1LineWidth/RefillDataWidth)-1:0] burst_len_t;

  typedef struct packed {
    logic        is_burst;
    burst_len_t  burst_len;
  } burst_req_t;

  typedef struct packed {
      logic                  for_write_pend;
      cache_ways_entry_ptr_t depth;
      way_ptr_t              way;
  } cache_info_t;

  typedef struct packed {
    logic [CoreIDWidth-1:0] core_id;
    logic                   is_amo;
    reqid_t                 req_id;
    logic                   is_fpu;
  } tcdm_user_t;

  typedef struct packed {
    logic [BankIDWidth:0]   bank_id;
    cache_info_t            info;
    burst_req_t             burst;
  } refill_user_t;

  // Do we need to keep DMA here?
  localparam int unsigned NumTileWideAxi      = 2;
  typedef enum integer {
    TileBootROM       = 0,
    TileMem           = 1
  } tile_wide_e;

  localparam int unsigned NumTileNarrowAxi    = 1;
  typedef enum integer {
    TilePeriph        = 0
  } tile_narrow_e;

  typedef enum integer {
    L2Channel0         = 0,
    L2Channel1         = 1,
    L2Channel2         = 2,
    L2Channel3         = 3
  } cluster_slv_e;

  // Cache refill bus
  // This bus is at the interface of each cache controller
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

  `REQRSP_TYPEDEF_ALL (cache_trans, axi_addr_t, axi_data_t, axi_strb_t, refill_user_t)

  // L2 Memory
  localparam int unsigned NumL2Channel        = `ifdef L2_CHANNEL `L2_CHANNEL `else 0 `endif;
  localparam int unsigned L2BankWidth         = `ifdef L2_BANK_WIDTH `L2_BANK_WIDTH `else 0 `endif;
  localparam int unsigned L2BankBeWidth       = L2BankWidth / 8;
  parameter               DramType            = "DDR4"; // "DDR4", "DDR3", "HBM2", "LPDDR4"
  parameter  int unsigned DramBase            = 32'h8000_0000;

  // TODO: multi-tile support
  // One more from the Snitch core
  localparam int unsigned NumClusterMst    = 1 + NumL1CacheCtrl;
  // One more for UART?
  localparam int unsigned NumClusterSlv    = NumL2Channel;

  `REQRSP_TYPEDEF_ALL (l2,          axi_addr_t, axi_data_t, axi_strb_t, refill_user_t)

  // DRAM Configuration
  localparam int unsigned DramAddr        = 32'h8000_0000;
  localparam int unsigned DramSize        = 32'h4000_0000; // 1GB
  localparam int unsigned DramPerChSize   = DramSize / NumL2Channel;

  // DRAM Interleaving Functions
  typedef struct packed {
    int                           dram_ctrl_id;
    logic [SpatzAxiAddrWidth-1:0] dram_ctrl_addr;
  } dram_ctrl_interleave_t;

  // Currently set to 16 for now
  parameter int unsigned Interleave  = `ifdef L2_INTERLEAVE `L2_INTERLEAVE `else 0 `endif;

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
      // input address needs to move the dram_id bits to correct location for interleaving
      // [Reminder][InterChange][Scramble][Constant] => [Reminder][Scramble][InterChange][Constant]
      // log2(32'h0100_0000) = 24
      // 32'h0100_0000 has 24b trailing zeros => in total 24b offset
      localparam int unsigned SizeOffsetBits  = $clog2(DramPerChSize);
      // log2(512/8*8) = 9, can be modified to find best pattern
      localparam int unsigned ConstantBits    = $clog2(L2BankBeWidth * Interleave);
      // log2(32'h0100_0000) - 9 = 24 - 9 = 15
      localparam int unsigned InterChangeBits = SizeOffsetBits - ConstantBits;
      // log2(4) = 2
      localparam int unsigned ScrambleBits    = $clog2(NumL2Channel);
      // 32 - 24 - 2 = 6
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
      // input address needs to move the dram_id bits to correct location for interleaving
      // [Reminder][Scramble][InterChange][Constant] => [Reminder][InterChange][Scramble][Constant]
      // log2(32'h0100_0000) = 24
      localparam int unsigned SizeOffsetBits  = $clog2(DramPerChSize);
      // log2(512/8*8) = 9
      localparam int unsigned ConstantBits    = $clog2(L2BankBeWidth * Interleave);
      // log2(32'h0100_0000) - 9 = 24 - 9 = 15
      localparam int unsigned InterChangeBits = SizeOffsetBits - ConstantBits;
      // log2(4) = 2
      localparam int unsigned ScrambleBits    = $clog2(NumL2Channel);
      // 32 - 24 - 2 = 6
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
