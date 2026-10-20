// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

/// style-waive: COMMENT_BLOCK: function description
/// Exposes cluster confugration and information as memory mapped information.
/// The L1D/xbar configuration is not wired to the groups: every commit is handed to
/// cachepool_group_cfg_sender as one batch, which writes it into each group's
/// cachepool_group_cfg over the L2 mesh. L1D_FLUSH_STATUS stays busy until the batch is done.

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

module cachepool_peripheral
  import snitch_pkg::*;
  import cachepool_pkg::*;
  import cachepool_peripheral_reg_pkg::*;
#(
  parameter int unsigned AddrWidth       = 0,
  parameter int unsigned DMADataWidth    = 0,
  parameter int unsigned SPMWidth        = 0,
  // Number of tiles (used for flush controller granularity)
  parameter int unsigned NumTiles        = 1,
  // Number of groups (used for the cluster-level barrier participation mask)
  parameter int unsigned NumGroups       = 1,
  // Independent barrier round trackers (must match cachepool_pkg::NumBarrierSlots, checked below)
  parameter int unsigned NumBarrierSlots = 1,
  // Width actually used from the (fixed 4b) L1D_PRIVATE CSR field.
  parameter int unsigned PrivateWidth    = 4,
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  /// Derived parameter *Do not override*
  parameter type addr_t = logic [AddrWidth-1:0],
  parameter type spm_size_t = logic [SPMWidth-1:0]
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  input  reg_req_t                   reg_req_i,
  output reg_rsp_t                   reg_rsp_o,

  output logic [3:0]                 eoc_o,
  input  addr_t                      tcdm_start_address_i,
  input  addr_t                      tcdm_end_address_i,
  output logic                       cluster_probe_o,
  input  logic [9:0]                 cluster_hart_base_id_i,
  output spm_size_t                  l1d_spm_size_o,
  // Per-tile flush interlock, high from an L1D instruction commit until its batch is done
  output logic [NumTiles-1:0]        l1d_busy_o,
  // Configuration batch towards cachepool_group_cfg_sender, stable until cfg_done_i
  output logic                       cfg_start_o,
  output logic                       cfg_issue_o,
  output logic [1:0]                 cfg_insn_o,
  output logic [NumTiles-1:0]        cfg_tile_sel_o,
  output l1d_cfg_t                   cfg_o,
  input  logic                       cfg_done_i,
  // One group-participation mask per barrier slot (see HW_BARRIER_PARTICIPATION_MASK multireg)
  output logic [NumBarrierSlots-1:0][NumGroups-1:0] barrier_part_mask_o
);

  // These two counts are generated independently and must agree exactly.
  `ASSERT_INIT(CheckBarrierSlotsMatchRegPkg,
               NumBarrierSlots == cachepool_peripheral_reg_pkg::NumBarrierSlots,
               "NumBarrierSlots does not match cachepool_peripheral_reg_pkg::NumBarrierSlots -- regenerate the peripheral register file for this config")
  `ASSERT_INIT(CheckPrivateWidth, PrivateWidth == L1PrivWidth,
               "PrivateWidth does not match cachepool_pkg::L1PrivWidth")

  cachepool_peripheral_reg2hw_t reg2hw;
  cachepool_peripheral_hw2reg_t hw2reg;

  cachepool_peripheral_reg_top #(
    .reg_req_t (reg_req_t),
    .reg_rsp_t (reg_rsp_t)
  ) i_cachepool_peripheral_reg_top (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .reg_req_i (reg_req_i),
    .reg_rsp_o (reg_rsp_o),
    .devmode_i (1'b0),
    .reg2hw (reg2hw),
    .hw2reg (hw2reg)
  );

  //////////// EOC /////////////
  assign eoc_o = reg2hw.cluster_eoc_exit.q;

  //////////// L1 DCache SPM ////////////
  logic [9:0]              l1d_spm_size_d, l1d_spm_size_q;
  logic                    l1d_spm_commit;

  // For committing the cfg, if the cfg is taken, it will be pulled to 0;
  // Otherwise, it will be kept at 1 until taken.
  assign       l1d_spm_commit  = reg2hw.l1d_spm_commit.q;

  // TODO: Change it to power of 2 to save space
  // SPM Size
  always_comb begin : l1d_spm_cfg
    l1d_spm_size_d   = l1d_spm_size_q;

    hw2reg.l1d_spm_commit.d  = 1'b0;
    hw2reg.l1d_spm_commit.de = 1'b0;

    if (l1d_spm_commit) begin
      l1d_spm_size_d = reg2hw.cfg_l1d_spm.q;
      // Clear the commit
      hw2reg.l1d_spm_commit.d  = 1'b0;
      hw2reg.l1d_spm_commit.de = 1'b1;
    end
  end

  `FF(l1d_spm_size_q, l1d_spm_size_d, '0, clk_i, rst_ni)
  // 10b is enough for 1024 cache lines, we should not need all of them
  assign l1d_spm_size_o       = l1d_spm_size_q[SPMWidth-1:0];

  //////////// L1D / Cache XBar configuration ////////////
  // Concatenate all tile-select register words into one wide vector and slice
  // to NumTiles.  Unused upper bits (for small configs) are optimised away.
  localparam int unsigned NumTileSelWords = cachepool_peripheral_reg_pkg::NumTileSelRegs;
  logic [NumTileSelWords*32-1:0] tile_sel_raw;
  always_comb begin : tile_sel_concat
    for (int i = 0; i < NumTileSelWords; i++) begin
      tile_sel_raw[i*32 +: 32] = reg2hw.cfg_l1d_tile_sel[i].q;
    end
  end

  // Committed configuration, the copy every group-level register holds once a batch is done
  l1d_cfg_t            cfg_d,      cfg_q;
  // A batch is in flight from its commit until all groups have answered
  logic                busy_d,     busy_q;
  logic                start_d,    start_q;
  logic                issue_d,    issue_q;
  logic [1:0]          insn_d,     insn_q;
  logic [NumTiles-1:0] tile_sel_d, tile_sel_q;
  // L1 is running flush/invalidation
  logic [NumTiles-1:0] l1d_lock_d, l1d_lock_q;

  logic l1d_insn_commit, xbar_offset_commit, prefetch_update;

  assign l1d_insn_commit    = reg2hw.l1d_insn_commit.q;
  assign xbar_offset_commit = reg2hw.xbar_offset_commit.q;
  // ICACHE_PREFETCH_ENABLE has no commit register, a changed value starts a batch
  assign prefetch_update    = (reg2hw.icache_prefetch_enable.q != cfg_q.prefetch_en);

  // A commit is only taken while no batch is in flight; otherwise its commit bit
  // stays set until the previous batch is done. One commit per batch, INSN first.
  always_comb begin : cfg_ctrl
    cfg_d      = cfg_q;
    busy_d     = busy_q;
    start_d    = 1'b0;
    issue_d    = issue_q;
    insn_d     = insn_q;
    tile_sel_d = tile_sel_q;
    l1d_lock_d = l1d_lock_q;

    hw2reg.l1d_insn_commit.d     = 1'b0;
    hw2reg.l1d_insn_commit.de    = 1'b0;
    hw2reg.xbar_offset_commit.d  = 1'b0;
    hw2reg.xbar_offset_commit.de = 1'b0;

    if (busy_q) begin
      if (cfg_done_i) begin
        busy_d     = 1'b0;
        l1d_lock_d = '0;
      end
    end else if (l1d_insn_commit) begin
      // An L1D instruction also commits the partition and its start address
      cfg_d.l1d_private  = {reg2hw.l1d_private.group_fold.q,
                            reg2hw.l1d_private.partition.q};
      cfg_d.private_addr = reg2hw.l1d_addr.q;
      issue_d            = 1'b1;
      insn_d             = reg2hw.cfg_l1d_insn.q;
      // For non-private modes (shared/all/init), tile_sel is forced to '1.
      tile_sel_d         = (reg2hw.cfg_l1d_insn.q == 2'b00) ? tile_sel_raw[NumTiles-1:0]
                                                            : '1;
      // Lock only the tiles that will receive the instruction.
      l1d_lock_d         = tile_sel_d;
      busy_d             = 1'b1;
      start_d            = 1'b1;
      hw2reg.l1d_insn_commit.de = 1'b1;
    end else if (xbar_offset_commit) begin
      cfg_d.xbar_offset  = reg2hw.xbar_offset.q;
      issue_d            = 1'b0;
      busy_d             = 1'b1;
      start_d            = 1'b1;
      hw2reg.xbar_offset_commit.de = 1'b1;
    end else if (prefetch_update) begin
      cfg_d.prefetch_en  = reg2hw.icache_prefetch_enable.q;
      issue_d            = 1'b0;
      busy_d             = 1'b1;
      start_d            = 1'b1;
    end
  end

  `FF(cfg_q,      cfg_d,      L1dCfgRst, clk_i, rst_ni)
  `FF(busy_q,     busy_d,     1'b0,      clk_i, rst_ni)
  `FF(start_q,    start_d,    1'b0,      clk_i, rst_ni)
  `FF(issue_q,    issue_d,    1'b0,      clk_i, rst_ni)
  `FF(insn_q,     insn_d,     '0,        clk_i, rst_ni)
  `FF(tile_sel_q, tile_sel_d, '0,        clk_i, rst_ni)
  `FF(l1d_lock_q, l1d_lock_d, '0,        clk_i, rst_ni)

  // The batch starts one cycle after its commit, so the sender sees the updated values
  assign cfg_start_o    = start_q;
  assign cfg_issue_o    = issue_q;
  assign cfg_insn_o     = insn_q;
  assign cfg_tile_sel_o = tile_sel_q;
  assign cfg_o          = cfg_q;

  assign l1d_busy_o     = l1d_lock_q;
  // Busy from the cycle the commit is visible, so a status read right behind the commit write
  // never sees idle before the batch has started.
  assign hw2reg.l1d_flush_status.d = busy_q | l1d_insn_commit | xbar_offset_commit |
                                     prefetch_update;

  // One 32-bit register per barrier slot; single register is enough at
  // group granularity (max 32 groups).
  always_comb begin : barrier_mask_concat
    for (int s = 0; s < NumBarrierSlots; s++) begin
      barrier_part_mask_o[s] = reg2hw.hw_barrier_participation_mask[s].q[NumGroups-1:0];
    end
  end

  // Probe
  assign cluster_probe_o = reg2hw.spatz_status.q;

  // The hardware barrier is external and always reads `0`.
  assign hw2reg.hw_barrier.d = 0;

endmodule
