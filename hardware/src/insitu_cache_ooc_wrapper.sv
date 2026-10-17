// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Zexin Fu, ETH Zurich
//
// -----------------------------------------------------------------------------
// Out-of-context (OOC) timing harness for ONE L1 cache controller slice.
// -----------------------------------------------------------------------------
// This is a SYNTHESIS-ONLY block.  It is never instantiated by the design; it
// exists so the backend can run a small, fast Fusion Compiler job on exactly
// the logic that owns the design's critical path, instead of re-running a whole
// group (16 tiles x 4 cores + NoC) for every RTL experiment.
//
// Post-placement analysis of cachepool_group_noc_wrapper (1 GHz, ssgnp 0.675V
// -40C) showed that ~91% of the design TNS sits on the L1 tag/meta SRAM pins,
// and that the WNS path is a single SAME-CYCLE loop:
//
//   meta SRAM Q -> insitu_cache_decoder -> Cache_FSM -> tcdm_data_bank_we_o
//     -> any_other_write_in_col -> l1_data_bank_gnt -> i_access_ctrl_for_meta
//     -> tcdm_meta_bank_req_o -> meta SRAM address / CEB / clock-gate enable
//
// Both ends of that loop are SRAM macro pins, and the cross-way arm runs
// through the tile's skew-column arbiter.  So the harness must contain the
// controller AND its macros AND the grant logic -- a controller alone would cut
// the loop at the block boundary and measure nothing.
//
// Contents (one `cb` slice of cachepool_tile.sv, copied verbatim):
//   * 1 x cachepool_cache_ctrl                (the logic under test)
//   * NumTagBankPerCtrl  meta/tag SRAM macros (loop start AND end)
//   * the folded/skewed data SRAM macros      (tcdm_data_bank_we_o source)
//   * any_other_write_in_col + grant propagation (the cross-way arm)
//
// Every block-boundary port is registered inside, so in2reg/reg2out paths
// cannot mask the internal SRAM->SRAM loop: after synthesis the only paths that
// matter are reg2reg and SRAM2SRAM, which is exactly what we want to measure.
//
// KEEP IN SYNC WITH cachepool_tile.sv.  The bank/grant code below is a copy of
// the `gen_l1_cache_ctrl` slice; if that changes, change it here too or the OOC
// numbers stop tracking the real design.
// -----------------------------------------------------------------------------

module insitu_cache_ooc_wrapper
  import cachepool_pkg::*;
