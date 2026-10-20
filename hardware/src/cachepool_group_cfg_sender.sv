// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

/// style-waive: COMMENT_BLOCK: function description
/// Forwards one committed configuration batch of the cluster peripheral to every group-level
/// configuration register (cachepool_group_cfg) as sequential unicast writes over the L2 mesh,
/// and pulses done_o once all NumGroups responses are back. Group g is written at
/// GroupCfgBase + g * GroupCfgStride with its own tile_sel slice. The batch inputs must stay
/// stable from start_i until done_o (the peripheral blocks new commits meanwhile).
module cachepool_group_cfg_sender
  import cachepool_pkg::*;
#(
  parameter type   req_chan_t = logic,
  parameter type   rsp_chan_t = logic,
  parameter type   user_t     = logic,
  /// User field of every request; carries this endpoint's l2_src_id for response routing
  parameter user_t ReqUser    = '0
) (
  input  logic                clk_i,
  input  logic                rst_ni,
  // Batch from the cluster peripheral
  input  logic                start_i,
  input  logic                issue_i,
  input  logic [1:0]          insn_i,
  input  logic [NumTiles-1:0] tile_sel_i,
  input  l1d_cfg_t            cfg_i,
  output logic                done_o,
  // Manager port into the L2 mesh chimney
  output req_chan_t           req_o,
  output logic                req_valid_o,
  input  logic                req_ready_i,
  input  rsp_chan_t           rsp_i,
  input  logic                rsp_valid_i,
  output logic                rsp_ready_o
);

  localparam int unsigned CntWidth = $clog2(NumGroups + 1);
  typedef logic [CntWidth-1:0] cnt_t;

  logic                busy_d,     busy_q;
  cnt_t                send_cnt_d, send_cnt_q;
  cnt_t                rsp_cnt_d,  rsp_cnt_q;
  axi_addr_t           addr_d,     addr_q;
  // Tile selection of the remaining groups; the current group's slice sits at the LSBs
  logic [NumTiles-1:0] tile_sel_d, tile_sel_q;

  logic                        req_fire;
  logic [NumTilesPerGroup-1:0] group_tile_sel;
  group_cfg_t                  group_cfg;

  assign req_valid_o    = busy_q && (send_cnt_q != NumGroups);
  assign req_fire       = req_valid_o && req_ready_i;
  assign rsp_ready_o    = 1'b1;
  assign group_tile_sel = tile_sel_q[NumTilesPerGroup-1:0];

  // A private flush only issues in groups with at least one selected tile
  always_comb begin : group_cfg_pack
    group_cfg.issue         = issue_i && ((insn_i != 2'b00) || (group_tile_sel != '0));
    group_cfg.insn.insn     = insn_i;
    group_cfg.insn.tile_sel = group_tile_sel;
    group_cfg.cfg           = cfg_i;
  end

  always_comb begin : req_pack
    req_o                              = '0;
    req_o.addr                         = addr_q;
    req_o.write                        = 1'b1;
    req_o.amo                          = reqrsp_pkg::AMONone;
    req_o.data[$bits(group_cfg_t)-1:0] = group_cfg;
    req_o.strb                         = '1;
    req_o.user                         = ReqUser;
  end

  always_comb begin : batch_ctrl
    busy_d     = busy_q;
    send_cnt_d = send_cnt_q;
    rsp_cnt_d  = rsp_cnt_q;
    addr_d     = addr_q;
    tile_sel_d = tile_sel_q;
    done_o     = 1'b0;

    if (!busy_q) begin
      if (start_i) begin
        busy_d     = 1'b1;
        send_cnt_d = '0;
        rsp_cnt_d  = '0;
        addr_d     = GroupCfgBase;
        tile_sel_d = tile_sel_i;
      end
    end else begin
      if (req_fire) begin
        send_cnt_d = send_cnt_q + 1'b1;
        addr_d     = addr_q + GroupCfgStride;
        tile_sel_d = tile_sel_q >> NumTilesPerGroup;
      end
      if (rsp_valid_i) begin
        rsp_cnt_d = rsp_cnt_q + 1'b1;
      end
      if (rsp_cnt_q == NumGroups) begin
        busy_d = 1'b0;
        done_o = 1'b1;
      end
    end
  end

  `FF(busy_q,     busy_d,     1'b0, clk_i, rst_ni)
  `FF(send_cnt_q, send_cnt_d, '0,   clk_i, rst_ni)
  `FF(rsp_cnt_q,  rsp_cnt_d,  '0,   clk_i, rst_ni)
  `FF(addr_q,     addr_d,     '0,   clk_i, rst_ni)
  `FF(tile_sel_q, tile_sel_d, '0,   clk_i, rst_ni)

  `ASSERT_INIT(CheckNumGroups, NumGroups > 1, "cachepool_group_cfg_sender: NumGroups must be > 1")
  `ASSERT_INIT(CheckCfgFitsData, $bits(group_cfg_t) <= $bits(req_o.data),
      "cachepool_group_cfg_sender: group_cfg_t does not fit into the request data")
  `ASSERT(NoRspWhenIdle, rsp_valid_i |-> busy_q, clk_i, !rst_ni,
      "cachepool_group_cfg_sender: response without an outstanding batch")
  `ASSERT(NoExtraRsp, rsp_valid_i |-> (rsp_cnt_q < NumGroups), clk_i, !rst_ni,
      "cachepool_group_cfg_sender: more responses than groups")
  `ASSERT(NoStartWhenBusy, start_i |-> !busy_q, clk_i, !rst_ni,
      "cachepool_group_cfg_sender: new batch while the previous one is in flight")

endmodule
