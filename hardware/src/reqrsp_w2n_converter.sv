// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Diyou Shen <dishen@iis.ee.ethz.ch>
//
// REQRSP data-width converter (wide -> narrow).
// One-at-a-time: only one narrow beat is outstanding at any moment.
// A single wide request is serialized into Ratio = SlvDataWidth/MstDataWidth
// narrow beats.  The next beat is not issued until the current beat's
// response has been received.
//
// Optional read buffer + MSHR (EnRdBuf): a single-entry, whole-request,
// read-only cache plus a small merge FIFO, both keyed on an exact full
// address match (no tag/offset decomposition, to sidestep any alignment
// assumptions -- some hit opportunities are given up for simplicity):
//
//  - Post-completion cache: once a read finishes with no error, its full
//    address and assembled data are latched. A later read in IDLE for the
//    exact same address is returned immediately, skipping the narrow-beat
//    serialization entirely.
//  - Mid-flight merge (MSHR): while a read is being serialized (SEND_BEAT/
//    WAIT_RSP), a second read for the exact same address is accepted too
//    (instead of being backpressured) and its `.user` is pushed into a
//    depth-MSHRDepth FIFO. Once the in-flight read completes, its response
//    is replayed once per queued FIFO entry (same data/error, each with its
//    own `.user`), in FIFO (arrival) order, before returning to IDLE.
//
// Either mechanism is only ever populated/consulted for reads; any write
// (in IDLE) invalidates the cache outright (no per-address comparison), and
// writes never participate in merging.
//
// The post-completion cache is further restricted to an explicit allowlisted
// address window (CacheableBase/CacheableSize, default empty = nothing
// cacheable). This is deliberately an allowlist, not a blocklist: some
// registers behind this converter (e.g. status bits driven by direct wires
// from hardware state, not by writes that pass through here) can change
// without this converter ever observing a write, so caching them would make
// a polling loop see a stale value forever. Only address ranges known to be
// pure, bus-write-invalidated read data (e.g. a ROM) should be allowlisted.
// The mid-flight MSHR merge is unaffected by this window: it never persists
// data across separate transactions, so it cannot go stale.

