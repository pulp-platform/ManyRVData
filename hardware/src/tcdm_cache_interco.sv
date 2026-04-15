// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

// The cache xbar used to select the cache banks.
//
// Supports cache partitioning modes, selected at runtime via
// num_private_cache_i (registered one cycle):
//
//   Mode          | num_private_cache_q | Private banks       | Shared banks
//   --------------|---------------------|---------------------|-------------------
//   All-shared    |          0          | none                | [0..N-1]
//   1-priv 3-shr  |          1          | [0]                 | [1..N-1]
//   Half-half     |         N/2         | [0..N/2-1]          | [N/2..N-1]
//   3-priv 1-shr  |         N-1         | [0..N-2]            | [N-1]
//   All-private   |          N          | [0..N-1]            | none
//
// Bank selection uses modulo folding so that any partition size is supported:
//   private_bank = addr_bank_bits % num_private_cache_q
//   shared_bank  = num_private_cache_q + (addr_bank_bits % num_shared_cache_q)
// For non-power-of-2 partition sizes this causes uneven bank utilisation.

`include "common_cells/registers.svh"

module tcdm_cache_interco #(
  /// Number of Tiles ('>= 1')
  parameter int unsigned NumTiles             = 32'd1,
  /// Number of inputs into the interconnect (Cores per Tile) (`> 0`).
  parameter int unsigned NumCores             = 32'd0,
  /// Number of remote ports added to xbar ('>= 0').
  parameter int unsigned NumRemotePort        = 32'd0,
  /// Number of outputs from the interconnect (Cache banks per Tile) (`> 0`).
  parameter int unsigned NumCache             = 32'd0,
  /// Number of total cache banks across all tiles (used for address scramble).
  parameter int unsigned NumTotCache          = 32'd0,
  /// Address width in bits (cacheline offset: 512b => 6 bits).
  parameter int unsigned AddrWidth            = 32'd32,
  /// Tile ID width ('> 0').
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
  /// Dependency parameters – do not override.
  parameter type         tile_id_t            = logic [TileIDWidth-1:0],
  parameter type         addr_t               = logic [AddrWidth-1:0]

) (
  /// Clock, positive edge triggered.
  input  logic                                     clk_i,
  /// Reset, active low.
  input  logic                                     rst_ni,
  /// This tile's ID.
  input  tile_id_t                                 tile_id_i,
  /// Configurations-----------------------------------------------------
  /// Dynamic address offset for cache bank selection (= log2 of cacheline size).
  input  logic             [$clog2(AddrWidth)-1:0] dynamic_offset_i,
  /// Number of private cache banks for this tile. Must be 0, NumCache/2, or NumCache.
  input  logic                [$clog2(NumCache):0] num_private_cache_i,
  /// Partitioning address
  input  addr_t                                    private_start_addr_i,
  /// Request port (cores + remote-in) ----------------------------------
  input  tcdm_req_t   [NumCores+NumRemotePort-1:0] core_req_i,
  /// Response ready in.
  input  logic        [NumCores+NumRemotePort-1:0] core_rsp_ready_i,
  /// Response port (cores + remote-in).
  output tcdm_rsp_t   [NumCores+NumRemotePort-1:0] core_rsp_o,
  /// Memory side -------------------------------------------------------
  /// Which remote tile is targeted (one entry per remote output port).
  output tile_id_t             [NumRemotePort-1:0] tile_sel_o,
  // output logic                                     remote_group_o,
  /// Requests to cache banks and remote output ports.
  output tcdm_req_t   [NumCache+NumRemotePort-1:0] mem_req_o,
  /// Response ready out.
  output logic        [NumCache+NumRemotePort-1:0] mem_rsp_ready_o,
  /// Responses from cache banks and remote output ports.
  input  tcdm_rsp_t   [NumCache+NumRemotePort-1:0] mem_rsp_i
);

  // -------------------------------------------------------------------------
  // Local parameters
  // -------------------------------------------------------------------------

  // Bits to index into xbar outputs (local banks + one remote slot).
  localparam int unsigned NumOutSelBits  = $clog2(NumCache + NumRemotePort);
  // Bits to index into xbar inputs.
  localparam int unsigned NumInpSelBits  = $clog2(NumCores + NumRemotePort);
  // Bits needed to select among local cache banks.
  localparam int unsigned CacheBankBits  = $clog2(NumCache);
  // Bits needed to select the tile in the shared address space.
  // Equals TileIDWidth by construction (NumTotCache / NumCache == NumTiles).
  localparam int unsigned TileBits       = $clog2(NumTotCache / NumCache);

  // -------------------------------------------------------------------------
  // Types
  // -------------------------------------------------------------------------

  typedef logic [NumInpSelBits-1:0]  mem_sel_t;
  typedef logic [NumOutSelBits -1:0] core_sel_t;

  // -------------------------------------------------------------------------
  // Internal signals
  // -------------------------------------------------------------------------

  // Xbar routing signals.
  core_sel_t [NumCores+NumRemotePort-1:0] core_req_sel;
  mem_sel_t  [NumCache+NumRemotePort-1:0] mem_rsp_sel;
  // '1' when this request stays on local banks.
  logic      [NumCores+NumRemotePort-1:0] local_sel;
  // '1' when a request targets the private partition.
  logic      [NumCores+NumRemotePort-1:0] is_private;

  // Xbar channel signals.
  tcdm_req_chan_t [NumCores+NumRemotePort-1:0] core_req;
  logic           [NumCores+NumRemotePort-1:0] core_req_valid, core_req_ready;

  tcdm_req_chan_t [NumCache+NumRemotePort-1:0] mem_req;
  logic           [NumCache+NumRemotePort-1:0] mem_req_valid, mem_req_ready;

  tcdm_rsp_chan_t [NumCores+NumRemotePort-1:0] core_rsp;
  logic           [NumCores+NumRemotePort-1:0] core_rsp_valid, core_rsp_ready;

  tcdm_rsp_chan_t [NumCache+NumRemotePort-1:0] mem_rsp;
  logic           [NumCache+NumRemotePort-1:0] mem_rsp_valid, mem_rsp_ready;

  // -------------------------------------------------------------------------
  // Partition control – registered to ease timing
  // -------------------------------------------------------------------------

  logic [$clog2(NumCache):0] num_private_cache_q, num_private_cache_d;
  logic [$clog2(NumCache):0] num_shared_cache_q,  num_shared_cache_d;

  addr_t private_start_addr_d, private_start_addr_q;

  `FF(num_private_cache_q,  num_private_cache_d,  1'b0)
  `FF(num_shared_cache_q,   num_shared_cache_d,   NumCache[$clog2(NumCache):0])
  `FF(private_start_addr_q, private_start_addr_d, 1'b0)

  always_comb begin
    num_private_cache_d   = num_private_cache_i;
    num_shared_cache_d    = ($clog2(NumCache)+1)'(NumCache) - num_private_cache_i;
    private_start_addr_d  = private_start_addr_i;
  end

  // -------------------------------------------------------------------------
  // Private/shared classification (request side, before xbar)
  // -------------------------------------------------------------------------

  for (genvar inp = 0; inp < NumCores+NumRemotePort; inp++) begin : gen_is_private
    assign is_private[inp] = (core_req[inp].addr >= private_start_addr_q);
  end

  // -------------------------------------------------------------------------
  // Crossbar
  // -------------------------------------------------------------------------

  reqrsp_xbar #(
    .NumInp           (NumCores + NumRemotePort),
    .NumOut           (NumCache + NumRemotePort),
    .PipeReg          (1'b0                    ),
    .ExtReqPrio       (1'b0                    ),
    .ExtRspPrio       (1'b0                    ),
    .tcdm_req_chan_t  (tcdm_req_chan_t         ),
    .tcdm_rsp_chan_t  (tcdm_rsp_chan_t         )
  ) i_cache_xbar (
    .clk_i            (clk_i                   ),
    .rst_ni           (rst_ni                  ),
    .slv_req_i        (core_req                ),
    .slv_rr_i         ('0                      ),
    .slv_req_valid_i  (core_req_valid          ),
    .slv_req_ready_o  (core_req_ready          ),
    .slv_rsp_o        (core_rsp                ),
    .slv_rsp_valid_o  (core_rsp_valid          ),
    .slv_rsp_ready_i  (core_rsp_ready          ),
    .slv_sel_i        (core_req_sel            ),
    .slv_selected_o   (/* unused */            ),
    .mst_req_o        (mem_req                 ),
    .mst_rr_i         ('0                      ),
    .mst_req_valid_o  (mem_req_valid           ),
    .mst_req_ready_i  (mem_req_ready           ),
    .mst_rsp_i        (mem_rsp                 ),
    .mst_rsp_valid_i  (mem_rsp_valid           ),
    .mst_rsp_ready_o  (mem_rsp_ready           ),
    .mst_sel_i        (mem_rsp_sel             )
  );

  // -------------------------------------------------------------------------
  // Request routing (xbar input-side selection)
  // -------------------------------------------------------------------------
  //
  // Address layout (example: offset=6, CacheBankBits=2, TileBits=2):
  //
  //   31      14 | 13    12 | 11    10 | 9     7 | 5        0
  //   Tag        | TileID   | BankSel  | Index   | CL offset
  //              ^-- [offset+CacheBankBits+TileBits-1 : offset+CacheBankBits]
  //                         ^-- [offset+CacheBankBits-1 : offset]
  //
  // Partitioning supports any num_private_cache_q in [0..NumCache]:
  //   Private banks : ports [0 .. num_private_cache_q-1]
  //   Shared  banks : ports [num_private_cache_q .. NumCache-1]
  //
  // Bank selection uses modulo folding:
  //   private_bank = (addr_bank_bits % num_private_cache_q)
  //   shared_bank  = num_private_cache_q + (addr_bank_bits % num_shared_cache_q)
  //
  // For power-of-2 partition sizes this reduces to a simple bit mask.
  // For non-power-of-2 sizes (e.g. 3) the modulo is a small comparator since
  // addr_bank_bits is only CacheBankBits wide.

  for (genvar port = 0; port < NumCores+NumRemotePort; port++) begin : gen_req_sel
    logic [CacheBankBits-1:0] addr_bank;

    always_comb begin
      // Defaults.
      local_sel[port]    = 1'b1;
      core_req_sel[port] = '0;

      // Extract the raw BankSel field from the address.
      addr_bank = core_req[port].addr[dynamic_offset_i +: CacheBankBits];

      if (num_private_cache_q == ($clog2(NumCache)+1)'(NumCache) || NumTiles == 1) begin
        // All-private or single-tile: every request is local.
        // Use the full BankSel field directly (no folding needed).
        local_sel[port]    = 1'b1;
        core_req_sel[port] = core_sel_t'(addr_bank);

      end else if (num_private_cache_q == '0) begin
        // All-shared: check TileID to decide local vs. remote.
        // Use the full BankSel field directly (no folding needed).
        local_sel[port] =
          (core_req[port].addr[(dynamic_offset_i + CacheBankBits) +: TileIDWidth] == tile_id_i);
        core_req_sel[port] = local_sel[port]
                           ? core_sel_t'(addr_bank)
                           : core_sel_t'(NumCache);

      end else begin
        // Mixed: fold addr_bank into the appropriate partition via modulo.
        if (is_private[port]) begin
          // Private request: always local.
          // bank = addr_bank % num_private_cache_q, offset from bank 0.
          local_sel[port]    = 1'b1;
          core_req_sel[port] = core_sel_t'(addr_bank % num_private_cache_q);
        end else begin
          // Shared request: check TileID to decide local vs. remote.
          // bank = num_private_cache_q + (addr_bank % num_shared_cache_q).
          local_sel[port] =
            (core_req[port].addr[(dynamic_offset_i + CacheBankBits) +: TileIDWidth] == tile_id_i);
          core_req_sel[port] = local_sel[port]
                             ? core_sel_t'(num_private_cache_q + (addr_bank % num_shared_cache_q))
                             : core_sel_t'(NumCache);
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Response routing (xbar output-side selection)
  // -------------------------------------------------------------------------

  for (genvar port = 0; port < NumCache+NumRemotePort; port++) begin : gen_rsp_sel
    always_comb begin
      mem_rsp_sel[port] = mem_rsp[port].user.core_id;
      if (mem_rsp[port].user.tile_id != tile_id_i) begin
        // Response from a remote tile: forward to the remote interco port.
        mem_rsp_sel[port] = mem_sel_t'(NumCores);
      end
    end
  end

  // -------------------------------------------------------------------------
  // Input-side pipeline registers
  // -------------------------------------------------------------------------

  for (genvar port = 0; port < NumCores+NumRemotePort; port++) begin : gen_cache_interco_reg
    spill_register #(
      .T      (tcdm_req_chan_t          )
    ) i_tcdm_req_reg (
      .clk_i  (clk_i                   ),
      .rst_ni (rst_ni                  ),
      .data_i (core_req_i[port].q      ),
      .valid_i(core_req_i[port].q_valid),
      .ready_o(core_rsp_o[port].q_ready),
      .data_o (core_req[port]          ),
      .valid_o(core_req_valid[port]    ),
      .ready_i(core_req_ready[port]    )
    );

    fall_through_register #(
      .T         (tcdm_rsp_chan_t           )
    ) i_tcdm_rsp_reg (
      .clk_i     (clk_i                    ),
      .rst_ni    (rst_ni                   ),
      .clr_i     (1'b0                     ),
      .testmode_i(1'b0                     ),
      .data_i    (core_rsp[port]           ),
      .valid_i   (core_rsp_valid[port]     ),
      .ready_o   (core_rsp_ready[port]     ),
      .data_o    (core_rsp_o[port].p       ),
      .valid_o   (core_rsp_o[port].p_valid ),
      .ready_i   (core_rsp_ready_i[port]   )
    );
  end

  // -------------------------------------------------------------------------
  // Output-side address rotation
  // -------------------------------------------------------------------------
  //
  // After the xbar each bank port receives only its own requests.  The N
  // routing bits (BankSel, and for shared also TileID) sitting immediately
  // above dynamic_offset_i must be hidden from the cache's tag/index logic.
  //
  // Instead of stripping them (which wastes tag SRAM by leaving constant zeros
  // at the top), we *rotate* them to the MSB:
  //
  //   Original:  [ Tag | {TileID,BankSel} | Index | CLoffset ]
  //   Rotated:   [ {TileID,BankSel} | Tag | Index | CLoffset ]
  //
  // The cache stores the rotated address as-is.  On a miss the refill unit
  // (outside this module) receives num_private_cache from the same mmapped
  // register and applies the inverse rotation before issuing to the NoC.
  //
  // Rotation per mode / bank port (N = bits_to_rotate):
  //
  //   Mode                      | port < num_private_cache_q  | port >= num_private_cache_q
  //   --------------------------|-----------------------------|--------------------------
  //   All-shared   (priv=0)     |            N/A              | CacheBankBits + TileBits
  //   1-private  3-shared       |        CacheBankBits        | CacheBankBits + TileBits
  //   Half-half  (priv=N/2)     |        CacheBankBits        | CacheBankBits + TileBits
  //   3-private  1-shared       |        CacheBankBits        | CacheBankBits + TileBits
  //   All-private  (priv=N)     |        CacheBankBits        |           N/A
  //
  // Construction (all arithmetic on addr_t width to avoid overflow):
  //
  //   lower     = addr & ((1 << offset) - 1)              // CLoffset, verbatim
  //   rot_field = (addr >> offset) & ((1 << N) - 1)       // N routing bits
  //   upper     = addr >> (offset + N)                     // Tag+Index
  //
  //   addr_rot  = lower
  //             | (upper     << offset)                    // close the hole
  //             | (rot_field << (AddrWidth - N))           // park at MSB

  // Width of bits_to_rotate signal: must hold values up to CacheBankBits+TileBits.
  localparam int unsigned RotWidth = $clog2(CacheBankBits + TileBits + 1) + 1;

  addr_t [NumCache-1:0] addr_rot;

  for (genvar port = 0; port < NumCache; port++) begin : gen_scramble
    logic [RotWidth-1:0] bits_to_rotate;

    always_comb begin
      // All-private: rotate BankSel only (no TileID in private addresses).
      // All-shared:  rotate BankSel + TileID.
      // Half-half:   private ports rotate BankSel only,
      //              shared  ports rotate BankSel + TileID.
      // The port index is a genvar constant so the if/else is static per bank.
      if (num_private_cache_q == '0) begin
        // All-shared: every bank is shared.
        bits_to_rotate = RotWidth'(CacheBankBits + TileBits);
      end else if (num_private_cache_q == ($clog2(NumCache)+1)'(NumCache)) begin
        // All-private: every bank is private.
        bits_to_rotate = RotWidth'(CacheBankBits);
      end else begin
        // Mixed: port index determines private vs. shared.
        if (port < int'(num_private_cache_q))
          bits_to_rotate = RotWidth'(CacheBankBits);             // private bank
        else
          bits_to_rotate = RotWidth'(CacheBankBits + TileBits);  // shared bank
      end
    end

    always_comb begin
      addr_t lower, rot_field, upper;

      // CL offset: bits below dynamic_offset_i, kept verbatim.
      lower     = mem_req[port].addr & ((addr_t'(1) << dynamic_offset_i) - 1);

      // Routing field: N bits starting at dynamic_offset_i.
      rot_field = (mem_req[port].addr >> dynamic_offset_i)
                & ((addr_t'(1) << bits_to_rotate) - 1);

      // Tag+Index: everything above the routing field.
      upper     = mem_req[port].addr >> (dynamic_offset_i + bits_to_rotate);

      // Reassemble: close the hole, park routing bits at the MSB.
      addr_rot[port] = lower
                     | (upper     << dynamic_offset_i)
                     | (rot_field << (AddrWidth - bits_to_rotate));
    end
  end

  // -------------------------------------------------------------------------
  // Output assignment
  // -------------------------------------------------------------------------

  for (genvar port = 0; port < NumCache + NumRemotePort; port++) begin : gen_cache_io
    always_comb begin
      mem_req_o[port] = '{
        q       : mem_req[port],
        q_valid : mem_req_valid[port],
        default : '0
      };

      if (port < NumCache) begin
        // Local bank: forward address with routing bits rotated to MSB.
        mem_req_o[port].q.addr = addr_rot[port];
      end else begin
        // Remote port: pass address untouched; extract target tile ID.
        tile_sel_o[port - NumCache] =
          mem_req[port].addr[(dynamic_offset_i + CacheBankBits) +: TileIDWidth];
      end
    end

    assign mem_rsp[port]       = mem_rsp_i[port].p;
    assign mem_rsp_valid[port] = mem_rsp_i[port].p_valid;
    assign mem_req_ready[port] = mem_rsp_i[port].q_ready;
  end

  assign mem_rsp_ready_o = mem_rsp_ready;

endmodule
