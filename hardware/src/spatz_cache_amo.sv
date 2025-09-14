// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Author: Diyou Shen <dishen@iis.ee.ethz.ch>
// Author: Zexin Fu <zexifu@iis.ee.ethz.ch>
`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

/// Shim in front of SRAMs which translates atomic (and normal)
/// memory operations to RMW sequences. The requests are atomic except
/// for the DMA which can request priority. The current model is
/// that the DMA will never write to the same memory location.
/// We provide `amo_conflict_o` to detect such event and
/// indicate a fault to the programmer.

/// LR/SC reservations are happening on `DataWidth` granularity.
module spatz_cache_amo
  import snitch_pkg::*;
  import reqrsp_pkg::*;
#(
  /// Address width.
  parameter int unsigned AddrMemWidth = 32,
  /// Word width.
  parameter int unsigned DataWidth    = 64,
  /// Core ID type.
  parameter int unsigned CoreIDWidth  = 1,
  /// Port type of the data request ports.
  parameter type         tcdm_req_t           = logic,
  /// Port type of the data response ports.
  parameter type         tcdm_rsp_t           = logic,
  /// Payload type of the data request ports.
  parameter type         tcdm_req_chan_t      = logic,
  /// Payload type of the data response ports.
  parameter type         tcdm_rsp_chan_t      = logic,

  parameter type         tcdm_user_t          = logic,
  /// Do not override. Derived parameter.
  parameter int unsigned StrbWidth    = DataWidth/8
) (
  input   logic          clk_i,
  input   logic          rst_ni,

  input  tcdm_req_t      core_req_i,
  /// Response ready in
  input  logic           core_rsp_ready_i,
  /// Resposne port.
  output tcdm_rsp_t      core_rsp_o,
  /// Memory Side
  /// Request.
  output tcdm_req_t      mem_req_o,
  /// Response ready out
  output logic           mem_rsp_ready_o,
  /// Response.
  input  tcdm_rsp_t      mem_rsp_i
);

  logic                     idx_q, idx_d;
  logic [31:0]              operand_a, operand_b_q, amo_result, amo_result_q;
  logic [AddrMemWidth-1:0]  addr_q;
  amo_op_e    amo_op_q;
  logic       load_amo;
  logic       sc_successful, sc_successful_q;
  tcdm_user_t amo_user, amo_user_q;

  typedef enum logic [1:0] {
    Idle, Wait, DoAMO, WriteBackAMO
  } state_e;
  state_e state_q, state_d;

  typedef struct packed {
    /// Is the reservation valid.
    logic valid;
    /// On which address is the reservation placed.
    /// This address is aligned to the memory size
    /// implying that the reservation happen on a set size
    /// equal to the word width of the memory (32 or 64 bit).
    logic [AddrMemWidth-1:0] addr;
    /// Which core made this reservation. Important to
    /// track the reservations from different cores and
    /// to prevent any live-locking.
    logic [CoreIDWidth-1:0]  core;
  } reservation_t;
  reservation_t reservation_d, reservation_q;

  logic                   core_ready;

  tcdm_req_chan_t         amo_req;
  tcdm_rsp_chan_t         amo_rsp;
  logic                   amo_req_valid, amo_req_ready, amo_rsp_valid, amo_rsp_ready;
  amo_op_e                amo_insn;
  logic [CoreIDWidth-1:0] amo_cid;


  assign amo_insn = amo_req.amo;
  assign amo_cid  = amo_req.user.core_id;
  assign amo_user = amo_req.user;

  always_comb begin : amo_req_comb
    // By default pass through
    amo_req       = core_req_i.q;
    // Data swap
    amo_req.data  = core_req_i.q.data;
    // HandShaking
    amo_req_valid = core_req_i.q_valid;
    amo_req_ready = mem_rsp_i.q_ready;

    amo_rsp       = mem_rsp_i.p;
    amo_rsp_valid = mem_rsp_i.p_valid;
    amo_rsp_ready = core_rsp_ready_i;
  end


  // -----
  // LR/SC
  // -----
  logic           sc_req_valid, sc_req_ready;
  logic           sc_rsp_valid;
  logic           sc_q, sc_d;
  logic           sc_set, sc_clr, sc_en;
  tcdm_user_t     sc_user_d, sc_user_q;
  tcdm_rsp_chan_t sc_rsp;

  assign  sc_req_valid = core_req_i.q_valid & (core_req_i.q.amo inside {AMOSC});
  assign  sc_req_ready = mem_rsp_i.q_ready;
  assign  sc_rsp_valid = sc_clr & sc_q;

  assign sc_user_d  = core_req_i.q.user;
  assign sc_en      = sc_set | sc_clr;
  assign sc_set     = amo_req_valid & amo_req_ready & (amo_insn == AMOSC);
  assign sc_clr     = amo_rsp_valid & amo_rsp_ready & sc_q &
                      (sc_user_q.core_id == amo_rsp.user.core_id) &
                      (sc_user_q.req_id  == amo_rsp.user.req_id);
  assign sc_d       = sc_set & ~sc_clr;

  `FFL(sc_successful_q, sc_successful, sc_set, 1'b0)
  `FFL(sc_q, sc_d, sc_en, 1'b0)
  `FFL(sc_user_q, sc_user_d, sc_set, '0)
  `FF(reservation_q, reservation_d, '0)

  always_comb begin : sc_rsp_comb
    sc_rsp = mem_rsp_i.p;
    sc_rsp.data = sc_q ? {DataWidth/32{31'h0,~sc_successful_q}} : mem_rsp_i.p.data;
  end

  always_comb begin
    reservation_d = reservation_q;
    sc_successful = 1'b0;
    // new valid transaction
    if (amo_req_valid & amo_req_ready) begin

      // An SC can only pair with the most recent LR in program order.
      // Place a reservation on the address if there isn't already a valid reservation.
      // We prevent a live-lock by don't throwing away the reservation of a hart unless
      // it makes a new reservation in program order or issues any SC.
      if (amo_req.amo == AMOLR && (!reservation_q.valid || reservation_q.core == amo_cid)) begin
        reservation_d.valid = 1'b1;
        reservation_d.addr = amo_req.addr;
        reservation_d.core = amo_cid;
      end

      // An SC may succeed only if no store from another hart (or other device) to
      // the reservation set can be observed to have occurred between
      // the LR and the SC, and if there is no other SC between the
      // LR and itself in program order.

      // check whether another core has made a write attempt
      if ((amo_cid != reservation_q.core) &&
          (amo_req.addr == reservation_q.addr) &&
          (!(amo_insn inside {AMONone, AMOLR, AMOSC}) || amo_req.write)) begin
        reservation_d.valid = 1'b0;
      end

      // An SC from the same hart clears any pending reservation.
      if (reservation_q.valid && amo_insn == AMOSC && reservation_q.core == amo_cid) begin
        reservation_d.valid = 1'b0;
        sc_successful = reservation_q.addr == amo_req.addr;
      end
    end
  end

  // -------
  // Atomics
  // -------
  logic [63:0] wdata;
  assign wdata = $unsigned(amo_req.data);
  logic amo_result_en_d, amo_result_en_q;

  `FF(state_q, state_d, Idle)
  `FFL(amo_user_q, amo_user, load_amo, '0)

  `FFL(amo_op_q, amo_insn,     load_amo, AMOAdd)
  `FFL(addr_q,   amo_req.addr, load_amo, '0)
  // Which word to pick.
  `FFL(idx_q,    idx_d,        load_amo, '0)
  `FFL(operand_b_q, (amo_req.strb[0] ? wdata[31:0] : wdata[63:32]), load_amo, '0)
  `FFL(amo_result_q, amo_result, amo_result_en_q, '0)
  `FF(amo_result_en_q, amo_result_en_d, '0)

  assign idx_d     = ((DataWidth == 64) ? amo_req.strb[DataWidth/8/2] : 0);
  assign load_amo  = amo_req_valid & amo_req_ready & core_ready &
          ~(amo_insn inside {AMONone, AMOLR, AMOSC});
  assign operand_a = amo_rsp.data[32*idx_q+:32];

  // Need to be adjusted here. we are in a cache system, and do not have a well-defined visiting latency
  always_comb begin
    // pass-through by default
    mem_req_o.q       = amo_req;
    mem_req_o.q_valid = amo_req_valid;
    core_ready        = amo_req_ready;
    mem_req_o.q.write = amo_req.write | (sc_successful & (amo_insn == AMOSC));
    mem_req_o.q.amo   = AMONone;
    mem_req_o.q.data  = amo_req.data;

    amo_result_en_d = 1'b0;

    state_d = state_q;

    unique case (state_q)
      // First cycle: Read operand a.
      Idle: begin
        if (load_amo) begin
          state_d = DoAMO;
          // Load result only in the first cycle entering DoAMO state
          amo_result_en_d = 1'b1;
        end
      end
      DoAMO: begin
        mem_req_o.q_valid = 1'b0;
        core_ready        = 1'b0;
        if (amo_rsp_valid &&
             // In case a response of a previous sc from other request trigger this transition
            (amo_user_q.core_id == amo_rsp.user.core_id) &&
            (amo_user_q.req_id == amo_rsp.user.req_id)
            ) begin
          state_d = WriteBackAMO;
        end
      end
      // Third cycle: Try to write-back result.
      WriteBackAMO: begin
        mem_req_o.q_valid = 1'b1;
        core_ready        = 1'b0;
        mem_req_o.q.write = 1'b1;
        mem_req_o.q.addr  = addr_q;
        mem_req_o.q.strb  = 'b1111 << (idx_q*4);
        mem_req_o.q.data  = amo_result_q << (idx_q*32);
        mem_req_o.q.user  = amo_user_q;
        // Indicate that we are doing an AMO write-back
        // Used to filter out the response
        mem_req_o.q.user.is_amo = 1'b1;

        if (mem_rsp_i.q_ready) begin
        // if (amo_rsp_valid && mem_rsp_i.p.user.is_amo) begin
          // Can we exit AMO immediately after write accepted?
          // Should we wait until the write is successful?
          state_d = Wait;
        end
      end
      Wait: begin
        // Wait until the write is complete
        mem_req_o = '0;
        core_ready = 1'b0;
        if (amo_rsp_valid && mem_rsp_i.p.user.is_amo) begin
          // Can we exit AMO immediately after write accepted?
          // Should we wait until the write is successful?
          state_d = Idle;
        end
      end
      default:;
    endcase
  end

  amo_alu i_amo_alu (
    .amo_op_i    (amo_op_q   ),
    .operand_a_i (operand_a  ),
    .operand_b_i (operand_b_q),
    .result_o    (amo_result )
  );

  // ----------
  // Resp to core
  // ----------
  always_comb begin : output_req_comb
    core_rsp_o.p       = sc_rsp_valid ? sc_rsp : amo_rsp;
    core_rsp_o.p_valid = amo_rsp_valid;
    core_rsp_o.q_ready = core_ready;
    mem_rsp_ready_o    = amo_rsp_ready;

    if (amo_rsp_valid && mem_rsp_i.p.user.is_amo) begin
      // Means we receive a response message generated by AMO, should not forward to core
      core_rsp_o.p       = '0;
      core_rsp_o.p_valid = 1'b0;
      mem_rsp_ready_o    = 1'b1;
    end
  end

  // ----------
  // Assertions
  // ----------
  // Check that data width is legal (a power of two and at least 32 bit).
  `ASSERT_INIT(DataWidthCheck,
    DataWidth >= 32 &&  DataWidth <= 64 && 2**$clog2(DataWidth) == DataWidth)
  // Make sure that write is never set for AMOs.
  `ASSERT(AMOWriteEnable,  amo_req_valid && !amo_insn inside {AMONone} |-> !amo_req.write)
  // Byte enable mask is correct
  `ASSERT(ByteMaskCorrect, amo_req_valid && !amo_insn inside {AMONone} |-> amo_req.strb[4*idx_d+:4] == '1)

endmodule

/// Simple ALU supporting atomic memory operations.
module amo_alu import reqrsp_pkg::*; (
  input  amo_op_e amo_op_i,
  input  logic [31:0]         operand_a_i,
  input  logic [31:0]         operand_b_i,
  output logic [31:0]         result_o
);
  // ----------------
  // AMO ALU
  // ----------------
  logic [33:0] adder_sum;
  logic [32:0] adder_operand_a, adder_operand_b;

  assign adder_sum = adder_operand_a + adder_operand_b;
  /* verilator lint_off WIDTH */
  always_comb begin : amo_alu

    adder_operand_a = $signed(operand_a_i);
    adder_operand_b = $signed(operand_b_i);

    result_o = operand_b_i;

    unique case (amo_op_i)
      // the default is to output operand_b
      AMOSwap:;
      AMOAdd: result_o = adder_sum[31:0];
      AMOAnd: result_o = operand_a_i & operand_b_i;
      AMOOr:  result_o = operand_a_i | operand_b_i;
      AMOXor: result_o = operand_a_i ^ operand_b_i;
      AMOMax: begin
        adder_operand_b = -$signed(operand_b_i);
        result_o = adder_sum[32] ? operand_b_i : operand_a_i;
      end
      AMOMin: begin
        adder_operand_b = -$signed(operand_b_i);
        result_o = adder_sum[32] ? operand_a_i : operand_b_i;
      end
      AMOMaxu: begin
        adder_operand_a = $unsigned(operand_a_i);
        adder_operand_b = -$unsigned(operand_b_i);
        result_o = adder_sum[32] ? operand_b_i : operand_a_i;
      end
      AMOMinu: begin
        adder_operand_a = $unsigned(operand_a_i);
        adder_operand_b = -$unsigned(operand_b_i);
        result_o = adder_sum[32] ? operand_a_i : operand_b_i;
      end
      default: result_o = '0;
    endcase
  end
endmodule
