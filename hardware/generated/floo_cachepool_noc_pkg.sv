// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// AUTOMATICALLY GENERATED! DO NOT EDIT!

`include "axi/typedef.svh"
`include "floo_noc/typedef.svh"

package floo_cachepool_noc_pkg;

  import floo_pkg::*;

  /////////////////////
  //   Address Map   //
  /////////////////////

  typedef enum logic[3:0] {
    GroupX0Y0 = 0,
    GroupX0Y1 = 1,
    GroupX1Y0 = 2,
    GroupX1Y1 = 3,
    Hbm0 = 4,
    Hbm1 = 5,
    Hbm2 = 6,
    Hbm3 = 7,
    NumEndpoints = 8} ep_id_e;



  typedef enum logic[2:0] {
    Hbm0SamIdx = 2,
    Hbm1SamIdx = 3,
    Hbm2SamIdx = 4,
    Hbm3SamIdx = 5} sam_idx_e;



  typedef logic[0:0] rob_idx_t;
typedef logic[0:0] port_id_t;
typedef logic[2:0] id_t;
typedef logic[8:0] route_t;


  typedef struct packed {
    id_t idx;
    id_t start_addr;
    id_t end_addr;
  } route_map_rule_t;

  localparam int unsigned SamNumRules = 6;

typedef struct packed {
    id_t idx;
    logic [31:0] start_addr;
    logic [31:0] end_addr;
} sam_rule_t;

localparam sam_rule_t[SamNumRules-1:0] Sam = '{
'{    idx: 7,
    start_addr: 32'hb0000000,
    end_addr: 32'hbfffffff},// Hbm3
'{    idx: 6,
    start_addr: 32'ha0000000,
    end_addr: 32'hafffffff},// Hbm2
'{    idx: 5,
    start_addr: 32'h90000000,
    end_addr: 32'h9fffffff},// Hbm1
'{    idx: 4,
    start_addr: 32'h00000000,
    end_addr: 32'h7fffffff},// Hbm0
'{    idx: 4,
    start_addr: 32'h80000000,
    end_addr: 32'h8fffffff},// Hbm0
'{    idx: 4,
    start_addr: 32'hc0000000,
    end_addr: 32'hffffffff} // Hbm0

};


  localparam route_t[NumEndpoints-1:0][NumEndpoints-1:0] RoutingTables = '{
