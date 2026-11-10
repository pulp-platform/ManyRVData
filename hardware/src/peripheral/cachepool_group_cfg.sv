// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

/// style-waive: COMMENT_BLOCK: function description
/// Group-level configuration register. Receives single-register writes (group_cfg_reg_e) from the
/// cluster peripheral over the narrow L2 mesh (subordinate port of the group chimney) and drives
/// the L1D/xbar configuration of this group's tiles. A GroupCfgL1dInsn write starts its L1D
/// instruction in the selected tiles and is only answered once all of them have finished; any
/// other write is answered at once. The request is always accepted right away, so a pending flush
/// never stalls the mesh.
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
  output logic                        l1d_bypass_o,
  output cache_insn_t                 l1d_insn_o,
  output logic                        l1d_insn_valid_o,
  input  logic [NumTilesPerGroup-1:0] l1d_insn_ready_i
);

  // style-waive: COMMENT_BLOCK: FSM transition table
  //   Idle  -(GroupCfgL1dInsn write)-> Flush -(selected tiles done)-> Resp -(rsp_ready)-> Idle
  //   Idle  -(other write)----------------------------------------> Resp
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

  // Register index and value of the incoming write
  group_cfg_reg_e req_reg;
  logic [31:0]    req_data;
  cache_insn_t    req_insn;
  assign req_reg  = group_cfg_reg_e'(req_i.addr[2 +: $bits(group_cfg_reg_e)]);
  assign req_data = req_i.data[31:0];
  assign req_insn = req_data[$bits(cache_insn_t)-1:0];

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
          user_d  = req_i.user;
          state_d = Resp;
          unique case (req_reg)
            GroupCfgXbarOffset: cfg_d.xbar_offset  = req_data[$bits(xbar_offset_t)-1:0];
            GroupCfgL1dPrivate: cfg_d.l1d_private  = req_data[L1PrivWidth-1:0];
            GroupCfgL1dAddr:    cfg_d.private_addr = req_data;
            GroupCfgPrefetch:   cfg_d.prefetch_en  = req_data[0];
            GroupCfgL1dBypass:  cfg_d.bypass_en    = req_data[0];
            GroupCfgL1dInsn: begin
              insn_d       = req_insn;
              insn_valid_d = 1'b1;
              // Only private flushes target a subset of the tiles
              lock_d       = (req_insn.insn == 2'b00) ? req_insn.tile_sel : '1;
              state_d      = Flush;
            end
            default: ;
          endcase
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
  assign l1d_bypass_o             = cfg_q.bypass_en;
  assign l1d_insn_o               = insn_q;
  assign l1d_insn_valid_o         = insn_valid_q;

  `ASSERT_INIT(CheckRegsFitStride, GroupCfgStride >= 4 * (2 ** $bits(group_cfg_reg_e)),
      "cachepool_group_cfg: GroupCfgStride is too small for the register block")
  `ASSERT_INIT(CheckInsnFitsWord, $bits(cache_insn_t) <= 32,
      "cachepool_group_cfg: cache_insn_t does not fit into one 32-bit register")
  `ASSERT(OnlyCfgWrites, req_valid_i |-> req_i.write, clk_i, !rst_ni,
      "cachepool_group_cfg: only writes from the cluster peripheral are expected")
  `ASSERT(CfgAddrInRange, req_valid_i |-> (req_i.addr >= GroupCfgBase), clk_i, !rst_ni,
      "cachepool_group_cfg: request address below GroupCfgBase")
  `ASSERT(KnownCfgReg, req_valid_i |-> (req_reg inside {GroupCfgXbarOffset, GroupCfgL1dPrivate,
      GroupCfgL1dAddr, GroupCfgPrefetch, GroupCfgL1dInsn, GroupCfgL1dBypass}), clk_i, !rst_ni,
      "cachepool_group_cfg: write to an unknown register")

endmodule
