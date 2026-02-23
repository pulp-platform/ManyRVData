// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

// The cache xbar used to select the cache banks

module tcdm_cache_interco #(
  /// Number of Tiles ('>=0')
  parameter int unsigned NumTiles             = 32'd1,
  /// Number of inputs into the interconnect (Cores per Tile) (`> 0`).
  parameter int unsigned NumCores             = 32'd0,
  /// Number of remote ports added to xbar ('>= 0').
  parameter int unsigned NumRemotePort        = 32'd0,
  /// Number of outputs from the interconnect (Cache per Tile) (`> 0`).
  parameter int unsigned NumCache             = 32'd0,
  /// Offset bits based on cacheline: 512b => 6 bits
  parameter int unsigned AddrWidth            = 32'd32,
  /// Tile ID Width, used for checking tile id ('> 0')
  parameter int unsigned TileIDWidth          = 32'd1,

  /// Port type of the data request ports.
  parameter type         tcdm_req_t           = logic,
  /// Port type of the data response ports.
  parameter type         tcdm_rsp_t           = logic,
  /// Payload type of the data request ports.
  parameter type         tcdm_req_chan_t      = logic,
  /// Payload type of the data response ports.
  parameter type         tcdm_rsp_chan_t      = logic,

  parameter snitch_pkg::topo_e Topology       = snitch_pkg::LogarithmicInterconnect,
  /// Dependency parameter, do not change
  parameter type         tile_id_t            = logic [TileIDWidth-1:0]

) (
  /// Clock, positive edge triggered.
  input  logic                                     clk_i,
  /// Reset, active low.
  input  logic                                     rst_ni,
  /// Tile ID
  input  tile_id_t                                 tile_id_i,
  /// Dynamic address offset for cache bank selection
  input  logic             [$clog2(AddrWidth)-1:0] dynamic_offset_i,
  /// Request port.
  input  tcdm_req_t   [NumCores+NumRemotePort-1:0] core_req_i,
  /// Response ready in
  input  logic        [NumCores+NumRemotePort-1:0] core_rsp_ready_i,
  /// Resposne port.
  output tcdm_rsp_t   [NumCores+NumRemotePort-1:0] core_rsp_o,
  /// Memory Side
  /// Request.
  output tcdm_req_t   [NumCache+NumRemotePort-1:0] mem_req_o,
  /// Response ready out
  output logic        [NumCache+NumRemotePort-1:0] mem_rsp_ready_o,
  /// Response.
  input  tcdm_rsp_t   [NumCache+NumRemotePort-1:0] mem_rsp_i
);

  // --------
  // Parameters and Signals
  // --------

  // One bit more for remote access
  // Selection signal width and types
  localparam int unsigned NumOutSelBits  = $clog2(NumCache + NumRemotePort);
  // The bits used to select the local Cache bank
  localparam int unsigned NumCacheSelBits  = $clog2(NumCache);
  // localparam int unsigned NumInpSelBits = $clog2(NumCores);
  localparam int unsigned NumInpSelBits = $clog2(NumCores + NumRemotePort);

  localparam int unsigned RemotePortSel  = (NumRemotePort > 0) ? NumRemotePort : 1;

  typedef logic [NumInpSelBits-1:0]  mem_sel_t;
  typedef logic [NumOutSelBits -1:0] core_sel_t;

  // core select which cache bank to go
  core_sel_t [NumCores+NumRemotePort-1 :0] core_req_sel;
  mem_sel_t  [NumCache+NumRemotePort-1 :0] mem_rsp_sel;
  // tile id bits (is the destination outside of current tile?)
  tile_id_t  [NumCores+NumRemotePort-1 :0] bank_sel;
  // Select if local or remote
  logic      [NumCores+NumRemotePort-1 :0] local_sel;

  // Number of bits used to identify the cache bank
  localparam int unsigned CacheBankBits  = $clog2(NumCache);

  tcdm_req_chan_t [NumCores+NumRemotePort-1:0] core_req;
  logic           [NumCores+NumRemotePort-1:0] core_req_valid, core_req_ready;

  tcdm_req_chan_t [NumCache+NumRemotePort-1:0] mem_req;
  logic           [NumCache+NumRemotePort-1:0] mem_req_valid, mem_req_ready;

  tcdm_rsp_chan_t [NumCores+NumRemotePort-1:0] core_rsp;
  logic           [NumCores+NumRemotePort-1:0] core_rsp_valid, core_rsp_ready;

  tcdm_rsp_chan_t [NumCache+NumRemotePort-1:0] mem_rsp;
  logic           [NumCache+NumRemotePort-1:0] mem_rsp_valid, mem_rsp_ready;


  reqrsp_xbar #(
    .NumInp           (NumCores + NumRemotePort ),
    .NumOut           (NumCache + NumRemotePort ),
    .PipeReg          (1'b0                     ),
    .ExtReqPrio       (1'b0                     ),
    .ExtRspPrio       (1'b0                     ),
    .tcdm_req_chan_t  (tcdm_req_chan_t          ),
    .tcdm_rsp_chan_t  (tcdm_rsp_chan_t          )
  ) i_cache_xbar (
    .clk_i            (clk_i                    ),
    .rst_ni           (rst_ni                   ),
    .slv_req_i        (core_req                 ),
    .slv_rr_i         ('0                       ),
    .slv_req_valid_i  (core_req_valid           ),
    .slv_req_ready_o  (core_req_ready           ),
    .slv_rsp_o        (core_rsp                 ),
    .slv_rsp_valid_o  (core_rsp_valid           ),
    .slv_rsp_ready_i  (core_rsp_ready           ),
    .slv_sel_i        (core_req_sel             ),
    .slv_selected_o   ( /* unused */            ),
    .mst_req_o        (mem_req                  ),
    .mst_rr_i         ('0                       ),
    .mst_req_valid_o  (mem_req_valid            ),
    .mst_req_ready_i  (mem_req_ready            ),
    .mst_rsp_i        (mem_rsp                  ),
    .mst_rsp_valid_i  (mem_rsp_valid            ),
    .mst_rsp_ready_o  (mem_rsp_ready            ),
    .mst_sel_i        (mem_rsp_sel              )
  );

  // --------
  // Selection Signals
  // --------

  // select the target cache bank based on the `bank` bits
  // Example: 128 KiB total, 4 way, 4 cache banks, 512b cacheline
  // => 128*1024 = 2^17 Byte => 2^(17-6) = 2^11 cachelines
  // => 2^11/4 = 2^9 sets per cache bank => 2^9/4 = 2^7 sets per way per cache bank
  // => 7 bits index; 2 bits cache bank bits;
  // addr: Tag: [31:14]; Index: [13:7]; Cache Bank: [7:6]; Offset: [5:0]
  for (genvar port = 0; port < NumCores+NumRemotePort; port++) begin : gen_req_sel
    always_comb begin
      core_req_sel[port] = '0;
      // Determine if we are targetting to a remote tile
      local_sel[port] = (NumTiles == 1) ?
                        1'b1 : (core_req[port].addr[(dynamic_offset_i+CacheBankBits)+:TileIDWidth] == tile_id_i);

      // Determine which bank is targeting at
      core_req_sel[port] = local_sel[port] ?
                           core_req[port].addr[dynamic_offset_i+:CacheBankBits] : (1'b1 << NumOutSelBits);
    end
  end

  // forward response to the sender core
  // TODO: Add remote identifier bits here
  for (genvar port = 0; port < NumCache+NumRemotePort;  port++) begin : gen_rsp_sel
    assign mem_rsp_sel[port] = mem_rsp[port].user.core_id;
  end


  // --------
  // Registers
  // --------

  for (genvar port = 0; port < NumCores+NumRemotePort; port++) begin : gen_cache_interco_reg
    spill_register #(
      .T      (tcdm_req_chan_t          )
    ) i_tcdm_req_reg (
      .clk_i  (clk_i                    ),
      .rst_ni (rst_ni                   ),
      .data_i (core_req_i[port].q       ),
      .valid_i(core_req_i[port].q_valid ),
      .ready_o(core_rsp_o[port].q_ready ),
      .data_o (core_req[port]           ),
      .valid_o(core_req_valid[port]     ),
      .ready_i(core_req_ready[port]     )
    );

    fall_through_register #(
      .T         (tcdm_rsp_chan_t           )
    ) i_tcdm_rsp_reg (
      .clk_i     (clk_i                     ),
      .rst_ni    (rst_ni                    ),
      .clr_i     (1'b0                      ),
      .testmode_i(1'b0                      ),
      .data_i    (core_rsp[port]            ),
      .valid_i   (core_rsp_valid[port]      ),
      .ready_o   (core_rsp_ready[port]      ),
      .data_o    (core_rsp_o[port].p        ),
      .valid_o   (core_rsp_o[port].p_valid  ),
      .ready_i   (core_rsp_ready_i[port]    )
    );
  end


  // --------
  // IO Assignment
  // --------

  // TODO: Correctly handle the multi-tile case
  // Plan: We should only do the scrambling at the destination

  // We will also take away the offset bits we used from the full address for scrambling

  logic [AddrWidth-1:0] bitmask_up, bitmask_lo;
  // These are the address we will keep from original
  assign bitmask_lo = (1 << dynamic_offset_i) - 1;
  // We will keep AddrWidth - Offset - log2(CacheBanks) bits in the upper half, and remove the NumOutSelBits bits
  assign bitmask_up = ((1 << (AddrWidth - dynamic_offset_i - $clog2(NumCache))) - 1) << dynamic_offset_i;


  for (genvar port = 0; port < NumCache + NumRemotePort; port++) begin : gen_cache_io
    always_comb begin
      mem_req_o[port] = '{
        q:        mem_req[port],
        q_valid:  mem_req_valid[port],
        default:  '0
      };

      // remove the middle bits
      mem_req_o[port].q.addr = (mem_req[port].addr & bitmask_lo) |
                              ((mem_req[port].addr >> $clog2(NumCache)) & bitmask_up);

    end

    assign mem_rsp[port]          = mem_rsp_i[port].p;
    assign mem_rsp_valid[port]    = mem_rsp_i[port].p_valid;
    assign mem_req_ready[port]    = mem_rsp_i[port].q_ready;
  end

  assign mem_rsp_ready_o  = mem_rsp_ready;

`ifndef TARGET_SYNTHESIS
  // Debug scoreboard: track outstanding requests per (output-bank, input-core)
  // and validate that each response targets a core with outstanding traffic.
  int unsigned outstanding_q [NumCache+NumRemotePort-1:0][NumCores+NumRemotePort-1:0];
  int signed   delta_d       [NumCache+NumRemotePort-1:0][NumCores+NumRemotePort-1:0];
  int unsigned outstanding_n [NumCache+NumRemotePort-1:0][NumCores+NumRemotePort-1:0];
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int o = 0; o < NumCache + NumRemotePort; o++) begin
        for (int c = 0; c < NumCores + NumRemotePort; c++) begin
          outstanding_q[o][c] <= '0;
        end
      end
    end else begin
      // Start from previous occupancy.
      for (int o = 0; o < NumCache + NumRemotePort; o++) begin
        for (int c = 0; c < NumCores + NumRemotePort; c++) begin
          delta_d[o][c] = 0;
        end
      end

      // Account accepted requests (+1).
      for (int c = 0; c < NumCores + NumRemotePort; c++) begin
        if (core_req_valid[c] && core_req_ready[c]) begin
          delta_d[core_req_sel[c]][c] = delta_d[core_req_sel[c]][c] + 1;
        end
      end

      // Account accepted responses (-1), allowing same-cycle req/rsp for same
      // (output, core) pair without false mismatch reports.
      for (int o = 0; o < NumCache + NumRemotePort; o++) begin
        if (mem_rsp_valid[o] && mem_rsp_ready[o]) begin
          if (mem_rsp_sel[o] >= (NumCores + NumRemotePort)) begin
            $error("[tcdm_cache_interco] Invalid mem_rsp_sel=%0d on output %0d",
                   mem_rsp_sel[o], o);
          end else if ((outstanding_q[o][mem_rsp_sel[o]] + delta_d[o][mem_rsp_sel[o]]) == 0) begin
            $error("[tcdm_cache_interco] Response without outstanding req on output %0d -> core %0d",
                   o, mem_rsp_sel[o]);
          end else begin
            delta_d[o][mem_rsp_sel[o]] = delta_d[o][mem_rsp_sel[o]] - 1;
          end
        end
      end

      // Commit updated outstanding counters.
      for (int o = 0; o < NumCache + NumRemotePort; o++) begin
        for (int c = 0; c < NumCores + NumRemotePort; c++) begin
          outstanding_n[o][c] = outstanding_q[o][c] + delta_d[o][c];
          if (outstanding_n[o][c][31]) begin
            // Should never go negative.
            $error("[tcdm_cache_interco] Outstanding underflow on output %0d core %0d", o, c);
            outstanding_q[o][c] <= '0;
          end else begin
            outstanding_q[o][c] <= outstanding_n[o][c];
          end
        end
      end
    end
  end
`endif


endmodule
