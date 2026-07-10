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

module reqrsp_w2n_converter #(
  parameter int unsigned SlvDataWidth  = 512,
  parameter int unsigned MstDataWidth  = 32,
  parameter int unsigned AddrWidth     = 32,
  parameter int unsigned SlvUserWidth  = 1,
  parameter int unsigned MstUserWidth  = 1,
  parameter int unsigned MaxTrans      = 4,
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
  typedef enum logic [1:0] {
    IDLE,
    SEND_BEAT,
    WAIT_RSP,
    SLV_RESP
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

        if (mst_rsp_i.q_ready) begin
          state_d = WAIT_RSP;
        end
      end

      // ------------------------------------------------------------------
      // WAIT_RSP: wait for the narrow response
      // ------------------------------------------------------------------
      WAIT_RSP: begin
        mst_req_o.p_ready = 1'b1;
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
          state_d = IDLE;
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
    end
  end

endmodule : reqrsp_w2n_converter
