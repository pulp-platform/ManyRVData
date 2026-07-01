// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

/// Exposes cluster confugration and information as memory mapped information

`include "common_cells/registers.svh"

module cachepool_peripheral
  import snitch_pkg::*;
  import cachepool_peripheral_reg_pkg::*;
#(
  parameter int unsigned AddrWidth    = 0,
  parameter int unsigned DMADataWidth = 0,
  parameter int unsigned SPMWidth     = 0,
  // Number of tiles (used for flush controller granularity)
  parameter int unsigned NumTiles     = 1,
  // Number of cores (one per-core LP1 CMO slot).  Must be <= NumLp1CmoRegs.
  parameter int unsigned NumCores     = 1,
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter type cache_insn_t = logic,
  parameter type lp1_cmo_req_t = logic,
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
  output addr_t                      private_start_addr_o,
  output logic                       icache_prefetch_enable_o,
  output logic                       cluster_probe_o,
  input  logic [9:0]                 cluster_hart_base_id_i,
  /// For cache xbar dynamic configuration
  output logic [4:0]                 dynamic_offset_o,
  output spm_size_t                  l1d_spm_size_o,
  output logic [3:0]                 l1d_private_o,
  output cache_insn_t                l1d_insn_o,
  output logic                       l1d_insn_valid_o,
  input  logic [NumTiles-1:0]        l1d_insn_ready_i,
  output logic [NumTiles-1:0]        l1d_busy_o,
  // Per-core private-L1 (LP1) CMO injector interface (one slot per core).
  output lp1_cmo_req_t [NumCores-1:0] lp1_cmo_req_o,
  output logic         [NumCores-1:0] lp1_cmo_valid_o,
  input  logic         [NumCores-1:0] lp1_cmo_done_i
);

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

  //////////// Cache XBar ////////////
  logic [4:0] xbar_offset_d, xbar_offset_q;
  assign      dynamic_offset_o    = xbar_offset_q;
  logic       xbar_offset_commit;
  assign      xbar_offset_commit  = reg2hw.xbar_offset_commit.q;
  always_comb begin : xbar_offset_cfg
    xbar_offset_d = xbar_offset_q;
    hw2reg.xbar_offset_commit.d  = 1'b0;
    hw2reg.xbar_offset_commit.de = 1'b0;

    if (xbar_offset_commit) begin
      xbar_offset_d = reg2hw.xbar_offset.q;
      hw2reg.xbar_offset_commit.d  = 1'b0;
      hw2reg.xbar_offset_commit.de = 1'b1;
    end
  end
  // Default value is 13
  `FF(xbar_offset_q, xbar_offset_d, 5'd14, clk_i, rst_ni)


  //////////// L1 DCache ////////////
  logic [9:0]           l1d_spm_size_d, l1d_spm_size_q;
  logic [3:0]           l1d_private_d, l1d_private_q;
  addr_t                private_start_addr_d, private_start_addr_q;
  // L1 is running flush/invalidation
  logic [NumTiles-1:0]  l1d_lock_d, l1d_lock_q;
  logic                 l1d_spm_commit, l1d_insn_commit;

  // L1D Cache
  // For committing the cfg, if the cfg is taken, it will be pulled to 0;
  // Otherwise, it will be kept at 1 until taken.
  assign       l1d_spm_commit  = reg2hw.l1d_spm_commit.q;
  assign       l1d_insn_commit = reg2hw.l1d_insn_commit.q;

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

  assign l1d_private_o        = l1d_private_q;
  assign private_start_addr_o = private_start_addr_q;

  // Concatenate all tile-select register words into one wide vector and slice
  // to NumTiles.  Unused upper bits (for small configs) are optimised away.
  localparam int unsigned NumTileSelWords = cachepool_peripheral_reg_pkg::NumTileSelRegs;
  logic [NumTileSelWords*32-1:0] tile_sel_raw;
  always_comb begin : tile_sel_concat
    for (int i = 0; i < NumTileSelWords; i++) begin
      tile_sel_raw[i*32 +: 32] = reg2hw.cfg_l1d_tile_sel[i].q;
    end
  end

  // Cache Flush Controller
  // Operates at tile granularity.  l1d_lock_q[t] is set when tile t is
  // issued an instruction and cleared when tile t returns ready.
  // Busy is asserted while any selected tile has not yet completed.
  always_comb begin : l1d_insn_cfg
    // Flush takes time, we cannot take next insn while flushing
    l1d_insn_o            = '0;
    l1d_insn_valid_o      = '0;
    l1d_lock_d            = l1d_lock_q;
    l1d_private_d         = l1d_private_q;
    private_start_addr_d  = private_start_addr_q;

    hw2reg.l1d_insn_commit.d  = 1'b0;
    hw2reg.l1d_insn_commit.de = 1'b0;

    if (l1d_insn_commit) begin
      l1d_private_d         = reg2hw.l1d_private.q;
      private_start_addr_d  = reg2hw.l1d_addr.q;
      // User issues a flush/invalidation
      if (|l1d_lock_q == '0) begin
        // We are ready to accept a new instruction.
        // Build the cache_insn_t: pack insn + tile_sel.
        // For non-private modes (shared/all/init), tile_sel is forced to '1.
        l1d_insn_o.insn     = reg2hw.cfg_l1d_insn.q;
        l1d_insn_o.tile_sel = (reg2hw.cfg_l1d_insn.q == 2'b00)
                            ? tile_sel_raw[NumTiles-1:0]
                            : {NumTiles{1'b1}};
        l1d_insn_valid_o    = 1'b1;
        // Lock only the tiles that will receive the instruction.
        l1d_lock_d          = l1d_insn_o.tile_sel;
        // Clear the commit
        hw2reg.l1d_insn_commit.d  = 1'b0;
        hw2reg.l1d_insn_commit.de = 1'b1;
      end
    end

    for (int t = 0; t < NumTiles; t++) begin
      // Unlock tile t when it signals completion (one-cycle ready pulse).
      if (l1d_insn_ready_i[t]) begin
        l1d_lock_d[t] = 1'b0;
      end
      l1d_busy_o[t] = l1d_lock_q[t];
    end
  end

  `FF(private_start_addr_q, private_start_addr_d, 32'hA000_0000, clk_i, rst_ni)
  `FF(l1d_private_q, l1d_private_d, 0, clk_i, rst_ni)
  `FF(l1d_lock_q, l1d_lock_d, '0, clk_i, rst_ni)
  // To show if the current flush/invalidation is complete
  assign hw2reg.l1d_flush_status.d = (l1d_lock_q != '0);
  // assign l1d_busy_o = (l1d_lock_q != '0);

  //////////// Private-L1 (LP1) per-core CMO ////////////
  // Per-core handshake mirroring the L1D flush path above, but vectorized so
  // that independent cores running unrelated critical sections issue CMOs
  // without contending on a shared trigger register.  Per core slot [c]:
  //   commit[c] & !lock[c] -> pulse valid[c], present op/addr, set lock[c],
  //                           and self-clear the commit bit
  //   done[c]              -> clear lock[c]
  //   status[c]            = lock[c]  (busy while a CMO is in flight)
  logic [NumLp1CmoRegs-1:0] lp1_cmo_lock_d, lp1_cmo_lock_q;

  always_comb begin : lp1_cmo_cfg
    lp1_cmo_lock_d = lp1_cmo_lock_q;

    // Default every register-file back-channel low (covers unused upper slots
    // when NumCores < NumLp1CmoRegs).
    for (int unsigned i = 0; i < NumLp1CmoRegs; i++) begin
      hw2reg.lp1_cmo_commit[i].d  = 1'b0;
      hw2reg.lp1_cmo_commit[i].de = 1'b0;
      hw2reg.lp1_cmo_status[i].d  = 1'b0;
    end

    // Default the per-core outputs.
    lp1_cmo_req_o   = '0;
    lp1_cmo_valid_o = '0;

    for (int unsigned c = 0; c < NumCores; c++) begin
      // Present the requested op/addr for this core's injector.
      lp1_cmo_req_o[c].op   = reg2hw.cfg_lp1_cmo[c].q;
      lp1_cmo_req_o[c].addr = reg2hw.cfg_lp1_cmo_addr[c].q;

      // Issue when committed and not already in flight.
      if (reg2hw.lp1_cmo_commit[c].q && !lp1_cmo_lock_q[c]) begin
        lp1_cmo_valid_o[c]          = 1'b1;
        lp1_cmo_lock_d[c]           = 1'b1;
        hw2reg.lp1_cmo_commit[c].d  = 1'b0;   // self-clear the commit
        hw2reg.lp1_cmo_commit[c].de = 1'b1;
      end

      // Clear the lock when the injector signals completion.
      if (lp1_cmo_done_i[c]) begin
        lp1_cmo_lock_d[c] = 1'b0;
      end

      // Busy/done status polled by the runtime.
      hw2reg.lp1_cmo_status[c].d = lp1_cmo_lock_q[c];
    end
  end

  `FF(lp1_cmo_lock_q, lp1_cmo_lock_d, '0, clk_i, rst_ni)

  // Enable icache prefetch
  assign icache_prefetch_enable_o = reg2hw.icache_prefetch_enable.q;

  // Probe
  assign cluster_probe_o = reg2hw.spatz_status.q;

  // The hardware barrier is external and always reads `0`.
  assign hw2reg.hw_barrier.d = 0;

endmodule
