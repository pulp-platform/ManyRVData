// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

// REQRSP to AXI for the off-chip (DRAM) refill path, from reqrsp_to_axi: single beats, no atomics,
// reads and writes never in flight together. user.uniq_id selects a fresh AXI ID (else the fixed
// ID); the reqrsp user rides in the AXI user, which the memory must echo back.

// L1 bypass (user.bypass): data in data[BypassDataWidth-1:0], xbar info above it. AXI user is
// {info, part = addr[part bits], reqrsp user}; write data/strb move to the part, and the read
// part returns in slot 0 with the info above it.
module cachepool_reqrsp_to_axi #(
  /// Number of same transactions which can be in-flight simultaneously, greater than 1.
  parameter int unsigned MaxTrans        = 32,
  /// Fixed AXI ID, used when user.uniq_id is 0.
  parameter int unsigned ID              = 0,
  parameter int unsigned AxiIdWidth      = 8,
  parameter int unsigned DataWidth       = 512,
  /// Width of the reqrsp user, and of its zero-extended slot in the AXI user.
  parameter int unsigned UserWidth       = 8,
  parameter int unsigned BaseUserWidth   = UserWidth,
  /// L1 bypass data slot, part index and info widths.
  parameter int unsigned BypassDataWidth = 128,
  parameter int unsigned BypassPartWidth = 2,
  parameter int unsigned BypassInfoWidth = 1,
  parameter type         reqrsp_req_t    = logic,
  parameter type         reqrsp_rsp_t    = logic,
  parameter type         axi_req_t       = logic,
  parameter type         axi_rsp_t       = logic,
  // Dependent parameter, do not override.
  localparam int unsigned AxiUserWidth   = BaseUserWidth + BypassPartWidth + BypassInfoWidth
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  reqrsp_req_t reqrsp_req_i,
  output reqrsp_rsp_t reqrsp_rsp_o,
  output axi_req_t    axi_req_o,
  input  axi_rsp_t    axi_rsp_i
);

  localparam int unsigned CounterWidth   = cf_math_pkg::idx_width(MaxTrans);
  localparam int unsigned BypassStrbWidth = BypassDataWidth / 8;
  localparam bit          BypassSupported = (BypassDataWidth + BypassInfoWidth <= DataWidth);
  // Info position in the data word; folded to 0 where unsupported so the slices stay legal
  localparam int unsigned BypassInfoLsb   = BypassSupported ? BypassDataWidth : 0;
  localparam int unsigned BeatOfstWidth   = $clog2(DataWidth/8);

  typedef logic [CounterWidth-1:0]  cnt_t;
  typedef logic [AxiUserWidth-1:0]  axi_user_t;
  typedef logic [DataWidth-1:0]     data_t;
  typedef logic [DataWidth/8-1:0]   strb_t;

  // ----------------
  // Ordering control
  // ----------------
  // A new transaction stalls while the other type is in flight or its counter would overflow.
  cnt_t                  read_cnt_d,  read_cnt_q;
  cnt_t                  write_cnt_d, write_cnt_q;
  logic [AxiIdWidth-1:0] id_cnt_d,    id_cnt_q;

  logic is_write, q_valid, q_ready;
  logic q_valid_read, q_ready_read, q_valid_write, q_ready_write;
  logic stall_read, dec_read_cnt, read_cnt_not_zero;
  logic stall_write, dec_write_cnt, write_cnt_not_zero;
  logic r_valid, r_ready, b_valid, b_ready;

  assign is_write      = reqrsp_req_i.q.write;
  assign r_valid       = axi_rsp_i.r_valid;
  assign b_valid       = axi_rsp_i.b_valid;
  assign dec_read_cnt  = r_valid & r_ready & axi_rsp_i.r.last;
  assign dec_write_cnt = b_valid & b_ready;

  assign read_cnt_not_zero  = (read_cnt_q > 1)  | ((read_cnt_q == 1)  & ~dec_read_cnt);
  assign write_cnt_not_zero = (write_cnt_q > 1) | ((write_cnt_q == 1) & ~dec_write_cnt);
  assign stall_write = is_write  & ((write_cnt_q == MaxTrans-1) | read_cnt_not_zero);
  assign stall_read  = !is_write & ((read_cnt_q  == MaxTrans-1) | write_cnt_not_zero);

  assign q_valid       = reqrsp_req_i.q_valid & ~(stall_write | stall_read);
  assign q_valid_read  = q_valid & ~is_write;
  assign q_valid_write = q_valid &  is_write;
  assign q_ready       = (q_valid_read & q_ready_read) | (q_valid_write & q_ready_write);

  `FF(read_cnt_q,  read_cnt_d,  '0)
  `FF(write_cnt_q, write_cnt_d, '0)
  // Start above the fixed ID to avoid a collision with it
  `FF(id_cnt_q,    id_cnt_d,    AxiIdWidth'($unsigned(ID) + 1))

  always_comb begin
    read_cnt_d  = read_cnt_q;
    write_cnt_d = write_cnt_q;
    id_cnt_d    = id_cnt_q;
    if (q_valid && q_ready) begin
      if (is_write) write_cnt_d = write_cnt_d + 1;
      else          read_cnt_d  = read_cnt_d  + 1;
      id_cnt_d = (&id_cnt_q) ? AxiIdWidth'($unsigned(ID) + 1) : id_cnt_q + 1;
    end
    if (dec_read_cnt)  read_cnt_d  = read_cnt_d  - 1;
    if (dec_write_cnt) write_cnt_d = write_cnt_d - 1;
  end

  // ----------------
  // Request payload
  // ----------------
  logic                       q_bypass;
  logic [BypassPartWidth-1:0] q_part;
  logic [AxiIdWidth-1:0]      q_id;
  logic [$bits(reqrsp_req_i.q.addr)-1:0] q_addr;
  axi_user_t                  q_axi_user;
  data_t                      q_wdata;
  strb_t                      q_wstrb;

  assign q_bypass = reqrsp_req_i.q.user.bypass;
  assign q_part   = reqrsp_req_i.q.addr[$clog2(BypassStrbWidth) +: BypassPartWidth];
  assign q_id     = reqrsp_req_i.q.user.uniq_id ? id_cnt_q : AxiIdWidth'($unsigned(ID));
  // A bypass address points into the beat (word offset); AXI wants it beat aligned, the
  // part index above keeps the original offset for data placement and routing.
  assign q_addr   = (BypassSupported && q_bypass)
                  ? (reqrsp_req_i.q.addr & ({$bits(q_addr){1'b1}} << BeatOfstWidth))
                  : reqrsp_req_i.q.addr;

  always_comb begin
    q_axi_user                  = '0;
    q_axi_user[UserWidth-1:0]   = reqrsp_req_i.q.user;
    q_wdata                     = reqrsp_req_i.q.data;
    q_wstrb                     = reqrsp_req_i.q.strb;
    if (BypassSupported && q_bypass) begin
      q_axi_user[BaseUserWidth +: BypassPartWidth] = q_part;
      q_axi_user[BaseUserWidth + BypassPartWidth +: BypassInfoWidth] =
        reqrsp_req_i.q.data[BypassInfoLsb +: BypassInfoWidth];
      q_wdata = '0;
      q_wstrb = '0;
      q_wdata[q_part * BypassDataWidth +: BypassDataWidth] =
        reqrsp_req_i.q.data[BypassDataWidth-1:0];
      q_wstrb[q_part * BypassStrbWidth +: BypassStrbWidth] =
        reqrsp_req_i.q.strb[BypassStrbWidth-1:0];
    end
  end

  // -------------
  // Read Channel
  // -------------
  assign axi_req_o.ar.id     = q_id;
  assign axi_req_o.ar.addr   = q_addr;
  assign axi_req_o.ar.len    = '0;
  assign axi_req_o.ar.size   = {1'b0, reqrsp_req_i.q.size};
  assign axi_req_o.ar.burst  = axi_pkg::BURST_INCR;
  assign axi_req_o.ar.lock   = '0;
  assign axi_req_o.ar.cache  = axi_pkg::CACHE_MODIFIABLE;
  assign axi_req_o.ar.prot   = '0;
  assign axi_req_o.ar.qos    = '0;
  assign axi_req_o.ar.region = '0;
  assign axi_req_o.ar.user   = q_axi_user;
  assign axi_req_o.ar_valid  = q_valid_read;
  assign q_ready_read        = axi_rsp_i.ar_ready;

  // -------------
  // Write Channel
  // -------------
  assign axi_req_o.aw.id     = q_id;
  assign axi_req_o.aw.addr   = q_addr;
  assign axi_req_o.aw.len    = '0;
  assign axi_req_o.aw.size   = {1'b0, reqrsp_req_i.q.size};
  assign axi_req_o.aw.burst  = axi_pkg::BURST_INCR;
  assign axi_req_o.aw.lock   = '0;
  assign axi_req_o.aw.cache  = axi_pkg::CACHE_MODIFIABLE;
  assign axi_req_o.aw.prot   = '0;
  assign axi_req_o.aw.qos    = '0;
  assign axi_req_o.aw.region = '0;
  assign axi_req_o.aw.atop   = '0;
  assign axi_req_o.aw.user   = q_axi_user;
  assign axi_req_o.w.data    = q_wdata;
  assign axi_req_o.w.strb    = q_wstrb;
  assign axi_req_o.w.last    = 1'b1;
  assign axi_req_o.w.user    = q_axi_user;

  // AW and W handshake independently
  stream_fork #(
    .N_OUP (2)
  ) i_stream_fork (
    .clk_i,
    .rst_ni,
    .valid_i (q_valid_write                             ),
    .ready_o (q_ready_write                             ),
    .valid_o ({axi_req_o.aw_valid, axi_req_o.w_valid}   ),
    .ready_i ({axi_rsp_i.aw_ready, axi_rsp_i.w_ready}   )
  );

  assign reqrsp_rsp_o.q_ready = q_ready;

  // -----------
  // Return Path
  // -----------
  // Reads and writes are never in flight together, so R and B are never valid together.
  assign r_ready            = reqrsp_req_i.p_ready & r_valid;
  assign b_ready            = reqrsp_req_i.p_ready & b_valid;
  assign axi_req_o.r_ready  = r_ready;
  assign axi_req_o.b_ready  = b_ready;

  axi_user_t                  p_axi_user;
  logic                       p_bypass;
  logic [BypassPartWidth-1:0] p_part;

  assign p_axi_user = r_valid ? axi_rsp_i.r.user : axi_rsp_i.b.user;
  assign p_part     = p_axi_user[BaseUserWidth +: BypassPartWidth];

  always_comb begin
    reqrsp_rsp_o.p_valid = r_valid | b_valid;
    reqrsp_rsp_o.p.user  = p_axi_user[UserWidth-1:0];
    reqrsp_rsp_o.p.write = b_valid;
    reqrsp_rsp_o.p.error = (r_valid & axi_rsp_i.r.resp[1]) | (b_valid & axi_rsp_i.b.resp[1]);
    reqrsp_rsp_o.p.data  = r_valid ? axi_rsp_i.r.data : '0;
    p_bypass             = reqrsp_rsp_o.p.user.bypass;
    if (BypassSupported && p_bypass) begin
      reqrsp_rsp_o.p.data = '0;
      if (r_valid) begin
        reqrsp_rsp_o.p.data[BypassDataWidth-1:0] =
          axi_rsp_i.r.data[p_part * BypassDataWidth +: BypassDataWidth];
      end
      reqrsp_rsp_o.p.data[BypassInfoLsb +: BypassInfoWidth] =
        p_axi_user[BaseUserWidth + BypassPartWidth +: BypassInfoWidth];
    end
  end

  // ----------
  // Assertions
  // ----------
  `ASSERT_INIT(MaxTransGreaterThanOne, MaxTrans > 1)
  `ASSERT_INIT(CheckAxiUserWidth, $bits(axi_req_o.ar.user) == AxiUserWidth)
  `ASSERT_INIT(CheckBaseUserWidth, BaseUserWidth >= UserWidth)
  `ASSERT(WriteCntOverflow,  (write_cnt_q == MaxTrans - 1) |=> !(write_cnt_q == 0))
  `ASSERT(ReadCntOverflow,   (read_cnt_q  == MaxTrans - 1) |=> !(read_cnt_q  == 0))
  `ASSERT(WriteCntUnderflow, (write_cnt_q == 0) |=> !(write_cnt_q == MaxTrans - 1))
  `ASSERT(ReadCntUnderflow,  (read_cnt_q  == 0) |=> !(read_cnt_q  == MaxTrans - 1))
  `ASSERT(WriteStable, q_valid_write && !q_ready_write |=> q_valid_write)
  `ASSERT(NoReadWriteRspOverlap, !(r_valid && b_valid))
  `ASSERT(SingleBeatRead, r_valid |-> axi_rsp_i.r.last)
  // AXI: the start address of a transfer is aligned to its size (reported, not fatal)
  `ASSERT(ArAddrAligned, axi_req_o.ar_valid |->
          ((axi_req_o.ar.addr & ((1 << axi_req_o.ar.size) - 1)) == '0))
  `ASSERT(AwAddrAligned, axi_req_o.aw_valid |->
          ((axi_req_o.aw.addr & ((1 << axi_req_o.aw.size) - 1)) == '0))
  `ASSERT(NoUnsupportedBypass,
          reqrsp_req_i.q_valid |-> (BypassSupported || !reqrsp_req_i.q.user.bypass))

endmodule : cachepool_reqrsp_to_axi
