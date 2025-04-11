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

  localparam int unsigned NumTiles = 1;

  ///////////
  //  AXI  //
  ///////////

  // AXI Data Width
  localparam int unsigned SpatzAxiDataWidth = 256;
  localparam int unsigned SpatzAxiStrbWidth = SpatzAxiDataWidth / 8;
  localparam int unsigned SpatzAxiNarrowDataWidth = 64;
  // AXI Address Width
  localparam int unsigned SpatzAxiAddrWidth = 32;
  // AXI ID Width
  localparam int unsigned SpatzAxiIdInWidth = 6;
  localparam int unsigned SpatzAxiIdOutWidth = 2;

  // FIXED AxiIdOutWidth
  localparam int unsigned IwcAxiIdOutWidth = 3 + $clog2(4);

  // AXI User Width
  localparam int unsigned SpatzAxiUserWidth = 10;


  typedef logic [SpatzAxiDataWidth-1:0] axi_data_t;
  typedef logic [SpatzAxiStrbWidth-1:0] axi_strb_t;
  typedef logic [SpatzAxiAddrWidth-1:0] axi_addr_t;
  typedef logic [SpatzAxiIdInWidth-1:0] axi_id_in_t;
  typedef logic [SpatzAxiIdOutWidth-1:0] axi_id_out_t;
  typedef logic [SpatzAxiUserWidth-1:0] axi_user_t;


  `AXI_TYPEDEF_ALL(spatz_axi_in, axi_addr_t, axi_id_in_t, logic [63:0], logic [7:0], axi_user_t)
  `AXI_TYPEDEF_ALL(spatz_axi_out, axi_addr_t, axi_id_out_t, axi_data_t, axi_strb_t, axi_user_t)

  typedef logic [IwcAxiIdOutWidth-1:0] axi_id_out_iwc_t;

  `AXI_TYPEDEF_ALL(spatz_axi_iwc_out, axi_addr_t, axi_id_out_iwc_t, axi_data_t, axi_strb_t, axi_user_t)

  ////////////////////
  //  Spatz Cluster //
  ////////////////////

  localparam int unsigned NumCores   = 4;

  localparam int unsigned DataWidth  = 64;
  localparam int unsigned BeWidth    = DataWidth / 8;
  localparam int unsigned ByteOffset = $clog2(BeWidth);

  localparam int unsigned ICacheLineWidth = 128;
  localparam int unsigned ICacheLineCount = 128;
  localparam int unsigned ICacheSets = 2;

  localparam int unsigned TCDMStartAddr = 32'h5100_0000;
  localparam int unsigned TCDMSize      = 32'h2_0000;

  localparam int unsigned PeriStartAddr = TCDMStartAddr + TCDMSize;

  localparam int unsigned BootAddr      = 32'h1000;

  // L2 Configuration
  localparam int unsigned L2Addr        = 48'h5180_0000;
  localparam int unsigned L2Size        = 48'h0080_0000;

  function automatic snitch_pma_pkg::rule_t [snitch_pma_pkg::NrMaxRules-1:0] get_cached_regions();
    automatic snitch_pma_pkg::rule_t [snitch_pma_pkg::NrMaxRules-1:0] cached_regions;
    cached_regions = '{default: '0};
    cached_regions[0] = '{base: 32'h80000000, mask: 32'h80000000};
    cached_regions[1] = '{base: 32'h51800000, mask: 32'hff800000};
    return cached_regions;
  endfunction

  localparam snitch_pma_pkg::snitch_pma_t SnitchPMACfg = '{
      NrCachedRegionRules: 2,
      CachedRegion: get_cached_regions(),
      default: 0
  };

  /////////////////
  //  Spatz Core //
  /////////////////

  localparam int unsigned NFpu          = 4;
  localparam int unsigned NIpu          = 4;


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

  // Number of Cache Banks per Tile
  // localparam int unsigned L1CacheBank     = 1;

  // // L1 Cache
  // localparam int unsigned L1AddrWidth     = 32;
  // localparam int unsigned L1LineWidth     = 256;
  // localparam int unsigned L1Associativity = 4;
  // localparam int unsigned L1BankFactor    = 2;
  // localparam int unsigned L1CoalFactor    = 2;
  // // 8 * 1024 * 64 / 512 = 1024)
  // localparam int unsigned L1NumEntry      = NrBanks * TCDMDepth * DataWidth / L1LineWidth;
  // localparam int unsigned L1NumWrapper    = L1LineWidth / DataWidth;
  // localparam int unsigned L1BankPerWP     = L1BankFactor * L1Associativity;
  // localparam int unsigned L1BankPerWay    = L1BankFactor * L1NumWrapper;
  // localparam int unsigned L1CacheWayEntry = L1NumEntry / L1Associativity;
  // localparam int unsigned L1NumSet        = L1CacheWayEntry / L1BankFactor;
  // localparam int unsigned L1NumTagBank    = L1BankFactor * L1Associativity;
  // localparam int unsigned L1NumDataBank   = L1BankFactor * L1NumWrapper * L1Associativity;

endpackage : cachepool_pkg
