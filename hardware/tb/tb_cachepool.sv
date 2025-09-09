// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

import "DPI-C" function void read_elf (input string filename);
import "DPI-C" function byte get_section (output longint address, output longint len);
import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);
import "DPI-C" function int fesvr_tick();
import "DPI-C" function int get_entry_point();

`define wait_for(signal) \
  do \
    @(negedge clk); \
  while (!signal);

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "reqrsp_interface/typedef.svh"

module tb_cachepool;

  /*****************
   *  Definitions  *
   *****************/

  import cachepool_pkg::*;
  import spatz_cluster_peripheral_reg_pkg::*;
  import axi_pkg::xbar_cfg_t;
  import axi_pkg::xbar_rule_32_t;

  localparam ClockPeriod = 2.0ns;
  localparam TA          = 0.1ns;
  localparam TT          = 0.4ns;

  localparam PollEoc     = 0;

  /********************************
   *  Clock and Reset Generation  *
   ********************************/

  logic clk;
  logic rst_n;
  logic eoc;

  // Toggling the clock
  always #(ClockPeriod/2) clk = !clk;

  // Controlling the reset
  initial begin
    clk   = 1'b1;
    rst_n = 1'b0;

    repeat (5)
      #(ClockPeriod);

    rst_n = 1'b1;
  end


  /*********
   *  AXI  *
   *********/

  localparam NumAXISlaves = 2;
  localparam NumRules     = NumAXISlaves-1;

  // Spatz wide port to SoC (currently dram)
  spatz_axi_out_req_t  [NumL2Channel-1:0] axi_from_cluster_req;
  spatz_axi_out_resp_t [NumL2Channel-1:0] axi_from_cluster_resp;
  // From SoC to Spatz
  spatz_axi_in_req_t   axi_to_cluster_req;
  spatz_axi_in_resp_t  axi_to_cluster_resp;

  spatz_axi_narrow_req_t   axi_uart_req;
  spatz_axi_narrow_resp_t  axi_uart_rsp;

  // DRAM Scrambled request
  spatz_axi_out_req_t  [NumL2Channel-1:0] axi_dram_req;


  /*********
   *  DUT  *
   *********/

  logic cluster_probe;
  logic debug_req;

  cachepool_cluster_wrapper i_cluster_wrapper (
    .clk_i             (clk                   ),
    .rst_ni            (rst_n                 ),
    .eoc_o             (eoc                   ),
    .meip_i            ('0                    ),
    .msip_i            ('0                    ),
    .mtip_i            ('0                    ),
    .debug_req_i       (debug_req             ),
    .axi_out_req_o     (axi_from_cluster_req  ),
    .axi_out_resp_i    (axi_from_cluster_resp ),
    .axi_narrow_req_o  (axi_uart_req          ),
    .axi_narrow_resp_i (axi_uart_rsp          ),
    .axi_in_req_i      (axi_to_cluster_req    ),
    .axi_in_resp_o     (axi_to_cluster_resp   ),
    .cluster_probe_o   (cluster_probe         )
  );
/**************
 *  VCD Dump  *
 **************/

`ifdef VCD_DUMP
  initial begin: vcd_dump
    // Wait for the reset
    wait (rst_n);

    // Wait until the probe is high
    while (!cluster_probe)
      @(posedge clk);

    // Dump signals of group 0
    $dumpfile(`VCD_DUMP_FILE);
    $dumpvars(0, i_cluster_wrapper);
    $dumpon;

    // Wait until the probe is low
    while (cluster_probe)
      @(posedge clk);

    $dumpoff;

    // Stop the execution
    $finish(0);
  end: vcd_dump
`endif

  /************************
   *  Simulation control  *
   ************************/

  `REQRSP_TYPEDEF_ALL(reqrsp_cluster_in, axi_addr_t, logic [31:0], logic [3:0], tcdm_user_t)
  reqrsp_cluster_in_req_t to_cluster_req;
  reqrsp_cluster_in_rsp_t to_cluster_rsp;

  reqrsp_to_axi #(
    .DataWidth   (SpatzDataWidth         ),
    .AxiUserWidth(SpatzAxiUserWidth      ),
    .UserWidth   ($bits(tcdm_user_t)     ),
    .axi_req_t   (spatz_axi_in_req_t     ),
    .axi_rsp_t   (spatz_axi_in_resp_t    ),
    .reqrsp_req_t(reqrsp_cluster_in_req_t),
    .reqrsp_rsp_t(reqrsp_cluster_in_rsp_t)
  ) i_reqrsp_to_axi (
    .clk_i       (clk                ),
    .rst_ni      (rst_n              ),
    .user_i      ('0                 ),
    .axi_req_o   (axi_to_cluster_req ),
    .axi_rsp_i   (axi_to_cluster_resp),
    .reqrsp_req_i(to_cluster_req     ),
    .reqrsp_rsp_o(to_cluster_rsp     )
  );

  logic [31:0] entry_point;

  // Simulation Sequence
  initial begin
    automatic int exit_code;
    exit_code = fesvr_tick();
    // Idle
    to_cluster_req = '0;
    debug_req      = '0;

    // Wait for a while
    repeat (10)
      @(negedge clk);

    // Load the entry point
    entry_point = get_entry_point();
    $display("Loading entry point: %0x", entry_point);

    // Wait for a while
    repeat (1000)
      @(negedge clk);

    // Store the entry point in the Spatz cluster
    to_cluster_req = '{
      q: '{
        addr   : PeriStartAddr + SPATZ_CLUSTER_PERIPHERAL_CLUSTER_BOOT_CONTROL_OFFSET,
        data   : entry_point,
        write  : 1'b1,
        strb   : '1,
        amo    : reqrsp_pkg::AMONone,
        default: '0
      },
      q_valid: 1'b1,
      p_ready: 1'b0
    };
    `wait_for(to_cluster_rsp.q_ready);
    to_cluster_req = '0;
    `wait_for(to_cluster_rsp.p_valid);
    to_cluster_req = '{
      p_ready: 1'b1,
      q      : '{
        amo    : reqrsp_pkg::AMONone,
        default: '0
      },
      default: '0
    };
    @(negedge clk);
    to_cluster_req = '0;


    // Wake up cores
    debug_req = '1;
    @(negedge clk);
    debug_req = '0;

    // Wait for end of computing signal
    wait (eoc);
    $display("[EOC] Simulation ended at %t (retval = WIP).", $time);
    $finish(0);
  end

  /**********
  *  UART  *
  **********/

  axi_uart #(
    .axi_req_t (spatz_axi_narrow_req_t ),
    .axi_resp_t(spatz_axi_narrow_resp_t)
  ) i_axi_uart (
    .clk_i     (clk               ),
    .rst_ni    (rst_n             ),
    .testmode_i(1'b0              ),
    // TODO: connect correctly
    .axi_req_i (axi_uart_req      ),
    .axi_resp_o(axi_uart_rsp      )
  );

  /********
   *  L2  *
   ********/

  localparam int unsigned ConstantBits = $clog2(L2BankBeWidth * Interleave);
  localparam int unsigned ScrambleBits = (NumL2Channel == 1) ? 1 : $clog2(NumL2Channel);
  localparam int unsigned ReminderBits = SpatzAxiAddrWidth - ScrambleBits - ConstantBits;

  dram_sim_engine #(
    .ClkPeriod  (ClockPeriod )
  ) i_dram_engine (
    .clk_i      (clk  ),
    .rst_ni     (rst_n )
  );

  localparam int unsigned debug = 0;

  // DRAMSys Initialization
  for (genvar mem = 0; mem < NumL2Channel; mem++) begin : gen_drams_init
    initial begin : l2_init
      byte                              buffer [];
      axi_addr_t                        address;
      axi_addr_t                        length;
      string                            binary;
      // Initialize memories
      void'($value$plusargs("PRELOAD=%s", binary));

      #1;
      if (binary != "") begin
        // Read ELF
        read_elf(binary);
        $display("Loading %s", binary);
        while (get_section(address, length)) begin
          // Read sections
          // Align data to BankBeWidth
          automatic int nwords = (length + L2BankBeWidth - 1)/L2BankBeWidth;
          $display("Loading section %x of length %x", address, length);
          buffer = new[nwords * L2BankBeWidth];
          void'(read_section(address, buffer));
          if (address >= DramBase) begin
            for (int i = 0; i < nwords * L2BankBeWidth; i++) begin //per byte
              automatic dram_ctrl_interleave_t dram_ctrl_info;
              dram_ctrl_info = getDramCTRLInfo(address + i - DramBase);
              if (dram_ctrl_info.dram_ctrl_id == mem) begin
                gen_dram[mem].i_axi_dram_sim.i_sim_dram.load_a_byte_to_dram(dram_ctrl_info.dram_ctrl_addr, buffer[i]);
                if (debug == 1) begin
                  $display("putting data at %x into mem%x", dram_ctrl_info.dram_ctrl_addr, dram_ctrl_info.dram_ctrl_id);
                end
              end
            end
          end else begin
            $display("Cannot initialize address %x, which doesn't fall into the L2 DRAM region.", address);
          end
        end
      end
    end : l2_init
  end : gen_drams_init

  axi_addr_t [NumL2Channel-1:0] temp_addr_aw, temp_addr_ar;
  dram_ctrl_interleave_t [NumL2Channel-1:0] temp_dram_info_aw, temp_dram_info_ar;

  // DRAMSys address scrambling
  for (genvar ch = 0; ch < NumClusterSlv; ch ++) begin : gen_dram_scrambler
    always_comb begin
      axi_dram_req[ch]         = axi_from_cluster_req[ch];
      temp_addr_aw[ch]         = revertAddr(axi_from_cluster_req[ch].aw.addr);
      temp_addr_ar[ch]         = revertAddr(axi_from_cluster_req[ch].ar.addr);
      temp_dram_info_aw[ch]    = getDramCTRLInfo(temp_addr_aw[ch]);
      temp_dram_info_ar[ch]    = getDramCTRLInfo(temp_addr_ar[ch]);
      axi_dram_req[ch].aw.addr = temp_dram_info_aw[ch].dram_ctrl_addr;
      axi_dram_req[ch].ar.addr = temp_dram_info_ar[ch].dram_ctrl_addr;
    end
  end

  for (genvar mem = 0; mem < NumL2Channel; mem++) begin: gen_dram
    axi_dram_sim #(
      .BASE         ( DramBase                  ),
      .DRAMType     ( DramType                  ),
      .AxiAddrWidth ( SpatzAxiAddrWidth         ),
      .AxiDataWidth ( SpatzAxiDataWidth         ),
      .AxiIdWidth   ( SpatzAxiIdOutWidth        ),
      .AxiUserWidth ( SpatzAxiUserWidth         ),
      .axi_req_t    ( spatz_axi_out_req_t       ),
      .axi_resp_t   ( spatz_axi_out_resp_t      ),
      .axi_ar_t     ( spatz_axi_out_ar_chan_t   ),
      .axi_r_t      ( spatz_axi_out_r_chan_t    ),
      .axi_aw_t     ( spatz_axi_out_aw_chan_t   ),
      .axi_w_t      ( spatz_axi_out_w_chan_t    ),
      .axi_b_t      ( spatz_axi_out_b_chan_t    )
    ) i_axi_dram_sim (
      .clk_i        ( clk                       ),
      .rst_ni       ( rst_n                     ),
      .axi_req_i    ( axi_dram_req [mem]        ),
      .axi_resp_o   ( axi_from_cluster_resp[mem])
    );
  end

endmodule : tb_cachepool