#(
  /// Folded data bank configuration -- mirror of cachepool_tile.sv.
  parameter bit          UseFoldedDataBanks  = 1'b1,
  parameter int unsigned FoldWayGroup        = 0,
  parameter bit          UseHashWaySelect    = 1'b1,
  parameter bit          UseForwardingBuffer = 1'b1,
  parameter type         impl_in_t           = logic,
  // Dependent, do not override.
  localparam int unsigned NumPorts         = NrTCDMPortsPerCore,
  localparam int unsigned DataWidth        = SpatzDataWidth,
  localparam type         addr_t           = logic [L1AddrWidth-1:0],
  localparam type         word_t           = logic [DataWidth-1:0],
  localparam type         strb_t           = logic [DataWidth/8-1:0],
  localparam type         tag_data_t       = logic [L1TagDataWidth-1:0],
  localparam type         tcdm_bank_addr_t = logic [$clog2(L1NumSet)-1:0]
) (
  input  logic                                     clk_i,
  input  logic                                     rst_ni,

  // Sync / flush control
  input  logic                                     cache_sync_valid_i,
  output logic                                     cache_sync_ready_o,
  input  logic [1:0]                               cache_sync_insn_i,
  input  tcdm_bank_addr_t                          bank_depth_for_SPM_i,

  // Core side
  input  logic       [NumPorts-1:0]                core_req_valid_i,
  output logic       [NumPorts-1:0]                core_req_ready_o,
  input  addr_t      [NumPorts-1:0]                core_req_addr_i,
  input  tcdm_user_t [NumPorts-1:0]                core_req_meta_i,
  input  logic       [NumPorts-1:0]                core_req_write_i,
  input  word_t      [NumPorts-1:0]                core_req_wdata_i,
  input  strb_t      [NumPorts-1:0]                core_req_wstrb_i,
  output logic       [NumPorts-1:0]                core_resp_valid_o,
  input  logic       [NumPorts-1:0]                core_resp_ready_i,
  output logic       [NumPorts-1:0]                core_resp_write_o,
  output word_t      [NumPorts-1:0]                core_resp_data_o,
  output tcdm_user_t [NumPorts-1:0]                core_resp_meta_o,

  // Refill side
  output cache_refill_req_chan_t                   refill_req_o,
  output burst_req_t                               refill_burst_o,
  output logic                                     refill_req_valid_o,
  input  logic                                     refill_req_ready_i,
  input  cache_refill_rsp_chan_t                   refill_rsp_i,
  input  logic                                     refill_rsp_valid_i,
  output logic                                     refill_rsp_ready_o
);

  // ---------------------------------------------------------------------------
  // Local parameters -- copied from cachepool_tile.sv so the macro geometry and
  // the skew mapping are bit-for-bit the ones in the placed netlist.
  // ---------------------------------------------------------------------------
  localparam int unsigned NumWordPerLine           = L1LineWidth / DataWidth;
  localparam bit          UseSkewedFolded          = UseFoldedDataBanks && (L1AssoPerCtrl > 1);
  localparam int unsigned DefaultFoldWayGroup      = (L1AssoPerCtrl >= 4) ? 4 : 2;
  localparam int unsigned EffectiveFoldWayGroup    = UseSkewedFolded ?
      ((FoldWayGroup == 0) ? DefaultFoldWayGroup : FoldWayGroup) : L1AssoPerCtrl;
  localparam int unsigned NumWayGroups             = L1AssoPerCtrl / EffectiveFoldWayGroup;
  localparam int unsigned PartSplit                = UseSkewedFolded ? EffectiveFoldWayGroup : 1;
  localparam int unsigned NumDataBankPerWay        = NumDataBankPerCtrl / L1AssoPerCtrl;
  localparam int unsigned WordsPerPart             = NumWordPerLine / PartSplit;
  localparam int unsigned BankDataWidth            = DataWidth * WordsPerPart;
  localparam int unsigned BankByteCount            = BankDataWidth / 8;
  localparam int unsigned FoldedDataDepth          = (L1CacheWayEntry / L1BankFactor) * PartSplit;
  localparam int unsigned EffectiveCoalFactor      = UseSkewedFolded ? 1 : L1CoalFactor;

  // ---------------------------------------------------------------------------
  // Registered block boundary.
  // ---------------------------------------------------------------------------
  logic                    sync_valid_q, sync_ready_d;
  logic [1:0]              sync_insn_q;
  tcdm_bank_addr_t         spm_depth_q;

  logic       [NumPorts-1:0] req_valid_q, req_ready_d, req_write_q;
  addr_t      [NumPorts-1:0] req_addr_q;
  tcdm_user_t [NumPorts-1:0] req_meta_q;
  word_t      [NumPorts-1:0] req_wdata_q;
  strb_t      [NumPorts-1:0] req_wstrb_q;

  logic       [NumPorts-1:0] rsp_valid_d, rsp_ready_q, rsp_write_d;
  word_t      [NumPorts-1:0] rsp_data_d;
  tcdm_user_t [NumPorts-1:0] rsp_meta_d;

  cache_refill_req_chan_t    rfl_req_d;
  burst_req_t                rfl_burst_d;
  logic                      rfl_req_valid_d, rfl_req_ready_q;
  cache_refill_rsp_chan_t    rfl_rsp_q;
  logic                      rfl_rsp_valid_q, rfl_rsp_ready_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_boundary_regs
    if (!rst_ni) begin
      sync_valid_q <= '0; sync_insn_q <= '0; spm_depth_q <= '0;
      req_valid_q  <= '0; req_addr_q  <= '0; req_meta_q  <= '0;
      req_write_q  <= '0; req_wdata_q <= '0; req_wstrb_q <= '0;
      rsp_ready_q  <= '0;
      rfl_req_ready_q <= '0; rfl_rsp_q <= '0; rfl_rsp_valid_q <= '0;
      cache_sync_ready_o <= '0; core_req_ready_o <= '0;
      core_resp_valid_o  <= '0; core_resp_write_o <= '0;
      core_resp_data_o   <= '0; core_resp_meta_o  <= '0;
      refill_req_o <= '0; refill_burst_o <= '0; refill_req_valid_o <= '0;
      refill_rsp_ready_o <= '0;
    end else begin
      // inputs -> internal
      sync_valid_q <= cache_sync_valid_i;
      sync_insn_q  <= cache_sync_insn_i;
      spm_depth_q  <= bank_depth_for_SPM_i;
      req_valid_q  <= core_req_valid_i;
      req_addr_q   <= core_req_addr_i;
      req_meta_q   <= core_req_meta_i;
      req_write_q  <= core_req_write_i;
      req_wdata_q  <= core_req_wdata_i;
      req_wstrb_q  <= core_req_wstrb_i;
      rsp_ready_q  <= core_resp_ready_i;
      rfl_req_ready_q <= refill_req_ready_i;
      rfl_rsp_q       <= refill_rsp_i;
      rfl_rsp_valid_q <= refill_rsp_valid_i;
      // internal -> outputs
      cache_sync_ready_o <= sync_ready_d;
      core_req_ready_o   <= req_ready_d;
      core_resp_valid_o  <= rsp_valid_d;
      core_resp_write_o  <= rsp_write_d;
      core_resp_data_o   <= rsp_data_d;
      core_resp_meta_o   <= rsp_meta_d;
      refill_req_o       <= rfl_req_d;
      refill_burst_o     <= rfl_burst_d;
      refill_req_valid_o <= rfl_req_valid_d;
      refill_rsp_ready_o <= rfl_rsp_ready_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Bank interface nets (same names/shapes as cachepool_tile.sv, minus [cb]).
  // ---------------------------------------------------------------------------
  logic            [L1AssoPerCtrl-1:0][L1BankFactor-1:0]      l1_tag_bank_req;
  logic            [L1AssoPerCtrl-1:0][L1BankFactor-1:0]      l1_tag_bank_we;
  tcdm_bank_addr_t [L1AssoPerCtrl-1:0][L1BankFactor-1:0]      l1_tag_bank_addr;
  tag_data_t       [L1AssoPerCtrl-1:0][L1BankFactor-1:0]      l1_tag_bank_wdata;
  logic            [L1AssoPerCtrl-1:0][L1BankFactor-1:0]      l1_tag_bank_be;
  tag_data_t       [L1AssoPerCtrl-1:0][L1BankFactor-1:0]      l1_tag_bank_rdata;

  logic            [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0] l1_data_bank_req;
  logic            [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0] l1_data_bank_we;
  tcdm_bank_addr_t [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0] l1_data_bank_addr;
  word_t           [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0] l1_data_bank_wdata;
  logic            [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0][DataWidth/8-1:0] l1_data_bank_be;
  word_t           [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0] l1_data_bank_rdata;
  logic            [L1AssoPerCtrl-1:0][NumDataBankPerWay-1:0] l1_data_bank_gnt;

  // ---------------------------------------------------------------------------
  // The DUT.  Parameters copied from the cachepool_tile.sv instantiation.
  // ---------------------------------------------------------------------------
  cachepool_cache_ctrl #(
    .NumPorts            (NumPorts             ),
    .CoalExtFactor       (EffectiveCoalFactor  ),
    .AddrWidth           (L1AddrWidth          ),
    .WordWidth           (DataWidth            ),
    .ByteWidth           (8                    ),
    .TagWidth            (L1TagDataWidth       ),
    .NumCacheEntry       (L1NumEntryPerCtrl    ),
    .CacheLineWidth      (L1LineWidth          ),
    .SetAssociativity    (L1AssoPerCtrl        ),
    .DataPartSplit       (PartSplit            ),
    .UseHashWaySelect    (UseHashWaySelect     ),
    .UseForwardingBuffer (UseForwardingBuffer  ),
    .BankFactor          (L1BankFactor         ),
    .RefillDataWidth     (RefillDataWidth      ),
    .core_meta_t         (tcdm_user_t          ),
    .impl_in_t           (impl_in_t            ),
    .refill_req_t        (cache_refill_req_chan_t),
    .refill_rsp_t        (cache_refill_rsp_chan_t),
    .burst_req_t         (burst_req_t          )
  ) i_l1_controller (
    .clk_i                 (clk_i          ),
    .rst_ni                (rst_ni         ),
    .cache_sync_valid_i    (sync_valid_q   ),
    .cache_sync_ready_o    (sync_ready_d   ),
    .cache_sync_insn_i     (sync_insn_q    ),
    .bank_depth_for_SPM_i  (spm_depth_q    ),

    .core_req_valid_i      (req_valid_q    ),
    .core_req_ready_o      (req_ready_d    ),
    .core_req_addr_i       (req_addr_q     ),
    .core_req_meta_i       (req_meta_q     ),
    .core_req_write_i      (req_write_q    ),
    .core_req_wdata_i      (req_wdata_q    ),
    .core_req_wstrb_i      (req_wstrb_q    ),

    .core_resp_valid_o     (rsp_valid_d    ),
    .core_resp_ready_i     (rsp_ready_q    ),
    .core_resp_write_o     (rsp_write_d    ),
    .core_resp_data_o      (rsp_data_d     ),
    .core_resp_meta_o      (rsp_meta_d     ),

    .refill_req_o          (rfl_req_d      ),
    .refill_burst_o        (rfl_burst_d    ),
    .refill_req_valid_o    (rfl_req_valid_d),
    .refill_req_ready_i    (rfl_req_ready_q),
    .refill_rsp_i          (rfl_rsp_q      ),
    .refill_rsp_valid_i    (rfl_rsp_valid_q),
    .refill_rsp_ready_o    (rfl_rsp_ready_d),

    .impl_i                ('0             ),

    .tcdm_tag_bank_req_o   (l1_tag_bank_req  ),
    .tcdm_tag_bank_we_o    (l1_tag_bank_we   ),
    .tcdm_tag_bank_addr_o  (l1_tag_bank_addr ),
    .tcdm_tag_bank_wdata_o (l1_tag_bank_wdata),
    .tcdm_tag_bank_be_o    (l1_tag_bank_be   ),
    .tcdm_tag_bank_rdata_i (l1_tag_bank_rdata),

    .tcdm_data_bank_req_o  (l1_data_bank_req  ),
    .tcdm_data_bank_we_o   (l1_data_bank_we   ),
    .tcdm_data_bank_addr_o (l1_data_bank_addr ),
    .tcdm_data_bank_wdata_o(l1_data_bank_wdata),
    .tcdm_data_bank_be_o   (l1_data_bank_be   ),
    .tcdm_data_bank_rdata_i(l1_data_bank_rdata),
    .tcdm_data_bank_gnt_i  (l1_data_bank_gnt  )
  );

  // ---------------------------------------------------------------------------
  // Meta / tag SRAM macros -- verbatim from cachepool_tile.sv.
  // These are BOTH the launch point and the capture point of the critical loop.
  // ---------------------------------------------------------------------------
  for (genvar w = 0; w < L1AssoPerCtrl; w++) begin : gen_tag_ways
    for (genvar j = 0; j < L1BankFactor; j++) begin : gen_tag_banks
      tc_sram_impl #(
        .NumWords  (L1CacheWayEntry/L1BankFactor),
        .DataWidth ($bits(tag_data_t)           ),
        .ByteWidth ($bits(tag_data_t)           ),
        .NumPorts  (1                           ),
        .Latency   (1                           ),
        .SimInit   ("zeros"                     ),
        .impl_in_t (impl_in_t                   )
      ) i_meta_bank (
        .clk_i  (clk_i                ),
        .rst_ni (rst_ni               ),
        .impl_i ('0                   ),
        .impl_o (/* unused */          ),
        .req_i  (l1_tag_bank_req  [w][j]),
        .we_i   (l1_tag_bank_we   [w][j]),
        .addr_i (l1_tag_bank_addr [w][j]),
        .wdata_i(l1_tag_bank_wdata[w][j]),
        .be_i   (l1_tag_bank_be   [w][j]),
        .rdata_o(l1_tag_bank_rdata[w][j])
      );
    end
  end

  // ---------------------------------------------------------------------------
  // Folded / skewed data SRAM macros + the cross-way grant logic --
  // verbatim from cachepool_tile.sv (gen_folded_data_banks), [cb] removed.
  // ---------------------------------------------------------------------------
  if (UseSkewedFolded) begin : gen_folded_data_banks
    typedef logic [$clog2(FoldedDataDepth)-1:0] folded_bank_addr_t;

    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0]                    bank_req;
    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0]                    bank_we;
    folded_bank_addr_t [L1AssoPerCtrl-1:0][L1BankFactor-1:0]                    bank_addr;
    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0][BankDataWidth-1:0] bank_wdata;
    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0][BankByteCount-1:0] bank_be;
    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0][BankDataWidth-1:0] bank_rdata;

    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0] part_req;
    logic              [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0] part_we;
    folded_bank_addr_t [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0] part_addr;
    logic [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0][BankDataWidth-1:0] part_wdata;
    logic [L1AssoPerCtrl-1:0][L1BankFactor-1:0][PartSplit-1:0][BankByteCount-1:0] part_be;

    logic [L1AssoPerCtrl-1:0][L1AssoPerCtrl-1:0][L1BankFactor-1:0] any_other_write_in_col;
    always_comb begin
      for (int wW = 0; wW < L1AssoPerCtrl; wW++) begin
        for (int col = 0; col < L1AssoPerCtrl; col++) begin
          for (int bsel = 0; bsel < L1BankFactor; bsel++) begin
            any_other_write_in_col[wW][col][bsel] = 1'b0;
            for (int pp = 0; pp < PartSplit; pp++) begin
              int unsigned mapped_way;
              mapped_way =
                (col / EffectiveFoldWayGroup) * EffectiveFoldWayGroup +
                ((col - pp + EffectiveFoldWayGroup) % EffectiveFoldWayGroup);
              if (mapped_way != wW) begin
                any_other_write_in_col[wW][col][bsel] |= part_we[col][bsel][pp];
              end
            end
          end
        end
      end
    end

    for (genvar group = 0; group < NumWayGroups; group++) begin : gen_skew_groups
      for (genvar way = 0; way < EffectiveFoldWayGroup; way++) begin : gen_skew_ways
        localparam int unsigned WayIdx = group * EffectiveFoldWayGroup + way;
        for (genvar part = 0; part < PartSplit; part++) begin : gen_skew_parts
          localparam int unsigned ColIdx =
              group * EffectiveFoldWayGroup + ((way + part) % EffectiveFoldWayGroup);
          for (genvar bank_sel = 0; bank_sel < L1BankFactor; bank_sel++) begin : gen_skew_banks
            localparam int unsigned BankBase = bank_sel * NumWordPerLine + part * WordsPerPart;
            assign part_req[ColIdx][bank_sel][part] =
                |l1_data_bank_req[WayIdx][BankBase +: WordsPerPart];
            assign part_we[ColIdx][bank_sel][part] =
                |l1_data_bank_we [WayIdx][BankBase +: WordsPerPart];
            assign part_addr[ColIdx][bank_sel][part] =
                folded_bank_addr_t'((l1_data_bank_addr[WayIdx][BankBase] * PartSplit) + part);

            for (genvar w = 0; w < WordsPerPart; w++) begin : gen_part_words
              localparam int unsigned FlatIdx = BankBase + w;
              assign part_wdata[ColIdx][bank_sel][part][w*DataWidth +: DataWidth] =
                  l1_data_bank_wdata[WayIdx][FlatIdx];
              assign part_be[ColIdx][bank_sel][part][w*(DataWidth/8) +: (DataWidth/8)] =
                  l1_data_bank_be[WayIdx][FlatIdx];
              assign l1_data_bank_rdata[WayIdx][FlatIdx] =
                  bank_rdata[ColIdx][bank_sel][w*DataWidth +: DataWidth];
              assign l1_data_bank_gnt[WayIdx][FlatIdx] =
                  l1_data_bank_we[WayIdx][FlatIdx]
                  | ~any_other_write_in_col[WayIdx][ColIdx][bank_sel];
            end
          end
        end
      end
    end

    always_comb begin : select_skewed_part
      for (int col = 0; col < L1AssoPerCtrl; col++) begin
        for (int bank_sel = 0; bank_sel < L1BankFactor; bank_sel++) begin
          automatic logic sel_found;
          automatic int unsigned sel_part_idx;
          bank_we[col][bank_sel]   = |part_we[col][bank_sel];
          bank_req[col][bank_sel]  = (|part_we[col][bank_sel]) | (|part_req[col][bank_sel]);
          bank_addr[col][bank_sel] = '0;
          bank_wdata[col][bank_sel]= '0;
          bank_be[col][bank_sel]   = '0;
          sel_found = 1'b0;
          sel_part_idx = 0;
          for (int part = 0; part < PartSplit; part++) begin
            if (part_we[col][bank_sel][part] && !sel_found) begin
              sel_found = 1'b1; sel_part_idx = part;
            end
          end
          if (!sel_found) begin
            for (int part = 0; part < PartSplit; part++) begin
              if (part_req[col][bank_sel][part] && !sel_found) begin
                sel_found = 1'b1; sel_part_idx = part;
              end
            end
          end
          if (sel_found) begin
            bank_addr [col][bank_sel] = part_addr [col][bank_sel][sel_part_idx];
            bank_wdata[col][bank_sel] = part_wdata[col][bank_sel][sel_part_idx];
            bank_be   [col][bank_sel] = part_be   [col][bank_sel][sel_part_idx];
          end
        end
      end
    end

    for (genvar col = 0; col < L1AssoPerCtrl; col++) begin : gen_skew_cols
      for (genvar bank_sel = 0; bank_sel < L1BankFactor; bank_sel++) begin : gen_skew_col_banks
        tc_sram_impl #(
          .NumWords  (FoldedDataDepth),
          .DataWidth (BankDataWidth  ),
          .ByteWidth (8              ),
          .NumPorts  (1              ),
          .Latency   (1              ),
          .SimInit   ("zeros"        )
        ) i_data_bank (
          .clk_i  (clk_i       ),
          .rst_ni (rst_ni      ),
          .impl_i ('0          ),
          .impl_o (/* unused */),
          .req_i  (bank_req  [col][bank_sel]),
          .we_i   (bank_we   [col][bank_sel]),
          .addr_i (bank_addr [col][bank_sel]),
          .wdata_i(bank_wdata[col][bank_sel]),
          .be_i   (bank_be   [col][bank_sel]),
          .rdata_o(bank_rdata[col][bank_sel])
        );
      end
    end
  end

endmodule
