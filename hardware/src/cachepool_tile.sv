// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "mempool/mempool.svh"

/* verilator lint_off DECLFILENAME */
module cachepool_tile
  import cachepool_pkg::*;
  import cf_math_pkg::idx_width;
#(
  // TCDM
  parameter addr_t       TCDMBaseAddr = 32'b0,
  // Boot address
  parameter logic [31:0] BootAddr     = 32'h0000_1000,
  // Dependent parameters. DO NOT CHANGE.
  parameter int unsigned NumICaches    = NumCoresPerTile / NumCoresPerCache
) (
  // Clock and reset
  input  logic                                                                    clk_i,
  input  logic                                                                    rst_ni,
  // Scan chain
  input  logic                                                                    scan_enable_i,
  input  logic                                                                    scan_data_i,
  output logic                                                                    scan_data_o,
  // Tile ID
  input  logic              [idx_width(NumTiles)-1:0]                             tile_id_i,
  // TCDM Master interfaces
  output `STRUCT_VECT(tcdm_master_req_t,  [NumGroups+NumSubGroupsPerGroup-1-1:0]) tcdm_master_req_o,
  output logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_master_req_valid_o,
  input  logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_master_req_ready_i,
  input  `STRUCT_VECT(tcdm_master_resp_t, [NumGroups+NumSubGroupsPerGroup-1-1:0]) tcdm_master_resp_i,
  input  logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_master_resp_valid_i,
  output logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_master_resp_ready_o,
  // TCDM slave interfaces
  input  `STRUCT_VECT(tcdm_slave_req_t,   [NumGroups+NumSubGroupsPerGroup-1-1:0]) tcdm_slave_req_i,
  input  logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_slave_req_valid_i,
  output logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_slave_req_ready_o,
  output `STRUCT_VECT(tcdm_slave_resp_t,  [NumGroups+NumSubGroupsPerGroup-1-1:0]) tcdm_slave_resp_o,
  output logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_slave_resp_valid_o,
  input  logic              [NumGroups+NumSubGroupsPerGroup-1-1:0]                tcdm_slave_resp_ready_i,
  // TCDM DMA interfaces
  input  `STRUCT_PORT(tcdm_dma_req_t)                                             tcdm_dma_req_i,
  input  logic                                                                    tcdm_dma_req_valid_i,
  output logic                                                                    tcdm_dma_req_ready_o,
  output `STRUCT_PORT(tcdm_dma_resp_t)                                            tcdm_dma_resp_o,
  output logic                                                                    tcdm_dma_resp_valid_o,
  input  logic                                                                    tcdm_dma_resp_ready_i,
  // AXI Interface
  output `STRUCT_PORT(axi_tile_req_t)                                             axi_mst_req_o,
  input  `STRUCT_PORT(axi_tile_resp_t)                                            axi_mst_resp_i,
  // Wake up interface
  input  logic              [NumCoresPerTile-1:0]                                 wake_up_i
);

  // CachePool Tile will contains several Spatz CC and some cache banks

  /****************
   *   Includes   *
   ****************/

  `include "common_cells/registers.svh"

  /*****************
   *  Definitions  *
   *****************/

  import snitch_pkg::dreq_t;
  import snitch_pkg::dresp_t;

  typedef logic [idx_width(NumGroups)-1:0] group_id_t;

  // Local interconnect address width
  typedef logic [idx_width(NumCoresPerTile*NumDataPortsPerCore + NumGroups + NumSubGroupsPerGroup-1)-1:0] local_req_interco_addr_t;


  // L1 Data Cache Parameters

  /*********************
   *  Control Signals  *
   *********************/


  /***********
   *  Cores  *
   ***********/

  // Instruction interfaces
  addr_t [NumICaches-1:0][NumCoresPerCache-1:0] snitch_inst_addr;
  data_t [NumICaches-1:0][NumCoresPerCache-1:0] snitch_inst_data;
  logic  [NumICaches-1:0][NumCoresPerCache-1:0] snitch_inst_valid;
  logic  [NumICaches-1:0][NumCoresPerCache-1:0] snitch_inst_ready;

  // Data interfaces
  addr_t      [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qaddr;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qwrite;
  amo_t       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qamo;
  data_t      [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qdata;
  strb_t      [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qstrb;
  meta_id_t   [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qid;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qvalid;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_qready;
  data_t      [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_pdata;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_pwrite;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_perror;
  meta_id_t   [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_pid;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_pvalid;
  logic       [NumCoresPerTile-1:0][NumDataPortsPerCore-1:0] snitch_data_pready;

  for (genvar c = 0; unsigned'(c) < NumCoresPerTile; c++) begin: gen_cores
    logic [31:0] hart_id;
    if (NumCoresPerTile == 1) begin
      assign hart_id = unsigned'(tile_id_i);
    end else begin
      assign hart_id = {unsigned'(tile_id_i), c[idx_width(NumCoresPerTile)-1:0]};
    end

    spatz_mempool_cc #(
      .BootAddr             ( BootAddr            ),
      .RVE                  ( 0                   ),
      .RVM                  ( 1                   ),
      .RVV                  ( RVV                 ),
      .XFVEC                ( XFVEC               ),
      .XFDOTP               ( XFDOTP              ),
      .XFAUX                ( XFAUX               ),
      .RVF                  ( RVF                 ),
      .RVD                  ( RVD                 ),
      .XF16                 ( XF16                ),
      .XF16ALT              ( XF16ALT             ),
      .XF8                  ( XF8                 ),
      .XDivSqrt             ( XDivSqrt            ),
      .NumMemPortsPerSpatz  ( NumMemPortsPerSpatz ),
      .TCDMPorts            ( NumDataPortsPerCore )
    )
    riscv_core (
      .clk_i         (clk_i                                                    ),
      .rst_i         (!rst_ni                                                  ),
      .hart_id_i     (hart_id                                                  ),
      // IMEM Port
      .inst_addr_o   (snitch_inst_addr[c/NumCoresPerCache][c%NumCoresPerCache] ),
      .inst_data_i   (snitch_inst_data[c/NumCoresPerCache][c%NumCoresPerCache] ),
      .inst_valid_o  (snitch_inst_valid[c/NumCoresPerCache][c%NumCoresPerCache]),
      .inst_ready_i  (snitch_inst_ready[c/NumCoresPerCache][c%NumCoresPerCache]),
      // Data Ports
      .data_qaddr_o  (snitch_data_qaddr[c]                                     ),
      .data_qwrite_o (snitch_data_qwrite[c]                                    ),
      .data_qamo_o   (snitch_data_qamo[c]                                      ),
      .data_qdata_o  (snitch_data_qdata[c]                                     ),
      .data_qstrb_o  (snitch_data_qstrb[c]                                     ),
      .data_qid_o    (snitch_data_qid[c]                                       ),
      .data_qvalid_o (snitch_data_qvalid[c]                                    ),
      .data_qready_i (snitch_data_qready[c]                                    ),
      .data_pdata_i  (snitch_data_pdata[c]                                     ),
      .data_pwrite_i (snitch_data_pwrite[c]                                    ),
      .data_perror_i (snitch_data_perror[c]                                    ),
      .data_pid_i    (snitch_data_pid[c]                                       ),
      .data_pvalid_i (snitch_data_pvalid[c]                                    ),
      .data_pready_o (snitch_data_pready[c]                                    ),
      .wake_up_sync_i(wake_up_q[c]                                             ),
      // Core Events
      .core_events_o (/* Unused */                                             )
    );
  end

  /***********************
   *  Instruction Cache  *
   ***********************/
  // Instruction interface
  axi_core_req_t  [NumICaches-1:0] axi_cache_req_d, axi_cache_req_q;
  axi_core_resp_t [NumICaches-1:0] axi_cache_resp_d, axi_cache_resp_q;

  for (genvar c = 0; unsigned'(c) < NumICaches; c++) begin: gen_icaches
    snitch_icache #(
      .NR_FETCH_PORTS     (NumCoresPerCache                                    ),
      /// Cache Line Width
      .L0_LINE_COUNT      (4                                                   ),
      .LINE_WIDTH         (ICacheLineWidth                                     ),
      .LINE_COUNT         (ICacheSizeByte / (ICacheSets * ICacheLineWidth / 8) ),
      .SET_COUNT          (ICacheSets                                          ),
      .FETCH_AW           (AddrWidth                                           ),
      .FETCH_DW           (DataWidth                                           ),
      .FILL_AW            (AddrWidth                                           ),
      .FILL_DW            (AxiDataWidth                                        ),
      .L1_TAG_SCM         (1                                                   ),
      /// Make the early cache latch-based. This reduces latency at the cost of
      /// increased combinatorial path lengths and the hassle of having latches in
      /// the design.
      .EARLY_LATCH        (1                                                   ),
      .L0_EARLY_TAG_WIDTH (11                                                  ),
      .ISO_CROSSING       (0                                                   ),
      .axi_req_t          (axi_core_req_t                                      ),
      .axi_rsp_t          (axi_core_resp_t                                     )
    ) i_snitch_icache (
      .clk_i                (clk_i                   ),
      .clk_d2_i             (clk_i                   ),
      .rst_ni               (rst_ni                  ),
      .enable_prefetching_i (1'b1                    ),
      .icache_events_o      (/* Unused */            ),
      .flush_valid_i        (1'b0                    ),
      .flush_ready_o        (/* Unused */            ),
      .inst_addr_i          (snitch_inst_addr[c]     ),
      .inst_data_o          (snitch_inst_data[c]     ),
      .inst_cacheable_i     ({NumCoresPerCache{1'b1}}),
      .inst_valid_i         (snitch_inst_valid[c]    ),
      .inst_ready_o         (snitch_inst_ready[c]    ),
      .inst_error_o         (/* Unused */            ),
      .axi_req_o            (axi_cache_req_d[c]      ),
      .axi_rsp_i            (axi_cache_resp_q[c]     )
    );
    axi_cut #(
      .aw_chan_t (axi_core_aw_t  ),
      .w_chan_t  (axi_core_w_t   ),
      .b_chan_t  (axi_core_b_t   ),
      .ar_chan_t (axi_core_ar_t  ),
      .r_chan_t  (axi_core_r_t   ),
      .axi_req_t (axi_core_req_t ),
      .axi_resp_t(axi_core_resp_t)
    ) axi_cache_slice (
      .clk_i     (clk_i              ),
      .rst_ni    (rst_ni             ),
      .slv_req_i (axi_cache_req_d[c] ),
      .slv_resp_o(axi_cache_resp_q[c]),
      .mst_req_o (axi_cache_req_q[c] ),
      .mst_resp_i(axi_cache_resp_d[c])
    );
  end

  /*****************
   *  Cache Banks  *
   *****************/

  stream_xbar #(
    .NumInp   (1             ),
    .NumOut   (NumSuperbanks ),
    .payload_t(tcdm_dma_req_t)
  ) i_dma_req_interco (
    .clk_i  (clk_i                                                  ),
    .rst_ni (rst_ni                                                 ),
    .flush_i(1'b0                                                   ),
    // External priority flag
    .rr_i   ('0                                                     ),
    // Master
    .data_i (tcdm_dma_req_i_struct                                  ),
    .valid_i(tcdm_dma_req_valid_i                                   ),
    .ready_o(tcdm_dma_req_ready_o                                   ),
    .sel_i  (tcdm_dma_req_i_struct.tgt_addr[idx_width(NumBanksPerTile)-1:$clog2(DmaNumWords)]),
    // Slave
    .data_o (tcdm_dma_req                                           ),
    .valid_o(tcdm_dma_req_valid                                     ),
    .ready_i(tcdm_dma_req_ready                                     ),
    .idx_o  (/* Unused */                                           )
  );



  // TODO: Add a XBar for bank selection

  for (genvar c = 0; unsigned'(c) < NumDCaches; c++) begin: gen_dcaches
    flamingo_spatz_cache_ctrl #(
      // Core
      .NumPorts         (L1DNumPorts      ),
      .CoalExtFactor    (L1DCoalFactor    ),
      .AddrWidth        (AddrWidth        ),
      .WordWidth        (DataWidth        ),
      // Cache
      .NumCacheEntry    (L1DSizePerBank   ),
      .CacheLineWidth   (L1DCacheLine     ),
      .SetAssociativity (L1DCacheWay      ),
      .BankFactor       (L1DCacheBF       ),
      // Type
      .core_meta_t      (       ),
      .impl_in_t        (       ),
      .axi_req_t        (  ),
      .axi_resp_t       ( )
    ) i_l1_bank (
      .clk_i                 (clk_i                  ),
      .rst_ni                (rst_ni                 ),
      .impl_i                ('0                     ),
      // Sync Control
      .cache_sync_valid_i    (l1d_insn_valid         ),
      .cache_sync_ready_o    (l1d_insn_ready         ),
      .cache_sync_insn_i     (l1d_insn               ),
      // SPM Size, DO WE NEED IT FOR CACHEPOOL?
      .bank_depth_for_SPM_i  (num_spm_lines          ),
      // Request
      .core_req_valid_i      (cache_req_valid[c]     ),
      .core_req_ready_o      (cache_req_ready[c]     ),
      .core_req_addr_i       (cache_req_addr[c]      ),
      .core_req_meta_i       (cache_req_meta[c]      ),
      .core_req_write_i      (cache_req_write[c]     ),
      .core_req_wdata_i      (cache_req_data[c]      ),
      // Response
      .core_resp_valid_o     (cache_rsp_valid[c]     ),
      .core_resp_ready_i     (cache_rsp_ready[c]     ),
      .core_resp_write_o     (cache_rsp_write[c]     ),
      .core_resp_data_o      (cache_rsp_data[c]      ),
      .core_resp_meta_o      (cache_rsp_meta[c]      ),
      // AXI refill
      .axi_req_o             (l1_axi_mst_req[c]      ),
      .axi_resp_i            (l1_axi_mst_rsp[c]      ),
      // Tag Banks
      .tcdm_tag_bank_req_o   (l1_tag_bank_req[c]     ),
      .tcdm_tag_bank_we_o    (l1_tag_bank_we[c]      ),
      .tcdm_tag_bank_addr_o  (l1_tag_bank_addr[c]    ),
      .tcdm_tag_bank_wdata_o (l1_tag_bank_wdata[c]   ),
      .tcdm_tag_bank_be_o    (l1_tag_bank_be[c]      ),
      .tcdm_tag_bank_rdata_i (l1_tag_bank_rdata[c]   ),
      // Data Banks
      .tcdm_data_bank_req_o  (l1_data_bank_req[c]    ),
      .tcdm_data_bank_we_o   (l1_data_bank_w[c]      ),
      .tcdm_data_bank_addr_o (l1_data_bank_addr[c]   ),
      .tcdm_data_bank_wdata_o(l1_data_bank_wdata[c]  ),
      .tcdm_data_bank_be_o   (l1_data_bank_be[c]     ),
      .tcdm_data_bank_rdata_i(l1_data_bank_rdata[c]  ),
      .tcdm_data_bank_gnt_i  (l1_data_bank_gnt[c]    )
    );
  end



  /***************
   *  Registers  *
   ***************/


  /****************************
   *   Remote Interconnects   *
   ****************************/

  

  /**********************
   *   Local Intercos   *
   **********************/

  /*******************
   *   Core De/mux   *
   *******************/


  /****************
   *   AXI Plug   *
   ****************/


  /******************
   *   Assertions   *
   ******************/

  // Check invariants.
  if (BootAddr[1:0] != 2'b00)
    $fatal(1, "[cachepool_tile] Boot address should be aligned in a 4-byte boundary.");

  if (NumCoresPerTile != 2**$clog2(NumCoresPerTile))
    $fatal(1, "[cachepool_tile] The number of cores per tile must be a power of two.");

  if (NumCores != unsigned'(2**$clog2(NumCores)))
    $fatal(1, "[cachepool_tile] The number of cores must be a power of two.");

  if (NumBanksPerTile < 1)
    $fatal(1, "[cachepool_tile] The number of banks per tile must be larger than one");

  if (NumICaches != 1)
    $error("NumICaches > 1 is not supported!");

  if (DataWidth > AxiDataWidth)
    $error("AxiDataWidth needs to be larger than DataWidth!");

endmodule : cachepool_tile
