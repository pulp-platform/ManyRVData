// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>


`include "axi/typedef.svh"
`include "common_cells/registers.svh"

module cachepool_cluster_wrapper
 import cachepool_pkg::*;
 import fpnew_pkg::fpu_implementation_t;
 import snitch_pma_pkg::snitch_pma_t;
 #(
  parameter int unsigned AxiAddrWidth       = SpatzAxiAddrWidth,
  parameter int unsigned AxiDataWidth       = SpatzAxiDataWidth,
  parameter int unsigned AxiUserWidth       = SpatzAxiUserWidth,
  // External input ID width (SoC/testbench → wrapper); remapped to SpatzAxiIdInWidth inside.
  parameter int unsigned AxiInIdWidth       = WrapperAxiIdInWidth,
  // External wide output ID width (wrapper → DRAM); remapped from SpatzAxiIdOutWidth inside.
  parameter int unsigned AxiOutIdWidth      = WrapperAxiIdOutWidth,
  // External narrow output ID width (UART, wrapper → SoC); remapped from SpatzAxiUartIdWidth inside.
  parameter int unsigned AxiNarrowOutIdWidth = WrapperAxiNarrowIdOutWidth,

  // External input types use the wrapper-narrowed ID (WrapperAxiIdInWidth).
  parameter type axi_in_req_t               = spatz_axi_wrapper_in_req_t,
  parameter type axi_in_resp_t              = spatz_axi_wrapper_in_resp_t,

  // External wide output types use the wrapper-narrowed ID (WrapperAxiIdOutWidth).
  parameter type axi_out_req_t              = spatz_axi_wrapper_out_req_t,
  parameter type axi_out_resp_t             = spatz_axi_wrapper_out_resp_t,

  // External narrow output types use the wrapper-narrowed ID (WrapperAxiNarrowIdOutWidth).
  parameter type axi_narrow_out_req_t       = spatz_axi_wrapper_narrow_out_req_t,
  parameter type axi_narrow_out_resp_t      = spatz_axi_wrapper_narrow_out_resp_t

)(
  input  logic                                   clk_i,
  input  logic                                   rst_ni,
  output logic          [3:0]                    eoc_o,
  input  logic                                   debug_req_i,

  input  logic                                   meip_i,
  input  logic                                   mtip_i,
  input  logic                                   msip_i,
  output logic                                   cluster_probe_o,
  // AXI slave port (from SoC/testbench); external ID = AxiInIdWidth.
  input  axi_in_req_t                            axi_in_req_i,
  output axi_in_resp_t                           axi_in_resp_o,
  /// AXI Narrow out-port (UART); external ID = AxiNarrowOutIdWidth.
  output axi_narrow_out_req_t                    axi_narrow_req_o,
  input  axi_narrow_out_resp_t                   axi_narrow_resp_i,
  // AXI wide master ports (to DRAM); external ID = AxiOutIdWidth.
  output axi_out_req_t  [NumClusterSlv-1:0]      axi_out_req_o,
  input  axi_out_resp_t [NumClusterSlv-1:0]      axi_out_resp_i
);

  // Internal signals between wrapper remappers and cluster (fat IDs).
  spatz_axi_in_req_t                       axi_cluster_in_req;
  spatz_axi_in_resp_t                      axi_cluster_in_resp;
  axi_uart_req_t                           axi_cluster_narrow_req;
  axi_uart_resp_t                          axi_cluster_narrow_resp;
  spatz_axi_out_req_t  [NumClusterSlv-1:0] axi_cluster_out_req;
  spatz_axi_out_resp_t [NumClusterSlv-1:0] axi_cluster_out_resp;

  // Spatz cluster under test.
  // Internal AXI types are fixed (full-width IDs); the wrapper remaps at both boundaries.
  cachepool_cluster #(
    .AxiAddrWidth             (AxiAddrWidth             ),
    .AxiDataWidth             (AxiDataWidth             ),
    // Cluster always sees the full internal ID width on its slave port.
    .AxiIdWidthIn             (SpatzAxiIdInWidth        ),
    .AxiIdWidthOut            (SpatzAxiIdOutWidth       ),
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
    .FPUImplementation        (FPUImplementation_Core   ),
    .NumSpatzFPUs             (NFpu                     ),
    .NumSpatzIPUs             (NIpu                     ),
    .SnitchPMACfg             (SnitchPMACfg             ),
    .NumIntOutstandingLoads   (NumIntOutstandingLoads   ),
    .NumIntOutstandingMem     (NumIntOutstandingMem     ),
    .NumSpatzOutstandingLoads (NumSpatzOutstandingLoads ),
    // Cluster slave port uses full internal type (remap is above this level).
    .axi_in_req_t             (spatz_axi_in_req_t       ),
    .axi_in_resp_t            (spatz_axi_in_resp_t      ),
    // Cluster internally uses the fat output type; the wrapper remaps it.
    .axi_out_req_t            (spatz_axi_out_req_t      ),
    .axi_out_resp_t           (spatz_axi_out_resp_t     ),
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
    .impl_i                   ('0                       ),
    .error_o                  (                         ),
    .debug_req_i              (debug_req_i              ),
    .meip_i                   (meip_i                   ),
    .mtip_i                   (mtip_i                   ),
    .msip_i                   (msip_i                   ),
    .hart_base_id_i           (10'h0                    ),
    .cluster_base_addr_i      (TCDMStartAddr            ),
    .cluster_probe_o          (cluster_probe_o          ),
    // Remapped internal connections.
    .axi_in_req_i             (axi_cluster_in_req       ),
    .axi_in_resp_o            (axi_cluster_in_resp      ),
    .axi_narrow_req_o         (axi_cluster_narrow_req   ),
    .axi_narrow_resp_i        (axi_cluster_narrow_resp  ),
    // AXI Master Port (fat IDs; wrapper remaps before external port).
    .axi_out_req_o            (axi_cluster_out_req      ),
    .axi_out_resp_i           (axi_cluster_out_resp     )
  );

  // Expand WrapperAxiIdInWidth -> SpatzAxiIdInWidth on the cluster slave port.
  // The external SoC/testbench drives narrow IDs; the cluster expects full-width IDs.
  axi_id_remap #(
    .AxiSlvPortIdWidth    ( WrapperAxiIdInWidth         ),
    // Up to 2^WrapperAxiIdInWidth = 16 unique IDs from external host.
    .AxiSlvPortMaxUniqIds ( 2**WrapperAxiIdInWidth      ),
    .AxiMaxTxnsPerId      ( NumAxiMaxTrans              ),
    .AxiMstPortIdWidth    ( SpatzAxiIdInWidth           ),
    .slv_req_t            ( axi_in_req_t                ),
    .slv_resp_t           ( axi_in_resp_t               ),
    .mst_req_t            ( spatz_axi_in_req_t          ),
    .mst_resp_t           ( spatz_axi_in_resp_t         )
  ) i_in_id_remap (
    .clk_i      ( clk_i               ),
    .rst_ni     ( rst_ni              ),
    .slv_req_i  ( axi_in_req_i        ),
    .slv_resp_o ( axi_in_resp_o       ),
    .mst_req_o  ( axi_cluster_in_req  ),
    .mst_resp_i ( axi_cluster_in_resp )
  );

  // Remap SpatzAxiUartIdWidth -> WrapperAxiNarrowIdOutWidth on the UART master port.
  axi_id_remap #(
    .AxiSlvPortIdWidth    ( SpatzAxiUartIdWidth                ),
    // MaxUniqIds capped by the slave port's ID space.
    .AxiSlvPortMaxUniqIds ( 2**SpatzAxiUartIdWidth             ),
    .AxiMaxTxnsPerId      ( NumAxiMaxTrans                     ),
    .AxiMstPortIdWidth    ( WrapperAxiNarrowIdOutWidth         ),
    .slv_req_t            ( axi_uart_req_t                     ),
    .slv_resp_t           ( axi_uart_resp_t                    ),
    .mst_req_t            ( axi_narrow_out_req_t               ),
    .mst_resp_t           ( axi_narrow_out_resp_t              )
  ) i_narrow_out_id_remap (
    .clk_i      ( clk_i                    ),
    .rst_ni     ( rst_ni                   ),
    .slv_req_i  ( axi_cluster_narrow_req   ),
    .slv_resp_o ( axi_cluster_narrow_resp  ),
    .mst_req_o  ( axi_narrow_req_o         ),
    .mst_resp_i ( axi_narrow_resp_i        )
  );

  // Remap SpatzAxiIdOutWidth -> WrapperAxiIdOutWidth per DRAM channel.
  // With FlooNoC mesh, both are 6 bits (no-op remap); kept for interface stability.
  for (genvar ch = 0; ch < NumClusterSlv; ch++) begin : gen_out_id_remap
    axi_id_remap #(
      .AxiSlvPortIdWidth    ( SpatzAxiIdOutWidth           ),
      .AxiSlvPortMaxUniqIds ( NumAxiMaxTrans               ),
      .AxiMaxTxnsPerId      ( NumAxiMaxTrans               ),
      .AxiMstPortIdWidth    ( WrapperAxiIdOutWidth         ),
      .slv_req_t            ( spatz_axi_out_req_t          ),
      .slv_resp_t           ( spatz_axi_out_resp_t         ),
      .mst_req_t            ( spatz_axi_wrapper_out_req_t  ),
      .mst_resp_t           ( spatz_axi_wrapper_out_resp_t )
    ) i_out_id_remap (
      .clk_i      ( clk_i                     ),
      .rst_ni     ( rst_ni                     ),
      .slv_req_i  ( axi_cluster_out_req  [ch] ),
      .slv_resp_o ( axi_cluster_out_resp [ch] ),
      .mst_req_o  ( axi_out_req_o        [ch] ),
      .mst_resp_i ( axi_out_resp_i       [ch] )
    );
  end

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

  if (AxiInIdWidth != WrapperAxiIdInWidth)
    $error("[spatz_cluster_wrapper] AXI Id Width (In) does not match the configuration.");

  if (AxiOutIdWidth != WrapperAxiIdOutWidth)
    $error("[spatz_cluster_wrapper] AXI Id Width (Out) does not match the configuration.");

  if (AxiNarrowOutIdWidth != WrapperAxiNarrowIdOutWidth)
    $error("[spatz_cluster_wrapper] AXI Narrow Id Width (Out) does not match the configuration.");
`endif

endmodule
