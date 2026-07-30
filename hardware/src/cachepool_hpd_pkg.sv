// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Ho Tin Hung, ETH Zurich <hohung@ethz.ch>
//
// Private L1 (LP1) HPDcache configuration, geometry and type definitions.
//
// Everything the per-core private-L1 datapath needs to agree on lives here so
// that the tile (cachepool_tile) and the controller (cachepool_l1_ctrl) share a
// single definition instead of threading ~30 `parameter type`s across the
// hierarchy. All inputs resolve to global package constants
// (cachepool_pkg / spatz_pkg / hpdcache_pkg), so this content is elaboration-
// time constant and does not depend on any module instance.

`include "hpdcache_typedef.svh"

package cachepool_hpd_pkg;
  import cachepool_pkg::*;
  import hpdcache_pkg::*;

  // Physical-address width seen by the private L1 (TCDM address space).
  localparam int unsigned TCDMAddrWidth = 32;

  ////////////////////////////////////////////
  // Private L1 (LP1) HPDcache config & types //
  ////////////////////////////////////////////

  // Spatz coalescer geometry
  localparam int unsigned NrLP1CoalInputs      = NrTCDMPortsPerCore - 1;                     // Spatz lanes
  localparam int unsigned LP1ExtPorts          = NrLP1CoalInputs;
  localparam int unsigned LP1WordWidth         = 128;                                        // HPDcache word width
  localparam int unsigned LP1NrBitsCoalOffset  = $clog2(LP1WordWidth/spatz_pkg::DataWidth);  // coalescer offset_t width
  localparam int unsigned LP1NumWordOffsetBits = $clog2(LP1WordWidth/spatz_pkg::DataWidth);  // tid word-offset field
  localparam int unsigned LP1CoalInfoWidth     = LP1ExtPorts + LP1ExtPorts*LP1NrBitsCoalOffset;
  localparam int unsigned LP1ReqIdWidth        = $clog2(NumSpatzOutstandingLoads);
  localparam int unsigned LP1TidWidth          = CoreIDWidth + TileIDWidth + LP1ReqIdWidth + 2 + LP1CoalInfoWidth; // +2: is_fpu, write; tile_id+core_id round-tripped
  localparam int unsigned LP1NrRequesters      = 3;                                          // Spatz(coalesced) + Snitch + CMO injector
  localparam int unsigned LP1NumSets           = 16;
  localparam int unsigned LP1NumWays           = 4;
  localparam int unsigned LP1NumWordsPerLine   = 4;

  localparam hpdcache_pkg::hpdcache_user_cfg_t HPDcacheUserCfg = '{
      nRequesters:        LP1NrRequesters,
      paWidth:            TCDMAddrWidth,
      wordWidth:          LP1WordWidth,
      sets:               LP1NumSets,
      ways:               LP1NumWays,
      clWords:            LP1NumWordsPerLine,
      reqWords:           1,
      reqTransIdWidth:    LP1TidWidth + LP1NumWordOffsetBits,
      reqSrcIdWidth:      $clog2(LP1NrRequesters), // selects requester port (0 Spatz / 1 Snitch / 2 CMO)
      victimSel:          hpdcache_pkg::HPDCACHE_VICTIM_RANDOM,
      dataWaysPerRamWord: 1,
      dataSetsPerRam:     LP1NumSets,
      dataRamByteEnable:  1'b1,
      accessWords:        LP1NumWordsPerLine,
      mshrSets:           4,
      mshrWays:           4,
      mshrWaysPerRamWord: 4,
      mshrSetsPerRam:     4,
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
      // memIdWidth:         LP1TidWidth,
      memIdWidth:         $clog2(NumSpatzOutstandingLoads),
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

endpackage
