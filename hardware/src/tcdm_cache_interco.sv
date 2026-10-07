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
//
// Multi-group support (NumRemoteGroupPort > 0):
//
//   When the cluster contains multiple groups, tile IDs are globally unique
//   and encode both the group and tile-within-group:
//     tile_id = {group_id, local_tile_id}
//
//   The xbar performs three-way routing for shared (non-private) requests:
//     1. Local       : same tile             -> local cache bank
//     2. Intra-group : same group, diff tile -> remote port (existing xbar)
//     3. Inter-group : different group       -> inter-group remote port (new)
//
//   inter-group remote ports are appended after the remote ports on both input and output
//   sides of the xbar, preserving full backward compatibility when
//   NumRemoteGroupPort == 0.

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module tcdm_cache_interco #(
  /// Number of Tiles ('>= 1')
  parameter int unsigned NumTiles             = 32'd1,
  /// Number of inputs into the interconnect (Cores per Tile) (`> 0`).
  parameter int unsigned NumCores             = 32'd0,
  /// Number of remote ports added to xbar for intra-group traffic ('>= 0').
  parameter int unsigned NumLGPort            = 32'd0,
  /// Number of dedicated inter-group remote ports ('>= 0').
  /// When 0, the module behaves identically to the single-group configuration.
  /// Each inter-group remote port serves as both an output (requests to other groups) and an
  /// input (requests arriving from other groups), mirroring NumLGPort.
  parameter int unsigned NumRemoteGroupPort   = 32'd0,
  /// Number of outputs from the interconnect (Cache banks per Tile) (`> 0`).
  parameter int unsigned NumCache             = 32'd0,
  /// Number of total cache banks across all tiles (used for address scramble).
  /// For multi-group, this must cover all tiles across all groups.
  parameter int unsigned NumTotCache          = 32'd0,
  /// Address width in bits (cacheline offset: 512b => 6 bits).
  parameter int unsigned AddrWidth            = 32'd32,
  /// Tile ID width ('> 0').
  /// In multi-group configurations, TileIDWidth covers the globally unique
  /// tile ID which encodes both group and tile-within-group:
  ///   tile_id = {group_id, local_tile_id}
  parameter int unsigned TileIDWidth          = 32'd1,
  /// DRAM base address, used to check if we get illegal access
  parameter int unsigned DramBaseAddr         = 32'h8000_0000,
  /// Number of tiles within a single group.
  /// Used to extract the group portion from the address tile field:
  ///   group_id = addr_tile_bits / NumTilesPerGroup
  /// Only relevant when NumRemoteGroupPort > 0.  Defaults to NumTiles for
  /// backward compatibility (single-group: all tiles are in one group).
  parameter int unsigned NumTilesPerGroup     = NumTiles,

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
  parameter type         addr_t               = logic [AddrWidth-1:0],
  localparam             TotInPorts           = NumCores+NumLGPort+NumRemoteGroupPort,
  localparam             TotOutPorts          = NumCache+NumLGPort+NumRemoteGroupPort

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
  /// Number of private cache banks for this tile, 0..NumCache. The original
  /// design allowed only 0, NumCache/2 and NumCache; 1 and NumCache-1 were
  /// added later and are mapped by folding the bank field with a modulo, so
  /// non-power-of-two splits distribute lines unevenly by design.
  input  logic                [$clog2(NumCache):0] num_private_cache_i,
  /// Fold the private partition across the group instead of the tile. Only
  /// takes effect when every bank is private; ignored otherwise.
  input  logic                                     group_fold_i,
  /// Partitioning address
  input  addr_t                                    private_start_addr_i,
  /// Request port (cores + intra-group remote-in + inter-group remote-in).
  input  tcdm_req_t               [TotInPorts-1:0] core_req_i,
  /// Response ready in.
  input  logic                    [TotInPorts-1:0] core_rsp_ready_i,
  /// Response port (cores + intra-group remote-in + inter-group remote-in).
  output tcdm_rsp_t               [TotInPorts-1:0] core_rsp_o,
  /// Memory side -------------------------------------------------------
  /// Which remote tile is targeted (one entry per intra-group remote output).
  output tile_id_t                 [NumLGPort-1:0] tile_sel_o,
  /// Which tile is targeted via inter-group remote (one entry per inter-group remote output).
  /// Carries the full globally-unique tile ID; the wrapper decomposes it
  /// into group XY coordinates for the router and local tile ID for the
  /// receiving-side xbar.
  output tile_id_t        [NumRemoteGroupPort-1:0] remote_group_sel_o,
  /// Requests to cache banks, intra-group remote, and inter-group remote ports.
  output tcdm_req_t              [TotOutPorts-1:0] mem_req_o,
  /// Response ready out.
  output logic                   [TotOutPorts-1:0] mem_rsp_ready_o,
  /// Responses from cache banks, intra-group remote, and inter-group remote ports.
  input  tcdm_rsp_t              [TotOutPorts-1:0] mem_rsp_i
);

  // -------------------------------------------------------------------------
  // Local parameters
  // -------------------------------------------------------------------------

  // Total number of xbar input and output ports.
  localparam int unsigned NumInp        = NumCores + NumLGPort + NumRemoteGroupPort;
  localparam int unsigned NumOut        = NumCache + NumLGPort + NumRemoteGroupPort;
  // Bits to index into xbar outputs.
  localparam int unsigned NumOutSelBits = $clog2(NumOut);
  // Bits to index into xbar inputs.
  localparam int unsigned NumInpSelBits = $clog2(NumInp);
  // Bits needed to select among local cache banks.
  localparam int unsigned CacheBankBits = $clog2(NumCache);
  // Bits needed to select the tile in the shared address space.
  // Equals TileIDWidth by construction (NumTotCache / NumCache == NumTotalTiles).
  localparam int unsigned TileBits      = $clog2(NumTotCache / NumCache);

  // Group extraction: number of bits to identify the group within TileID.
  // LocalTileBits = $clog2(NumTilesPerGroup); GroupBits = TileBits - LocalTileBits.
  // Only meaningful when NumRemoteGroupPort > 0.
  localparam int unsigned LocalTileBits = $clog2(NumTilesPerGroup);

  // -------------------------------------------------------------------------
  // Types
  // -------------------------------------------------------------------------

  typedef logic [NumInpSelBits-1:0]  mem_sel_t;
  typedef logic [NumOutSelBits-1:0]  core_sel_t;

  // -------------------------------------------------------------------------
  // Internal signals
  // -------------------------------------------------------------------------

  // Xbar routing signals.
  core_sel_t [NumInp-1:0] core_req_sel;
  mem_sel_t  [NumOut-1:0] mem_rsp_sel;
  // '1' when a request targets the private partition.
  logic      [NumInp-1:0] is_private;

  // Xbar channel signals.
  tcdm_req_chan_t [NumInp-1:0] core_req;
  logic           [NumInp-1:0] core_req_valid, core_req_ready;

  tcdm_req_chan_t [NumOut-1:0] mem_req;
  logic           [NumOut-1:0] mem_req_valid, mem_req_ready;

  tcdm_rsp_chan_t [NumInp-1:0] core_rsp;
  logic           [NumInp-1:0] core_rsp_valid, core_rsp_ready;

  tcdm_rsp_chan_t [NumOut-1:0] mem_rsp;
  logic           [NumOut-1:0] mem_rsp_valid, mem_rsp_ready;

  // -------------------------------------------------------------------------
  // Partition control – registered to ease timing
  // -------------------------------------------------------------------------

  logic [$clog2(NumCache):0] num_private_cache_q, num_private_cache_d;
  logic                      group_fold_q,        group_fold_d;
  logic [$clog2(NumCache):0] num_shared_cache_q,  num_shared_cache_d;

  addr_t private_start_addr_d, private_start_addr_q;

  `FF(num_private_cache_q,  num_private_cache_d,  1'b0)
  `FF(num_shared_cache_q,   num_shared_cache_d,   NumCache[$clog2(NumCache):0])
  `FF(group_fold_q,         group_fold_d,         1'b0)
  `FF(private_start_addr_q, private_start_addr_d, 1'b0)

  always_comb begin
    num_private_cache_d   = num_private_cache_i;
    num_shared_cache_d    = ($clog2(NumCache)+1)'(NumCache) - num_private_cache_i;
    group_fold_d          = group_fold_i;
    private_start_addr_d  = private_start_addr_i;
  end

  // Only with every bank private do the tile's banks serve the whole group,
  // addressed by the local tile bits; other partitionings are unaffected.
  logic group_fold;
  assign group_fold = group_fold_q;

  // -------------------------------------------------------------------------
  // Private/shared classification (request side, before xbar)
  // -------------------------------------------------------------------------

  // Assumptions the routing below relies on, so they are checked once here
  // instead of being re-tested as conditions in the selection chain.
  // Bare `initial assert`: ASSERT_INIT expands to nothing (INC_ASSERT unset).
  initial assert (NumTilesPerGroup > 1)
    else $fatal(1, "tcdm_cache_interco: NumTilesPerGroup must exceed 1; with a single tile per group there is no sibling tile and LocalTileBits would be 0.");
  initial assert (NumTiles == NumTilesPerGroup || NumRemoteGroupPort > 0)
    else $fatal(1, "tcdm_cache_interco: a multi-group build (NumTiles > NumTilesPerGroup) needs NumRemoteGroupPort > 0, or cross-group requests have no port to leave on.");

  for (genvar inp = 0; inp < NumInp; inp++) begin : gen_is_private
    assign is_private[inp] = (core_req[inp].addr >= private_start_addr_q);
  end

  // -------------------------------------------------------------------------
  // Crossbar
  // -------------------------------------------------------------------------

  reqrsp_xbar #(
    .NumInp           (NumInp                  ),
    .NumOut           (NumOut                  ),
    .PipeReg          (1'b0                    ),
    .ExtReqPrio       (1'b0                    ),
    .ExtRspPrio       (1'b0                    ),
    .tcdm_req_chan_t  (tcdm_req_chan_t         ),
    .tcdm_rsp_chan_t  (tcdm_rsp_chan_t         )
  ) i_cache_xbar (
    .clk_i             (clk_i                   ),
    .rst_ni            (rst_ni                  ),
    .slv_req_i         (core_req                ),
    .slv_rr_i          ('0                      ),
    .slv_req_valid_i   (core_req_valid          ),
    .slv_req_ready_o   (core_req_ready          ),
    .slv_rsp_o         (core_rsp                ),
    .slv_rsp_valid_o   (core_rsp_valid          ),
    .slv_rsp_ready_i   (core_rsp_ready          ),
    .slv_sel_i         (core_req_sel            ),
    .slv_selected_o    (/* unused */            ),
    .mst_req_o         (mem_req                 ),
    .mst_rr_i          ('0                      ),
    .mst_req_valid_o   (mem_req_valid           ),
    .mst_req_ready_i   (mem_req_ready           ),
    .mst_rsp_i         (mem_rsp                 ),
    .mst_rsp_valid_i   (mem_rsp_valid           ),
    .mst_rsp_ready_o   (mem_rsp_ready           ),
    .mst_sel_i         (mem_rsp_sel             )
  );

  // -------------------------------------------------------------------------
  // Request routing (xbar input-side selection)
  // -------------------------------------------------------------------------
  //
  // Address layout (example: offset=6, CacheBankBits=2, TileBits=4 with
  // LocalTileBits=2 and GroupBits=2):
  //
  //   31    16 | 15  14 | 13  12 | 11  10 | 9     7 | 5        0
  //   Tag      | GroupID | LclTID | BankSel | Index  | CL offset
  //            ^-- [offset+CacheBankBits+TileBits-1 : offset+CacheBankBits+LocalTileBits]
  //                       ^-- [offset+CacheBankBits+LocalTileBits-1 : offset+CacheBankBits]
  //                                ^-- [offset+CacheBankBits-1 : offset]
  //
  // Three-way routing classification:
  //   1. Local       : addr tile == my tile          -> route to cache bank
  //   2. Intra-group : same group, different tile    -> route to remote port
  //   3. Inter-group : different group               -> route to inter-group remote port
  //
  // Partitioning (private/shared) interacts as follows:
  //   - Private requests are always local (same as before).
  //   - Shared requests use the full three-way classification.
  //
  // The original two-way classification (local vs. remote) is preserved
  // when NumRemoteGroupPort == 0, ensuring backward compatibility.

  // Derive this tile's group ID from the globally-unique tile_id_i.
  logic [TileBits-1:0] my_group_id;
  if (NumRemoteGroupPort == 0) begin
    assign my_group_id = tile_id_i;
  end else begin
    assign my_group_id = tile_id_i[TileBits-1:LocalTileBits];
  end

  for (genvar port = 0; port < NumInp; port++) begin : gen_req_sel
    logic [CacheBankBits-1:0] addr_bank;
    // Full tile ID extracted from the address (covers group + local tile).
    logic [TileBits-1:0]     addr_tile_id;
    // Group portion of the address tile field.
    logic [TileBits-1:0]     addr_group_id;
    // Whether the addressed group matches this tile's group.
    logic                    same_group;
    // Partition-mode shorthands, decoded once per port.
    logic                    all_private, all_shared, all_local;
    logic                    use_private, fold_remote;

    always_comb begin
      // Defaults.
      core_req_sel[port] = '0;

      // Extract the raw BankSel field from the address.
      addr_bank     = core_req[port].addr[dynamic_offset_i +: CacheBankBits];
      // Extract the full tile ID (group + local) from the address.
      addr_tile_id  = core_req[port].addr[(dynamic_offset_i + CacheBankBits) +: TileBits];
      // Extract group portion (upper bits of tile ID).
      addr_group_id = addr_tile_id >> LocalTileBits;
      // Compare group IDs.
      same_group    = (addr_group_id == my_group_id);

      // A request stays local when the partition it targets is the private
      // one, or when every bank is private. all_local also covers the
      // degenerate single-tile single-group build, which has no remote ports.
      all_private = (num_private_cache_q == ($clog2(NumCache)+1)'(NumCache));
      all_shared  = (num_private_cache_q == '0);
      all_local   = all_private;
      use_private = all_private || (!all_shared && is_private[port]);
      // A folded private line lives in the tile its local address bits select,
      // which may not be this one.
      fold_remote = group_fold
                  && (addr_tile_id[LocalTileBits-1:0] != tile_id_i[LocalTileBits-1:0]);

      if (use_private && fold_remote) begin
        core_req_sel[port] = core_sel_t'(NumCache + (port % NumLGPort));
      end else if (all_local || use_private) begin
        // Local private bank. Folding is a no-op when every bank is private,
        // and num_private_cache_q is non-zero on both paths that reach here.
        core_req_sel[port] = all_local ? core_sel_t'(addr_bank)
                                       : core_sel_t'(addr_bank % num_private_cache_q);
      end else if (!same_group) begin
        core_req_sel[port] = core_sel_t'(NumCache + NumLGPort
                                        + (port % NumRemoteGroupPort));
      end else if (addr_tile_id[LocalTileBits-1:0] != tile_id_i[LocalTileBits-1:0]) begin
        core_req_sel[port] = core_sel_t'(NumCache + (port % NumLGPort));
      end else begin
        // Local shared bank. num_shared_cache_q is non-zero here: all_private
        // was handled above, so at least one bank is shared.
        core_req_sel[port] = all_shared
                           ? core_sel_t'(addr_bank)
                           : core_sel_t'(num_private_cache_q
                                        + (addr_bank % num_shared_cache_q));
      end
    end
  end

  // -------------------------------------------------------------------------
  // Response routing (xbar output-side selection)
  // -------------------------------------------------------------------------
  //
  // Responses from local cache banks are routed back to the originating
  // core using core_id.  Responses from intra-group remote tiles and
  // inter-group remote ports carry a tile_id that differs from tile_id_i;
  // these are forwarded to the corresponding remote-in or inter-group remote-in port.

  for (genvar port = 0; port < NumOut; port++) begin : gen_rsp_sel
    logic [TileBits-1:0] rsp_group_id;
    if (NumRemoteGroupPort == 0) begin
      assign rsp_group_id = my_group_id;
    end else begin
      assign rsp_group_id = mem_rsp[port].user.tile_id[TileBits-1:LocalTileBits];
    end

    always_comb begin
      mem_rsp_sel[port] = mem_rsp[port].user.core_id;
      if (mem_rsp[port].user.tile_id != tile_id_i) begin
        // Response originates from a different tile (intra-group remote or
        // inter-group remote).  Determine which input port set it came from.
        if (rsp_group_id != my_group_id) begin
          // Inter-group: forward to the inter-group remote-in input port.
          mem_rsp_sel[port] = mem_sel_t'(NumCores + NumLGPort
                              + (mem_rsp[port].user.core_id % NumRemoteGroupPort));
        end else begin
          // Intra-group: forward to the remote-in input port.
          mem_rsp_sel[port] = mem_sel_t'(NumCores
                              + (mem_rsp[port].user.core_id % NumLGPort));
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Input-side pipeline registers
  // -------------------------------------------------------------------------

  for (genvar port = 0; port < NumInp; port++) begin : gen_cache_interco_reg
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
  //   upper     = addr >> (offset + N)                    // Tag+Index
  //
  //   addr_rot  = lower
  //             | (upper     << offset)                   // close the hole
  //             | (rot_field << (AddrWidth - N))          // park at MSB

  // Width of bits_to_rotate signal: must hold values up to CacheBankBits+TileBits.
  localparam int unsigned RotWidth = $clog2(CacheBankBits + TileBits + 1) + 1;

  addr_t [NumCache-1:0] addr_rot;

  for (genvar port = 0; port < NumCache; port++) begin : gen_scramble
    logic [RotWidth-1:0] bits_to_rotate;

    // Private banks rotate BankSel only; shared banks also rotate TileID.
    // The bank index is a genvar constant, so this covers the all-private
    // (every port below the boundary) and all-shared (none below) cases too.
    assign bits_to_rotate = (port < int'(num_private_cache_q))
          ? (group_fold ? RotWidth'(CacheBankBits + LocalTileBits)
                        : RotWidth'(CacheBankBits))
          : RotWidth'(CacheBankBits + TileBits);

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

  for (genvar port = 0; port < NumOut; port++) begin : gen_cache_io
    always_comb begin
      mem_req_o[port] = '{
        q       : mem_req[port],
        q_valid : mem_req_valid[port],
        default : '0
      };

      if (port < NumCache) begin
        // Local bank: forward address with routing bits rotated to MSB.
        mem_req_o[port].q.addr = addr_rot[port];
      end else if (port < NumCache + NumLGPort) begin
        // Intra-group remote port: pass address untouched; extract target tile ID.
        tile_sel_o[port - NumCache] =
          mem_req[port].addr[(dynamic_offset_i + CacheBankBits) +: TileBits];
      end else begin
        // Inter-group remote port: pass address untouched; extract target tile ID.
        remote_group_sel_o[port - NumCache - NumLGPort] =
          mem_req[port].addr[(dynamic_offset_i + CacheBankBits) +: TileBits];
      end
    end

    assign mem_rsp[port]       = mem_rsp_i[port].p;
    assign mem_rsp_valid[port] = mem_rsp_i[port].p_valid;
    assign mem_req_ready[port] = mem_rsp_i[port].q_ready;
  end

  assign mem_rsp_ready_o = mem_rsp_ready;

`ifndef TARGET_SYNTHESIS
  // Probe D: targeted addr watcher inside the cluster xbar.
  // Off by default; enable with +xbar_write_watch plusarg.
  bit xbar_write_watch_en = 1'b0;
  // verilog_lint: waive plusarg-assignment
  initial xbar_write_watch_en = $test$plusargs("xbar_write_watch");

  // Loop indices hoisted out of always blocks (debug-only).
  int unsigned dbg_xwwatch_p;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni && xbar_write_watch_en) begin
      for (dbg_xwwatch_p = 0; dbg_xwwatch_p < NumOut; dbg_xwwatch_p++) begin
        if (mem_req_valid[dbg_xwwatch_p] && mem_req_ready[dbg_xwwatch_p] &&
            mem_req[dbg_xwwatch_p].write) begin
          if (mem_req[dbg_xwwatch_p].addr == 32'ha0001308 ||
              mem_req[dbg_xwwatch_p].addr == 32'ha0001700 ||
              mem_req[dbg_xwwatch_p].addr == 32'ha0001730) begin
            $display({"[XBAR-WRITE-WATCH %0t %m port %0d] orig_addr=0x%08h ",
                      "post_rot=0x%08h is_remote=%0b data=0x%08h strb=0x%h ",
                      "user_tile=%0d user_core=%0d user_req=0x%h"},
                     $time, dbg_xwwatch_p, mem_req[dbg_xwwatch_p].addr,
                     mem_req_o[dbg_xwwatch_p].q.addr,
                     (dbg_xwwatch_p >= NumCache),
                     mem_req[dbg_xwwatch_p].data, mem_req[dbg_xwwatch_p].strb,
                     mem_req[dbg_xwwatch_p].user.tile_id, mem_req[dbg_xwwatch_p].user.core_id,
                     mem_req[dbg_xwwatch_p].user.req_id);
          end
        end
      end
    end
  end

`endif

  // -------------------------------------------------------------------------
  // Assertions
  // -------------------------------------------------------------------------
`ifndef TARGET_SYNTHESIS
  // This is used to ensure we will not have illegal visits to DRAM
  // This kind of error can be latent in the system until the entry is evicted
  for (genvar x = 0; x < TotInPorts; x++) begin : gen_addr_assert
    CoreReqAddrAboveDram: assert property (
      @(posedge clk_i) disable iff (!rst_ni !== '0)
      core_req_i[x].q_valid |-> core_req_i[x].q.addr >= addr_t'(DramBaseAddr)
    ) else begin
      $error("[%m] port %0d: addr 0x%08x is below DramBaseAddr 0x%08x",
             x, core_req_i[x].q.addr, DramBaseAddr);
    end
  end
`endif

endmodule