module reqrsp_w2n_converter #(
  parameter int unsigned SlvDataWidth  = 512,
  parameter int unsigned MstDataWidth  = 32,
  parameter int unsigned AddrWidth     = 32,
  parameter int unsigned SlvUserWidth  = 1,
  parameter int unsigned MstUserWidth  = 1,
  parameter int unsigned MaxTrans      = 4,
  parameter bit          EnRdBuf       = 1'b0,
  parameter int unsigned MSHRDepth     = 16,
  parameter logic [AddrWidth-1:0] CacheableBase = '0,
  parameter logic [AddrWidth-1:0] CacheableSize = '0,
  parameter type         slv_req_t     = logic,
  parameter type         slv_rsp_t     = logic,
  parameter type         mst_req_t     = logic,
  parameter type         mst_rsp_t     = logic,
  parameter type         slv_user_t    = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  slv_req_t slv_req_i,
  output slv_rsp_t slv_rsp_o,
  output mst_req_t mst_req_o,
  input  mst_rsp_t mst_rsp_i
);

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  localparam int unsigned Ratio    = SlvDataWidth / MstDataWidth;
  localparam int unsigned BeatCntW = (Ratio == 1) ? 1 : $clog2(Ratio);
  localparam int unsigned MstBytes = MstDataWidth / 8;
  localparam int unsigned SlvBytes = SlvDataWidth / 8;

  // ---------------------------------------------------------------------------
  // FSM states
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IDLE,
    SEND_BEAT,
    WAIT_RSP,
    SLV_RESP,
    MSHR_DRAIN
  } state_e;

  // ---------------------------------------------------------------------------
  // Registers: _d (next) / _q (current)
  // ---------------------------------------------------------------------------
  state_e                      state_d,     state_q;
  logic [BeatCntW-1:0]         beat_d,      beat_q;
  // When set, the request fits in a single narrow beat (size <= MstBytes).
  logic                        narrow_d,    narrow_q;

  // Latched slave-side request fields
  logic [AddrWidth-1:0]        slv_addr_d,  slv_addr_q;
  logic                        slv_write_d, slv_write_q;
  reqrsp_pkg::amo_op_e         slv_amo_d,   slv_amo_q;
  logic [SlvDataWidth-1:0]     slv_data_d,  slv_data_q;
  logic [SlvBytes-1:0]         slv_strb_d,  slv_strb_q;
  slv_user_t                   slv_user_d,  slv_user_q;

  // Assembled wide read-data and sticky error
  logic [SlvDataWidth-1:0]     rdata_d,     rdata_q;
  logic                        error_d,     error_q;

  // ---------------------------------------------------------------------------
  // Read buffer + MSHR (only meaningful when EnRdBuf = 1)
  // ---------------------------------------------------------------------------
  // Post-completion, whole-request, exact-address cache.
  logic                        buf_valid_d, buf_valid_q;
  logic [AddrWidth-1:0]        buf_addr_d,  buf_addr_q;
  logic [SlvDataWidth-1:0]     buf_data_d,  buf_data_q;

  // Mid-flight merge FIFO: holds the `.user` of reads that matched the
  // address currently being serialized, to be replayed once it completes.
  localparam int unsigned MSHRAddrDepth = (MSHRDepth > 1) ? $clog2(MSHRDepth) : 1;
  logic       mshr_push, mshr_pop, mshr_full, mshr_empty;
  logic [MSHRAddrDepth-1:0] mshr_usage;
  slv_user_t  mshr_push_data, mshr_pop_data;

  fifo_v3 #(
    .FALL_THROUGH ( 1'b0       ),
    .DEPTH        ( MSHRDepth  ),
    .dtype        ( slv_user_t )
  ) i_mshr_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    ( 1'b0           ),
    .testmode_i ( 1'b0           ),
    .full_o     ( mshr_full      ),
    .empty_o    ( mshr_empty     ),
    .usage_o    ( mshr_usage     ),
    .data_i     ( mshr_push_data ),
    .push_i     ( mshr_push      ),
    .data_o     ( mshr_pop_data  ),
    .pop_i      ( mshr_pop       )
  );

  // A read is being serialized right now, and can still accept a merge
  // (once the last beat is issued/answered there is nothing left to merge
  // into -- SLV_RESP/MSHR_DRAIN only ever backpressure new requests).
  logic mergeable_in_flight;
  assign mergeable_in_flight = EnRdBuf && !slv_write_q
                             && (state_q == SEND_BEAT || state_q == WAIT_RSP);
  logic merge_hit;
  assign merge_hit = mergeable_in_flight && slv_req_i.q_valid
                   && !slv_req_i.q.write && (slv_req_i.q.addr == slv_addr_q)
                   && !mshr_full;

  assign mshr_push      = merge_hit;
  assign mshr_push_data = slv_req_i.q.user;

  // Address allowlist for the post-completion cache (see header comment).
  function automatic logic addr_is_cacheable(input logic [AddrWidth-1:0] addr);
    addr_is_cacheable = (CacheableSize != '0)
                       && (addr >= CacheableBase)
                       && (addr < CacheableBase + CacheableSize);
  endfunction

  // ---------------------------------------------------------------------------
  // Combinational datapath + next-state logic
  // ---------------------------------------------------------------------------
  always_comb begin
    // Hold all registers by default
    state_d     = state_q;
    beat_d      = beat_q;
    narrow_d    = narrow_q;
    slv_addr_d  = slv_addr_q;
    slv_write_d = slv_write_q;
    slv_amo_d   = slv_amo_q;
    slv_data_d  = slv_data_q;
    slv_strb_d  = slv_strb_q;
    slv_user_d  = slv_user_q;
    rdata_d     = rdata_q;
    error_d     = error_q;

    // Read buffer/MSHR defaults: hold
    buf_valid_d = buf_valid_q;
    buf_addr_d  = buf_addr_q;
    buf_data_d  = buf_data_q;
    mshr_pop    = 1'b0;

    // Slave interface defaults (no handshake)
    slv_rsp_o   = '0;

    // Master interface defaults (no request)
    mst_req_o   = '0;

    unique case (state_q)
      // ------------------------------------------------------------------
      // IDLE: accept one wide request
      // ------------------------------------------------------------------
      IDLE: begin
        slv_rsp_o.q_ready = 1'b1;
        if (slv_req_i.q_valid) begin
          slv_addr_d  = slv_req_i.q.addr;
          slv_write_d = slv_req_i.q.write;
          slv_amo_d   = slv_req_i.q.amo;
          slv_data_d  = slv_req_i.q.data;
          slv_strb_d  = slv_req_i.q.strb;
          slv_user_d  = slv_req_i.q.user;
          rdata_d     = '0;
          error_d     = 1'b0;
          beat_d      = '0;
          narrow_d    = (slv_req_i.q.size <= reqrsp_pkg::size_t'($clog2(MstBytes)));
          state_d     = SEND_BEAT;

          if (EnRdBuf) begin
            if (slv_req_i.q.write) begin
              // Any write invalidates the cache outright.
              buf_valid_d = 1'b0;
            end else if (buf_valid_q && (slv_req_i.q.addr == buf_addr_q)) begin
              // Exact-address hit: bypass the narrow-beat serialization.
              // (Only ever reachable for a cacheable address -- the buffer
              // is only ever filled for addresses that passed the allowlist.)
              rdata_d = buf_data_q;
              error_d = 1'b0;
              state_d = SLV_RESP;
            end else if (addr_is_cacheable(slv_req_i.q.addr)) begin
              // Cacheable read miss: evict the old line, this fetch refills it.
              buf_valid_d = 1'b0;
              buf_addr_d  = slv_req_i.q.addr;
            end
            // Non-cacheable read: leave the buffer entirely untouched --
            // must not evict a legitimately cached line, and must never be
            // cached itself (see header comment on the allowlist).
          end
        end
      end

      // ------------------------------------------------------------------
      // SEND_BEAT: present the current narrow beat on the master port
      // ------------------------------------------------------------------
      SEND_BEAT: begin
        mst_req_o.q_valid = 1'b1;
        // Address increments by MstBytes per beat
        mst_req_o.q.addr  = slv_addr_q
                          + AddrWidth'({beat_q, {$clog2(MstBytes){1'b0}}});
        mst_req_o.q.write = slv_write_q;
        mst_req_o.q.amo   = slv_amo_q;
        mst_req_o.q.size  = reqrsp_pkg::size_t'($clog2(MstBytes));
        mst_req_o.q.user  = slv_user_q;

        // Write data/strb slicing
        mst_req_o.q.data  = slv_data_q[beat_q*MstDataWidth +: MstDataWidth];
        mst_req_o.q.strb  = slv_strb_q[beat_q*MstBytes     +: MstBytes];

        // Merge a same-address read into this in-flight fetch instead of
        // backpressuring it.
        slv_rsp_o.q_ready = merge_hit;

        if (mst_rsp_i.q_ready) begin
          state_d = WAIT_RSP;
        end
      end

      // ------------------------------------------------------------------
      // WAIT_RSP: wait for the narrow response
      // ------------------------------------------------------------------
      WAIT_RSP: begin
        mst_req_o.p_ready = 1'b1;
        // Merge a same-address read into this in-flight fetch instead of
        // backpressuring it.
        slv_rsp_o.q_ready = merge_hit;

        if (mst_rsp_i.p_valid) begin
          // Accumulate read data
          rdata_d[beat_q*MstDataWidth +: MstDataWidth] = mst_rsp_i.p.data;
          // Sticky error
          error_d = error_q | mst_rsp_i.p.error;

          if (narrow_q || beat_q == BeatCntW'(Ratio - 1)) begin
            // Last beat — deliver aggregated response
            state_d = SLV_RESP;
          end else begin
            beat_d  = beat_q + 1;
            state_d = SEND_BEAT;
          end
        end
      end

      // ------------------------------------------------------------------
      // SLV_RESP: return the assembled wide response to the slave port
      // ------------------------------------------------------------------
      SLV_RESP: begin
        slv_rsp_o.p_valid = 1'b1;
        slv_rsp_o.p.data  = rdata_q;
        slv_rsp_o.p.error = error_q;
        slv_rsp_o.p.write = slv_write_q;
        slv_rsp_o.p.user  = slv_user_q;
        if (slv_req_i.p_ready) begin
          if (EnRdBuf && !slv_write_q && !error_q && addr_is_cacheable(slv_addr_q)) begin
            // Cache the completed read for later exact-address hits.
            buf_valid_d = 1'b1;
            buf_addr_d  = slv_addr_q;
            buf_data_d  = rdata_q;
          end
          state_d = (EnRdBuf && !mshr_empty) ? MSHR_DRAIN : IDLE;
        end
      end

      // ------------------------------------------------------------------
      // MSHR_DRAIN: replay the just-completed response once per merged
      // request queued in the MSHR FIFO, in arrival order.
      // ------------------------------------------------------------------
      MSHR_DRAIN: begin
        slv_rsp_o.p_valid = 1'b1;
        slv_rsp_o.p.data  = rdata_q;
        slv_rsp_o.p.error = error_q;
        slv_rsp_o.p.write = 1'b0;
        slv_rsp_o.p.user  = mshr_pop_data;
        if (slv_req_i.p_ready) begin
          mshr_pop = 1'b1;
          // mshr_usage still reflects the pre-pop count: 1 means this is
          // the last queued entry, so the FIFO will be empty after this pop.
          state_d  = (mshr_usage == MSHRAddrDepth'(1)) ? IDLE : MSHR_DRAIN;
        end
      end

      default: state_d = IDLE;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Sequential — pure register updates, no logic
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= IDLE;
      beat_q      <= '0;
      narrow_q    <= 1'b0;
      slv_addr_q  <= '0;
      slv_write_q <= 1'b0;
      slv_amo_q   <= reqrsp_pkg::AMONone;
      slv_data_q  <= '0;
      slv_strb_q  <= '0;
      slv_user_q  <= slv_user_t'('0);
      rdata_q     <= '0;
      error_q     <= 1'b0;
      buf_valid_q <= 1'b0;
      buf_addr_q  <= '0;
      buf_data_q  <= '0;
    end else begin
      state_q     <= state_d;
      beat_q      <= beat_d;
      narrow_q    <= narrow_d;
      slv_addr_q  <= slv_addr_d;
      slv_write_q <= slv_write_d;
      slv_amo_q   <= slv_amo_d;
      slv_data_q  <= slv_data_d;
      slv_strb_q  <= slv_strb_d;
      slv_user_q  <= slv_user_d;
      rdata_q     <= rdata_d;
      error_q     <= error_d;
      buf_valid_q <= buf_valid_d;
      buf_addr_q  <= buf_addr_d;
      buf_data_q  <= buf_data_d;
    end
  end

endmodule : reqrsp_w2n_converter
