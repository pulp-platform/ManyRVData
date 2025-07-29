// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51



`include "axi/typedef.svh"
`include "common_cells/registers.svh"

module cachepool_cluster_wrapper
 import cachepool_pkg::*;
 import fpnew_pkg::fpu_implementation_t;
 import snitch_pma_pkg::snitch_pma_t;
 #(
  parameter int unsigned AxiAddrWidth  = SpatzAxiAddrWidth,
  parameter int unsigned AxiDataWidth  = SpatzAxiDataWidth,
  parameter int unsigned AxiUserWidth  = SpatzAxiUserWidth,
  parameter int unsigned AxiInIdWidth  = SpatzAxiIdInWidth,
  parameter int unsigned AxiOutIdWidth = SpatzAxiIdOutWidth,

  parameter type axi_in_resp_t = spatz_axi_in_resp_t,
  parameter type axi_in_req_t  = spatz_axi_in_req_t,

  parameter type axi_out_resp_t = spatz_axi_out_resp_t,
  parameter type axi_out_req_t  = spatz_axi_out_req_t,

  parameter type axi_narrow_req_t  = spatz_axi_narrow_req_t,
  parameter type axi_narrow_resp_t = spatz_axi_narrow_resp_t
)(
  input  logic                                 clk_i,
  input  logic                                 rst_ni,
  output logic                                 eoc_o,
  input  logic                                 debug_req_i,

  input  logic                                 meip_i,
  input  logic                                 mtip_i,
  input  logic                                 msip_i,
  output logic                                 cluster_probe_o,
  input  axi_in_req_t                          axi_in_req_i,
  output axi_in_resp_t                         axi_in_resp_o,
  /// AXI Narrow out-port (UART)
  output axi_narrow_req_t                      axi_narrow_req_o,
  input  axi_narrow_resp_t                     axi_narrow_resp_i,
  output axi_out_req_t  [NumClusterSlv-1:0]    axi_out_req_o,
  input  axi_out_resp_t [NumClusterSlv-1:0]    axi_out_resp_i
);


  spatz_axi_iwc_out_req_t  [NumClusterSlv-1:0] axi_from_cluster_iwc_req;
  spatz_axi_iwc_out_resp_t [NumClusterSlv-1:0] axi_from_cluster_iwc_resp;

  // Spatz cluster under test.
  cachepool_cluster #(
    .AxiAddrWidth             (AxiAddrWidth             ),
    .AxiDataWidth             (AxiDataWidth             ),
    .AxiIdWidthIn             (AxiInIdWidth             ),
    .AxiIdWidthOut            (AxiOutIdWidth            ),
    .AxiUserWidth             (AxiUserWidth             ),
    .BootAddr                 (BootAddr                 ),
    .UartAddr                 (UartAddr                 ),
    .ClusterPeriphSize        (64                       ),
    .NrCores                  (NumCores                 ),
    .TCDMDepth                (TCDMDepth                ),
    .NrBanks                  (NumBank                  ),
    .ICacheLineWidth          (ICacheLineWidth          ),
    .ICacheLineCount          (ICacheLineCount          ),
    .ICacheSets               (ICacheSets               ),
    .FPUImplementation        (FPUImplementation        ),
    .NumSpatzFPUs             (NFpu                     ),
    .NumSpatzIPUs             (NIpu                     ),
    .SnitchPMACfg             (SnitchPMACfg             ),
    .NumIntOutstandingLoads   (NumIntOutstandingLoads   ),
    .NumIntOutstandingMem     (NumIntOutstandingMem     ),
    .NumSpatzOutstandingLoads (NumSpatzOutstandingLoads ),
    .axi_in_req_t             (axi_in_req_t             ),
    .axi_in_resp_t            (axi_in_resp_t            ),
    .axi_narrow_req_t         (axi_narrow_req_t         ),
    .axi_narrow_resp_t        (axi_narrow_resp_t        ),
    .axi_out_req_t            (axi_out_req_t  ),
    .axi_out_resp_t           (axi_out_resp_t ),
    .Xdma                     (4'h0                     ),
    .DMAAxiReqFifoDepth       (3                        ),
    .DMAReqFifoDepth          (3                        ),
    .RegisterOffloadRsp       (1                        ),
    .RegisterCoreReq          (1                        ),
    .RegisterCoreRsp          (1                        ),
    .RegisterTCDMCuts         (1                        ),
    .RegisterExt              (1                        ),
    .XbarLatency              (axi_pkg::CUT_ALL_PORTS   ),
    .MaxMstTrans              (NumAxiMaxTrans           ),
    .MaxSlvTrans              (NumAxiMaxTrans           )
  ) i_cluster (
    .clk_i                    ,
    .rst_ni                   ,
    .eoc_o                    (eoc_o                    ),
    .impl_i                   ( '0 ),
    .error_o                  (),
    .debug_req_i              ({NumCores{debug_req_i}}),
    .meip_i                   ({NumCores{meip_i}}),
    .mtip_i                   ({NumCores{mtip_i}}),
    .msip_i                   ({NumCores{msip_i}}),
    .hart_base_id_i           (10'h0),
    .cluster_base_addr_i      (TCDMStartAddr),
    .cluster_probe_o          (cluster_probe_o),
    .axi_in_req_i             ,
    .axi_in_resp_o            ,
    .axi_narrow_req_o         ,
    .axi_narrow_resp_i        ,
    // AXI Master Port
    .axi_out_req_o            ( axi_out_req_o  ),
    .axi_out_resp_i           ( axi_out_resp_i )
  );

  // AXI utilization monitor
`ifndef TARGET_SYNTHESIS
  typedef logic [31:0] cnt_t;
  // AR channel utilization
  cnt_t [NumClusterSlv-1:0] axi_ar_valid_cnt_d, axi_ar_valid_cnt_q;
  cnt_t [NumClusterSlv-1:0] axi_ar_trans_cnt_d, axi_ar_trans_cnt_q;
  `FF (axi_ar_valid_cnt_q, axi_ar_valid_cnt_d, '0)
  `FF (axi_ar_trans_cnt_q, axi_ar_trans_cnt_d, '0)

  // R channel utilization
  cnt_t [NumClusterSlv-1:0] axi_r_valid_cnt_d, axi_r_valid_cnt_q;
  cnt_t [NumClusterSlv-1:0] axi_r_trans_cnt_d, axi_r_trans_cnt_q;
  `FF (axi_r_valid_cnt_q, axi_r_valid_cnt_d, '0)
  `FF (axi_r_trans_cnt_q, axi_r_trans_cnt_d, '0)

  // number of cycles inside kernel
  cnt_t act_cyc_d, act_cyc_q;
  `FF (act_cyc_q, act_cyc_d, '0)


  always_comb begin : gen_axi_perf_cnt_comb
    axi_ar_valid_cnt_d = axi_ar_valid_cnt_q;
    axi_ar_trans_cnt_d = axi_ar_trans_cnt_q;
    axi_r_valid_cnt_d  = axi_r_valid_cnt_q;
    axi_r_trans_cnt_d  = axi_r_trans_cnt_q;

    act_cyc_d = act_cyc_q;

    if (cluster_probe_o) begin
      act_cyc_d ++;

      for (int i = 0; i < NumClusterSlv; i++) begin
        if (axi_out_req_o[i].ar_valid) begin
          // AR valid
          axi_ar_valid_cnt_d[i] ++;
          if (axi_out_resp_i[i].ar_ready) begin
            // AR valid HS
            axi_ar_trans_cnt_d[i] ++;
          end
        end

        if (axi_out_resp_i[i].r_valid) begin
          // AR valid
          axi_r_valid_cnt_d[i] ++;
          if (axi_out_req_o[i].r_ready) begin
            // AR valid HS
            axi_r_trans_cnt_d[i] ++;
          end
        end
      end
    end
  end

  final begin

    automatic real active_cyc  = act_cyc_q;
    automatic real ar_act_tran = axi_ar_trans_cnt_q[0] + axi_ar_trans_cnt_q[1] + axi_ar_trans_cnt_q[2]+ axi_ar_trans_cnt_q[3];
    automatic real ar_act_util = active_cyc == 0 ?
                                0 : 100 * ar_act_tran / active_cyc / 4;

    automatic real r_act_tran  = axi_r_trans_cnt_q[0] + axi_r_trans_cnt_q[1] + axi_r_trans_cnt_q[2]+ axi_r_trans_cnt_q[3];
    automatic real r_act_util  = active_cyc == 0 ?
                                0 : 100 * r_act_tran / active_cyc / 4;

    automatic real ar_act_util0 = active_cyc == 0 ?
                                  0 : 100 * axi_ar_trans_cnt_q[0]/active_cyc;
    automatic real ar_act_util1 = active_cyc == 0 ?
                                  0 : 100 * axi_ar_trans_cnt_q[1]/active_cyc;
    automatic real ar_act_util2 = active_cyc == 0 ?
                                  0 : 100 * axi_ar_trans_cnt_q[2]/active_cyc;
    automatic real ar_act_util3 = active_cyc == 0 ?
                                  0 : 100 * axi_ar_trans_cnt_q[3]/active_cyc;

    automatic real r_act_util0  = active_cyc == 0 ?
                                  0 : 100 * axi_r_trans_cnt_q[0]/active_cyc;
    automatic real r_act_util1  = active_cyc == 0 ?
                                  0 : 100 * axi_r_trans_cnt_q[1]/active_cyc;
    automatic real r_act_util2  = active_cyc == 0 ?
                                  0 : 100 * axi_r_trans_cnt_q[2]/active_cyc;
    automatic real r_act_util3  = active_cyc == 0 ?
                                  0 : 100 * axi_r_trans_cnt_q[3]/active_cyc;

    $display(" ");
    $display(" ");
    $display("*********************************************************************");
    $display("***            CachePool Off-Chip AXI Utilization Report          ***");
    $display("   ---------------------------------------------------------------   ");
    $display("Read");
    $display("   Total Kernel Cycles:              %16d",   active_cyc  );
    $display("   Total AR Trans in Kernel:         %16d",   ar_act_tran );
    $display("   Active AR Utilization:            %16.2f", ar_act_util );
    $display("   Total R Trans in Kernel:          %16d",   r_act_tran  );
    $display("   Active R Utilization:             %16.2f", r_act_util  );
    $display(" Channel 0");
    $display("   CH0 AR Trans in Kernel:           %16d",   axi_ar_trans_cnt_q[0] );
    $display("   Active AR Utilization:            %16.2f", ar_act_util0 );
    $display("   CH0 R Trans in Kernel:            %16d",   axi_r_trans_cnt_q[0] );
    $display("   Active R Utilization:             %16.2f", r_act_util0 );
    $display(" Channel 1");
    $display("   CH1 AR Trans in Kernel:           %16d",   axi_ar_trans_cnt_q[1] );
    $display("   Active AR Utilization:            %16.2f", ar_act_util1 );
    $display("   CH1 R Trans in Kernel:            %16d",   axi_r_trans_cnt_q[1] );
    $display("   Active R Utilization:             %16.2f", r_act_util1 );
    $display(" Channel 2");
    $display("   CH2 AR Trans in Kernel:           %16d",   axi_ar_trans_cnt_q[2] );
    $display("   Active AR Utilization:            %16.2f", ar_act_util2 );
    $display("   CH2 R Trans in Kernel:            %16d",   axi_r_trans_cnt_q[2] );
    $display("   Active R Utilization:             %16.2f", r_act_util2 );
    $display(" Channel 3");
    $display("   CH3 AR Trans in Kernel:           %16d",   axi_ar_trans_cnt_q[3] );
    $display("   Active AR Utilization:            %16.2f", ar_act_util3 );
    $display("   CH3 R Trans in Kernel:            %16d",   axi_r_trans_cnt_q[3] );
    $display("   Active R Utilization:             %16.2f", r_act_util3 );
    $display("*********************************************************************");

  end

  // Assertions

  if (AxiAddrWidth != SpatzAxiAddrWidth)
    $error("[spatz_cluster_wrapper] AXI Address Width does not match the configuration.");

  if (AxiDataWidth != SpatzAxiDataWidth)
    $error("[spatz_cluster_wrapper] AXI Data Width does not match the configuration.");

  if (AxiUserWidth != SpatzAxiUserWidth)
    $error("[spatz_cluster_wrapper] AXI User Width does not match the configuration.");

  if (AxiInIdWidth != SpatzAxiIdInWidth)
    $error("[spatz_cluster_wrapper] AXI Id Width (In) does not match the configuration.");

  if (AxiOutIdWidth != SpatzAxiIdOutWidth)
    $error("[spatz_cluster_wrapper] AXI Id Width (Out) does not match the configuration.");
`endif

endmodule
