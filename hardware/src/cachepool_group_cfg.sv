// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

/// style-waive: COMMENT_BLOCK: function description
/// Group-level configuration register. Receives group_cfg_t writes from the cluster peripheral
/// over the L2 mesh (subordinate port of the group chimney) and drives the L1D/xbar configuration
/// of this group's tiles. A write with `issue` set starts its L1D instruction in the selected
/// tiles and is only answered once all of them have finished; any other write is answered at once.
/// The request is always accepted right away, so a pending flush never stalls the mesh.
module cachepool_group_cfg
  import cachepool_pkg::*;
#(
  parameter type req_chan_t = logic,
  parameter type rsp_chan_t = logic,
  parameter type user_t     = logic
) (
  input  logic                        clk_i,
  input  logic                        rst_ni,
  // Subordinate port from the L2 mesh chimney
  input  req_chan_t                   req_i,
  input  logic                        req_valid_i,
  output logic                        req_ready_o,
  output rsp_chan_t                   rsp_o,
  output logic                        rsp_valid_o,
  input  logic                        rsp_ready_i,
  // Configuration of the group's tiles
  output xbar_offset_t                dynamic_offset_o,
  output logic [L1PrivWidth-1:0]      l1d_private_o,
  output axi_addr_t                   private_start_addr_o,
  output logic                        icache_prefetch_enable_o,
  output cache_insn_t                 l1d_insn_o,
  output logic                        l1d_insn_valid_o,
  input  logic [NumTilesPerGroup-1:0] l1d_insn_ready_i
);

  // style-waive: COMMENT_BLOCK: FSM transition table
  //   Idle  -(write, issue)-> Flush -(selected tiles done)-> Resp -(rsp_ready)-> Idle
  //   Idle  -(write)------------------------------------> Resp
  typedef enum logic [1:0] {
    Idle,
    Flush,
    Resp
  } state_e;

  state_e                      state_d,      state_q;
  l1d_cfg_t                    cfg_d,        cfg_q;
  cache_insn_t                 insn_d,       insn_q;
  logic                        insn_valid_d, insn_valid_q;
  // Tiles that still have to finish the current instruction
  logic [NumTilesPerGroup-1:0] lock_d,       lock_q;
  user_t                       user_d,       user_q;

  group_cfg_t req_cfg;
  assign req_cfg = req_i.data[$bits(group_cfg_t)-1:0];

  always_comb begin : cfg_fsm
    state_d      = state_q;
    cfg_d        = cfg_q;
    insn_d       = insn_q;
    insn_valid_d = 1'b0;
    lock_d       = lock_q & ~l1d_insn_ready_i;
    user_d       = user_q;
    req_ready_o  = 1'b0;
    rsp_valid_o  = 1'b0;

    unique case (state_q)
      Idle: begin
        req_ready_o = 1'b1;
        if (req_valid_i) begin
          cfg_d  = req_cfg.cfg;
          user_d = req_i.user;
          if (req_cfg.issue) begin
            insn_d       = req_cfg.insn;
            insn_valid_d = 1'b1;
            // Only private flushes target a subset of the tiles
            lock_d       = (req_cfg.insn.insn == 2'b00) ? req_cfg.insn.tile_sel : '1;
            state_d      = Flush;
          end else begin
            state_d      = Resp;
          end
        end
      end
      Flush: begin
        if (lock_q == '0) state_d = Resp;
      end
      Resp: begin
        rsp_valid_o = 1'b1;
        if (rsp_ready_i) state_d = Idle;
      end
      default: state_d = Idle;
    endcase
  end

  always_comb begin : rsp_pack
    rsp_o       = '0;
    rsp_o.write = 1'b1;
    rsp_o.user  = user_q;
  end

  `FF(state_q,      state_d,      Idle,      clk_i, rst_ni)
  `FF(cfg_q,        cfg_d,        L1dCfgRst, clk_i, rst_ni)
  `FF(insn_q,       insn_d,       '0,        clk_i, rst_ni)
  `FF(insn_valid_q, insn_valid_d, 1'b0,      clk_i, rst_ni)
  `FF(lock_q,       lock_d,       '0,        clk_i, rst_ni)
  `FF(user_q,       user_d,       '0,        clk_i, rst_ni)

  assign dynamic_offset_o         = cfg_q.xbar_offset;
  assign l1d_private_o            = cfg_q.l1d_private;
  assign private_start_addr_o     = cfg_q.private_addr;
  assign icache_prefetch_enable_o = cfg_q.prefetch_en;
  assign l1d_insn_o               = insn_q;
  assign l1d_insn_valid_o         = insn_valid_q;

  `ASSERT(OnlyCfgWrites, req_valid_i |-> req_i.write, clk_i, !rst_ni,
      "cachepool_group_cfg: only writes from the cluster peripheral are expected")
  `ASSERT(CfgAddrInRange, req_valid_i |-> (req_i.addr >= GroupCfgBase), clk_i, !rst_ni,
      "cachepool_group_cfg: request address below GroupCfgBase")

endmodule
