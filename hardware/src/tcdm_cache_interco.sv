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
  /// Number of total cache (used for address scramble).
  parameter int unsigned NumTotCache          = 32'd0,
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
  parameter type         tile_id_t            = logic [TileIDWidth-1:0],
  parameter type         addr_t               = logic [AddrWidth-1:0]

) (
  /// Clock, positive edge triggered.
  input  logic                                     clk_i,
  /// Reset, active low.
  input  logic                                     rst_ni,
  /// Tile ID
  input  tile_id_t                                 tile_id_i,
  /// Dynamic address offset for cache bank selection
  input  logic             [$clog2(AddrWidth)-1:0] dynamic_offset_i,
  /// Number of private cache for each tile, range: [0, NumCache]
  input  logic                [$clog2(NumCache):0] num_private_cache_i,
  /// Request port.
  input  tcdm_req_t   [NumCores+NumRemotePort-1:0] core_req_i,
  /// Response ready in
  input  logic        [NumCores+NumRemotePort-1:0] core_rsp_ready_i,
  /// Resposne port.
  output tcdm_rsp_t   [NumCores+NumRemotePort-1:0] core_rsp_o,
  /// Memory Side
  /// Which remote tile visiting?
  output tile_id_t             [NumRemotePort-1:0] tile_sel_o,
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

  // Buffer the signal
  logic                   [$clog2(NumCache):0] num_private_cache_d, num_private_cache_q;
  logic                   [$clog2(NumCache):0] num_shared_cache_d,  num_shared_cache_q;

  assign num_private_cache_d = num_private_cache_i;
  assign num_shared_cache_d  = NumCache - num_private_cache_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_partition_ctrl
    if(~rst_ni) begin
      num_private_cache_q <= 0;
      num_shared_cache_q  <= NumCache;
    end else begin
      num_private_cache_q <= num_private_cache_d;
      num_shared_cache_q  <= num_shared_cache_d;
    end
  end

  // TODO: The private/shared tag should be generated based on REG or Compiler
  // Hardcode it temporarily for testing
  localparam logic [AddrWidth-1:0]    PrivateAddr = 32'hC000_0000;
  logic [NumCores+NumRemotePort-1:0]  is_private;
  logic [NumCache-1:0]                private_bank_mask;
  logic [$clog2(NumCache)-1:0]        private_addr_mask, shared_addr_mask;
  for (genvar inp = 0; inp < NumCores+NumRemotePort; inp++) begin
    // Judge if a request is targetting private/shared partition
    assign is_private[inp] = (core_req[inp].addr > PrivateAddr);
  end

  assign private_bank_mask = (num_private_cache_q == 0) ? '0 : ((1 << num_private_cache_q) - 1);
  // Used to calculate the address taken away for cache
  assign private_addr_mask = (num_private_cache_q == 0) ? '0 : (num_private_cache_q - 1);
  assign shared_addr_mask  = (num_shared_cache_q  == 0) ? '0 : (num_shared_cache_q - 1);


  // Actual Xbar
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

  // TODO: Cache Partitioning:
  // 1. We need to identify if a transaction is targetting private/shared
  //    This can be done through a. targetted address; b. tag in the request
  // 2. If private, use the clog2(#P_BANK) bits to select the bank
  // 3. If shared and in remote banks, proceed as before
  // 4. If shared and in local banks, remap it to local banks if needed
  // 5. Adjust the address reassembling accordingly (needs to be aware of partitioning)

  // To make the local remapping simple, we can start with supporting only
  // three configurations: all shared, half-half, all private


  // select the target cache bank based on the `bank` bits
  // Example: 128 KiB total, 4 way, 4 cache banks, 512b cacheline
  // => 128*1024 = 2^17 Byte => 2^(17-6) = 2^11 cachelines
  // => 2^11/4 = 2^9 sets per cache bank => 2^9/4 = 2^7 sets per way per cache bank
  // => 7 bits index; 2 bits cache bank bits;
  // addr: Tag: [31:14]; Index: [13:7]; Cache Bank: [7:6]; Offset: [5:0]
  for (genvar port = 0; port < NumCores+NumRemotePort; port++) begin : gen_req_sel
    always_comb begin
      core_req_sel[port] = '0;
      if (num_private_cache_q == NumCache | NumTiles == 1) begin
        // All private or only one tile
        local_sel[port] = 1'b1;
      end else begin
        // Determine if we are targetting to a remote tile
        local_sel[port] = (core_req[port].addr[(dynamic_offset_i+CacheBankBits)+:TileIDWidth] == tile_id_i);
      end

      // Determine which bank is targeting at
      core_req_sel[port] = local_sel[port] ?
                           core_req[port].addr[dynamic_offset_i+:CacheBankBits] : NumCache;
    end
  end

  // forward response to the sender core
  for (genvar port = 0; port < NumCache+NumRemotePort;  port++) begin : gen_rsp_sel
    always_comb begin
      mem_rsp_sel[port] = mem_rsp[port].user.core_id;
      if (mem_rsp[port].user.tile_id != tile_id_i) begin
        // go to the remote interco
        mem_rsp_sel[port] = NumCores;
      end
    end
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

  // Parameters & Types
  localparam int BankBits = $clog2(NumCache);
  localparam int TileBits = $clog2(NumTotCache/NumCache);
  addr_t [NumCache-1:0] addr_lo, addr_up, addr_mid;

  // Logic to determine how many bits to "hole" out of the address
  // If private_i is Y/2, we only remove (BankBits - 1) bits to preserve
  // the distinction between the private and shared halves.
  logic [$clog2(BankBits + TileBits):0] total_bits_to_remove;
  logic [$clog2(BankBits):0] bank_bits_to_remove;

  assign bank_bits_to_remove  = (num_private_cache_q == NumCache/2) ? (BankBits - 1) : BankBits;
  assign total_bits_to_remove = bank_bits_to_remove + TileBits;

  addr_t bitmask_up, bitmask_lo, bitmask_mid;
  // Generate masks based on the dynamic bit count
  assign bitmask_lo = (addr_t'(1) << dynamic_offset_i) - 1;
  // bitmask_mid only exists if private_i == Y/2.
  // It captures the 1 bit of BankID we want to keep.
  assign bitmask_mid = (num_private_cache_q == NumCache/2) ? (addr_t'(1) << dynamic_offset_i) : '0;
  // bitmask_up clears the lower bits AND the bits being "holed"
  assign bitmask_up = ~((addr_t'(1) << (dynamic_offset_i + BankBits + TileBits)) - 1);

  for (genvar port = 0; port < NumCache; port++) begin : gen_scramble
    // 1. Determine if this specific port/bank is in the Private or Shared range
    // Lower num_private_cache_q banks are private.
    logic is_private;
    assign is_private = (port < num_private_cache_q);

    // 2. Calculate bits to remove for THIS port
    // If Private: We only remove BankBits (to avoid indexing overlap).
    // If Shared:  We remove BankBits + TileBits.
    logic [$clog2(BankBits + TileBits):0] local_bits_to_remove;

    assign local_bits_to_remove = is_private ? BankBits : (BankBits + TileBits);

    // 3. Address Reconstruction
    // Note: We use the same bitmask_lo (based on dynamic_offset_i)
    // But bitmask_up must start ABOVE the specific hole we are making.
    addr_t local_up_mask;
    assign local_up_mask = ~((addr_t'(1) << (dynamic_offset_i + local_bits_to_remove)) - 1);

    assign addr_lo[port] = mem_req[port].addr & bitmask_lo;

    // We don't really need addr_mid anymore because 'is_private' handles the
    // shift logic. If you want to keep a bit for Y/2, that bit is naturally
    // preserved if local_bits_to_remove is 0.

    assign addr_up[port] = (mem_req[port].addr & local_up_mask) >> local_bits_to_remove;

end


  for (genvar port = 0; port < NumCache + NumRemotePort; port++) begin : gen_cache_io
    always_comb begin
      mem_req_o[port] = '{
        q:        mem_req[port],
        q_valid:  mem_req_valid[port],
        default:  '0
      };

      if (port < NumCache) begin
        // Only scramble address for request going to local banks
        mem_req_o[port].q.addr = addr_lo[port] | addr_up[port];
      end else begin
        tile_sel_o[port-NumCache] = mem_req[port].addr[(dynamic_offset_i+CacheBankBits)+:TileIDWidth];
      end
    end

    assign mem_rsp[port]          = mem_rsp_i[port].p;
    assign mem_rsp_valid[port]    = mem_rsp_i[port].p_valid;
    assign mem_req_ready[port]    = mem_rsp_i[port].q_ready;
  end

  assign mem_rsp_ready_o  = mem_rsp_ready;


endmodule
