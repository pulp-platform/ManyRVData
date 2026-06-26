// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Diyou Shen <dishen@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Simulation-only, central performance/session monitor for CachePool.
/// Instantiated as a sibling of the DUT at the testbench level and reaches
/// into it purely via hierarchical (cross-module) references, so none of
/// this needs to be threaded through the synthesizable RTL.
///
/// The whole run is split into "sessions" delimited by edges of
/// cluster_probe_i (the SPATZ_CLUSTER_PROBE peripheral bit toggled by
/// start_kernel()/stop_kernel() in software): each edge closes the current
/// session (dumped to file) and opens a new one.
module cachepool_monitor
  import cachepool_pkg::*;
(
  input logic clk_i,
  input logic rst_ni,
  input logic cluster_probe_i
);

`ifndef TARGET_SYNTHESIS
  typedef logic [31:0] cnt_t;

  `define TILE_PATH(gy, gx, t) \
    i_cluster_wrapper.i_cluster.gen_group_y[gy].gen_group_x[gx].i_group.i_group.gen_tiles[t].gen_tile.i_tile

  `define CC_PATH(gy, gx, t, c) \
    `TILE_PATH(gy, gx, t).gen_core[c].i_cachepool_cc

  `define CLUSTER_PATH i_cluster_wrapper.i_cluster

  // ---------------------------------------------------------------------
  // Session bookkeeping shared by every sub-monitor below.
  // ---------------------------------------------------------------------
  logic probe_q;
  `FF(probe_q, cluster_probe_i, 1'b0)
  logic session_edge;
  assign session_edge = cluster_probe_i ^ probe_q;

  cnt_t session_idx_d, session_idx_q;
  assign session_idx_d = session_edge ? session_idx_q + 1 : session_idx_q;
  `FF(session_idx_q, session_idx_d, '0)

  cnt_t cycle_d, cycle_q;
  assign cycle_d = cycle_q + 1;
  `FF(cycle_q, cycle_d, '0)

  cnt_t session_start_cycle_d, session_start_cycle_q;
  assign session_start_cycle_d = session_edge ? cycle_q : session_start_cycle_q;
  `FF(session_start_cycle_q, session_start_cycle_d, '0)

  // Labels a session by whether cluster_probe was high (a kernel actually
  // running) or low (idle/setup time) during it. At the moment session_edge
  // fires, probe_q still holds the phase of the session that just closed;
  // for the trailing/incomplete session dumped from `final`, use the live
  // cluster_probe_i instead since no edge has fired to register it yet.
  function automatic string session_tag(input logic phase, input bit is_final);
    session_tag = is_final ? (phase ? "kernel-final" : "idle-final")
                           : (phase ? "kernel"       : "idle");
  endfunction

  // ---------------------------------------------------------------------
  // Per-(group, tile) Traffic Locality Monitor.
  // Counts accepted TCDM requests per port slot, classified by the
  // interco's own routing decision: local cache bank / local-group /
  // remote-group (inter-group L1 NoC).
  // ---------------------------------------------------------------------
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_mon_gy
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_mon_gx
      for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_mon_tile

        cnt_t [NrTCDMPortsPerCore-1:0] local_cnt_d,  local_cnt_q;
        cnt_t [NrTCDMPortsPerCore-1:0] group_cnt_d,  group_cnt_q;
        cnt_t [NrTCDMPortsPerCore-1:0] remote_cnt_d, remote_cnt_q;
        `FF(local_cnt_q,  local_cnt_d,  '0)
        `FF(group_cnt_q,  group_cnt_d,  '0)
        `FF(remote_cnt_q, remote_cnt_d, '0)

        // Congestion: cycles a request sat with q_valid asserted (accepted
        // or not). avg_acceptance_cycle = valid_cyc / accepted_cnt, mirroring
        // spatz_vlsu.sv's existing "Mem AVG Req Accept Cycles" metric.
        cnt_t [NrTCDMPortsPerCore-1:0] local_valid_cyc_d,  local_valid_cyc_q;
        cnt_t [NrTCDMPortsPerCore-1:0] group_valid_cyc_d,  group_valid_cyc_q;
        cnt_t [NrTCDMPortsPerCore-1:0] remote_valid_cyc_d, remote_valid_cyc_q;
        `FF(local_valid_cyc_q,  local_valid_cyc_d,  '0)
        `FF(group_valid_cyc_q,  group_valid_cyc_d,  '0)
        `FF(remote_valid_cyc_q, remote_valid_cyc_d, '0)

        for (genvar j = 0; j < NrTCDMPortsPerCore; j++) begin : gen_mon_port
          always_comb begin
            automatic cnt_t local_inc, group_inc, local_valid_inc, group_valid_inc;
            local_inc       = '0;
            group_inc       = '0;
            local_valid_inc = '0;
            group_valid_inc = '0;

            for (int unsigned cb = 0; cb < NumL1CtrlTile; cb++) begin
              if (`TILE_PATH(gy, gx, t).cache_xbar_req[j][cb].q_valid) begin
                local_valid_inc++;
                if (`TILE_PATH(gy, gx, t).cache_xbar_rsp[j][cb].q_ready)
                  local_inc++;
              end
            end

            for (int unsigned r = 0; r < NumRemotePortCore; r++) begin
              if (`TILE_PATH(gy, gx, t).gen_cache_xbar[j].xbar_remote_req_o[r].q_valid) begin
                group_valid_inc++;
                if (`TILE_PATH(gy, gx, t).gen_cache_xbar[j].xbar_remote_rsp_i[r].q_ready)
                  group_inc++;
              end
            end

            local_cnt_d[j]       = session_edge ? '0 : local_cnt_q[j]       + local_inc;
            group_cnt_d[j]       = session_edge ? '0 : group_cnt_q[j]       + group_inc;
            local_valid_cyc_d[j] = session_edge ? '0 : local_valid_cyc_q[j] + local_valid_inc;
            group_valid_cyc_d[j] = session_edge ? '0 : group_valid_cyc_q[j] + group_valid_inc;
          end

          if (NumRemoteGroupPortCore > 0) begin : gen_mon_remote
            always_comb begin
              automatic cnt_t remote_inc, remote_valid_inc;
              remote_inc       = '0;
              remote_valid_inc = '0;
              for (int unsigned r = 0; r < NumRemoteGroupPortCore; r++) begin
                if (`TILE_PATH(gy, gx, t).gen_cache_xbar[j].gen_remote_group_slice.xbar_remote_group_out_req[r].q_valid) begin
                  remote_valid_inc++;
                  if (`TILE_PATH(gy, gx, t).gen_cache_xbar[j].gen_remote_group_slice.xbar_remote_group_out_rsp[r].q_ready)
                    remote_inc++;
                end
              end
              remote_cnt_d[j]       = session_edge ? '0 : remote_cnt_q[j]       + remote_inc;
              remote_valid_cyc_d[j] = session_edge ? '0 : remote_valid_cyc_q[j] + remote_valid_inc;
            end
          end else begin : gen_mon_no_remote
            assign remote_cnt_d[j]       = session_edge ? '0 : remote_cnt_q[j];
            assign remote_valid_cyc_d[j] = session_edge ? '0 : remote_valid_cyc_q[j];
          end
        end

        int    tile_f;
        string tile_f_name;

        initial begin
          @(posedge clk_i);
          $sformat(tile_f_name, "sim/bin/logs/others/monitor_tile_traffic_g%0d_%0d_t%0d.txt", gy, gx, t);
          tile_f = $fopen(tile_f_name, "w");
        end

        // A function (never a task) so it can legally be called from the
        // `final` block below: functions cannot contain timing controls by
        // construction, so simulators never warn about calling them there.
        function automatic void dump_tile_session(input cnt_t idx, input string tag);
          $fwrite(tile_f, "*** Session %0d (%s): cycles [%0d, %0d) ***\n",
                  idx, tag, session_start_cycle_q, cycle_q);
          for (int unsigned j = 0; j < NrTCDMPortsPerCore; j++) begin
            automatic real tot     = local_cnt_q[j] + group_cnt_q[j] + remote_cnt_q[j];
            automatic real l_pct   = tot == 0 ? 0 : 100 * local_cnt_q[j]  / tot;
            automatic real g_pct   = tot == 0 ? 0 : 100 * group_cnt_q[j]  / tot;
            automatic real r_pct   = tot == 0 ? 0 : 100 * remote_cnt_q[j] / tot;
            automatic real l_avg   = local_cnt_q[j]  == 0 ? 0 : real'(local_valid_cyc_q[j])  / real'(local_cnt_q[j]);
            automatic real g_avg   = group_cnt_q[j]  == 0 ? 0 : real'(group_valid_cyc_q[j])  / real'(group_cnt_q[j]);
            automatic real r_avg   = remote_cnt_q[j] == 0 ? 0 : real'(remote_valid_cyc_q[j]) / real'(remote_cnt_q[j]);
            $fwrite(tile_f, "   Port %0d: local=%0d (%0.2f%%)  group=%0d (%0.2f%%)  remote=%0d (%0.2f%%)\n",
                    j, local_cnt_q[j], l_pct, group_cnt_q[j], g_pct, remote_cnt_q[j], r_pct);
            $fwrite(tile_f, "            avg req accept cycles: local=%0.2f  group=%0.2f  remote=%0.2f\n",
                    l_avg, g_avg, r_avg);
          end
          $fwrite(tile_f, "\n");
        endfunction

        always_ff @(posedge clk_i) begin
          if (session_edge) dump_tile_session(session_idx_q, session_tag(probe_q, 1'b0));
        end

        final begin
          dump_tile_session(session_idx_q, session_tag(cluster_probe_i, 1'b1));
          $fclose(tile_f);
        end
      end
    end
  end

  // ---------------------------------------------------------------------
  // L1 Inter-Group NoC Monitor.
  // Cluster-level mesh-link handshakes (noc_req/rsp_out/in), aggregated per
  // group per direction across all NumTilesPerGroup*NumNoCPortsPerTile
  // parallel tile-links sharing that direction. One router pair exists per
  // (group, direction, tile-port) inside cachepool_group_noc_wrapper.sv, but
  // these cluster-level arrays already carry the same valid/ready handshake
  // without needing to reach inside the router instances.
  // Direction index (floo_pkg order): 0=North, 1=East, 2=South, 3=West.
  // "out" = this group sending on that link, "in" = this group receiving.
  // ---------------------------------------------------------------------
  localparam int unsigned NumNoCLinkPorts = NumTilesPerGroup * NumNoCPortsPerTile;

  for (genvar g = 0; g < NumGroups; g++) begin : gen_l1noc_g
    cnt_t [3:0] req_out_cnt_d,  req_out_cnt_q,  req_out_vcyc_d,  req_out_vcyc_q;
    cnt_t [3:0] req_in_cnt_d,   req_in_cnt_q,   req_in_vcyc_d,   req_in_vcyc_q;
    cnt_t [3:0] rsp_out_cnt_d,  rsp_out_cnt_q,  rsp_out_vcyc_d,  rsp_out_vcyc_q;
    cnt_t [3:0] rsp_in_cnt_d,   rsp_in_cnt_q,   rsp_in_vcyc_d,   rsp_in_vcyc_q;
    `FF(req_out_cnt_q,  req_out_cnt_d,  '0)
    `FF(req_out_vcyc_q, req_out_vcyc_d, '0)
    `FF(req_in_cnt_q,   req_in_cnt_d,   '0)
    `FF(req_in_vcyc_q,  req_in_vcyc_d,  '0)
    `FF(rsp_out_cnt_q,  rsp_out_cnt_d,  '0)
    `FF(rsp_out_vcyc_q, rsp_out_vcyc_d, '0)
    `FF(rsp_in_cnt_q,   rsp_in_cnt_d,   '0)
    `FF(rsp_in_vcyc_q,  rsp_in_vcyc_d,  '0)

    for (genvar dir = 0; dir < 4; dir++) begin : gen_l1noc_dir
      always_comb begin
        automatic cnt_t ro_c, ro_v, ri_c, ri_v, so_c, so_v, si_c, si_v;
        ro_c = '0; ro_v = '0; ri_c = '0; ri_v = '0;
        so_c = '0; so_v = '0; si_c = '0; si_v = '0;
        for (int unsigned p = 0; p < NumNoCLinkPorts; p++) begin
          if (`CLUSTER_PATH.noc_req_out_valid[g][dir][p]) begin
            ro_v++;
            if (`CLUSTER_PATH.noc_req_out_ready[g][dir][p]) ro_c++;
          end
          if (`CLUSTER_PATH.noc_req_in_valid[g][dir][p]) begin
            ri_v++;
            if (`CLUSTER_PATH.noc_req_in_ready[g][dir][p]) ri_c++;
          end
          if (`CLUSTER_PATH.noc_rsp_out_valid[g][dir][p]) begin
            so_v++;
            if (`CLUSTER_PATH.noc_rsp_out_ready[g][dir][p]) so_c++;
          end
          if (`CLUSTER_PATH.noc_rsp_in_valid[g][dir][p]) begin
            si_v++;
            if (`CLUSTER_PATH.noc_rsp_in_ready[g][dir][p]) si_c++;
          end
        end
        req_out_cnt_d[dir]  = session_edge ? '0 : req_out_cnt_q[dir]  + ro_c;
        req_out_vcyc_d[dir] = session_edge ? '0 : req_out_vcyc_q[dir] + ro_v;
        req_in_cnt_d[dir]   = session_edge ? '0 : req_in_cnt_q[dir]   + ri_c;
        req_in_vcyc_d[dir]  = session_edge ? '0 : req_in_vcyc_q[dir]  + ri_v;
        rsp_out_cnt_d[dir]  = session_edge ? '0 : rsp_out_cnt_q[dir]  + so_c;
        rsp_out_vcyc_d[dir] = session_edge ? '0 : rsp_out_vcyc_q[dir] + so_v;
        rsp_in_cnt_d[dir]   = session_edge ? '0 : rsp_in_cnt_q[dir]   + si_c;
        rsp_in_vcyc_d[dir]  = session_edge ? '0 : rsp_in_vcyc_q[dir]  + si_v;
      end
    end

    int    l1noc_f;
    string l1noc_f_name;

    initial begin
      @(posedge clk_i);
      $sformat(l1noc_f_name, "sim/bin/logs/noc/monitor_l1noc_g%0d.txt", g);
      l1noc_f = $fopen(l1noc_f_name, "w");
    end

    function automatic void dump_l1noc_session(input cnt_t idx, input string tag);
      automatic string dir_name [4] = '{"North", "East", "South", "West"};
      $fwrite(l1noc_f, "*** Session %0d (%s): cycles [%0d, %0d) ***\n",
              idx, tag, session_start_cycle_q, cycle_q);
      for (int unsigned dir = 0; dir < 4; dir++) begin
        automatic real ro_avg = req_out_cnt_q[dir] == 0 ? 0 : real'(req_out_vcyc_q[dir]) / real'(req_out_cnt_q[dir]);
        automatic real ri_avg = req_in_cnt_q[dir]  == 0 ? 0 : real'(req_in_vcyc_q[dir])  / real'(req_in_cnt_q[dir]);
        automatic real so_avg = rsp_out_cnt_q[dir] == 0 ? 0 : real'(rsp_out_vcyc_q[dir]) / real'(rsp_out_cnt_q[dir]);
        automatic real si_avg = rsp_in_cnt_q[dir]  == 0 ? 0 : real'(rsp_in_vcyc_q[dir])  / real'(rsp_in_cnt_q[dir]);
        $fwrite(l1noc_f, "   %s:\n", dir_name[dir]);
        $fwrite(l1noc_f, "     REQ out: accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                req_out_cnt_q[dir], req_out_vcyc_q[dir], ro_avg);
        $fwrite(l1noc_f, "     REQ in : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                req_in_cnt_q[dir], req_in_vcyc_q[dir], ri_avg);
        $fwrite(l1noc_f, "     RSP out: accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                rsp_out_cnt_q[dir], rsp_out_vcyc_q[dir], so_avg);
        $fwrite(l1noc_f, "     RSP in : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                rsp_in_cnt_q[dir], rsp_in_vcyc_q[dir], si_avg);
      end
      $fwrite(l1noc_f, "\n");
    endfunction

    always_ff @(posedge clk_i) begin
      if (session_edge) dump_l1noc_session(session_idx_q, session_tag(probe_q, 1'b0));
    end

    final begin
      dump_l1noc_session(session_idx_q, session_tag(cluster_probe_i, 1'b1));
      $fclose(l1noc_f);
    end
  end

  // ---------------------------------------------------------------------
  // L2 (DRAM) NoC Monitor.
  // Cluster-level mesh-link handshakes (l2_req/rsp_out/in). Unlike L1, one
  // router pair exists per group (not per tile), so there is no port
  // dimension to aggregate over. Direction index matches L1: 0=North,
  // 1=East, 2=South, 3=West.
  // ---------------------------------------------------------------------
  for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2noc_gx
    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_l2noc_gy

      cnt_t [3:0] req_out_cnt_d,  req_out_cnt_q,  req_out_vcyc_d,  req_out_vcyc_q;
      cnt_t [3:0] req_in_cnt_d,   req_in_cnt_q,   req_in_vcyc_d,   req_in_vcyc_q;
      cnt_t [3:0] rsp_out_cnt_d,  rsp_out_cnt_q,  rsp_out_vcyc_d,  rsp_out_vcyc_q;
      cnt_t [3:0] rsp_in_cnt_d,   rsp_in_cnt_q,   rsp_in_vcyc_d,   rsp_in_vcyc_q;
      `FF(req_out_cnt_q,  req_out_cnt_d,  '0)
      `FF(req_out_vcyc_q, req_out_vcyc_d, '0)
      `FF(req_in_cnt_q,   req_in_cnt_d,   '0)
      `FF(req_in_vcyc_q,  req_in_vcyc_d,  '0)
      `FF(rsp_out_cnt_q,  rsp_out_cnt_d,  '0)
      `FF(rsp_out_vcyc_q, rsp_out_vcyc_d, '0)
      `FF(rsp_in_cnt_q,   rsp_in_cnt_d,   '0)
      `FF(rsp_in_vcyc_q,  rsp_in_vcyc_d,  '0)

      for (genvar dir = 0; dir < 4; dir++) begin : gen_l2noc_dir
        always_comb begin
          automatic cnt_t ro_c, ro_v, ri_c, ri_v, so_c, so_v, si_c, si_v;
          ro_c = '0; ro_v = '0; ri_c = '0; ri_v = '0;
          so_c = '0; so_v = '0; si_c = '0; si_v = '0;
          if (`CLUSTER_PATH.l2_req_out_valid[gx][gy][dir]) begin
            ro_v = 1;
            if (`CLUSTER_PATH.l2_req_out_ready[gx][gy][dir]) ro_c = 1;
          end
          if (`CLUSTER_PATH.l2_req_in_valid[gx][gy][dir]) begin
            ri_v = 1;
            if (`CLUSTER_PATH.l2_req_in_ready[gx][gy][dir]) ri_c = 1;
          end
          if (`CLUSTER_PATH.l2_rsp_out_valid[gx][gy][dir]) begin
            so_v = 1;
            if (`CLUSTER_PATH.l2_rsp_out_ready[gx][gy][dir]) so_c = 1;
          end
          if (`CLUSTER_PATH.l2_rsp_in_valid[gx][gy][dir]) begin
            si_v = 1;
            if (`CLUSTER_PATH.l2_rsp_in_ready[gx][gy][dir]) si_c = 1;
          end
          req_out_cnt_d[dir]  = session_edge ? '0 : req_out_cnt_q[dir]  + ro_c;
          req_out_vcyc_d[dir] = session_edge ? '0 : req_out_vcyc_q[dir] + ro_v;
          req_in_cnt_d[dir]   = session_edge ? '0 : req_in_cnt_q[dir]   + ri_c;
          req_in_vcyc_d[dir]  = session_edge ? '0 : req_in_vcyc_q[dir]  + ri_v;
          rsp_out_cnt_d[dir]  = session_edge ? '0 : rsp_out_cnt_q[dir]  + so_c;
          rsp_out_vcyc_d[dir] = session_edge ? '0 : rsp_out_vcyc_q[dir] + so_v;
          rsp_in_cnt_d[dir]   = session_edge ? '0 : rsp_in_cnt_q[dir]   + si_c;
          rsp_in_vcyc_d[dir]  = session_edge ? '0 : rsp_in_vcyc_q[dir]  + si_v;
        end
      end

      int    l2noc_f;
      string l2noc_f_name;

      initial begin
        @(posedge clk_i);
        $sformat(l2noc_f_name, "sim/bin/logs/noc/monitor_l2noc_g%0d_%0d.txt", gx, gy);
        l2noc_f = $fopen(l2noc_f_name, "w");
      end

      function automatic void dump_l2noc_session(input cnt_t idx, input string tag);
        automatic string dir_name [4] = '{"North", "East", "South", "West"};
        $fwrite(l2noc_f, "*** Session %0d (%s): cycles [%0d, %0d) ***\n",
                idx, tag, session_start_cycle_q, cycle_q);
        for (int unsigned dir = 0; dir < 4; dir++) begin
          automatic real ro_avg = req_out_cnt_q[dir] == 0 ? 0 : real'(req_out_vcyc_q[dir]) / real'(req_out_cnt_q[dir]);
          automatic real ri_avg = req_in_cnt_q[dir]  == 0 ? 0 : real'(req_in_vcyc_q[dir])  / real'(req_in_cnt_q[dir]);
          automatic real so_avg = rsp_out_cnt_q[dir] == 0 ? 0 : real'(rsp_out_vcyc_q[dir]) / real'(rsp_out_cnt_q[dir]);
          automatic real si_avg = rsp_in_cnt_q[dir]  == 0 ? 0 : real'(rsp_in_vcyc_q[dir])  / real'(rsp_in_cnt_q[dir]);
          $fwrite(l2noc_f, "   %s:\n", dir_name[dir]);
          $fwrite(l2noc_f, "     REQ out: accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                  req_out_cnt_q[dir], req_out_vcyc_q[dir], ro_avg);
          $fwrite(l2noc_f, "     REQ in : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                  req_in_cnt_q[dir], req_in_vcyc_q[dir], ri_avg);
          $fwrite(l2noc_f, "     RSP out: accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                  rsp_out_cnt_q[dir], rsp_out_vcyc_q[dir], so_avg);
          $fwrite(l2noc_f, "     RSP in : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n",
                  rsp_in_cnt_q[dir], rsp_in_vcyc_q[dir], si_avg);
        end
        $fwrite(l2noc_f, "\n");
      endfunction

      always_ff @(posedge clk_i) begin
        if (session_edge) dump_l2noc_session(session_idx_q, session_tag(probe_q, 1'b0));
      end

      final begin
        dump_l2noc_session(session_idx_q, session_tag(cluster_probe_i, 1'b1));
        $fclose(l2noc_f);
      end
    end
  end

  // ---------------------------------------------------------------------
  // L2 DRAM Channel Monitor.
  // Per-HBM-channel AXI congestion at the DRAM endpoint, one level beyond
  // the L2 NoC mesh above: taps tb_cachepool.sv's own axi_dram_req/
  // axi_from_cluster_resp arrays (the AXI req/resp feeding each
  // axi_dram_sim instance), so it shows whether the NoC or the DRAM model
  // itself is the bottleneck.
  // ---------------------------------------------------------------------
  for (genvar mem = 0; mem < NumL2Channel; mem++) begin : gen_dram_mon

    cnt_t aw_cnt_d, aw_cnt_q, aw_vcyc_d, aw_vcyc_q;
    cnt_t ar_cnt_d, ar_cnt_q, ar_vcyc_d, ar_vcyc_q;
    cnt_t w_cnt_d,  w_cnt_q,  w_vcyc_d,  w_vcyc_q;
    cnt_t r_cnt_d,  r_cnt_q,  r_vcyc_d,  r_vcyc_q;
    cnt_t b_cnt_d,  b_cnt_q,  b_vcyc_d,  b_vcyc_q;
    `FF(aw_cnt_q, aw_cnt_d, '0)  `FF(aw_vcyc_q, aw_vcyc_d, '0)
    `FF(ar_cnt_q, ar_cnt_d, '0)  `FF(ar_vcyc_q, ar_vcyc_d, '0)
    `FF(w_cnt_q,  w_cnt_d,  '0)  `FF(w_vcyc_q,  w_vcyc_d,  '0)
    `FF(r_cnt_q,  r_cnt_d,  '0)  `FF(r_vcyc_q,  r_vcyc_d,  '0)
    `FF(b_cnt_q,  b_cnt_d,  '0)  `FF(b_vcyc_q,  b_vcyc_d,  '0)

    always_comb begin
      automatic cnt_t aw_c, aw_v, ar_c, ar_v, w_c, w_v, r_c, r_v, b_c, b_v;
      aw_c = '0; aw_v = '0; ar_c = '0; ar_v = '0; w_c = '0;
      w_v  = '0; r_c  = '0; r_v  = '0; b_c  = '0; b_v  = '0;

      if ($root.tb_cachepool.axi_dram_req[mem].aw_valid) begin
        aw_v = 1;
        if ($root.tb_cachepool.axi_from_cluster_resp[mem].aw_ready) aw_c = 1;
      end
      if ($root.tb_cachepool.axi_dram_req[mem].ar_valid) begin
        ar_v = 1;
        if ($root.tb_cachepool.axi_from_cluster_resp[mem].ar_ready) ar_c = 1;
      end
      if ($root.tb_cachepool.axi_dram_req[mem].w_valid) begin
        w_v = 1;
        if ($root.tb_cachepool.axi_from_cluster_resp[mem].w_ready) w_c = 1;
      end
      if ($root.tb_cachepool.axi_from_cluster_resp[mem].r_valid) begin
        r_v = 1;
        if ($root.tb_cachepool.axi_dram_req[mem].r_ready) r_c = 1;
      end
      if ($root.tb_cachepool.axi_from_cluster_resp[mem].b_valid) begin
        b_v = 1;
        if ($root.tb_cachepool.axi_dram_req[mem].b_ready) b_c = 1;
      end

      aw_cnt_d  = session_edge ? '0 : aw_cnt_q  + aw_c;
      aw_vcyc_d = session_edge ? '0 : aw_vcyc_q + aw_v;
      ar_cnt_d  = session_edge ? '0 : ar_cnt_q  + ar_c;
      ar_vcyc_d = session_edge ? '0 : ar_vcyc_q + ar_v;
      w_cnt_d   = session_edge ? '0 : w_cnt_q   + w_c;
      w_vcyc_d  = session_edge ? '0 : w_vcyc_q  + w_v;
      r_cnt_d   = session_edge ? '0 : r_cnt_q   + r_c;
      r_vcyc_d  = session_edge ? '0 : r_vcyc_q  + r_v;
      b_cnt_d   = session_edge ? '0 : b_cnt_q   + b_c;
      b_vcyc_d  = session_edge ? '0 : b_vcyc_q  + b_v;
    end

    int    dram_f;
    string dram_f_name;

    initial begin
      @(posedge clk_i);
      $sformat(dram_f_name, "sim/bin/logs/noc/monitor_dram_ch%0d.txt", mem);
      dram_f = $fopen(dram_f_name, "w");
    end

    function automatic void dump_dram_session(input cnt_t idx, input string tag);
      automatic real aw_avg = aw_cnt_q == 0 ? 0 : real'(aw_vcyc_q) / real'(aw_cnt_q);
      automatic real ar_avg = ar_cnt_q == 0 ? 0 : real'(ar_vcyc_q) / real'(ar_cnt_q);
      automatic real w_avg  = w_cnt_q  == 0 ? 0 : real'(w_vcyc_q)  / real'(w_cnt_q);
      automatic real r_avg  = r_cnt_q  == 0 ? 0 : real'(r_vcyc_q)  / real'(r_cnt_q);
      automatic real b_avg  = b_cnt_q  == 0 ? 0 : real'(b_vcyc_q)  / real'(b_cnt_q);
      $fwrite(dram_f, "*** Session %0d (%s): cycles [%0d, %0d) ***\n",
              idx, tag, session_start_cycle_q, cycle_q);
      $fwrite(dram_f, "   AW: accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n", aw_cnt_q, aw_vcyc_q, aw_avg);
      $fwrite(dram_f, "   AR: accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n", ar_cnt_q, ar_vcyc_q, ar_avg);
      $fwrite(dram_f, "   W : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n", w_cnt_q,  w_vcyc_q,  w_avg);
      $fwrite(dram_f, "   R : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n", r_cnt_q,  r_vcyc_q,  r_avg);
      $fwrite(dram_f, "   B : accepted=%0d  valid_cyc=%0d  avg_accept_cyc=%0.2f\n", b_cnt_q,  b_vcyc_q,  b_avg);
      $fwrite(dram_f, "\n");
    endfunction

    always_ff @(posedge clk_i) begin
      if (session_edge) dump_dram_session(session_idx_q, session_tag(probe_q, 1'b0));
    end

    final begin
      dump_dram_session(session_idx_q, session_tag(cluster_probe_i, 1'b1));
      $fclose(dram_f);
    end
  end

  // ---------------------------------------------------------------------
  // Per-core Monitor: one unified, session-cut report merging the VLSU
  // Load Latency Monitor with the Spatz Controller/VLSU/VFU Utilization
  // Report (migrated from cachepool_cc.sv). All the underlying counters
  // inside spatz_controller.sv/spatz_vlsu.sv/spatz_vfu.sv are cumulative
  // (never reset); a single struct snapshot is taken at every session edge
  // and every printed number is the delta against that snapshot — i.e. that
  // session's own stats, not the whole run's.
  //
  // Exception: ROB peak utilization is a running maximum, not an additive
  // counter, so a delta of two peaks would be meaningless. It is reported
  // as-is (the peak reached so far over the whole run, not session-local),
  // and clearly labeled below.
  // ---------------------------------------------------------------------
  typedef struct packed {
    cnt_t [2:0] ctrl_wvalid;    // [0]=VFU [1]=VLSU [2]=VSLDU
    cnt_t [2:0] ctrl_wtrans;
    cnt_t ctrl_vlsu_insn, ctrl_vlsu_stall, ctrl_vlsu_active;
    cnt_t ctrl_vfu_insn,  ctrl_vfu_stall,  ctrl_vfu_active;
    cnt_t ctrl_vsldu_insn, ctrl_vsldu_stall, ctrl_vsldu_active;
    cnt_t vlsu_wvalid, vlsu_wtrans;
    cnt_t vlsu_mem_valid, vlsu_mem_trans;
    cnt_t vlsu_rob_usage, vlsu_rob_use_cyc, vlsu_rob_full_cyc;
    cnt_t vlsu_insn_valid_cyc, vlsu_insn_cnt;
    cnt_t vlsu_load_lat_sum, vlsu_load_lat_cnt;
    cnt_t vfu_wvalid, vfu_wtrans;
    cnt_t [2:0] vfu_rvalid;
    cnt_t [2:0] vfu_rtrans;
    cnt_t vfu_insn_valid_cyc, vfu_insn_cnt;
  } spatz_stats_t;

  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_core_gy
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_core_gx
      for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_core_tile
        for (genvar c = 0; c < NumCoresTile; c++) begin : gen_core_core

          // Reads every cumulative Spatz counter for this core in one shot.
          function automatic spatz_stats_t read_spatz_stats();
            read_spatz_stats.ctrl_wvalid[0] = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_wvalid_cnt_q[0];
            read_spatz_stats.ctrl_wvalid[1] = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_wvalid_cnt_q[1];
            read_spatz_stats.ctrl_wvalid[2] = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_wvalid_cnt_q[2];
            read_spatz_stats.ctrl_wtrans[0] = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_wtrans_cnt_q[0];
            read_spatz_stats.ctrl_wtrans[1] = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_wtrans_cnt_q[1];
            read_spatz_stats.ctrl_wtrans[2] = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_wtrans_cnt_q[2];

            read_spatz_stats.ctrl_vlsu_insn   = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vlsu_insn_q;
            read_spatz_stats.ctrl_vlsu_stall  = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vlsu_stall_q;
            read_spatz_stats.ctrl_vlsu_active = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vlsu_active_q;
            read_spatz_stats.ctrl_vfu_insn    = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vfu_insn_q;
            read_spatz_stats.ctrl_vfu_stall   = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vfu_stall_q;
            read_spatz_stats.ctrl_vfu_active  = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vfu_active_q;
            read_spatz_stats.ctrl_vsldu_insn   = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vsldu_insn_q;
            read_spatz_stats.ctrl_vsldu_stall  = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vsldu_stall_q;
            read_spatz_stats.ctrl_vsldu_active = `CC_PATH(gy, gx, t, c).i_spatz.i_controller.ctrl_vsldu_active_q;

            read_spatz_stats.vlsu_wvalid = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.vrf_wvalid_cnt_q;
            read_spatz_stats.vlsu_wtrans = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.vrf_wtrans_cnt_q;
            read_spatz_stats.vlsu_mem_valid = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.mem_valid_cnt_q;
            read_spatz_stats.vlsu_mem_trans = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.mem_trans_cnt_q;
            read_spatz_stats.vlsu_rob_usage    = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.rob_usage_q;
            read_spatz_stats.vlsu_rob_use_cyc  = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.rob_use_cyc_q;
            read_spatz_stats.vlsu_rob_full_cyc = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.rob_full_cyc_q;
            read_spatz_stats.vlsu_insn_valid_cyc = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.vlsu_insn_valid_cyc_q;
            read_spatz_stats.vlsu_insn_cnt       = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.vlsu_insn_cnt_q;
            read_spatz_stats.vlsu_load_lat_sum = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.load_lat_sum_q;
            read_spatz_stats.vlsu_load_lat_cnt = `CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.load_lat_cnt_q;

            read_spatz_stats.vfu_wvalid = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_wvalid_cnt_q;
            read_spatz_stats.vfu_wtrans = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_wtrans_cnt_q;
            read_spatz_stats.vfu_rvalid[0] = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_rvalid_cnt_q[0];
            read_spatz_stats.vfu_rvalid[1] = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_rvalid_cnt_q[1];
            read_spatz_stats.vfu_rvalid[2] = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_rvalid_cnt_q[2];
            read_spatz_stats.vfu_rtrans[0] = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_rtrans_cnt_q[0];
            read_spatz_stats.vfu_rtrans[1] = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_rtrans_cnt_q[1];
            read_spatz_stats.vfu_rtrans[2] = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vrf_rtrans_cnt_q[2];
            read_spatz_stats.vfu_insn_valid_cyc = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vfu_insn_valid_cyc_q;
            read_spatz_stats.vfu_insn_cnt       = `CC_PATH(gy, gx, t, c).i_spatz.i_vfu.vfu_insn_cnt_q;
          endfunction

          spatz_stats_t stats_base_d, stats_base_q;
          `FF(stats_base_q, stats_base_d, '0)
          assign stats_base_d = session_edge ? read_spatz_stats() : stats_base_q;

          int    core_f;
          string core_f_name;

          initial begin
            @(posedge clk_i);
            $sformat(core_f_name, "sim/bin/logs/core/monitor_core_g%0d_%0d_t%0d_c%0d.txt", gy, gx, t, c);
            core_f = $fopen(core_f_name, "w");
          end

          // A function (never a task), see dump_tile_session above for why.
          function automatic void dump_core_session(input cnt_t idx, input string tag);
            automatic spatz_stats_t now = read_spatz_stats();
            automatic spatz_stats_t d;
            automatic real load_lat_avg, ctrl_vlsu_wstall, ctrl_vfu_wstall, ctrl_vsldu_wstall;
            automatic real vlsu_vrf_w_util, vlsu_vrf_w_avg_cyc, vlsu_mem_util, vlsu_mem_avg_cyc;
            automatic real vlsu_rob_usage_avg, vlsu_rob_peak_util, vlsu_avg_insn_cyc;
            automatic real vfu_vrf_w_util, vfu_vrf_w_avg_cyc, vfu_avg_insn_cyc;
            automatic real vfu_vrf_r_util [3], vfu_vrf_r_avg_cyc [3];

            d.ctrl_wvalid[0] = now.ctrl_wvalid[0] - stats_base_q.ctrl_wvalid[0];
            d.ctrl_wvalid[1] = now.ctrl_wvalid[1] - stats_base_q.ctrl_wvalid[1];
            d.ctrl_wvalid[2] = now.ctrl_wvalid[2] - stats_base_q.ctrl_wvalid[2];
            d.ctrl_wtrans[0] = now.ctrl_wtrans[0] - stats_base_q.ctrl_wtrans[0];
            d.ctrl_wtrans[1] = now.ctrl_wtrans[1] - stats_base_q.ctrl_wtrans[1];
            d.ctrl_wtrans[2] = now.ctrl_wtrans[2] - stats_base_q.ctrl_wtrans[2];
            d.ctrl_vlsu_insn    = now.ctrl_vlsu_insn    - stats_base_q.ctrl_vlsu_insn;
            d.ctrl_vlsu_stall   = now.ctrl_vlsu_stall   - stats_base_q.ctrl_vlsu_stall;
            d.ctrl_vlsu_active  = now.ctrl_vlsu_active  - stats_base_q.ctrl_vlsu_active;
            d.ctrl_vfu_insn     = now.ctrl_vfu_insn     - stats_base_q.ctrl_vfu_insn;
            d.ctrl_vfu_stall    = now.ctrl_vfu_stall    - stats_base_q.ctrl_vfu_stall;
            d.ctrl_vfu_active   = now.ctrl_vfu_active   - stats_base_q.ctrl_vfu_active;
            d.ctrl_vsldu_insn   = now.ctrl_vsldu_insn   - stats_base_q.ctrl_vsldu_insn;
            d.ctrl_vsldu_stall  = now.ctrl_vsldu_stall  - stats_base_q.ctrl_vsldu_stall;
            d.ctrl_vsldu_active = now.ctrl_vsldu_active - stats_base_q.ctrl_vsldu_active;

            d.vlsu_wvalid = now.vlsu_wvalid - stats_base_q.vlsu_wvalid;
            d.vlsu_wtrans = now.vlsu_wtrans - stats_base_q.vlsu_wtrans;
            d.vlsu_mem_valid = now.vlsu_mem_valid - stats_base_q.vlsu_mem_valid;
            d.vlsu_mem_trans = now.vlsu_mem_trans - stats_base_q.vlsu_mem_trans;
            d.vlsu_rob_usage    = now.vlsu_rob_usage    - stats_base_q.vlsu_rob_usage;
            d.vlsu_rob_use_cyc  = now.vlsu_rob_use_cyc  - stats_base_q.vlsu_rob_use_cyc;
            d.vlsu_rob_full_cyc = now.vlsu_rob_full_cyc - stats_base_q.vlsu_rob_full_cyc;
            d.vlsu_insn_valid_cyc = now.vlsu_insn_valid_cyc - stats_base_q.vlsu_insn_valid_cyc;
            d.vlsu_insn_cnt       = now.vlsu_insn_cnt       - stats_base_q.vlsu_insn_cnt;
            d.vlsu_load_lat_sum = now.vlsu_load_lat_sum - stats_base_q.vlsu_load_lat_sum;
            d.vlsu_load_lat_cnt = now.vlsu_load_lat_cnt - stats_base_q.vlsu_load_lat_cnt;

            d.vfu_wvalid = now.vfu_wvalid - stats_base_q.vfu_wvalid;
            d.vfu_wtrans = now.vfu_wtrans - stats_base_q.vfu_wtrans;
            d.vfu_rvalid[0] = now.vfu_rvalid[0] - stats_base_q.vfu_rvalid[0];
            d.vfu_rvalid[1] = now.vfu_rvalid[1] - stats_base_q.vfu_rvalid[1];
            d.vfu_rvalid[2] = now.vfu_rvalid[2] - stats_base_q.vfu_rvalid[2];
            d.vfu_rtrans[0] = now.vfu_rtrans[0] - stats_base_q.vfu_rtrans[0];
            d.vfu_rtrans[1] = now.vfu_rtrans[1] - stats_base_q.vfu_rtrans[1];
            d.vfu_rtrans[2] = now.vfu_rtrans[2] - stats_base_q.vfu_rtrans[2];
            d.vfu_insn_valid_cyc = now.vfu_insn_valid_cyc - stats_base_q.vfu_insn_valid_cyc;
            d.vfu_insn_cnt       = now.vfu_insn_cnt       - stats_base_q.vfu_insn_cnt;

            load_lat_avg = d.vlsu_load_lat_cnt == 0 ? 0 : real'(d.vlsu_load_lat_sum) / real'(d.vlsu_load_lat_cnt);

            ctrl_vlsu_wstall  = real'(d.ctrl_wvalid[1]) - real'(d.ctrl_wtrans[1]);
            ctrl_vfu_wstall   = real'(d.ctrl_wvalid[0]) - real'(d.ctrl_wtrans[0]);
            ctrl_vsldu_wstall = real'(d.ctrl_wvalid[2]) - real'(d.ctrl_wtrans[2]);

            vlsu_vrf_w_util    = d.vlsu_wvalid == 0 ? 0 : 100 * real'(d.vlsu_wtrans) / real'(d.vlsu_wvalid);
            vlsu_vrf_w_avg_cyc = d.vlsu_wtrans == 0 ? 0 : real'(d.vlsu_wvalid) / real'(d.vlsu_wtrans);
            vlsu_mem_util      = d.vlsu_mem_valid == 0 ? 0 : 100 * real'(d.vlsu_mem_trans) / real'(d.vlsu_mem_valid);
            vlsu_mem_avg_cyc   = d.vlsu_mem_trans == 0 ? 0 : real'(d.vlsu_mem_valid) / real'(d.vlsu_mem_trans);
            // ROB in use for x cycle, total usage Y: Utilization = Y/(X*depth)
            vlsu_rob_usage_avg = d.vlsu_rob_use_cyc == 0 ? 0 :
                100 * real'(d.vlsu_rob_usage) / real'(d.vlsu_rob_use_cyc) / real'(NumSpatzOutstandingLoads);
            // Not session-cut: cumulative peak over the whole run so far.
            vlsu_rob_peak_util = 100 * real'(`CC_PATH(gy, gx, t, c).i_spatz.i_vlsu.rob_peak_q) / real'(NumSpatzOutstandingLoads);
            vlsu_avg_insn_cyc  = d.vlsu_insn_cnt == 0 ? 0 : real'(d.vlsu_insn_valid_cyc) / real'(d.vlsu_insn_cnt);

            vfu_vrf_w_util    = d.vfu_wvalid == 0 ? 0 : 100 * real'(d.vfu_wtrans) / real'(d.vfu_wvalid);
            vfu_vrf_w_avg_cyc = d.vfu_wtrans == 0 ? 0 : real'(d.vfu_wvalid) / real'(d.vfu_wtrans);
            for (int unsigned p = 0; p < 3; p++) begin
              vfu_vrf_r_util[p]    = d.vfu_rvalid[p] == 0 ? 0 : 100 * real'(d.vfu_rtrans[p]) / real'(d.vfu_rvalid[p]);
              vfu_vrf_r_avg_cyc[p] = d.vfu_rtrans[p] == 0 ? 0 : real'(d.vfu_rvalid[p]) / real'(d.vfu_rtrans[p]);
            end
            vfu_avg_insn_cyc = d.vfu_insn_cnt == 0 ? 0 : real'(d.vfu_insn_valid_cyc) / real'(d.vfu_insn_cnt);

            $fwrite(core_f, "*********************************************************************\n");
            $fwrite(core_f, "*** Session %0d (%s): cycles [%0d, %0d)                    ***\n",
                    idx, tag, session_start_cycle_q, cycle_q);
            $fwrite(core_f, "*********************************************************************\n");
            $fwrite(core_f, "   VLSU Load Req-to-Commit Count:    %32d\n", d.vlsu_load_lat_cnt       );
            $fwrite(core_f, "   VLSU Load AVG Req-to-Commit Cyc:  %32.2f\n", load_lat_avg             );
            $fwrite(core_f, "\n"                                                                     );
            $fwrite(core_f, "***            Spatz Controller Utilization                       ***\n");
            $fwrite(core_f, "   VLSU:\n"                                                             );
            $fwrite(core_f, "   VLSU Active (not accurate):       %32d\n", d.ctrl_vlsu_active        );
            $fwrite(core_f, "   VLSU Num Instructions:            %32d\n", d.ctrl_vlsu_insn          );
            $fwrite(core_f, "   VLSU Stall Cycles:                %32d\n", d.ctrl_vlsu_stall         );
            $fwrite(core_f, "   VLSU WR Stalls:                   %32.2f\n", ctrl_vlsu_wstall        );
            $fwrite(core_f, "   VFU:\n"                                                              );
            $fwrite(core_f, "   VFU Active (not accurate):        %32d\n", d.ctrl_vfu_active         );
            $fwrite(core_f, "   VFU Num Instructions:             %32d\n", d.ctrl_vfu_insn           );
            $fwrite(core_f, "   VFU Stall Cycles:                 %32d\n", d.ctrl_vfu_stall          );
            $fwrite(core_f, "   VFU WR Stalls:                    %32.2f\n", ctrl_vfu_wstall         );
            $fwrite(core_f, "   VSLDU:\n"                                                            );
            $fwrite(core_f, "   VSLDU Active (not accurate):      %32d\n", d.ctrl_vsldu_active       );
            $fwrite(core_f, "   VSLDU Num Instructions:           %32d\n", d.ctrl_vsldu_insn         );
            $fwrite(core_f, "   VSLDU Stall Cycles:               %32d\n", d.ctrl_vsldu_stall        );
            $fwrite(core_f, "   VSLDU WR Stalls:                  %32.2f\n", ctrl_vsldu_wstall       );
            $fwrite(core_f, "\n"                                                                     );
            $fwrite(core_f, "***            Spatz VLSU Utilization                             ***\n");
            $fwrite(core_f, "   Number of VRF Valid Cycles:       %32d\n", d.vlsu_wvalid             );
            $fwrite(core_f, "   Number of VRF Transaction Counts: %32d\n", d.vlsu_wtrans             );
            $fwrite(core_f, "   VRF W Utilization:                %32.2f\n", vlsu_vrf_w_util         );
            $fwrite(core_f, "   VRF W AVG Cycles:                 %32.2f\n", vlsu_vrf_w_avg_cyc      );
            $fwrite(core_f, "   Number of Mem Valid Cycles:       %32d\n", d.vlsu_mem_valid          );
            $fwrite(core_f, "   Number of Mem Transaction Counts: %32d\n", d.vlsu_mem_trans          );
            $fwrite(core_f, "   Mem Utilization:                  %32.2f\n", vlsu_mem_util           );
            $fwrite(core_f, "   Mem AVG Req Accept Cycles:        %32.2f\n", vlsu_mem_avg_cyc        );
            $fwrite(core_f, "   VLSU Stall Cycles (ROB Full):     %32d\n", d.vlsu_rob_full_cyc       );
            $fwrite(core_f, "   ROB AVG Utilization:              %32.2f\n", vlsu_rob_usage_avg      );
            $fwrite(core_f, "   ROB Peak Utilization (cumulative):%32.2f\n", vlsu_rob_peak_util      );
            $fwrite(core_f, "   Total Insn Count:                 %32d\n", d.vlsu_insn_cnt           );
            $fwrite(core_f, "   AVG Insn Cycles:                  %32.2f\n", vlsu_avg_insn_cyc       );
            $fwrite(core_f, "\n"                                                                     );
            $fwrite(core_f, "***            Spatz VFU Utilization                              ***\n");
            $fwrite(core_f, "   VRF Write Port:\n"                                                   );
            $fwrite(core_f, "   Number of VRF Valid Cycles:       %32d\n", d.vfu_wvalid              );
            $fwrite(core_f, "   Number of VRF Transaction Counts: %32d\n", d.vfu_wtrans              );
            $fwrite(core_f, "   VRF W Utilization:                %32.2f\n", vfu_vrf_w_util          );
            $fwrite(core_f, "   VRF W AVG Cycles:                 %32.2f\n", vfu_vrf_w_avg_cyc       );
            for (int unsigned p = 0; p < 3; p++) begin
              $fwrite(core_f, "   VRF Read Port %0d:\n", p                                           );
              $fwrite(core_f, "   Number of VRF Valid Cycles:       %32d\n", d.vfu_rvalid[p]         );
              $fwrite(core_f, "   Number of VRF Transaction Counts: %32d\n", d.vfu_rtrans[p]         );
              $fwrite(core_f, "   VRF R Utilization:                %32.2f\n", vfu_vrf_r_util[p]     );
              $fwrite(core_f, "   VRF R AVG Cycles:                 %32.2f\n", vfu_vrf_r_avg_cyc[p]  );
            end
            $fwrite(core_f, "   Total Insn Count:                 %32d\n", d.vfu_insn_cnt            );
            $fwrite(core_f, "   AVG Insn Cycles:                  %32.2f\n", vfu_avg_insn_cyc        );
            $fwrite(core_f, "*********************************************************************\n");
            $fwrite(core_f, "\n"                                                                     );
          endfunction

          always_ff @(posedge clk_i) begin
            if (session_edge) dump_core_session(session_idx_q, session_tag(probe_q, 1'b0));
          end

          final begin
            dump_core_session(session_idx_q, session_tag(cluster_probe_i, 1'b1));
            $fclose(core_f);
          end
        end
      end
    end
  end

  `undef TILE_PATH
  `undef CC_PATH
  `undef CLUSTER_PATH
`endif

endmodule
