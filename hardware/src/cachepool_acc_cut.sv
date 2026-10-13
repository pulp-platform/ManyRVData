// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

/// style-waive: COMMENT_BLOCK: function description
/// Register cut on the Snitch -> Spatz offload request. A spill register takes the request, so
/// Snitch completes its handshake before Spatz decodes it. The issue response then no longer
/// belongs to Snitch's handshake, so the fields Snitch reads there are adjusted:
///   - loadstore: Spatz memory ops are counted here at Spatz's handshake. Snitch's own counter is
///     held at 0 and its fences wait on st_rsp_done, which also covers this count.
///   - isfloat:   also set while a request is buffered.
module cachepool_acc_cut #(
  parameter type         acc_issue_req_t = logic,
  parameter type         acc_issue_rsp_t = logic,
  /// Pass everything through unchanged
  parameter bit          Bypass          = 1'b0,
  /// Spatz memory-op counter width; offloads are held while it is saturated (as acc_mem_stall)
  parameter int unsigned MemCntWidth     = 3
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  // Snitch side
  input  acc_issue_req_t       snitch_qreq_i,
  input  logic                 snitch_qvalid_i,
  output logic                 snitch_qready_o,
  output acc_issue_rsp_t       snitch_qrsp_o,
  output logic           [1:0] snitch_mem_finished_o,
  output logic           [1:0] snitch_mem_str_finished_o,
  output logic                 snitch_st_rsp_done_o,
  // Spatz side
  output acc_issue_req_t       spatz_qreq_o,
  output logic                 spatz_qvalid_o,
  input  logic                 spatz_qready_i,
  input  acc_issue_rsp_t       spatz_qrsp_i,
  input  logic           [1:0] spatz_mem_finished_i,
  input  logic           [1:0] spatz_mem_str_finished_i,
  input  logic                 spatz_st_rsp_done_i,
  // A request is buffered and not yet accepted by Spatz
  output logic                 pending_o
);

  if (Bypass) begin : gen_bypass
    assign spatz_qreq_o              = snitch_qreq_i;
    assign spatz_qvalid_o            = snitch_qvalid_i;
    assign snitch_qready_o           = spatz_qready_i;
    assign snitch_qrsp_o             = spatz_qrsp_i;
    assign snitch_mem_finished_o     = spatz_mem_finished_i;
    assign snitch_mem_str_finished_o = spatz_mem_str_finished_i;
    assign snitch_st_rsp_done_o      = spatz_st_rsp_done_i;
    assign pending_o                 = 1'b0;
  end else begin : gen_cut
    logic                   buf_valid, buf_ready;
    logic                   spatz_fire, mem_cnt_full;
    logic [MemCntWidth-1:0] mem_cnt_d, mem_cnt_q;

    spill_register #(
      .T      ( acc_issue_req_t ),
      .Bypass ( 1'b0            )
    ) i_req_cut (
      .clk_i,
      .rst_ni,
      .valid_i ( snitch_qvalid_i ),
      .ready_o ( snitch_qready_o ),
      .data_i  ( snitch_qreq_i   ),
      .valid_o ( buf_valid       ),
      .ready_i ( buf_ready       ),
      .data_o  ( spatz_qreq_o    )
    );

    assign mem_cnt_full   = &mem_cnt_q;
    assign spatz_qvalid_o = buf_valid & ~mem_cnt_full;
    assign buf_ready      = spatz_qready_i & ~mem_cnt_full;
    assign spatz_fire     = spatz_qvalid_o & spatz_qready_i;
    assign pending_o      = buf_valid;

    always_comb begin
      mem_cnt_d = mem_cnt_q;
      if (spatz_fire && spatz_qrsp_i.loadstore) begin
        mem_cnt_d = mem_cnt_d + MemCntWidth'(1);
      end
      if (spatz_mem_finished_i[0]) begin
        mem_cnt_d = mem_cnt_d - MemCntWidth'(1);
      end
      if (spatz_mem_finished_i[1]) begin
        mem_cnt_d = mem_cnt_d - MemCntWidth'(1);
      end
    end

    `FF(mem_cnt_q, mem_cnt_d, '0, clk_i, rst_ni)

    always_comb begin
      snitch_qrsp_o           = spatz_qrsp_i;
      snitch_qrsp_o.loadstore = 1'b0;
      snitch_qrsp_o.isfloat   = spatz_qrsp_i.isfloat | buf_valid;
    end

    assign snitch_mem_finished_o     = '0;
    assign snitch_mem_str_finished_o = '0;
    assign snitch_st_rsp_done_o      = spatz_st_rsp_done_i & (mem_cnt_q == '0) & ~buf_valid;

    `ASSERT(MemCntNoUnderflow,
        (spatz_mem_finished_i[0] || spatz_mem_finished_i[1]) |->
        ({1'b0, mem_cnt_q} + (spatz_fire && spatz_qrsp_i.loadstore)
         >= spatz_mem_finished_i[0] + spatz_mem_finished_i[1]))
  end

  `ASSERT_INIT(MemCntWidthValid, MemCntWidth >= 1)

endmodule
