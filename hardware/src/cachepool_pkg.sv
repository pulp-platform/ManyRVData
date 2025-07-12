// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

package cachepool_pkg;
  import fpnew_pkg::*;

  /*********************
   *  TILE PARAMETERS  *
   *********************/

  `include "axi/assign.svh"
  `include "axi/typedef.svh"
  `include "reqrsp_interface/assign.svh"
  `include "reqrsp_interface/typedef.svh"

  localparam int unsigned NumTiles = 1;

  ///////////
  //  AXI  //
  ///////////

  // AXI Data Width
  localparam int unsigned SpatzAxiDataWidth       = 128;
  localparam int unsigned SpatzAxiStrbWidth       = SpatzAxiDataWidth / 8;
  localparam int unsigned SpatzAxiNarrowDataWidth = 32;
  // AXI Address Width
  localparam int unsigned SpatzAxiAddrWidth       = 32;
  // AXI ID Width
  localparam int unsigned SpatzAxiIdInWidth       = 6;
  localparam int unsigned SpatzAxiIdOutWidth      = 8;

  // FIXED AxiIdOutWidth
  // Add 3 because of cache controller (second-level xbar, 4 cache, 1 old port)
  localparam int unsigned IwcAxiIdOutWidth        = 3 + $clog2(4) + 3;

  // AXI User Width
  localparam int unsigned SpatzAxiUserWidth       = 10;


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

  localparam int unsigned NumCores        = 4;
  // TODO: read from CFG
  localparam int unsigned NumBank         = 16;
  localparam int unsigned TCDMDepth       = 256;
  localparam int unsigned L1Depth         = 4096;

  localparam int unsigned SpatzDataWidth  = 32;
  localparam int unsigned BeWidth         = SpatzDataWidth / 8;
  localparam int unsigned ByteOffset      = $clog2(BeWidth);

  localparam int unsigned ICacheLineWidth = 128;
  localparam int unsigned ICacheLineCount = 128;
  localparam int unsigned ICacheSets      = 2;

  localparam int unsigned TCDMStartAddr   = 32'h5100_0000;
  localparam int unsigned TCDMSize        = 32'h4000;

  localparam int unsigned PeriStartAddr   = TCDMStartAddr + TCDMSize;

  localparam int unsigned BootAddr        = 32'h1000;


  // UART Configuration
  localparam int unsigned UartAddr        = 32'hC000_0000;

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

  localparam int unsigned NFpu          = 4;
  localparam int unsigned NIpu          = 4;

  localparam int unsigned NumIntOutstandingLoads   [NumCores] = '{default: 64};
  localparam int unsigned NumIntOutstandingMem     [NumCores] = '{default: 64};
  localparam int unsigned NumSpatzOutstandingLoads [NumCores] = '{default: 64};

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

  // Stack
  localparam int unsigned StackDepth          = 512;

  // Address width of cache
  localparam int unsigned L1AddrWidth         = 32;
  // Cache lane width
  localparam int unsigned L1LineWidth         = SpatzAxiDataWidth;
  // Coalecser window
  localparam int unsigned L1CoalFactor        = 2;
  // Total number of Data banks
  localparam int unsigned L1NumDataBank       = 128;
  // Number of bank wraps SPM can see
  localparam int unsigned L1NumWrapper        = NumBank;
  // SPM view: Number of banks in each bank wrap (Use to mitigate routing complexity of such many banks)
  localparam int unsigned L1BankPerWP         = L1NumDataBank / NumBank;
  // Pesudo dual bank
  localparam int unsigned L1BankFactor        = 2;
  // Cache ways (total way number across multiple cache controllers)
  localparam int unsigned L1Associativity     = L1NumDataBank / (L1LineWidth / SpatzDataWidth) / L1BankFactor;
  // 8 * 1024 * 64 / 512 = 1024)
  // Number of entrys of L1 Cache (total number across multiple cache controllers)
  localparam int unsigned L1NumEntry          = NumBank * L1Depth * SpatzDataWidth / L1LineWidth;
  // Number of cache entries each cache way has
  localparam int unsigned L1CacheWayEntry     = L1NumEntry / L1Associativity;
  // Number of cache sets each cache way has
  localparam int unsigned L1NumSet            = L1CacheWayEntry / L1BankFactor;
  // Number of Tag banks
  localparam int unsigned L1NumTagBank        = L1BankFactor * L1Associativity;
  // Number of lines per bank unit
  localparam int unsigned DepthPerBank        = L1Depth / L1BankPerWP;
  // Cache total size in KB
  localparam int unsigned L1Size              = NumBank * L1Depth * BeWidth / 1024;

  localparam int unsigned L1TagDataWidth      = 64;

  // Number of cache controller (now is fixde to NrCores (if we change it, we need to change the controller axi output id width too)
  localparam int unsigned NumL1CacheCtrl      = NumCores;
  // Number of data banks assigned to each cache controller
  localparam int unsigned NumDataBankPerCtrl  = L1NumDataBank / NumL1CacheCtrl;
  // Number of tag banks assigned to each cache controller
  localparam int unsigned NumTagBankPerCtrl   = L1NumTagBank / NumL1CacheCtrl;
  // Number of ways per cache controller
  localparam int unsigned L1AssoPerCtrl       = L1Associativity / NumL1CacheCtrl;
  // Number of entries per cache controller
  localparam int unsigned L1NumEntryPerCtrl   = L1NumEntry / NumL1CacheCtrl;

  localparam int unsigned CoreIDWidth       = cf_math_pkg::idx_width(NumCores);
  localparam int unsigned BankIDWidth       = cf_math_pkg::idx_width(NumL1CacheCtrl);

  typedef logic [$clog2(NumSpatzOutstandingLoads[0])-1:0] reqid_t;

  typedef logic [$clog2(L1CacheWayEntry)-1:0] cache_ways_entry_ptr_t;
  typedef logic [$clog2(L1AssoPerCtrl)-1:0]   way_ptr_t;

  typedef struct packed {
      logic                  for_write_pend;
      cache_ways_entry_ptr_t depth;
      way_ptr_t              way;
  } cache_info_t;

  typedef struct packed {
    logic [CoreIDWidth-1:0] core_id;
    logic is_amo;
    reqid_t req_id;
  } tcdm_user_t;

  typedef struct packed {
    logic [BankIDWidth:0]   bank_id;
    cache_info_t            info;
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
    axi_addr_t   addr;
    cache_info_t info;
    logic        write;
    axi_data_t   wdata;
    axi_strb_t   wstrb;
  } cache_refill_req_chan_t;

  typedef struct packed {
    logic        write;
    axi_data_t   data;
    cache_info_t info;
  } cache_refill_rsp_chan_t;

  `REQRSP_TYPEDEF_ALL (cache_trans, axi_addr_t, axi_data_t, axi_strb_t, refill_user_t)

  // L2 Memory
  localparam int unsigned NumL2Channel        = 4;
  localparam int unsigned L2BankWidth         = 256;
  localparam int unsigned L2BankBeWidth       = L2BankWidth / 8;
  parameter               DramType            = "DDR4"; // "DDR4", "DDR3", "HBM2", "LPDDR4"
  parameter  int unsigned DramBase            = 32'h8000_0000;

  // TODO: multi-tile support
  // One more from the Snitch core
  localparam int unsigned NumClusterMst    = 1 + NumL1CacheCtrl;
  // One more for UART?
  localparam int unsigned NumClusterSlv    = NumL2Channel;

  // Additional id for route back
  typedef struct packed {
    logic [BankIDWidth:0]                      bank_id;
    cache_info_t                               info;
  } l2_user_t;

  `REQRSP_TYPEDEF_ALL (l2,          axi_addr_t, axi_data_t, axi_strb_t, l2_user_t)

  // DRAM Configuration
  localparam int unsigned DramAddr        = 32'h8000_0000;
  localparam int unsigned DramSize        = 32'h4000_0000; // 1GB
  localparam int unsigned DramPerChSize   = DramSize / NumL2Channel;

`ifdef TARGET_DRAMSYS
  // DRAM Interleaving Functions
  typedef struct packed {
    int                           dram_ctrl_id;
    logic [SpatzAxiAddrWidth-1:0] dram_ctrl_addr;
  } dram_ctrl_interleave_t;

  // Currently set to 16 for now
  parameter int unsigned Interleave  = 512;

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

`endif


endpackage : cachepool_pkg
