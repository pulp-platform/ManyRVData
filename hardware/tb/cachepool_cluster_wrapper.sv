// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51



`include "axi/typedef.svh"

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
  parameter type axi_out_req_t  = spatz_axi_out_req_t
)(
  input  logic                                 clk_i,
  input  logic                                 rst_ni,
  output logic                                 eoc_o,
  input  logic          [NumCores-1:0]         debug_req_i,

  input  logic          [NumCores-1:0]         meip_i,
  input  logic          [NumCores-1:0]         mtip_i,
  input  logic          [NumCores-1:0]         msip_i,
  output logic                                 cluster_probe_o,
  input  axi_in_req_t                          axi_in_req_i,
  output axi_in_resp_t                         axi_in_resp_o,
  output axi_out_req_t  [NumClusterAxiSlv-1:0] axi_out_req_o,
  input  axi_out_resp_t [NumClusterAxiSlv-1:0] axi_out_resp_i
);

  localparam int unsigned NumIntOutstandingLoads   [NumCores] = '{default: 4};
  localparam int unsigned NumIntOutstandingMem     [NumCores] = '{default: 4};
  localparam int unsigned NumSpatzOutstandingLoads [NumCores] = '{default: 16};

  spatz_axi_iwc_out_req_t  [NumClusterAxiSlv-1:0] axi_from_cluster_iwc_req;
  spatz_axi_iwc_out_resp_t [NumClusterAxiSlv-1:0] axi_from_cluster_iwc_resp;

  for (genvar port = 0; port < NumL2Channel; port ++) begin : gen_iw_conv
    axi_iw_converter #(
      .AxiSlvPortIdWidth      ( IwcAxiIdOutWidth  ),
      .AxiMstPortIdWidth      ( AxiOutIdWidth     ),
      .AxiSlvPortMaxUniqIds   ( 2                 ),
      .AxiSlvPortMaxTxnsPerId ( 2                 ),
      .AxiSlvPortMaxTxns      ( 4                 ),
      .AxiMstPortMaxUniqIds   ( 2                 ),
      .AxiMstPortMaxTxnsPerId ( 4                 ),
      .AxiAddrWidth           ( AxiAddrWidth      ),
      .AxiDataWidth           ( AxiDataWidth      ),
      .AxiUserWidth           ( AxiUserWidth      ),
      .slv_req_t              ( spatz_axi_iwc_out_req_t ),
      .slv_resp_t             ( spatz_axi_iwc_out_resp_t),
      .mst_req_t              ( axi_out_req_t     ),
      .mst_resp_t             ( axi_out_resp_t    )
    ) iw_converter(
      .clk_i                  ( clk_i                           ),
      .rst_ni                 ( rst_ni                          ),
      .slv_req_i              ( axi_from_cluster_iwc_req [port] ),
      .slv_resp_o             ( axi_from_cluster_iwc_resp[port] ),
      .mst_req_o              ( axi_out_req_o            [port] ),
      .mst_resp_i             ( axi_out_resp_i           [port] )
    );
  end

  // Spatz cluster under test.
  cachepool_cluster #(
    .AxiAddrWidth             (AxiAddrWidth             ),
    .AxiDataWidth             (AxiDataWidth             ),
    .AxiIdWidthIn             (AxiInIdWidth             ),
    .AxiIdWidthOut            (IwcAxiIdOutWidth         ),
    .AxiUserWidth             (AxiUserWidth             ),
    .BootAddr                 (BootAddr                 ),
    .L2Addr                   (L2Addr                   ),
    .L2Size                   (L2Size                   ),
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
    .axi_out_req_t            (spatz_axi_iwc_out_req_t  ),
    .axi_out_resp_t           (spatz_axi_iwc_out_resp_t ),
    .Xdma                     (4'h1                     ),
    .DMAAxiReqFifoDepth       (3                        ),
    .DMAReqFifoDepth          (3                        ),
    .RegisterOffloadRsp       (1                        ),
    .RegisterCoreReq          (1                        ),
    .RegisterCoreRsp          (1                        ),
    .RegisterTCDMCuts         (1                        ),
    .RegisterExt              (0                        ),
    .XbarLatency              (axi_pkg::CUT_ALL_PORTS   ),
    .MaxMstTrans              (4                        ),
    .MaxSlvTrans              (4                        )
  ) i_cluster (
    .clk_i                    ,
    .rst_ni                   ,
    .eoc_o                    (eoc_o                    ),
    .impl_i                   ( '0 ),
    .error_o                  (),
    .debug_req_i              ,
    .meip_i                   ,
    .mtip_i                   ,
    .msip_i                   ,
    .hart_base_id_i           (10'h10),
    .cluster_base_addr_i      (TCDMStartAddr),
    .cluster_probe_o          ,
    .axi_in_req_i             ,
    .axi_in_resp_o            ,
    // AXI Master Port
    .axi_out_req_o            ( axi_from_cluster_iwc_req  ),
    .axi_out_resp_i           ( axi_from_cluster_iwc_resp )
  );

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

endmodule
