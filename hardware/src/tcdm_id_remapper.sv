// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Description: Merges N parallel TCDM requests into a single flow.
//
// Author: Diyou Shen         <dishen@iis.ee.ethz.ch>
// Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

`include "common_cells/registers.svh"
`include "reqrsp_interface/typedef.svh"

module tcdm_id_remapper
  #(
    parameter int unsigned NumIn    = 1,
    parameter int unsigned IdWidth  = 1,
    parameter int unsigned RobDepth = 1,

    /// Address width of the interface.
    parameter int unsigned               AddrWidth    = 0,
    /// Data width of the interface.
    parameter int unsigned               DataWidth    = 0,

    parameter type         dreq_t  = logic,
    parameter type         user_t  = logic,
    parameter type         drsp_t  = logic
  ) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    // Master side
    input  dreq_t            [NumIn-1:0] slv_req_i,
    output drsp_t            [NumIn-1:0] slv_rsp_o,
    // Slave side
    output dreq_t                        mst_req_o,
    input  drsp_t                        mst_rsp_i
  );

  typedef logic [AddrWidth-1:0] addr_t;
  typedef logic [DataWidth-1:0] data_t;
  typedef logic [DataWidth/8-1:0] strb_t;

  `REQRSP_TYPEDEF_REQ_CHAN_T(dreq_chan_t, addr_t, data_t, strb_t, user_t)
  `REQRSP_TYPEDEF_RSP_CHAN_T(drsp_chan_t, data_t, user_t)

  dreq_chan_t [NumIn-1:0] req_qpayload;
  drsp_chan_t [NumIn-1:0] rsp_ppayload;
  logic       [NumIn-1:0] req_qvalid, req_qready;
  logic       [NumIn-1:0] rsp_pvalid, rsp_pready;


  for (genvar port = 0; port < NumIn; port ++) begin
    // Unpack the inputs for easier assignment
    assign req_qpayload[port]      = slv_req_i[port].q;
    assign req_qvalid[port]        = slv_req_i[port].q_valid;
    assign slv_rsp_o[port].q_ready = req_qready[port];

    assign slv_rsp_o[port].p       = rsp_ppayload[port];
    assign slv_rsp_o[port].p_valid = rsp_pvalid[port];
    assign rsp_pready[port]        = slv_req_i[port].p_ready;
  end 



  if (NumIn == 1) begin: gen_single_port
    assign mst_req_o.q       = req_qpayload;
    assign mst_req_o.q_valid = req_qvalid;
    assign mst_req_o.p_ready = rsp_pready;


    assign rsp_ppayload      = mst_rsp_i.p;
    assign rsp_pvalid        = mst_rsp_i.p_valid;
    assign req_qready        = mst_rsp_i.q_ready;

  end: gen_single_port else begin: gen_remapper
    dreq_chan_t req;
    logic       req_valid;
    logic       req_ready;

    // ROB transaction ID type and signal
    typedef logic [IdWidth-1:0] meta_id_t;
    meta_id_t   next_id;
    logic       no_free_id;

    // Lock the output id if the request has not been taken yet
    logic       id_lock_d, id_lock_q;

    // Port ID type and signal
    typedef logic [cf_math_pkg::idx_width(NumIn)-1:0] id_t;
    id_t id;

    meta_id_t [RobDepth-1:0] remapped_id_q,       remapped_id_d;
    logic     [RobDepth-1:0] remapped_id_valid_q, remapped_id_valid_d;
    id_t      [RobDepth-1:0] id_q, id_d;

    `FF(remapped_id_q, remapped_id_d, '0)
    `FF(remapped_id_valid_q, remapped_id_valid_d, '0)
    `FF(id_q, id_d, '0)
    `FF(id_lock_q, id_lock_d, '0)

    lzc #(
      .WIDTH(RobDepth)
    ) i_next_id_lzc (
      .in_i   (~remapped_id_valid_q),
      .cnt_o  (next_id             ),
      .empty_o(no_free_id          )
    );

    always_comb begin
      // Maintain state
      remapped_id_d       = remapped_id_q;
      remapped_id_valid_d = remapped_id_valid_q;
      id_d                = id_q;
      id_lock_d           = id_lock_q;

      if (mst_req_o.q_valid && !mst_rsp_i.q_ready) begin
        // valid but not ready, we need to keep the id unchanged
        id_lock_d         = 1'b1;
      end

      // Did we get a new request?
      if (mst_req_o.q_valid && mst_rsp_i.q_ready) begin
        if (id_lock_q) begin
          // the outstanding ID is already stored in req
          remapped_id_d[req.user.req_id]        = req.user.req_id;
          remapped_id_valid_d[req.user.req_id]  = 1'b1;
          id_d[req.user.req_id]                 = id;
          id_lock_d                    = 1'b0;
        end else begin
          remapped_id_d[next_id]       = req.user.req_id;
          remapped_id_valid_d[next_id] = 1'b1;
          id_d[next_id]                = id;
        end
      end

      // Did we sent a new response?
      if (mst_rsp_i.p_valid && mst_req_o.p_ready)
        remapped_id_valid_d[mst_rsp_i.p.user.req_id] = 1'b0;
    end

    ///////////////
    //  Request  //
    ///////////////

    rr_arb_tree #(
      .NumIn     (NumIn   ),
      .DataType  (dreq_chan_t  ),
      .AxiVldRdy (1'b1    ),
      .LockIn    (1'b1    )
    ) i_arbiter (
      .clk_i  (clk_i        ),
      .rst_ni (rst_ni       ),
      .flush_i(1'b0         ),
      .rr_i   ('0           ),
      .req_i  (req_qvalid   ),
      .gnt_o  (req_qready   ),
      .data_i (req_qpayload ),
      .gnt_i  (req_ready    ),
      .req_o  (req_valid    ),
      .data_o (req          ),
      .idx_o  (id           )
    );

    always_comb begin
      // Ready if upstream is ready and we have a free id
      mst_req_o.q_valid = req_valid && !no_free_id;
      req_ready         = mst_rsp_i.q_ready && !no_free_id;

      // Forward the request payload
      mst_req_o.q    = req;
      if (!id_lock_q)
        mst_req_o.q.user.req_id = next_id;
    end

    ////////////////
    //  Response  //
    ////////////////

    stream_demux #(
      .N_OUP(NumIn)
    ) i_response_demux (
      .inp_valid_i(mst_rsp_i.p_valid    ),
      .inp_ready_o(mst_req_o.p_ready    ),
      .oup_sel_i  (id_q[mst_rsp_i.p.user.req_id] ),
      .oup_ready_i(rsp_pready           ),
      .oup_valid_o(rsp_pvalid           )
    );

    always_comb begin
      for (int port = 0; port < NumIn; port++) begin
        // Pass the payload
        rsp_ppayload[port]    = mst_rsp_i.p;
        rsp_ppayload[port].user.req_id = remapped_id_q[mst_rsp_i.p.user.req_id];
      end
    end
  end: gen_remapper

endmodule: tcdm_id_remapper