'{
9'b000000000,// -> hbm3_ni
9'b000000000,// -> hbm2_ni
9'b000000000,// -> hbm1_ni
9'b000000000,// -> hbm0_ni
9'b000000100,// -> group_ni_1_1
9'b000100010,// -> group_ni_1_0
9'b000100011,// -> group_ni_0_1
9'b100010011 // -> group_ni_0_0
},
'{
9'b000000000,// -> hbm3_ni
9'b000000000,// -> hbm2_ni
9'b000000000,// -> hbm1_ni
9'b000000000,// -> hbm0_ni
9'b000100000,// -> group_ni_1_1
9'b000000100,// -> group_ni_1_0
9'b100000011,// -> group_ni_0_1
9'b000100011 // -> group_ni_0_0
},
'{
9'b000000000,// -> hbm3_ni
9'b000000000,// -> hbm2_ni
9'b000000000,// -> hbm1_ni
9'b000000000,// -> hbm0_ni
9'b000100001,// -> group_ni_1_1
9'b100001010,// -> group_ni_1_0
9'b000000100,// -> group_ni_0_1
9'b000100010 // -> group_ni_0_0
},
'{
9'b000000000,// -> hbm3_ni
9'b000000000,// -> hbm2_ni
9'b000000000,// -> hbm1_ni
9'b000000000,// -> hbm0_ni
9'b100001000,// -> group_ni_1_1
9'b000100001,// -> group_ni_1_0
9'b000100000,// -> group_ni_0_1
9'b000000100 // -> group_ni_0_0
},
'{
9'b000000001,// -> hbm3_ni
9'b000001010,// -> hbm2_ni
9'b000011011,// -> hbm1_ni
9'b011010011,// -> hbm0_ni
9'b000000000,// -> group_ni_1_1
9'b000000000,// -> group_ni_1_0
9'b000000000,// -> group_ni_0_1
9'b000000000 // -> group_ni_0_0
},
'{
9'b000001000,// -> hbm3_ni
9'b000000001,// -> hbm2_ni
9'b011000011,// -> hbm1_ni
9'b000011011,// -> hbm0_ni
9'b000000000,// -> group_ni_1_1
9'b000000000,// -> group_ni_1_0
9'b000000000,// -> group_ni_0_1
9'b000000000 // -> group_ni_0_0
},
'{
9'b000001001,// -> hbm3_ni
9'b001001010,// -> hbm2_ni
9'b000000011,// -> hbm1_ni
9'b000011010,// -> hbm0_ni
9'b000000000,// -> group_ni_1_1
9'b000000000,// -> group_ni_1_0
9'b000000000,// -> group_ni_0_1
9'b000000000 // -> group_ni_0_0
},
'{
9'b001001000,// -> hbm3_ni
9'b000001001,// -> hbm2_ni
9'b000011000,// -> hbm1_ni
9'b000000011,// -> hbm0_ni
9'b000000000,// -> group_ni_1_1
9'b000000000,// -> group_ni_1_0
9'b000000000,// -> group_ni_0_1
9'b000000000 // -> group_ni_0_0
}}
;


  localparam route_cfg_t RouteCfg = '{    RouteAlgo: SourceRouting,
    UseIdTable: 1'b1,
    XYAddrOffsetX: 0,
    XYAddrOffsetY: 0,
    IdAddrOffset: 0,
    NumSamRules: 6,
    NumRoutes: 8,
    CollectiveCfg: '{    OpCfg: '{    EnNarrowMulticast: 1'b0,
    EnWideMulticast: 1'b0,
    EnLsbAnd: 1'b0,
    EnFpAdd: 1'b0,
    EnFpMul: 1'b0,
    EnFpMin: 1'b0,
    EnFpMax: 1'b0,
    EnIntAdd: 1'b0,
    EnIntMul: 1'b0,
    EnIntMinS: 1'b0,
    EnIntMinU: 1'b0,
    EnIntMaxS: 1'b0,
    EnIntMaxU: 1'b0},
    NarrRedCfg: RedDefaultCfg,
    WideRedCfg: RedDefaultCfg}};

  

    typedef logic[31:0] axi_wide_in_addr_t;
typedef logic[511:0] axi_wide_in_data_t;
typedef logic[63:0] axi_wide_in_strb_t;
typedef logic[6:0] axi_wide_in_id_t;
typedef logic[20:0] axi_wide_in_user_t;
`AXI_TYPEDEF_ALL_CT(axi_wide_in,             axi_wide_in_req_t,             axi_wide_in_rsp_t,             axi_wide_in_addr_t,             axi_wide_in_id_t,             axi_wide_in_data_t,             axi_wide_in_strb_t,             axi_wide_in_user_t)


    typedef logic[31:0] axi_wide_out_addr_t;
typedef logic[511:0] axi_wide_out_data_t;
typedef logic[63:0] axi_wide_out_strb_t;
typedef logic[5:0] axi_wide_out_id_t;
typedef logic[20:0] axi_wide_out_user_t;
`AXI_TYPEDEF_ALL_CT(axi_wide_out,             axi_wide_out_req_t,             axi_wide_out_rsp_t,             axi_wide_out_addr_t,             axi_wide_out_id_t,             axi_wide_out_data_t,             axi_wide_out_strb_t,             axi_wide_out_user_t)



  `FLOO_TYPEDEF_HDR_T(hdr_t, route_t, id_t, axi_ch_e, rob_idx_t)
  localparam axi_cfg_t AxiCfg = '{    AddrWidth: 32,
    DataWidth: 512,
    InIdWidth: 7,
    OutIdWidth: 6,
    UserWidth: 21};
`FLOO_TYPEDEF_AXI_CHAN_ALL(axi, req, rsp, axi_wide_in, AxiCfg, hdr_t)

`FLOO_TYPEDEF_AXI_LINK_ALL(req, rsp, req, rsp)


endpackage
