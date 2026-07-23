// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Ho Tin Hung, ETH Zurich <hohung@ethz.ch>
//
// Per-core private L1 data cache controller.
//
// Core side is a plain TCDM interface: NrTCDMPortsPerCore request/response
// streams (the Spatz lanes + one Snitch port). Inside, this module:
//   * coalesces the Spatz lanes into one wide HPDcache request (sid=0),
//   * translates the Snitch port into one HPDcache request (sid=1),
//   * packs all metadata that must survive the HPDcache round-trip into `tid`,
//   * runs one HPDcache (write-through, no coherence) as the private L1,
//   * merges HPDcache's mem read/write channels into one downstream TCDM pair
//     (l2_req_o/l2_rsp_i) that feeds the shared distributed L2 through the
//     existing tcdm_cache_interco,
//   * scatters the response back to the originating lanes.
//
// No cache coherence is implemented here. Write-through narrows but does not
// close the cross-core shared-data window; that is accepted for now.
//
// Coalescer metadata has no package; all coalescer-facing types (tcdm_meta_t,
// downstream_info_t, word_offset_t, ...) are defined at the tile and passed in
// as parameters.
`include "axi/typedef.svh"
`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"
`include "reqrsp_interface/typedef.svh"
`include "snitch_vm/typedef.svh"
`include "hpdcache_typedef.svh"

module cachepool_l1_ctrl
  import cachepool_pkg::*;
  import hpdcache_pkg::*;
  import reqrsp_pkg::*;
#(
  // Core-side topology
  parameter int unsigned NrTCDMPortsPerCore = 5,   // Spatz lanes + 1 Snitch
  parameter int unsigned DataWidth          = 32,  // narrow (per-lane) data width
  parameter int unsigned ByteWidth          = 8,

  // tid / coalescer geometry (must match the types below)
  parameter int unsigned LP1NumWordOffsetBits = 2, // $clog2(wordWidth/DataWidth)
  parameter int unsigned LP1NrBitsCoalOffset  = 2, // bits per coalescer ofst entry
                                                   // (lane count is NrLP1CoalInputs, derived below)

  parameter hpdcache_cfg_t HPDcacheCfg = '0,
  parameter type wbuf_timecnt_t = logic,

  // Core-side TCDM request/response
  parameter type l1_cache_req_t = logic,
  parameter type l1_cache_rsp_t = logic,

  // Coalescer payload types (defined at tile)
  parameter type tcdm_meta_t       = logic,  // { tcdm_user_t user; logic write; hpdcache_req_op_t amo; }
  parameter type downstream_info_t = logic,  // par_coalescer_top downstream info struct
  parameter type word_offset_t     = logic,  // logic[LP1NumWordOffsetBits-1:0]

  // Downstream (L2) TCDM request/response
  parameter type l2_cache_req_t = logic,
  parameter type l2_cache_rsp_t = logic,

  //  HPDcache request interface types
  parameter type hpdcache_tag_t        = logic,
  parameter type hpdcache_data_word_t  = logic,
  parameter type hpdcache_data_be_t    = logic,
  parameter type hpdcache_req_offset_t = logic,
  parameter type hpdcache_req_data_t   = logic,
  parameter type hpdcache_req_be_t     = logic,
  parameter type hpdcache_req_sid_t    = logic,
  parameter type hpdcache_req_tid_t    = logic,
  parameter type hpdcache_req_t        = logic,
  parameter type hpdcache_rsp_t        = logic,

  //  HPDcache memory interface types
  parameter type hpdcache_mem_addr_t   = logic,
  parameter type hpdcache_mem_id_t     = logic,
  parameter type hpdcache_mem_data_t   = logic,
  parameter type hpdcache_mem_be_t     = logic,
  parameter type hpdcache_mem_req_t    = logic,
  parameter type hpdcache_mem_req_w_t  = logic,
  parameter type hpdcache_mem_resp_r_t = logic,
  parameter type hpdcache_mem_resp_w_t = logic
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic wbuf_flush_i,

  //  Per-core CMO injector interface (driven by this core via CSR_LP1CMO).
  //  lp1_cmo_valid_i is held while a `csrw CSR_LP1CMO` stalls the core; it
  //  requests the CMO in lp1_cmo_req_i.  lp1_cmo_done_o pulses when the CMO has
  //  completed, which releases the core's stall.
  input  lp1_cmo_req_t  lp1_cmo_req_i,
  input  logic          lp1_cmo_valid_i,
  output logic          lp1_cmo_done_o,

  //  Core-side TCDM interface (Spatz lanes [0..NrLP1CoalInputs-1] + Snitch [last]).
  //  Request handshake : core_req_i.q_valid / core_req_ready_o
  //  Response handshake: core_rsp_o.p_valid  / core_rsp_ready_i
  input  l1_cache_req_t [NrTCDMPortsPerCore-1:0] core_req_i,
  output l1_cache_rsp_t [NrTCDMPortsPerCore-1:0] core_rsp_o,
  output logic          [NrTCDMPortsPerCore-1:0] core_req_ready_o,
  input  logic          [NrTCDMPortsPerCore-1:0] core_rsp_ready_i,

  //  Downstream (L2) TCDM interface
  output l2_cache_req_t l2_req_o,
  input  l2_cache_rsp_t l2_rsp_i,
  output logic          l2_rsp_ready_o,  // response ready -> interco core_rsp_ready_i

  //  Performance events
  output logic          evt_cache_write_miss_o,
  output logic          evt_cache_read_miss_o,
  output logic          evt_cache_dir_unc_err_o,
  output logic          evt_cache_dir_cor_err_o,
  output logic          evt_cache_dat_unc_err_o,
  output logic          evt_cache_dat_cor_err_o,
  output logic          evt_scrub_complete_o,
  output logic          evt_uncached_req_o,
  output logic          evt_cmo_req_o,
  output logic          evt_write_req_o,
  output logic          evt_read_req_o,
  output logic          evt_prefetch_req_o,
  output logic          evt_req_on_hold_o,
  output logic          evt_rtab_rollback_o,
  output logic          evt_stall_refill_o,
  output logic          evt_stall_o,

  //  Status interface
  output logic          wbuf_empty_o,

  //  Configuration interface
  input  logic          cfg_enable_i,
  input  wbuf_timecnt_t cfg_wbuf_threshold_i,
  input  logic          cfg_wbuf_reset_timecnt_on_write_i,
  input  logic          cfg_wbuf_sequential_waw_i,
  input  logic          cfg_wbuf_inhibit_write_coalescing_i,
  input  logic          cfg_prefetch_updt_plru_i,
  input  logic          cfg_error_on_cacheable_amo_i,
  input  logic          cfg_rtab_single_entry_i,
  input  logic          cfg_default_wb_i,
  input  logic          cfg_scrub_enable_i,
  input  logic [5:0]    cfg_scrub_period_i,
  input  logic          cfg_scrub_restart_i
);

  ////////////////
  // PARAMETERS //
  ////////////////
  localparam int unsigned NrLP1CoalInputs    = NrTCDMPortsPerCore - 1;  // Spatz lanes
  localparam int unsigned SnitchPort            = NrTCDMPortsPerCore - 1;  // last port
  localparam int unsigned coalescedDataWidth    = HPDcacheCfg.u.wordWidth; // wide word
  localparam int unsigned LaneBytes             = DataWidth / ByteWidth;   // bytes per lane word
  localparam int unsigned WordBytes             = coalescedDataWidth / ByteWidth;

  // tid layout (one fixed, non-overlapping scheme), MSB -> LSB:
  //   { word_offset | is_fpu | tile_id | core_id | write | req_id | ofsts | hitmap }
  // Snitch path uses word_offset (ofsts/hitmap = 0); Spatz path uses ofsts/hitmap
  // (word_offset = 0). The {is_fpu, tile_id, core_id, write, req_id} block is at
  // fixed positions for both. sid (0 Spatz / 1 Snitch) selects the unpack path.
  // tile_id is round-tripped so the core-side response recovers the full origin
  // metadata (the private L1 is otherwise core/tile-agnostic).
  localparam int unsigned ReqIdW        = $bits(reqid_t);
  localparam int unsigned HitmapW       = NrLP1CoalInputs;
  localparam int unsigned OfstsW        = NrLP1CoalInputs * LP1NrBitsCoalOffset;
  localparam int unsigned CoalInfoW     = HitmapW + OfstsW;
  localparam int unsigned TidUserW      = CoreIDWidth + TileIDWidth + ReqIdW + 2;  // {is_fpu,tile_id,core_id,write,req_id}
  localparam int unsigned HitmapLsb     = 0;
  localparam int unsigned OfstsLsb      = HitmapW;
  localparam int unsigned ReqIdLsb      = CoalInfoW;
  localparam int unsigned WritePos      = CoalInfoW + ReqIdW;
  localparam int unsigned CoreIdLsb     = CoalInfoW + ReqIdW + 1;
  localparam int unsigned TileIdLsb     = CoreIdLsb + CoreIDWidth;
  localparam int unsigned IsFpuPos      = TileIdLsb + TileIDWidth;
  localparam int unsigned WordOffLsb    = CoalInfoW + TidUserW;

  ///////////////////
  // LOCAL SIGNALS //
  ///////////////////

  // Per-port unpacked core request fields
  logic                 [NrTCDMPortsPerCore-1:0]                  cache_req_valid;
  logic                 [NrTCDMPortsPerCore-1:0]                  cache_req_ready;
  hpdcache_req_offset_t [NrTCDMPortsPerCore-1:0]                  cache_req_addr_offset;
  word_offset_t         [NrTCDMPortsPerCore-1:0]                  cache_req_word_offset;
  logic                 [NrTCDMPortsPerCore-1:0][CoreIDWidth-1:0] cache_req_coreid;
  logic                 [NrTCDMPortsPerCore-1:0][TileIDWidth-1:0] cache_req_tileid;
  reqid_t               [NrTCDMPortsPerCore-1:0]                  cache_req_reqid;
  logic                 [NrTCDMPortsPerCore-1:0]                  cache_req_is_fpu;
  logic                 [NrTCDMPortsPerCore-1:0]                  cache_req_write;
  narrow_data_t         [NrTCDMPortsPerCore-1:0]                  cache_req_data;
  amo_op_e              [NrTCDMPortsPerCore-1:0]                  cache_req_amo;
  narrow_addr_t         [NrTCDMPortsPerCore-1:0]                  cache_req_addr;
  narrow_strb_t         [NrTCDMPortsPerCore-1:0]                  cache_req_strb;

  // Per-port HPDcache request view + coalescer info payload
  hpdcache_req_t [NrTCDMPortsPerCore-1:0] l1_cache_req;
  tcdm_meta_t    [NrTCDMPortsPerCore-1:0] cache_req_info;

  // Coalescer downstream request payload (Spatz path)
  logic                              coal_req_valid;
  logic                              coal_req_ready;
  narrow_addr_t                      coal_req_addr;
  downstream_info_t                  coal_req_info;
  logic                              coal_req_write;
  logic [coalescedDataWidth-1:0]     coal_req_wdata;
  logic [WordBytes-1:0]              coal_req_wmask;

  // Coalescer upstream response (Spatz lanes)
  logic         [NrLP1CoalInputs-1:0] coal_resp_valid;
  logic         [NrLP1CoalInputs-1:0] coal_resp_ready;
  logic         [NrLP1CoalInputs-1:0] coal_resp_write;
  narrow_data_t [NrLP1CoalInputs-1:0] coal_resp_data;
  tcdm_meta_t   [NrLP1CoalInputs-1:0] coal_resp_info;

  // Coalescer downstream response payload (reconstructed from the HPDcache rsp)
  logic             coal_resp_down_valid;
  logic             coal_resp_down_ready;
  downstream_info_t coal_resp_down_info;
  logic             coal_resp_down_write;

  // HPDcache requester arrays (0 = Spatz, 1 = Snitch)
  logic          l1_req_valid [HPDcacheCfg.u.nRequesters];
  logic          l1_req_ready [HPDcacheCfg.u.nRequesters];
  hpdcache_req_t l1_req       [HPDcacheCfg.u.nRequesters];
  logic          l1_rsp_valid [HPDcacheCfg.u.nRequesters];
  hpdcache_rsp_t l1_rsp       [HPDcacheCfg.u.nRequesters];
  logic          core_req_abort [HPDcacheCfg.u.nRequesters];
  hpdcache_tag_t core_req_tag   [HPDcacheCfg.u.nRequesters];
  hpdcache_pma_t dummy_pma      [HPDcacheCfg.u.nRequesters];

  // HPDcache <-> L2 mem channels
  hpdcache_mem_req_t    l1_mem_req_read, l1_mem_req_write, l1_l2_req;
  hpdcache_mem_req_w_t  l1_mem_req_write_data;
  logic                 l1_mem_req_read_valid,  l1_mem_req_read_ready;
  logic                 l1_mem_req_write_valid, l1_mem_req_write_ready, __l1_mem_req_write_ready;
  logic                 l1_mem_req_write_data_valid, l1_mem_req_write_data_ready;
  logic                 l1_mem_req_write_both_valid;
  logic                 l1_l2_req_valid;
  tcdm_user_t           l1_l2_req_meta;

  hpdcache_mem_resp_r_t l1_mem_resp_read;
  hpdcache_mem_resp_w_t l1_mem_resp_write;
  logic                 l1_mem_resp_read_valid,  l1_mem_resp_read_ready;
  logic                 l1_mem_resp_write_valid, l1_mem_resp_write_ready;

  ///////////////////////////////
  // Core request unpacking     //
  ///////////////////////////////
  for (genvar i = 0; i < NrTCDMPortsPerCore; i++) begin : gen_req_unpack
    // Request grant on the explicit handshake port.
    assign core_req_ready_o[i]      = cache_req_ready[i];
    assign cache_req_valid[i]       = core_req_i[i].q_valid;
    assign cache_req_addr_offset[i] = core_req_i[i].q.addr[HPDcacheCfg.reqOffsetWidth-1:0];
    assign cache_req_word_offset[i] = core_req_i[i].q.addr[$clog2(DataWidth/ByteWidth) +: LP1NumWordOffsetBits];
    assign cache_req_coreid[i]      = core_req_i[i].q.user.core_id;
    assign cache_req_tileid[i]      = core_req_i[i].q.user.tile_id;
    assign cache_req_reqid[i]       = core_req_i[i].q.user.req_id;
    assign cache_req_is_fpu[i]      = core_req_i[i].q.user.is_fpu;
    assign cache_req_write[i]       = core_req_i[i].q.write;
    assign cache_req_data[i]        = core_req_i[i].q.data;
    assign cache_req_amo[i]         = core_req_i[i].q.amo;
    assign cache_req_addr[i]        = core_req_i[i].q.addr;
    assign cache_req_strb[i]        = core_req_i[i].q.strb;
  end

  ///////////////////////////////
  // Per-port HPDcache req view //
  ///////////////////////////////
  for (genvar i = 0; i < NrTCDMPortsPerCore; i++) begin : gen_req_view
    assign l1_cache_req[i].addr_offset  = cache_req_addr_offset[i];
    assign l1_cache_req[i].wdata        = cache_req_data[i];
    assign l1_cache_req[i].be           = cache_req_strb[i];
    assign l1_cache_req[i].size         = hpdcache_req_size_t'($clog2(coalescedDataWidth/8));
    assign l1_cache_req[i].sid          = hpdcache_req_sid_t'(!cache_req_is_fpu[i]);  // 0 Spatz / 1 Snitch
    assign l1_cache_req[i].need_rsp     = 1'b1;
    assign l1_cache_req[i].phys_indexed = 1'b1;
    assign l1_cache_req[i].addr_tag     = cache_req_addr[i][HPDcacheCfg.reqOffsetWidth +: HPDcacheCfg.tagWidth];
    assign l1_cache_req[i].pma.uncacheable    = 1'b0;
    assign l1_cache_req[i].pma.io             = 1'b0;
    assign l1_cache_req[i].pma.wr_policy_hint = HPDCACHE_WR_POLICY_WT;
    // Snitch-path tid (per-port). Spatz lanes get their tid rebuilt post-coalesce.
    assign l1_cache_req[i].tid          = pack_tid_snitch(cache_req_word_offset[i],
                                                          cache_req_is_fpu[i],
                                                          cache_req_tileid[i],
                                                          cache_req_coreid[i],
                                                          cache_req_write[i],
                                                          cache_req_reqid[i]);

    // Op map (loads/stores/AMOs). AMOs flow through HPDcache in phase 1.
    always_comb begin : gen_op
      if (cache_req_amo[i] == AMONone) begin
        l1_cache_req[i].op = cache_req_write[i] ? HPDCACHE_REQ_STORE : HPDCACHE_REQ_LOAD;
      end else begin
        unique case (cache_req_amo[i])
          AMOSwap: l1_cache_req[i].op = HPDCACHE_REQ_AMO_SWAP;
          AMOAdd:  l1_cache_req[i].op = HPDCACHE_REQ_AMO_ADD;
          AMOAnd:  l1_cache_req[i].op = HPDCACHE_REQ_AMO_AND;
          AMOOr:   l1_cache_req[i].op = HPDCACHE_REQ_AMO_OR;
          AMOXor:  l1_cache_req[i].op = HPDCACHE_REQ_AMO_XOR;
          AMOMax:  l1_cache_req[i].op = HPDCACHE_REQ_AMO_MAX;
          AMOMaxu: l1_cache_req[i].op = HPDCACHE_REQ_AMO_MAXU;
          AMOMin:  l1_cache_req[i].op = HPDCACHE_REQ_AMO_MIN;
          AMOMinu: l1_cache_req[i].op = HPDCACHE_REQ_AMO_MINU;
          AMOLR:   l1_cache_req[i].op = HPDCACHE_REQ_AMO_LR;
          AMOSC:   l1_cache_req[i].op = HPDCACHE_REQ_AMO_SC;
          default: l1_cache_req[i].op = HPDCACHE_REQ_LOAD;
        endcase
      end
    end

    // Coalescer info payload (carried per lane, returned with the response).
    assign cache_req_info[i].user.core_id = cache_req_coreid[i];
    assign cache_req_info[i].user.tile_id = cache_req_tileid[i];  // round-tripped for core rsp
    assign cache_req_info[i].user.is_amo  = (cache_req_amo[i] != AMONone);
    assign cache_req_info[i].user.req_id  = cache_req_reqid[i];
    assign cache_req_info[i].user.is_fpu  = cache_req_is_fpu[i];
    assign cache_req_info[i].write        = cache_req_write[i];
    assign cache_req_info[i].amo          = l1_cache_req[i].op;
  end

  //////////////////////////
  // Spatz req coalescing  //
  //////////////////////////
  par_coalescer_top #(
    .ReqAddrWidth        (L1AddrWidth),
    .NumPorts            (NrLP1CoalInputs),
    .info_t              (tcdm_meta_t),
    .UpstreamDataWidth   (DataWidth),
    .DownstreamDataWidth (coalescedDataWidth),
    .ByteWidth           (ByteWidth)
  ) i_l1_req_coalescer (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .id_i   ('0),

    .upstream_req_valid_i (cache_req_valid[NrLP1CoalInputs-1:0]),
    .upstream_req_ready_o (cache_req_ready[NrLP1CoalInputs-1:0]),
    .upstream_req_addr_i  (cache_req_addr[NrLP1CoalInputs-1:0]),
    .upstream_req_info_i  (cache_req_info[NrLP1CoalInputs-1:0]),
    .upstream_req_write_i (cache_req_write[NrLP1CoalInputs-1:0]),
    .upstream_req_wdata_i (cache_req_data[NrLP1CoalInputs-1:0]),
    .upstream_req_wstrb_i (cache_req_strb[NrLP1CoalInputs-1:0]),

    .upstream_resp_valid_o (coal_resp_valid),
    .upstream_resp_ready_i (coal_resp_ready),
    .upstream_resp_write_o (coal_resp_write),
    .upstream_resp_data_o  (coal_resp_data),
    .upstream_resp_info_o  (coal_resp_info),

    .downstream_req_valid_o (coal_req_valid),
    .downstream_req_ready_i (coal_req_ready),
    .downstream_req_addr_o  (coal_req_addr),
    .downstream_req_info_o  (coal_req_info),
    .downstream_req_write_o (coal_req_write),
    .downstream_req_wdata_o (coal_req_wdata),
    .downstream_req_wmask_o (coal_req_wmask),

    .downstream_resp_valid_i (coal_resp_down_valid),
    .downstream_resp_ready_o (coal_resp_down_ready),
    .downstream_resp_data_i  (l1_rsp[0].rdata),
    .downstream_resp_info_i  (coal_resp_down_info),
    .downstream_resp_write_i (coal_resp_down_write)
  );

  //////////////////////////////////////
  // HPDcache requester 0 (Spatz/coal) //
  //////////////////////////////////////
  // Shared user for the coalesced request: all coalesced lanes belong to one
  // Spatz instruction (same core/req_id), so any hit lane's user is the shared
  // one. Pick the first hit lane.
  logic       coal_hit;
  tcdm_meta_t coal_meta;
  always_comb begin : gen_coal_shared_meta
    coal_hit  = 1'b0;
    coal_meta = '0;
    for (int unsigned id = 0; id < NrLP1CoalInputs; id++) begin
      if (coal_req_info.hitmap[id] && !coal_hit) begin
        coal_hit  = 1'b1;
        coal_meta = coal_req_info.infos[id];
      end
    end
  end

  // BE for the coalesced (wide) request: use the coalescer's wmask
  // logic [WordBytes-1:0] coal_be;
  // always_comb begin : gen_coal_be
  //   coal_be = '0;
  //   for (int unsigned id = 0; id < NrLP1CoalInputs; id++) begin
  //     if (coal_req_info.hitmap[id]) begin
  //       coal_be |= ({LaneBytes{1'b1}} << (id * LaneBytes));
  //     end
  //   end
  // end

  always_comb begin : gen_l1_req_spatz
    l1_req[0]             = '0;
    l1_req[0].addr_offset = coal_req_addr[HPDcacheCfg.reqOffsetWidth-1:0];
    l1_req[0].addr_tag    = coal_req_addr[HPDcacheCfg.reqOffsetWidth +: HPDcacheCfg.tagWidth];
    l1_req[0].wdata       = coal_req_wdata;
    l1_req[0].be = coal_req_wmask;
    // l1_req[0].be          = coal_req_write ? coal_req_wmask : coal_be;
    l1_req[0].size        = hpdcache_req_size_t'($clog2(coalescedDataWidth/8));
    l1_req[0].sid         = hpdcache_req_sid_t'(0);   // Spatz
    l1_req[0].need_rsp    = 1'b1;
    l1_req[0].phys_indexed = 1'b1;
    l1_req[0].pma.uncacheable    = 1'b0;
    l1_req[0].pma.io             = 1'b0;
    l1_req[0].pma.wr_policy_hint = HPDCACHE_WR_POLICY_WT;
    // op: AMOs are never coalesced; for an AMO carry the hit lane's op.
    l1_req[0].op  = coal_meta.user.is_amo ? coal_meta.amo
                  : (coal_req_write ? HPDCACHE_REQ_STORE : HPDCACHE_REQ_LOAD);
    // tid: pack the coalescer scatter info + shared user.
    l1_req[0].tid = coal_req_valid
                  ? pack_tid_spatz(coal_req_addr[2+:LP1NumWordOffsetBits],
                                   coal_req_info.hitmap, coal_req_info.ofsts,
                                   coal_meta.user.is_fpu, coal_meta.user.tile_id,
                                   coal_meta.user.core_id,
                                   coal_req_write, coal_meta.user.req_id)
                  : '0;
  end

  assign l1_req_valid[0] = coal_req_valid;
  assign coal_req_ready  = l1_req_ready[0];

  ///////////////////////////////////
  // HPDcache requester 1 (Snitch)  //
  ///////////////////////////////////
  // Snitch writes its narrow word into the wide cache word at its byte position.
  // assign sn_byte_pos = l1_cache_req[SnitchPort].addr_offset % WordBytes;
  logic [$clog2(WordBytes)-1:0] sn_byte_pos;
  assign sn_byte_pos = ($clog2(WordBytes))'(cache_req_word_offset[SnitchPort] * LaneBytes);

  always_comb begin : gen_l1_req_snitch
    l1_req[1]             = l1_cache_req[SnitchPort];
    l1_req[1].sid         = hpdcache_req_sid_t'(1);  // Snitch
    l1_req[1].wdata       = hpdcache_req_data_t'(cache_req_data[SnitchPort]) << (sn_byte_pos * ByteWidth);
    l1_req[1].be          = hpdcache_req_be_t'(cache_req_strb[SnitchPort]) << sn_byte_pos;
    l1_req[1].tid         = core_req_i[SnitchPort].q_valid ? l1_cache_req[SnitchPort].tid : '0;
    l1_req[1].pma.uncacheable = (cache_req_amo[SnitchPort] != AMONone);
  end

  assign l1_req_valid[1]            = core_req_i[SnitchPort].q_valid;
  assign cache_req_ready[SnitchPort] = l1_req_ready[1];

  //////////////////////////////////////////
  // HPDcache requester 2 (CMO injector)    //
  //////////////////////////////////////////
  // Converts the core's lp1_cmo_valid_i request (asserted by a `csrw CSR_LP1CMO`
  // that stalls the core) into an HPDcache CMO on requester port 2, then reports
  // completion via lp1_cmo_done_o, which releases the core's stall.  The core
  // holds only one CMO in flight (it is blocked until done), so no flow control
  // is needed on the request -- it is latched here.
  //
  //   IDLE : wait for lp1_cmo_valid_i; decode + latch op/addr.
  //   REQ  : hold l1_req_valid[2] until l1_req_ready[2] accepts the request.
  //   RESP : wait for l1_rsp_valid[2]; pulse lp1_cmo_done_o; return to IDLE.
  //
  // lp1_cmo_req_i.op encoding (from the core's CSR write):
  //   0 = FENCE (write-through WBUF drain), 1 = INVAL_ALL, 2 = INVAL_NLINE
  localparam int unsigned CmoReqId = 2;

  typedef enum logic [1:0] { CMO_IDLE, CMO_REQ, CMO_RESP } cmo_state_e;
  cmo_state_e       cmo_state_q, cmo_state_d;
  hpdcache_req_op_t cmo_op_q,    cmo_op_d;
  logic [31:0]      cmo_addr_q,  cmo_addr_d;

  // Translate the peripheral op code into the HPDcache CMO request op.
  function automatic hpdcache_req_op_t cmo_decode(input logic [2:0] op);
    case (op)
      3'd0:    cmo_decode = HPDCACHE_REQ_CMO_FENCE;
      3'd1:    cmo_decode = HPDCACHE_REQ_CMO_INVAL_ALL;
      3'd2:    cmo_decode = HPDCACHE_REQ_CMO_INVAL_NLINE;
      default: cmo_decode = HPDCACHE_REQ_CMO_FENCE;
    endcase
  endfunction

  always_comb begin : gen_l1_req_cmo
    cmo_state_d    = cmo_state_q;
    cmo_op_d       = cmo_op_q;
    cmo_addr_d     = cmo_addr_q;
    lp1_cmo_done_o = 1'b0;

    // Compose the CMO request (INVAL_NLINE uses addr; FENCE/INVAL_ALL ignore it).
    l1_req[CmoReqId]                    = '0;
    l1_req[CmoReqId].op                 = cmo_op_q;
    l1_req[CmoReqId].addr_offset        = cmo_addr_q[HPDcacheCfg.reqOffsetWidth-1:0];
    l1_req[CmoReqId].addr_tag           = cmo_addr_q[HPDcacheCfg.reqOffsetWidth +: HPDcacheCfg.tagWidth];
    l1_req[CmoReqId].sid                = hpdcache_req_sid_t'(CmoReqId);
    l1_req[CmoReqId].tid                = '0;
    l1_req[CmoReqId].need_rsp           = 1'b1;   // required: how we learn it completed
    l1_req[CmoReqId].phys_indexed       = 1'b1;
    l1_req[CmoReqId].pma.uncacheable    = 1'b0;
    l1_req[CmoReqId].pma.io             = 1'b0;
    l1_req[CmoReqId].pma.wr_policy_hint = HPDCACHE_WR_POLICY_WT;
    l1_req_valid[CmoReqId]              = 1'b0;

    unique case (cmo_state_q)
      CMO_IDLE: begin
        if (lp1_cmo_valid_i) begin
          cmo_op_d    = cmo_decode(lp1_cmo_req_i.op);
          cmo_addr_d  = lp1_cmo_req_i.addr;
          cmo_state_d = CMO_REQ;
        end
      end
      CMO_REQ: begin
        l1_req_valid[CmoReqId] = 1'b1;
        if (l1_req_ready[CmoReqId]) begin
          cmo_state_d = CMO_RESP;
        end
      end
      CMO_RESP: begin
        if (l1_rsp_valid[CmoReqId]) begin
          lp1_cmo_done_o = 1'b1;
          cmo_state_d    = CMO_IDLE;
        end
      end
      default: cmo_state_d = CMO_IDLE;
    endcase
  end

  `FF(cmo_state_q, cmo_state_d, CMO_IDLE,               clk_i, rst_ni)
  `FF(cmo_op_q,    cmo_op_d,    HPDCACHE_REQ_CMO_FENCE, clk_i, rst_ni)
  `FF(cmo_addr_q,  cmo_addr_d,  '0,                     clk_i, rst_ni)

  ///////////////////////////////
  // Spatz response scatter     //
  ///////////////////////////////
  // Rebuild the coalescer downstream response info from the round-tripped tid
  // (requester 0), then feed the coalescer so it scatters to the Spatz lanes.
  tcdm_user_t coal_resp_user;
  always_comb begin : gen_coal_resp_info
    coal_resp_down_info = '0;
    coal_resp_down_info.hitmap = l1_rsp[0].tid[HitmapLsb +: HitmapW];
    coal_resp_down_info.ofsts  = l1_rsp[0].tid[OfstsLsb  +: OfstsW];

    coal_resp_user          = '0;
    coal_resp_user.is_fpu   = l1_rsp[0].tid[IsFpuPos];
    coal_resp_user.tile_id  = l1_rsp[0].tid[TileIdLsb +: TileIDWidth];
    coal_resp_user.core_id  = l1_rsp[0].tid[CoreIdLsb +: CoreIDWidth];
    coal_resp_user.req_id   = l1_rsp[0].tid[ReqIdLsb  +: ReqIdW];
    coal_resp_user.is_amo   = 1'b0;

    // All coalesced lanes share the same user (one Spatz instruction).
    for (int unsigned j = 0; j < NrLP1CoalInputs; j++) begin
      coal_resp_down_info.infos[j].user = coal_resp_user;
      coal_resp_down_info.infos[j].write = l1_rsp[0].tid[WritePos];
      coal_resp_down_info.infos[j].amo   = HPDCACHE_REQ_LOAD;
    end
  end

  assign coal_resp_down_valid = l1_rsp_valid[0];
  assign coal_resp_down_write = l1_rsp[0].tid[WritePos];

  // Coalescer upstream responses -> Spatz lane TCDM responses. The core's
  // per-lane response ready drains the coalescer's resp FIFOs (which absorb the
  // un-back-pressurable HPDcache core response).
  for (genvar i = 0; i < NrLP1CoalInputs; i++) begin : gen_spatz_resp
    assign core_rsp_o[i].q_ready = cache_req_ready[i];   // request grant (also on core_req_ready_o)
    assign coal_resp_ready[i]    = core_rsp_ready_i[i];
    assign core_rsp_o[i].p_valid = coal_resp_valid[i];
    assign core_rsp_o[i].p.data  = coal_resp_data[i];
    assign core_rsp_o[i].p.user  = coal_resp_info[i].user;
    assign core_rsp_o[i].p.write = coal_resp_write[i];
  end

  ///////////////////////////////
  // Snitch response (bypass)   //
  ///////////////////////////////
  // NOTE: HPDcache's core response is not back-pressurable, so core_rsp_ready_i
  // [SnitchPort] cannot stall it. Snitch is scalar with a single outstanding load
  // and is assumed always ready; add a spill here if that ever changes.
  logic [$clog2(coalescedDataWidth)-1:0] sn_bit_offset;
  assign sn_bit_offset = l1_rsp[1].tid[WordOffLsb +: LP1NumWordOffsetBits] * DataWidth;

  always_comb begin : gen_snitch_resp
    core_rsp_o[SnitchPort]         = '0;
    core_rsp_o[SnitchPort].p_valid = l1_rsp_valid[1];
    core_rsp_o[SnitchPort].q_ready = cache_req_ready[SnitchPort];
    core_rsp_o[SnitchPort].p.data  = l1_rsp[1].rdata[0][sn_bit_offset +: DataWidth];
    core_rsp_o[SnitchPort].p.user.is_fpu  = l1_rsp[1].tid[IsFpuPos];
    core_rsp_o[SnitchPort].p.user.core_id = l1_rsp[1].tid[CoreIdLsb +: CoreIDWidth];
    core_rsp_o[SnitchPort].p.user.req_id  = l1_rsp[1].tid[ReqIdLsb  +: ReqIdW];
    core_rsp_o[SnitchPort].p.user.is_amo  = 1'b0;
    core_rsp_o[SnitchPort].p.user.tile_id = l1_rsp[1].tid[TileIdLsb +: TileIDWidth];
    core_rsp_o[SnitchPort].p.write        = l1_rsp[1].tid[WritePos];
  end

  ////////////////////////
  // L2 -> L1 response   //
  ////////////////////////
  always_comb begin : rsp_translation
    l1_mem_resp_read_valid  = 1'b0;
    l1_mem_resp_write_valid = 1'b0;
    l1_mem_resp_read        = '0;
    l1_mem_resp_write       = '0;

    if (l2_rsp_i.p.write) begin
      l1_mem_resp_write_valid                = l2_rsp_i.p_valid;
      l1_mem_resp_write.mem_resp_w_is_atomic = l2_rsp_i.p.user.is_amo;
      l1_mem_resp_write.mem_resp_w_error     = HPDCACHE_MEM_RESP_OK;
      l1_mem_resp_write.mem_resp_w_id        = l2_rsp_i.p.user.req_id - l2_rsp_i.p.user.core_id - l2_rsp_i.p.user.tile_id;
    end else begin
      l1_mem_resp_read_valid             = l2_rsp_i.p_valid;
      l1_mem_resp_read.mem_resp_r_error  = HPDCACHE_MEM_RESP_OK;
      l1_mem_resp_read.mem_resp_r_id     = l2_rsp_i.p.user.req_id - l2_rsp_i.p.user.core_id - l2_rsp_i.p.user.tile_id;
      l1_mem_resp_read.mem_resp_r_data   = l2_rsp_i.p.data;
      l1_mem_resp_read.mem_resp_r_last   = 1'b1;
    end
  end

  // Response ready back to the interco: HPDcache mem-resp ready for the matching channel.
  assign l2_rsp_ready_o = l2_rsp_i.p.write ? l1_mem_resp_write_ready
                                           : l1_mem_resp_read_ready;

  ///////////////////////////
  // L1 -> L2 request merge //
  ///////////////////////////
  assign l1_mem_req_write_both_valid = l1_mem_req_write_valid && l1_mem_req_write_data_valid;

  rr_arb_tree #(
    .NumIn     (2),
    .DataType  (hpdcache_mem_req_t),
    .AxiVldRdy (1'b1)
  ) i_l1_l2_req_rr_arb (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (1'b0),
    .rr_i    (1'b1),
    .req_i   ({l1_mem_req_read_valid, l1_mem_req_write_both_valid}),
    .gnt_o   ({l1_mem_req_read_ready, __l1_mem_req_write_ready}),
    .data_i  ({l1_mem_req_read, l1_mem_req_write}),
    .req_o   (l1_l2_req_valid),
    .gnt_i   (l2_rsp_i.q_ready),
    .data_o  (l1_l2_req),
    .idx_o   ()
  );

  assign l1_mem_req_write_ready      = __l1_mem_req_write_ready & l1_mem_req_write_both_valid;
  assign l1_mem_req_write_data_ready = __l1_mem_req_write_ready & l1_mem_req_write_both_valid;

  // Downstream request metadata.
  always_comb begin : req_meta
    l1_l2_req_meta         = '0;
    l1_l2_req_meta.is_amo  = (l1_l2_req.mem_req_command == HPDCACHE_MEM_ATOMIC);
    l1_l2_req_meta.is_fpu  = l1_l2_req.mem_req_id[HPDcacheCfg.u.memIdWidth-1];
    l1_l2_req_meta.req_id  = l1_l2_req.mem_req_id;
    l1_l2_req_meta.core_id = '0;
    l1_l2_req_meta.tile_id = '0;
  end

  always_comb begin : l2_req_drive
    l2_req_o         = '0;
    l2_req_o.q.addr  = l1_l2_req.mem_req_addr;
    l2_req_o.q.write = (l1_l2_req.mem_req_command == HPDCACHE_MEM_WRITE);
    l2_req_o.q.amo   = AMONone;
    l2_req_o.q.data  = l1_mem_req_write_data.mem_req_w_data;
    l2_req_o.q.strb  = l1_mem_req_write_data.mem_req_w_be;
    l2_req_o.q.user  = l1_l2_req_meta;
    l2_req_o.q_valid = l1_l2_req_valid;

    if (l1_l2_req.mem_req_command == HPDCACHE_MEM_ATOMIC) begin
      unique case (l1_l2_req.mem_req_atomic)
        HPDCACHE_MEM_ATOMIC_ADD : l2_req_o.q.amo = AMOAdd;
        HPDCACHE_MEM_ATOMIC_SET : l2_req_o.q.amo = AMOOr;
        HPDCACHE_MEM_ATOMIC_EOR : l2_req_o.q.amo = AMOXor;
        HPDCACHE_MEM_ATOMIC_SMAX: l2_req_o.q.amo = AMOMax;
        HPDCACHE_MEM_ATOMIC_SMIN: l2_req_o.q.amo = AMOMin;
        HPDCACHE_MEM_ATOMIC_UMAX: l2_req_o.q.amo = AMOMaxu;
        HPDCACHE_MEM_ATOMIC_UMIN: l2_req_o.q.amo = AMOMinu;
        HPDCACHE_MEM_ATOMIC_SWAP: l2_req_o.q.amo = AMOSwap;
        HPDCACHE_MEM_ATOMIC_LDEX: l2_req_o.q.amo = AMOLR;
        HPDCACHE_MEM_ATOMIC_STEX: l2_req_o.q.amo = AMOSC;
        // HPDcache encodes RISC-V AMOAND as ATOP CLR with an inverted operand
        // (clears the bits set in ~rs2, i.e. mem & ~(~rs2)). The spatz AMO ALU only
        // has AMOAnd (A & B), so re-invert the operand here to recover rs2.
        HPDCACHE_MEM_ATOMIC_CLR : begin
          l2_req_o.q.amo  = AMOAnd;
          l2_req_o.q.data = ~l1_mem_req_write_data.mem_req_w_data;
        end
        default                 : l2_req_o.q.amo = AMONone;
      endcase
    end
  end

  //////////////
  // L1 CACHE //
  //////////////
  for (genvar i = 0; i < int'(HPDcacheCfg.u.nRequesters); i++) begin : gen_pma
    assign dummy_pma[i].uncacheable    = 1'b0;
    assign dummy_pma[i].io             = 1'b0;
    assign dummy_pma[i].wr_policy_hint = HPDCACHE_WR_POLICY_WT;
    assign core_req_abort[i]           = 1'b0;     // phys-indexed: never abort
    assign core_req_tag[i]             = '0;       // phys-indexed: tag in req
  end

  hpdcache #(
    .HPDcacheCfg          (HPDcacheCfg),
    .wbuf_timecnt_t       (wbuf_timecnt_t),
    .hpdcache_tag_t       (hpdcache_tag_t),
    .hpdcache_data_word_t (hpdcache_data_word_t),
    .hpdcache_data_be_t   (hpdcache_data_be_t),
    .hpdcache_req_offset_t(hpdcache_req_offset_t),
    .hpdcache_req_data_t  (hpdcache_req_data_t),
    .hpdcache_req_be_t    (hpdcache_req_be_t),
    .hpdcache_req_sid_t   (hpdcache_req_sid_t),
    .hpdcache_req_tid_t   (hpdcache_req_tid_t),
    .hpdcache_req_t       (hpdcache_req_t),
    .hpdcache_rsp_t       (hpdcache_rsp_t),
    .hpdcache_mem_addr_t  (hpdcache_mem_addr_t),
    .hpdcache_mem_id_t    (hpdcache_mem_id_t),
    .hpdcache_mem_data_t  (hpdcache_mem_data_t),
    .hpdcache_mem_be_t    (hpdcache_mem_be_t),
    .hpdcache_mem_req_t   (hpdcache_mem_req_t),
    .hpdcache_mem_req_w_t (hpdcache_mem_req_w_t),
    .hpdcache_mem_resp_r_t(hpdcache_mem_resp_r_t),
    .hpdcache_mem_resp_w_t(hpdcache_mem_resp_w_t)
  ) i_l1_hpdcache (
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .wbuf_flush_i(wbuf_flush_i),

    .core_req_valid_i(l1_req_valid),
    .core_req_ready_o(l1_req_ready),
    .core_req_i      (l1_req),
    .core_req_abort_i(core_req_abort),
    .core_req_tag_i  (core_req_tag),
    .core_req_pma_i  (dummy_pma),
    .core_rsp_valid_o(l1_rsp_valid),
    .core_rsp_o      (l1_rsp),

    //  Read memory interface
    .mem_req_read_ready_i (l1_mem_req_read_ready),
    .mem_req_read_valid_o (l1_mem_req_read_valid),
    .mem_req_read_o       (l1_mem_req_read),
    .mem_resp_read_ready_o(l1_mem_resp_read_ready),
    .mem_resp_read_valid_i(l1_mem_resp_read_valid),
    .mem_resp_read_i      (l1_mem_resp_read),
    .mem_resp_read_inval_i      (1'b0),
    .mem_resp_read_inval_nline_i('0),

    //  Write memory interface
    .mem_req_write_ready_i     (l1_mem_req_write_ready),
    .mem_req_write_valid_o     (l1_mem_req_write_valid),
    .mem_req_write_o           (l1_mem_req_write),
    .mem_req_write_data_ready_i(l1_mem_req_write_data_ready),
    .mem_req_write_data_valid_o(l1_mem_req_write_data_valid),
    .mem_req_write_data_o      (l1_mem_req_write_data),
    .mem_resp_write_ready_o    (l1_mem_resp_write_ready),
    .mem_resp_write_valid_i    (l1_mem_resp_write_valid),
    .mem_resp_write_i          (l1_mem_resp_write),

    //  Performance events
    .evt_cache_write_miss_o (evt_cache_write_miss_o),
    .evt_cache_read_miss_o  (evt_cache_read_miss_o),
    .evt_cache_dir_unc_err_o(evt_cache_dir_unc_err_o),
    .evt_cache_dir_cor_err_o(evt_cache_dir_cor_err_o),
    .evt_cache_dat_unc_err_o(evt_cache_dat_unc_err_o),
    .evt_cache_dat_cor_err_o(evt_cache_dat_cor_err_o),
    .evt_scrub_complete_o   (evt_scrub_complete_o),
    .evt_uncached_req_o     (evt_uncached_req_o),
    .evt_cmo_req_o          (evt_cmo_req_o),
    .evt_write_req_o        (evt_write_req_o),
    .evt_read_req_o         (evt_read_req_o),
    .evt_prefetch_req_o     (evt_prefetch_req_o),
    .evt_req_on_hold_o      (evt_req_on_hold_o),
    .evt_rtab_rollback_o    (evt_rtab_rollback_o),
    .evt_stall_refill_o     (evt_stall_refill_o),
    .evt_stall_o            (evt_stall_o),

    //  Status
    .wbuf_empty_o(wbuf_empty_o),

    //  Configuration
    .cfg_enable_i                       (cfg_enable_i),
    .cfg_wbuf_threshold_i               (cfg_wbuf_threshold_i),
    .cfg_wbuf_reset_timecnt_on_write_i  (cfg_wbuf_reset_timecnt_on_write_i),
    .cfg_wbuf_sequential_waw_i          (cfg_wbuf_sequential_waw_i),
    .cfg_wbuf_inhibit_write_coalescing_i(cfg_wbuf_inhibit_write_coalescing_i),
    .cfg_prefetch_updt_plru_i           (cfg_prefetch_updt_plru_i),
    .cfg_error_on_cacheable_amo_i       (cfg_error_on_cacheable_amo_i),
    .cfg_rtab_single_entry_i            (cfg_rtab_single_entry_i),
    .cfg_default_wb_i                   (cfg_default_wb_i),
    .cfg_scrub_enable_i                 (cfg_scrub_enable_i),
    .cfg_scrub_period_i                 (cfg_scrub_period_i),
    .cfg_scrub_restart_i                (cfg_scrub_restart_i)
  );

  ////////////////////////
  // tid pack functions //
  ////////////////////////
  function automatic hpdcache_req_tid_t pack_tid_snitch(
      input word_offset_t              word_offset,
      input logic                      is_fpu,
      input logic [TileIDWidth-1:0]    tile_id,
      input logic [CoreIDWidth-1:0]    core_id,
      input logic                      write,
      input reqid_t                    req_id);
    pack_tid_snitch = '0;
    pack_tid_snitch[ReqIdLsb  +: ReqIdW]      = req_id;
    pack_tid_snitch[WritePos]                 = write;
    pack_tid_snitch[CoreIdLsb +: CoreIDWidth] = core_id;
    pack_tid_snitch[TileIdLsb +: TileIDWidth] = tile_id;
    pack_tid_snitch[IsFpuPos]                 = is_fpu;
    pack_tid_snitch[WordOffLsb +: LP1NumWordOffsetBits] = word_offset;
  endfunction

  function automatic hpdcache_req_tid_t pack_tid_spatz(
      input word_offset_t              word_offset,
      input logic [HitmapW-1:0]        hitmap,
      input logic [OfstsW-1:0]         ofsts,
      input logic                      is_fpu,
      input logic [TileIDWidth-1:0]    tile_id,
      input logic [CoreIDWidth-1:0]    core_id,
      input logic                      write,
      input reqid_t                    req_id);
    pack_tid_spatz = '0;
    pack_tid_spatz[HitmapLsb  +: HitmapW]     = hitmap;
    pack_tid_spatz[OfstsLsb   +: OfstsW]      = ofsts;
    pack_tid_spatz[ReqIdLsb   +: ReqIdW]      = req_id;
    pack_tid_spatz[WritePos]                  = write;
    pack_tid_spatz[CoreIdLsb  +: CoreIDWidth] = core_id;
    pack_tid_spatz[TileIdLsb  +: TileIDWidth] = tile_id;
    pack_tid_spatz[IsFpuPos]                  = is_fpu;
    pack_tid_spatz[WordOffLsb +: LP1NumWordOffsetBits] = word_offset;
  endfunction

endmodule
