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
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter type cache_insn_t = logic,
  // Nr of course in the cluster
  parameter logic [31:0] NrCores       = 0,
  /// Derived parameter *Do not override*
  parameter type addr_t = logic [AddrWidth-1:0],
  parameter type spm_size_t = logic [SPMWidth-1:0]
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  input  reg_req_t                   reg_req_i,
  output reg_rsp_t                   reg_rsp_o,

  output logic                       eoc_o,
  input  addr_t                      tcdm_start_address_i,
  input  addr_t                      tcdm_end_address_i,
  output addr_t                      private_start_addr_o,
  output logic                       icache_prefetch_enable_o,
  output logic [NrCores-1:0]         cl_clint_o,
  output logic                       cluster_probe_o,
  input  logic [9:0]                 cluster_hart_base_id_i,
  /// For cache xbar dynamic configuration
  output logic [4:0]                 dynamic_offset_o,
  output spm_size_t                  l1d_spm_size_o,
  output logic [3:0]                 l1d_private_o,
  output cache_insn_t                l1d_insn_o,
  output logic                       l1d_insn_valid_o,
  input  logic [NumTiles-1:0]        l1d_insn_ready_i,
  output logic [NumTiles-1:0]        l1d_busy_o
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
  logic [NumPerfCounters-1:0][47:0] perf_counter_d, perf_counter_q;
  logic [31:0]          cl_clint_d, cl_clint_q;
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
                            ? reg2hw.cfg_l1d_tile_sel.q[NumTiles-1:0]
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
  `FF(l1d_private_q, l1d_private_d, '0, clk_i, rst_ni)
  `FF(l1d_lock_q, l1d_lock_d, '0, clk_i, rst_ni)
  // To show if the current flush/invalidation is complete
  assign hw2reg.l1d_flush_status.d = (l1d_lock_q != '0);
  // assign l1d_busy_o = (l1d_lock_q != '0);

  // Wake-up logic: Bits in cl_clint_q can be set/cleared with writes to
  // cl_clint_set/cl_clint_clear
  always_comb begin
    cl_clint_d = cl_clint_q;
    if (reg2hw.cl_clint_set.qe) begin
      cl_clint_d = cl_clint_q | reg2hw.cl_clint_set.q;
    end else if (reg2hw.cl_clint_clear.qe) begin
      cl_clint_d = cl_clint_q & ~reg2hw.cl_clint_clear.q;
    end
  end
  `FF(cl_clint_q, cl_clint_d, '0, clk_i, rst_ni)
  assign cl_clint_o = cl_clint_q[NrCores-1:0];

  // Enable icache prefetch
  assign icache_prefetch_enable_o = reg2hw.icache_prefetch_enable.q;

  // Probe
  assign cluster_probe_o = reg2hw.spatz_status.q;

  // The hardware barrier is external and always reads `0`.
  assign hw2reg.hw_barrier.d = 0;

endmodule
