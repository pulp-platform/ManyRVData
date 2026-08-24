// Copyright 2025 ETH Zurich and University of Bologna.
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
  /// Tile ID width. `core_id` is only unique inside a tile, but this AMO unit
  /// sits at a cache controller and serves every tile, so the reservation owner
  /// must be identified by {tile_id, core_id} to be a hart id.
  parameter int unsigned TileIDWidth  = 1,
  /// Grace period, in cycles, that an LR reservation is held without its paired
  /// SC before it is dropped. Must exceed the worst-case LR->SC round trip of a
  /// constrained sequence, otherwise every sequence expires and no SC ever
  /// succeeds. It only bounds how long a hart that never issues its SC can
  /// block other harts; it is not a performance knob.
  parameter int unsigned ResvTimeoutCycles = 1024,
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
  logic       sc_successful;
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
    /// `core` alone is not a hart id: it is only unique within a tile, and this
    /// unit serves all tiles. Both fields together identify the owner.
    logic [CoreIDWidth-1:0]  core;
    logic [TileIDWidth-1:0]  tile;
  } reservation_t;
  reservation_t reservation_d, reservation_q;

  /// Reservation aging. Restoring the "do not steal a valid reservation" rule
  /// (below) is what removes the starvation ring, but on its own it reintroduces
  /// the hazard the rule was originally disabled for: a hart may legally execute
  /// LR and never the paired SC, and would then hold the reservation forever.
  /// The timer bounds that: a reservation that is not consumed within
  /// ResvTimeoutCycles is dropped, so blocking is bounded and some hart always
  /// makes progress.
  localparam int unsigned ResvTimerWidth = $clog2(ResvTimeoutCycles + 1);
  logic [ResvTimerWidth-1:0] resv_timer_d, resv_timer_q;
  logic                      resv_expired;

  assign resv_expired = reservation_q.valid & (resv_timer_q == '0);

  logic                   core_ready;
  /// The request handshake as the core actually sees it. `amo_req_ready` is only
  /// the memory's ready; the unit can additionally stall (FSM busy, or an SC
  /// already in flight), and the reservation/SC bookkeeping must only advance on
  /// requests that were really accepted.
  logic                   amo_req_accepted;

  tcdm_req_chan_t         amo_req;
  tcdm_rsp_chan_t         amo_rsp;
  logic                   amo_req_valid, amo_req_ready, amo_rsp_valid, amo_rsp_ready;
  amo_op_e                amo_insn;
  logic [CoreIDWidth-1:0] amo_cid;
  logic [TileIDWidth-1:0] amo_tid;
  /// True when the request comes from the hart that owns the reservation.
  logic                   amo_is_owner;


  assign amo_req_accepted = amo_req_valid & core_ready;

  assign amo_insn = amo_req.amo;
  assign amo_cid  = amo_req.user.core_id;
  assign amo_tid  = amo_req.user.tile_id;
  assign amo_is_owner = (reservation_q.core == amo_cid) &&
                        (reservation_q.tile == amo_tid);
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
  /// The SC outcome is decided here, at issue, and then travels with the
  /// transaction in `user.is_sc` / `user.sc_fail`; the memory system echoes
  /// `user` back untouched, so a response carries its own status.
  ///
  /// It used to be looked up instead, from single registers holding "the"
  /// outstanding SC. With one AMO unit shared by every core of every tile there
  /// is rarely just one: a response that did not match the tracked entry fell
  /// through with the raw memory word as its data, and because `sc.w` reads
  /// rd == 0 as success, any zero word there told a hart its store-conditional
  /// had succeeded when it never wrote. Silent lost update.
  logic           sc_rsp_valid;
  tcdm_rsp_chan_t sc_rsp;

  assign sc_rsp_valid = amo_rsp_valid & amo_rsp.user.is_sc;

  `FF(reservation_q, reservation_d, '0)
  `FF(resv_timer_q, resv_timer_d, '0)

  always_comb begin : sc_rsp_comb
    sc_rsp      = mem_rsp_i.p;
    // rd = 0 on success, 1 on failure, per the ISA.
    sc_rsp.data = {DataWidth/32{31'h0, mem_rsp_i.p.user.sc_fail}};
  end

  always_comb begin
    reservation_d = reservation_q;
    resv_timer_d  = resv_timer_q;
    sc_successful = 1'b0;

    // Age an outstanding reservation and drop it once the grace period is over.
    // This runs every cycle, not only on a transaction: the point is to bound a
    // reservation whose owner never comes back with its SC.
    if (reservation_q.valid && (resv_timer_q != '0)) begin
      resv_timer_d = resv_timer_q - 1'b1;
    end
    if (resv_expired) begin
      reservation_d.valid = 1'b0;
    end

    // new accepted transaction
    if (amo_req_accepted) begin

      // An SC can only pair with the most recent LR in program order.
      // Place a reservation only if none is currently held, if the held one has
      // expired, or if the holder is re-issuing its own LR.
      //
      // Letting an LR steal a live reservation from another hart is what broke
      // forward progress: with several harts in symmetric LR/SC retry loops on
      // words homed at this AMO unit, each LR invalidated the previous hart's
      // reservation, so every SC could fail indefinitely (RISC-V requires that
      // a constrained LR/SC sequence eventually succeeds). Keeping the incumbent
      // makes one hart win the race; the aging above keeps that bounded.
      if (amo_req.amo == AMOLR && (!reservation_q.valid || resv_expired ||
                                   amo_is_owner)) begin
        reservation_d.valid = 1'b1;
        reservation_d.addr = amo_req.addr;
        reservation_d.core = amo_cid;
        reservation_d.tile = amo_tid;
        // Reload the grace period only when the reservation is actually
        // (re)acquired. A hart that loops on LR alone must not be able to keep
        // refreshing its own reservation and lock everyone else out.
        if (!reservation_q.valid || resv_expired) begin
          resv_timer_d = ResvTimeoutCycles[ResvTimerWidth-1:0];
        end
      end

      // An SC may succeed only if no store from another hart (or other device) to
      // the reservation set can be observed to have occurred between
      // the LR and the SC, and if there is no other SC between the
      // LR and itself in program order.

      // check whether another core has made a write attempt
      if (!amo_is_owner &&
          (amo_req.addr == reservation_q.addr) &&
          (!(amo_insn inside {AMONone, AMOLR, AMOSC}) || amo_req.write)) begin
        reservation_d.valid = 1'b0;
      end

      // An SC from the same hart clears any pending reservation.
      if (reservation_q.valid && amo_insn == AMOSC && amo_is_owner) begin
        reservation_d.valid = 1'b0;
        sc_successful = reservation_q.addr == amo_req.addr;
      end
    end
  end

`ifndef TARGET_SYNTHESIS
`ifdef AMO_DEBUG
  // Trace every accepted LR/SC and every SC response match. Debug only.
  always_ff @(posedge clk_i) begin
    if (rst_ni && amo_req_accepted && (amo_insn inside {AMOLR, AMOSC})) begin
      $display("[AMOREQ] t=%0t %m insn=%0d hart={t%0d,c%0d} rid=%0d addr=%0h | resv v=%b {t%0d,c%0d} a=%0h tmr=%0d | sc_ok=%b",
               $time, amo_insn, amo_tid, amo_cid, amo_req.user.req_id, amo_req.addr,
               reservation_q.valid, reservation_q.tile, reservation_q.core,
               reservation_q.addr, resv_timer_q, sc_successful);
    end
    if (rst_ni && amo_rsp_valid && amo_rsp.user.is_sc) begin
      $display("[AMORSP] t=%0t %m SC rsp={t%0d,c%0d,r%0d} sc_fail=%b data=%0h",
               $time, amo_rsp.user.tile_id, amo_rsp.user.core_id, amo_rsp.user.req_id,
               amo_rsp.user.sc_fail, core_rsp_o.p.data);
    end
  end
`endif
`endif

  // -------
  // Atomics
  // -------
  logic [63:0] wdata;
  assign wdata = $unsigned(amo_req.data);
  logic amo_result_en;

  `FF(state_q, state_d, Idle)
  `FFL(amo_user_q, amo_user, load_amo, '0)

  `FFL(amo_op_q, amo_insn,     load_amo, AMOAdd)
  `FFL(addr_q,   amo_req.addr, load_amo, '0)
  // Which word to pick.
  `FFL(idx_q,    idx_d,        load_amo, '0)
  `FFL(operand_b_q, (amo_req.strb[0] ? wdata[31:0] : wdata[63:32]), load_amo, '0)
  `FFL(amo_result_q, amo_result, amo_result_en, '0)

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
    // Carry the SC outcome with the request so the response can be decoded on
    // its own, without any per-unit bookkeeping.
    mem_req_o.q.user.is_sc   = (amo_insn == AMOSC);
    mem_req_o.q.user.sc_fail = (amo_insn == AMOSC) & ~sc_successful;
    mem_req_o.q.write = amo_req.write | (sc_successful & (amo_insn == AMOSC));
    mem_req_o.q.amo   = AMONone;
    mem_req_o.q.data  = amo_req.data;

    amo_result_en   = 1'b0;

    state_d = state_q;

    unique case (state_q)
      // First cycle: Read operand a.
      Idle: begin
        if (load_amo) begin
          state_d = DoAMO;
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
          amo_result_en = 1'b1; // Only load amo result when we receive the data response
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
