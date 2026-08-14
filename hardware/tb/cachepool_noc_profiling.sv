// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Ported from TeraNoC's hardware/tb/tb_noc_profiling.svh to CachePool's
// group/tile/core hierarchy. Instantiated as a sibling of the DUT (same
// pattern as cachepool_monitor.sv) and reaches in purely via hierarchical
// references -- nothing here is threaded through synthesizable RTL.
//
// The S/P/Q log-line WIRE FORMAT is kept byte-for-byte identical to
// TeraNoC's, so hardware/scripts/perfetto_gen.py parses these logs
// unmodified -- only the SV-side data source changed. See that script's
// load_noc_router_logs/load_noc_tile_logs/load_pe_logs for the consumer.
//
// Architectural differences from MemPool/TeraNoC that shaped this port
// (see cachepool_pkg.sv for the underlying types):
//  - CachePool has ONE req + one resp network per tile (width
//    NumNoCPortsPerTile), not MemPool's wide/rdwr split -- so there is only
//    one "port" dimension (`n`), not two.
//  - No dedicated meta_id/MetaIdWidth field anywhere. The closest analog
//    used throughout is `.user.req_id` (reqid_t, sized by
//    NumSpatzOutstandingLoads).
//  - Groups are addressed 2-D (x,y), row-major flat id g = gy*NumGroupsX+gx
//    (see cachepool_cluster.sv's gen_group_y/gen_group_x). Router-level P
//    lines carry x/y directly (the RTL's own noc_group_hdr_t already
//    decodes them), so no re-derivation is needed there. Tile-level P/Q
//    lines need a flat scalar to match TeraNoC's src_grp/dst_grp fields;
//    decode_group() below re-derives it from the dst_tile_id/tile_id bit
//    fields using the SAME layout formula as
//    cachepool_group_noc_wrapper.sv's NocGroupOffset/NocGroupBitsX/Y
//    (kept in sync manually -- there's no shared package constant for it).
//    CAVEAT: perfetto_gen.py's `_gname` decodes g as
//    (g // mesh_y, g % mesh_y), i.e. an X-major-fast convention. CachePool's
//    g is Y-major/X-fast, so pass `--mesh-y NumGroupsX` (not NumGroupsY) to
//    get the arithmetic right -- the printed tuple order then reads (y,x)
//    rather than (x,y). Cosmetic only; no data is wrong.
//  - The inter-group ("RG") mesh is entirely tied to '0 whenever
//    NumRemoteGroupPortCore == 0 (the default single-group build, see
//    config/config.mk num_rg_ports_per_core), so router and RG-tile logs
//    are legitimately empty then -- this module mirrors the DUT's own
//    `if (NumRemoteGroupPortCore > 0)` guard and only traces PE (core)
//    ports unconditionally. Meaningful router/tile output needs a
//    multi-group config, e.g. config/cachepool_4g.mk.
//  - Intra-group ("LG") remote traffic (cachepool_group.sv's crossbar) has
//    no MemPool equivalent and is NOT traced here (kept the port scope
//    1:1 with the original tb_noc_profiling.svh).
module cachepool_noc_profiling
  import cachepool_pkg::*;
(
  input logic clk_i,
  input logic rst_ni,
  // SPATZ_CLUSTER_PROBE bit (same signal cachepool_monitor.sv uses): gates all tracing to active kernel sessions and opens a new session_<N>/ subfolder per rising edge.
  input logic cluster_probe_i
);

`ifndef TARGET_SYNTHESIS
`ifndef TARGET_VERILATOR
  logic [63:0] cycle_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      cycle_q <= '0;
    end else begin
      cycle_q <= cycle_q + 64'd1;
    end
  end

`ifdef NOC_PROFILING
  // Hierarchical paths (no `dut.` alias exists in this TB -- see
  // hardware/tb/tb_cachepool.sv, DUT instance is i_cluster_wrapper).
  `define NOCPROF_GRP(gy, gx) \
    i_cluster_wrapper.i_cluster.gen_group_y[gy].gen_group_x[gx].i_group
  `define NOCPROF_TILE(gy, gx, t) \
    `NOCPROF_GRP(gy, gx).i_group.gen_tiles[t].gen_tile.i_tile

  // Mirrors cachepool_group_noc_wrapper.sv's private dst_tile_id/tile_id bit
  // layout (group_y | group_x | local_tile), row-major. Kept manually in
  // sync since that layout isn't exported as a package constant.
  localparam int unsigned NocGroupOffset = $clog2(NumTilesPerGroup);
  localparam int unsigned NocGroupBitsX  = (NumGroupsX > 1) ? $clog2(NumGroupsX) : 0;
  localparam int unsigned NocGroupBitsY  = (NumGroupsY > 1) ? $clog2(NumGroupsY) : 0;
  // Same "at least 1" floor cachepool_group_noc_wrapper.sv uses for
  // NumRemoteGroupPortTile: avoids a zero-size unpacked array dimension on
  // the state-register arrays below when NumRemoteGroupPortCore==0 (the
  // default single-group build) -- the generate-if guards ensure those
  // elements are simply never touched in that case.
  localparam int unsigned NumRGPortTile  = (NumRemoteGroupPortCore == 0) ? 1
                                          : NumRemoteGroupPortCore * NrTCDMPortsPerCore;
  // Part-select WIDTHS floored to 1 to dodge an illegal zero-width
  // `+:`/range select when a dimension is degenerate (NumGroupsX==1 etc.,
  // i.e. NocGroupBits{X,Y}==0 or NocGroupOffset==0) -- unlike the DUT's own
  // decode (cachepool_group_noc_wrapper.sv:311-322), which dodges this with
  // a `generate if/else` that drops the untaken branch before elaboration,
  // a function body can't do that: a runtime `?:` still requires BOTH
  // branches to be well-typed at elaboration time, so the slice must always
  // be legal; the surrounding ternary below then discards the resulting
  // (don't-care) bit whenever the real width is 0.
  localparam int unsigned NocGroupBitsXSafe = (NocGroupBitsX == 0) ? 1 : NocGroupBitsX;
  localparam int unsigned NocGroupBitsYSafe = (NocGroupBitsY == 0) ? 1 : NocGroupBitsY;
  localparam int unsigned NocGroupOffsetSafe = (NocGroupOffset == 0) ? 1 : NocGroupOffset;
  // Start-index clamp for the degenerate NumGroups==1 case (NocGroupOffset
  // == TileIDWidth, i.e. dst_tile_id has no group bits at all -- only
  // possible/relevant if NumRemoteGroupPortCore>0 with a single-group build,
  // which the RTL doesn't meaningfully support anyway): keeps the slice
  // in-bounds so it stays a legal constant part-select; decode_group()
  // still returns 0 in this case via the NocGroupBits{X,Y}==0 check above.
  localparam int unsigned NocGroupXStart = (NocGroupOffset + NocGroupBitsXSafe <= TileIDWidth)
                                          ? NocGroupOffset : (TileIDWidth - NocGroupBitsXSafe);
  localparam int unsigned NocGroupYStart = (NocGroupOffset + NocGroupBitsX + NocGroupBitsYSafe <= TileIDWidth)
                                          ? (NocGroupOffset + NocGroupBitsX) : (TileIDWidth - NocGroupBitsYSafe);

  function automatic int unsigned decode_group(logic [TileIDWidth-1:0] gtile_id);
    automatic int unsigned gx = (NocGroupBitsX == 0) ? 0 :
      int'(gtile_id[NocGroupXStart +: NocGroupBitsXSafe]);
    automatic int unsigned gy = (NocGroupBitsY == 0) ? 0 :
      int'(gtile_id[NocGroupYStart +: NocGroupBitsYSafe]);
    return gy * NumGroupsX + gx;
  endfunction

  function automatic int unsigned decode_local_tile(logic [TileIDWidth-1:0] gtile_id);
    return (NocGroupOffset == 0) ? 0 : int'(gtile_id[NocGroupOffsetSafe-1:0]);
  endfunction

  string  app, log_path;
  integer retval;
  // MERGED file handles, same layout as TeraNoC: routers -> ONE req + ONE
  // resp file per group (line tagged with flat noc_port); tiles/PE -> ONE
  // file per tile (line tagged with port/core idx).
  int f_rreq  [NumGroups];
  int f_rresp [NumGroups];
  int f_tile  [NumGroups][NumTilesPerGroup];
  int f_pe    [NumGroups][NumTilesPerGroup];
  // L2 (DRAM-refill) mesh: one router pair per group, no tile/port fan-out.
  int l2_f_req  [NumGroups];
  int l2_f_resp [NumGroups];

  // Session bookkeeping: session_idx_q numbers each cluster_probe_i rising edge (a kernel session); files_open_q is the trace blocks' write-enable, deliberately registered one cycle behind the actual fopen/fclose (via closing_q) so no always_ff race can hit a file descriptor before it's open or after it's closed.
  logic probe_q;
  int   session_idx_q;
  logic files_open_q;
  logic closing_q;

  // Opens a fresh log_path/session_<idx>/ subfolder and (re)assigns every file handle to it.
  task automatic open_session_files(input int idx);
    string session_path;
    session_path = $sformatf("%s/session_%0d", log_path, idx);
    retval = $system({"mkdir -p ", session_path});
    for (int g = 0; g < NumGroups; g++) begin
      f_rreq[g]    = $fopen($sformatf("%s/router_g%0d_req.log",     session_path, g), "w");
      f_rresp[g]   = $fopen($sformatf("%s/router_g%0d_resp.log",    session_path, g), "w");
      l2_f_req[g]  = $fopen($sformatf("%s/l2_router_g%0d_req.log",  session_path, g), "w");
      l2_f_resp[g] = $fopen($sformatf("%s/l2_router_g%0d_resp.log", session_path, g), "w");
      for (int t = 0; t < NumTilesPerGroup; t++) begin
        f_tile[g][t] = $fopen($sformatf("%s/tile_g%0d_t%0d.log", session_path, g, t), "w");
        f_pe[g][t]   = $fopen($sformatf("%s/pe_g%0d_t%0d.log",   session_path, g, t), "w");
      end
    end
  endtask

  // Flushes each port's still-open RLE run (same trailing writes the old bare `final` block did) then closes every handle from open_session_files -- shared by a mid-run falling edge and by $finish leaving a session open.
  task automatic close_session_files();
    for (int g = 0; g < NumGroups; g++) begin
      for (int t = 0; t < NumTilesPerGroup; t++) begin
        if (NumRemoteGroupPortCore > 0) begin
          for (int n = 0; n < NumNoCPortsPerTile; n++) begin
            automatic int noc_port = t*NumNoCPortsPerTile + n;
            for (int d = 0; d < 4; d++) begin
              $fwrite(f_rreq[g], "%0d S %0d 0 %0d %0d %0d\n", noc_port, d, rsq_start[g][t][n][d][0], cycle_q, rsq_st[g][t][n][d][0]);
              $fwrite(f_rreq[g], "%0d S %0d 1 %0d %0d %0d\n", noc_port, d, rsq_start[g][t][n][d][1], cycle_q, rsq_st[g][t][n][d][1]);
            end
            $fwrite(f_rreq[g], "%0d S 4 0 %0d %0d %0d\n", noc_port, rsq_start[g][t][n][4][0], cycle_q, rsq_st[g][t][n][4][0]);
            $fwrite(f_rreq[g], "%0d S 4 1 %0d %0d %0d\n", noc_port, rsq_start[g][t][n][4][1], cycle_q, rsq_st[g][t][n][4][1]);
            for (int d = 0; d < 4; d++) begin
              $fwrite(f_rresp[g], "%0d S %0d 0 %0d %0d %0d\n", noc_port, d, rsp_start[g][t][n][d][0], cycle_q, rsp_st[g][t][n][d][0]);
              $fwrite(f_rresp[g], "%0d S %0d 1 %0d %0d %0d\n", noc_port, d, rsp_start[g][t][n][d][1], cycle_q, rsp_st[g][t][n][d][1]);
            end
            $fwrite(f_rresp[g], "%0d S 4 0 %0d %0d %0d\n", noc_port, rsp_start[g][t][n][4][0], cycle_q, rsp_st[g][t][n][4][0]);
            $fwrite(f_rresp[g], "%0d S 4 1 %0d %0d %0d\n", noc_port, rsp_start[g][t][n][4][1], cycle_q, rsp_st[g][t][n][4][1]);
          end
          for (int p = 0; p < NumRGPortTile; p++) begin
            $fwrite(f_tile[g][t], "S 0 1 %0d %0d %0d %0d\n", p, ts_mreq_s[g][t][p], cycle_q, ts_mreq_st[g][t][p]);
            $fwrite(f_tile[g][t], "S 0 0 %0d %0d %0d %0d\n", p, ts_sreq_s[g][t][p], cycle_q, ts_sreq_st[g][t][p]);
            $fwrite(f_tile[g][t], "S 1 0 %0d %0d %0d %0d\n", p, ts_mrsp_s[g][t][p], cycle_q, ts_mrsp_st[g][t][p]);
            $fwrite(f_tile[g][t], "S 1 1 %0d %0d %0d %0d\n", p, ts_srsp_s[g][t][p], cycle_q, ts_srsp_st[g][t][p]);
          end
        end
        $fclose(f_tile[g][t]);
        for (int c = 0; c < NumCoresTile; c++) begin
          $fwrite(f_pe[g][t], "%0d S 0 1 0 %0d %0d %0d\n", c, pe_req_s[g][t][c], cycle_q, pe_req_st[g][t][c]);
          $fwrite(f_pe[g][t], "%0d S 1 0 0 %0d %0d %0d\n", c, pe_rsp_s[g][t][c], cycle_q, pe_rsp_st[g][t][c]);
        end
        $fclose(f_pe[g][t]);
      end
      $fclose(f_rreq[g]);
      $fclose(f_rresp[g]);
      for (int d = 0; d < 4; d++) begin
        $fwrite(l2_f_req[g], "S %0d 0 %0d %0d %0d\n", d, l2q_start[g][d][0], cycle_q, l2q_st[g][d][0]);
        $fwrite(l2_f_req[g], "S %0d 1 %0d %0d %0d\n", d, l2q_start[g][d][1], cycle_q, l2q_st[g][d][1]);
        $fwrite(l2_f_resp[g], "S %0d 0 %0d %0d %0d\n", d, l2p_start[g][d][0], cycle_q, l2p_st[g][d][0]);
        $fwrite(l2_f_resp[g], "S %0d 1 %0d %0d %0d\n", d, l2p_start[g][d][1], cycle_q, l2p_st[g][d][1]);
      end
      $fclose(l2_f_req[g]);
      $fclose(l2_f_resp[g]);
    end
  endtask

  initial begin
    void'($value$plusargs("APP=%s", app));
    log_path = "noc_profiling";
    retval   = $system({"mkdir -p ", log_path});
  end

  // Opens session_<N>/ on each cluster_probe_i rising edge and closes it on the matching falling edge; idle time between sessions is neither opened nor written (see the trace blocks' `!files_open_q` reset gating below).
  //
  // files_open_q only becomes visible to the (separately-clocked) trace
  // blocks the cycle AFTER open_session_files() actually runs, and
  // close_session_files() itself is deferred by one cycle (via closing_q)
  // past the cycle files_open_q drops -- both one-cycle offsets exist solely
  // so no trace block's always_ff can ever race this one's fopen/fclose on
  // the same edge (assumes sessions are >1 cycle apart, always true for a
  // real kernel region).
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      probe_q       <= 1'b0;
      session_idx_q <= '0;
      files_open_q  <= 1'b0;
      closing_q     <= 1'b0;
    end else begin
      probe_q <= cluster_probe_i;
      if (cluster_probe_i && !probe_q) begin
        open_session_files(session_idx_q);
        session_idx_q <= session_idx_q + 1;
        files_open_q  <= 1'b1;
      end else if (!cluster_probe_i && probe_q && files_open_q) begin
        files_open_q <= 1'b0;
        closing_q    <= 1'b1;
      end else if (closing_q) begin
        close_session_files();
        closing_q <= 1'b0;
      end
    end
  end

  // Module-scope state registers, flushed by close_session_files above.
  // router: [group][tile][noc-port][portidx 0..4][io 0..1]
  logic [1:0]  rsq_st    [NumGroups][NumTilesPerGroup][NumNoCPortsPerTile][5][2];
  logic [63:0] rsq_start [NumGroups][NumTilesPerGroup][NumNoCPortsPerTile][5][2];
  logic [1:0]  rsp_st    [NumGroups][NumTilesPerGroup][NumNoCPortsPerTile][5][2];
  logic [63:0] rsp_start [NumGroups][NumTilesPerGroup][NumNoCPortsPerTile][5][2];
  // tile: [group][tile][RG port]
  logic [1:0]  ts_mreq_st [NumGroups][NumTilesPerGroup][NumRGPortTile]; logic [63:0] ts_mreq_s [NumGroups][NumTilesPerGroup][NumRGPortTile];
  logic [1:0]  ts_sreq_st [NumGroups][NumTilesPerGroup][NumRGPortTile]; logic [63:0] ts_sreq_s [NumGroups][NumTilesPerGroup][NumRGPortTile];
  logic [1:0]  ts_mrsp_st [NumGroups][NumTilesPerGroup][NumRGPortTile]; logic [63:0] ts_mrsp_s [NumGroups][NumTilesPerGroup][NumRGPortTile];
  logic [1:0]  ts_srsp_st [NumGroups][NumTilesPerGroup][NumRGPortTile]; logic [63:0] ts_srsp_s [NumGroups][NumTilesPerGroup][NumRGPortTile];
  // PE (Snitch core) reqrsp data port: req = core_req[c] (out), resp = core_rsp[c] (in).
  logic [1:0]  pe_req_st [NumGroups][NumTilesPerGroup][NumCoresTile]; logic [63:0] pe_req_s [NumGroups][NumTilesPerGroup][NumCoresTile];
  logic [1:0]  pe_rsp_st [NumGroups][NumTilesPerGroup][NumCoresTile]; logic [63:0] pe_rsp_s [NumGroups][NumTilesPerGroup][NumCoresTile];
  // L2 router: [group][portidx 0..3][io 0..1] -- one router pair per group,
  // no tile/port dimension (see cachepool_group_noc_wrapper.sv's single
  // i_l2_req_router/i_l2_rsp_router per group).
  logic [1:0]  l2q_st    [NumGroups][4][2]; logic [63:0] l2q_start [NumGroups][4][2];
  logic [1:0]  l2p_st    [NumGroups][4][2]; logic [63:0] l2p_start [NumGroups][4][2];

  // ------------------------------------------------------------
  // Router port capture: mesh directions 0..3 (N/E/S/W, floo_pkg convention)
  // + local (portidx 4) inject/eject -> per-group req/resp files. S lines
  // RLE idle/stall/read/write; P lines log every accepted request/response
  // flit. Guarded like the DUT's own `gen_noc`: under the default
  // single-group build (NumRemoteGroupPortCore==0) req_mesh_*/rsp_mesh_* are
  // tied to '0 by `gen_noc_disabled`, and packed_req/eject_req/inject_rsp/
  // eject_rsp don't exist at all -- so this whole block only elaborates
  // when NumRemoteGroupPortCore > 0 (multi-group configs).
  // ------------------------------------------------------------
  if (NumRemoteGroupPortCore > 0) begin : gen_router_trace
    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_rstate_gy
      for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_rstate_gx
        localparam int unsigned g = gy * NumGroupsX + gx;
        always_ff @(posedge clk_i or negedge rst_ni) begin
          if (!rst_ni || !files_open_q) begin
            rsq_st[g] <= '{default: '0}; rsq_start[g] <= '{default: '0};
            rsp_st[g] <= '{default: '0}; rsp_start[g] <= '{default: '0};
          end else begin
            for (int t = 0; t < NumTilesPerGroup; t++) begin
              for (int n = 0; n < NumNoCPortsPerTile; n++) begin
                automatic int noc_port = t*NumNoCPortsPerTile + n;
                for (int d = 0; d < 4; d++) begin
                  automatic logic [1:0] si = `NOCPROF_GRP(gy, gx).req_mesh_in_valid[t][n][d]
                    ? (`NOCPROF_GRP(gy, gx).req_mesh_in_ready[t][n][d]
                       ? (`NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].payload.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
                  automatic logic [1:0] so = `NOCPROF_GRP(gy, gx).req_mesh_out_valid[t][n][d]
                    ? (`NOCPROF_GRP(gy, gx).req_mesh_out_ready[t][n][d]
                       ? (`NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].payload.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
                  if (si != rsq_st[g][t][n][d][0]) begin
                    $fwrite(f_rreq[g], "%0d S %0d 0 %0d %0d %0d\n", noc_port, d, rsq_start[g][t][n][d][0], cycle_q, rsq_st[g][t][n][d][0]);
                    rsq_st[g][t][n][d][0] <= si; rsq_start[g][t][n][d][0] <= cycle_q;
                  end
                  if (so != rsq_st[g][t][n][d][1]) begin
                    $fwrite(f_rreq[g], "%0d S %0d 1 %0d %0d %0d\n", noc_port, d, rsq_start[g][t][n][d][1], cycle_q, rsq_st[g][t][n][d][1]);
                    rsq_st[g][t][n][d][1] <= so; rsq_start[g][t][n][d][1] <= cycle_q;
                  end
                  // P: portidx io cycle wen tgt_addr dst_x dst_y src_x src_y src_tile core req_id
                  if (si >= 2)
                    $fwrite(f_rreq[g], "%0d P %0d 0 %0d %0d %0h %0d %0d %0d %0d %0d %0d %0d\n", noc_port, d, cycle_q,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].payload.write,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].payload.addr,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).req_mesh_in[t][n][d].payload.user.req_id);
                  if (so >= 2)
                    $fwrite(f_rreq[g], "%0d P %0d 1 %0d %0d %0h %0d %0d %0d %0d %0d %0d %0d\n", noc_port, d, cycle_q,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].payload.write,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].payload.addr,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).req_mesh_out[t][n][d].payload.user.req_id);
                end
                begin : req_local
                  automatic logic [1:0] sli = `NOCPROF_GRP(gy, gx).gen_noc.packed_req_valid[noc_port]
                    ? (`NOCPROF_GRP(gy, gx).gen_noc.packed_req_ready[noc_port]
                       ? (`NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].payload.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
                  automatic logic [1:0] slo = `NOCPROF_GRP(gy, gx).gen_noc.eject_req_valid[noc_port]
                    ? (`NOCPROF_GRP(gy, gx).gen_noc.eject_req_ready[noc_port]
                       ? (`NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].payload.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
                  if (sli != rsq_st[g][t][n][4][0]) begin
                    $fwrite(f_rreq[g], "%0d S 4 0 %0d %0d %0d\n", noc_port, rsq_start[g][t][n][4][0], cycle_q, rsq_st[g][t][n][4][0]);
                    rsq_st[g][t][n][4][0] <= sli; rsq_start[g][t][n][4][0] <= cycle_q;
                  end
                  if (slo != rsq_st[g][t][n][4][1]) begin
                    $fwrite(f_rreq[g], "%0d S 4 1 %0d %0d %0d\n", noc_port, rsq_start[g][t][n][4][1], cycle_q, rsq_st[g][t][n][4][1]);
                    rsq_st[g][t][n][4][1] <= slo; rsq_start[g][t][n][4][1] <= cycle_q;
                  end
                  if (sli >= 2)
                    $fwrite(f_rreq[g], "%0d P 4 0 %0d %0d %0h %0d %0d %0d %0d %0d %0d %0d\n", noc_port, cycle_q,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].payload.write,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].payload.addr,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.packed_req[noc_port].payload.user.req_id);
                  if (slo >= 2)
                    $fwrite(f_rreq[g], "%0d P 4 1 %0d %0d %0h %0d %0d %0d %0d %0d %0d %0d\n", noc_port, cycle_q,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].payload.write,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].payload.addr,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_req[noc_port].payload.user.req_id);
                end
                // ---- resp: no read/write split, no addr (resp flit carries none) ----
                for (int d = 0; d < 4; d++) begin
                  automatic logic [1:0] si = `NOCPROF_GRP(gy, gx).rsp_mesh_in_valid[t][n][d]
                    ? (`NOCPROF_GRP(gy, gx).rsp_mesh_in_ready[t][n][d] ? 2'd2 : 2'd1) : 2'd0;
                  automatic logic [1:0] so = `NOCPROF_GRP(gy, gx).rsp_mesh_out_valid[t][n][d]
                    ? (`NOCPROF_GRP(gy, gx).rsp_mesh_out_ready[t][n][d] ? 2'd2 : 2'd1) : 2'd0;
                  if (si != rsp_st[g][t][n][d][0]) begin
                    $fwrite(f_rresp[g], "%0d S %0d 0 %0d %0d %0d\n", noc_port, d, rsp_start[g][t][n][d][0], cycle_q, rsp_st[g][t][n][d][0]);
                    rsp_st[g][t][n][d][0] <= si; rsp_start[g][t][n][d][0] <= cycle_q;
                  end
                  if (so != rsp_st[g][t][n][d][1]) begin
                    $fwrite(f_rresp[g], "%0d S %0d 1 %0d %0d %0d\n", noc_port, d, rsp_start[g][t][n][d][1], cycle_q, rsp_st[g][t][n][d][1]);
                    rsp_st[g][t][n][d][1] <= so; rsp_start[g][t][n][d][1] <= cycle_q;
                  end
                  // P: portidx io cycle dst_x dst_y src_x src_y src_tile core req_id
                  if (si >= 2)
                    $fwrite(f_rresp[g], "%0d P %0d 0 %0d %0d %0d %0d %0d %0d %0d %0d\n", noc_port, d, cycle_q,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_in[t][n][d].payload.user.req_id);
                  if (so >= 2)
                    $fwrite(f_rresp[g], "%0d P %0d 1 %0d %0d %0d %0d %0d %0d %0d %0d\n", noc_port, d, cycle_q,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).rsp_mesh_out[t][n][d].payload.user.req_id);
                end
                begin : rsp_local
                  automatic logic [1:0] sli = `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp_valid[noc_port]
                    ? (`NOCPROF_GRP(gy, gx).gen_noc.inject_rsp_ready[noc_port] ? 2'd2 : 2'd1) : 2'd0;
                  automatic logic [1:0] slo = `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp_valid[noc_port]
                    ? (`NOCPROF_GRP(gy, gx).gen_noc.eject_rsp_ready[noc_port] ? 2'd2 : 2'd1) : 2'd0;
                  if (sli != rsp_st[g][t][n][4][0]) begin
                    $fwrite(f_rresp[g], "%0d S 4 0 %0d %0d %0d\n", noc_port, rsp_start[g][t][n][4][0], cycle_q, rsp_st[g][t][n][4][0]);
                    rsp_st[g][t][n][4][0] <= sli; rsp_start[g][t][n][4][0] <= cycle_q;
                  end
                  if (slo != rsp_st[g][t][n][4][1]) begin
                    $fwrite(f_rresp[g], "%0d S 4 1 %0d %0d %0d\n", noc_port, rsp_start[g][t][n][4][1], cycle_q, rsp_st[g][t][n][4][1]);
                    rsp_st[g][t][n][4][1] <= slo; rsp_start[g][t][n][4][1] <= cycle_q;
                  end
                  if (sli >= 2)
                    $fwrite(f_rresp[g], "%0d P 4 0 %0d %0d %0d %0d %0d %0d %0d %0d\n", noc_port, cycle_q,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.inject_rsp[noc_port].payload.user.req_id);
                  if (slo >= 2)
                    $fwrite(f_rresp[g], "%0d P 4 1 %0d %0d %0d %0d %0d %0d %0d %0d\n", noc_port, cycle_q,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].hdr.dst_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].hdr.dst_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].hdr.src_id.x,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].hdr.src_id.y,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].hdr.src_tile_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].payload.user.core_id,
                      `NOCPROF_GRP(gy, gx).gen_noc.eject_rsp[noc_port].payload.user.req_id);
                end
              end
            end
          end
        end
      end
    end
  end : gen_router_trace

  // ------------------------------------------------------------
  // Tile port capture -> per-tile file. RG (inter-group) ports only (see
  // header comment) -- req=remote_group_req_o(out,master)/remote_group_req_i
  // (in,slave) split read/write by .q.write + P packet lines; resp=
  // remote_group_rsp_i(in,master)/remote_group_rsp_o(out,slave) single
  // handshake state (no address).
  // ------------------------------------------------------------
  if (NumRemoteGroupPortCore > 0) begin : gen_tile_trace
    for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_tstate_gy
      for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_tstate_gx
        localparam int unsigned g = gy * NumGroupsX + gx;
        for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_tstate_t
          always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni || !files_open_q) begin
              ts_mreq_st[g][t] <= '{default: '0}; ts_mreq_s[g][t] <= '{default: '0};
              ts_sreq_st[g][t] <= '{default: '0}; ts_sreq_s[g][t] <= '{default: '0};
              ts_mrsp_st[g][t] <= '{default: '0}; ts_mrsp_s[g][t] <= '{default: '0};
              ts_srsp_st[g][t] <= '{default: '0}; ts_srsp_s[g][t] <= '{default: '0};
            end else begin
              for (int p = 0; p < NumRGPortTile; p++) begin
                automatic logic [1:0] smo = `NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q_valid
                  ? (`NOCPROF_TILE(gy, gx, t).remote_group_rsp_i[p].q_ready
                     ? (`NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
                automatic logic [1:0] ssi = `NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q_valid
                  ? (`NOCPROF_TILE(gy, gx, t).remote_group_rsp_o[p].q_ready
                     ? (`NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
                if (smo != ts_mreq_st[g][t][p]) begin
                  $fwrite(f_tile[g][t], "S 0 1 %0d %0d %0d %0d\n", p, ts_mreq_s[g][t][p], cycle_q, ts_mreq_st[g][t][p]);
                  ts_mreq_st[g][t][p] <= smo; ts_mreq_s[g][t][p] <= cycle_q;
                end
                if (ssi != ts_sreq_st[g][t][p]) begin
                  $fwrite(f_tile[g][t], "S 0 0 %0d %0d %0d %0d\n", p, ts_sreq_s[g][t][p], cycle_q, ts_sreq_st[g][t][p]);
                  ts_sreq_st[g][t][p] <= ssi; ts_sreq_s[g][t][p] <= cycle_q;
                end
                // P: io port cycle wen tgt_addr src_group dst_group req_tile req_core req_id
                if (smo >= 2)  // remote_group_req_o out (this tile issues a request)
                  $fwrite(f_tile[g][t], "P 1 %0d %0d %0d %0h %0d %0d %0d %0d %0d\n", p, cycle_q,
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q.write,
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q.addr,
                    g,                                                                          // src group
                    decode_group(`NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q.user.dst_tile_id), // dst group
                    t,                                                                          // requester tile
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q.user.core_id,               // requester core
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].q.user.req_id);               // req_id
                if (ssi >= 2)  // remote_group_req_i in (a request arrives at this tile)
                  $fwrite(f_tile[g][t], "P 0 %0d %0d %0d %0h %0d %0d %0d %0d %0d\n", p, cycle_q,
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.write,
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.addr,
                    (`NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.user.src_group_y * NumGroupsX
                     + `NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.user.src_group_x),        // src group
                    g,                                                                          // dst group
                    decode_local_tile(`NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.user.tile_id), // requester tile (local to src group)
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.user.core_id,               // requester core
                    `NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].q.user.req_id);               // req_id
              end
              for (int p = 0; p < NumRGPortTile; p++) begin
                automatic logic [1:0] smi = `NOCPROF_TILE(gy, gx, t).remote_group_rsp_i[p].p_valid
                  ? (`NOCPROF_TILE(gy, gx, t).remote_group_req_o[p].p_ready ? 2'd2 : 2'd1) : 2'd0;
                automatic logic [1:0] sso = `NOCPROF_TILE(gy, gx, t).remote_group_rsp_o[p].p_valid
                  ? (`NOCPROF_TILE(gy, gx, t).remote_group_req_i[p].p_ready ? 2'd2 : 2'd1) : 2'd0;
                // Q lines (kept apart from P req lines):
                //   Q <io> <port> <cycle> <srcvalid> <src_grp> <dst_grp> <req_tile> <req_core> <req_id>
                //   remote_group_rsp_i(in,io0): responder group unknown at this port -> srcvalid=0, dst=this group.
                //   remote_group_rsp_o(out,io1): src=this group, dst=decoded from the echoed requester tile_id.
                if (smi != ts_mrsp_st[g][t][p]) begin
                  $fwrite(f_tile[g][t], "S 1 0 %0d %0d %0d %0d\n", p, ts_mrsp_s[g][t][p], cycle_q, ts_mrsp_st[g][t][p]);
                  ts_mrsp_st[g][t][p] <= smi; ts_mrsp_s[g][t][p] <= cycle_q;
                end
                if (smi >= 2)  // remote_group_rsp_i in: response arrives for this tile's core
                  $fwrite(f_tile[g][t], "Q 0 %0d %0d 0 %0d %0d %0d %0d %0d\n", p, cycle_q,
                    g, g, t,
                    `NOCPROF_TILE(gy, gx, t).remote_group_rsp_i[p].p.user.core_id,
                    `NOCPROF_TILE(gy, gx, t).remote_group_rsp_i[p].p.user.req_id);
                if (sso != ts_srsp_st[g][t][p]) begin
                  $fwrite(f_tile[g][t], "S 1 1 %0d %0d %0d %0d\n", p, ts_srsp_s[g][t][p], cycle_q, ts_srsp_st[g][t][p]);
                  ts_srsp_st[g][t][p] <= sso; ts_srsp_s[g][t][p] <= cycle_q;
                end
                if (sso >= 2)  // remote_group_rsp_o out: this tile responds to a requester
                  $fwrite(f_tile[g][t], "Q 1 %0d %0d 1 %0d %0d %0d %0d %0d\n", p, cycle_q,
                    g,
                    decode_group(`NOCPROF_TILE(gy, gx, t).remote_group_rsp_o[p].p.user.tile_id),
                    decode_local_tile(`NOCPROF_TILE(gy, gx, t).remote_group_rsp_o[p].p.user.tile_id),
                    `NOCPROF_TILE(gy, gx, t).remote_group_rsp_o[p].p.user.core_id,
                    `NOCPROF_TILE(gy, gx, t).remote_group_rsp_o[p].p.user.req_id);
              end
            end
          end
        end
      end
    end
  end : gen_tile_trace

  // ------------------------------------------------------------
  // PE (Snitch core) reqrsp data-port capture -> per-tile file (one line
  // per core). Always traced, independent of NumRemoteGroupPortCore. Same
  // format as a tile port; req = core_req[c] (out, write by .q.write, addr=
  // .q.addr), resp = core_rsp[c] (in). No bw/util derived for PE ports.
  //   S <rr> <io> <port> <start> <end> <state> ; P <io> <port> <cycle> <wen> <addr(hex)> <req_id>
  // ------------------------------------------------------------
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_pe_gy
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_pe_gx
      localparam int unsigned g = gy * NumGroupsX + gx;
      for (genvar t = 0; t < NumTilesPerGroup; t++) begin : gen_pe_t
        always_ff @(posedge clk_i or negedge rst_ni) begin
          if (!rst_ni || !files_open_q) begin
            pe_req_st[g][t] <= '{default: '0}; pe_req_s[g][t] <= '{default: '0};
            pe_rsp_st[g][t] <= '{default: '0}; pe_rsp_s[g][t] <= '{default: '0};
          end else begin
            for (int c = 0; c < NumCoresTile; c++) begin
              automatic logic [1:0] rq = `NOCPROF_TILE(gy, gx, t).core_req[c].q_valid
                ? (`NOCPROF_TILE(gy, gx, t).core_rsp[c].q_ready
                   ? (`NOCPROF_TILE(gy, gx, t).core_req[c].q.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
              automatic logic [1:0] rp = `NOCPROF_TILE(gy, gx, t).core_rsp[c].p_valid
                ? (`NOCPROF_TILE(gy, gx, t).core_req[c].p_ready ? 2'd2 : 2'd1) : 2'd0;
              if (rq != pe_req_st[g][t][c]) begin
                $fwrite(f_pe[g][t], "%0d S 0 1 0 %0d %0d %0d\n", c, pe_req_s[g][t][c], cycle_q, pe_req_st[g][t][c]);
                pe_req_st[g][t][c] <= rq; pe_req_s[g][t][c] <= cycle_q;
              end
              if (rp != pe_rsp_st[g][t][c]) begin
                $fwrite(f_pe[g][t], "%0d S 1 0 0 %0d %0d %0d\n", c, pe_rsp_s[g][t][c], cycle_q, pe_rsp_st[g][t][c]);
                pe_rsp_st[g][t][c] <= rp; pe_rsp_s[g][t][c] <= cycle_q;
              end
              if (rq >= 2)  // req handshake -> one core load/store accepted (req_id = meta_id analog)
                $fwrite(f_pe[g][t], "%0d P 1 0 %0d %0d %0h %0d\n", c, cycle_q,
                  `NOCPROF_TILE(gy, gx, t).core_req[c].q.write,
                  `NOCPROF_TILE(gy, gx, t).core_req[c].q.addr,
                  `NOCPROF_TILE(gy, gx, t).core_req[c].q.user.req_id);
              if (rp >= 2)  // resp handshake -> a response returns to this core
                $fwrite(f_pe[g][t], "%0d P 0 0 %0d %0d\n", c, cycle_q,
                  `NOCPROF_TILE(gy, gx, t).core_rsp[c].p.user.req_id);
            end
          end
        end
      end
    end
  end

  // ------------------------------------------------------------
  // L2 (DRAM-refill) router capture: mesh directions 0..3 (N/E/S/W) -> one
  // req + one resp file per group. No tile/port fan-out (unlike the L1
  // router section above) and no local/Eject-port trace here -- the "Eject"
  // ports (each group's own manager chimney into this router) aren't graph
  // edges; the West-boundary HBM channels ARE ordinary West-direction mesh
  // links from the leftmost column's perspective, already covered below.
  // L2 uses SOURCE ROUTING (l2_noc_hdr_t), not XY, so there's no
  // hdr.dst_id.x/y to log -- only hdr.src_id (an opaque floo endpoint id)
  // and, for req flits, the payload addr/write. Always traced (the L2 mesh
  // exists regardless of NumRemoteGroupPortCore).
  //   S <portidx> <io> <start> <end> <state>
  //   req  P <portidx> <io> <cycle> <wen> <addr(hex)> <src_id>
  //   resp P <portidx> <io> <cycle> <src_id>
  // ------------------------------------------------------------
  for (genvar gy = 0; gy < NumGroupsY; gy++) begin : gen_l2_gy
    for (genvar gx = 0; gx < NumGroupsX; gx++) begin : gen_l2_gx
      localparam int unsigned g = gy * NumGroupsX + gx;
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni || !files_open_q) begin
          l2q_st[g] <= '{default: '0}; l2q_start[g] <= '{default: '0};
          l2p_st[g] <= '{default: '0}; l2p_start[g] <= '{default: '0};
        end else begin
          for (int d = 0; d < 4; d++) begin
            begin : l2_req
              automatic logic [1:0] si = `NOCPROF_GRP(gy, gx).l2_router_req_valid_in[d]
                ? (`NOCPROF_GRP(gy, gx).l2_router_req_ready_out[d]
                   ? (`NOCPROF_GRP(gy, gx).l2_router_req_in[d].payload.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
              automatic logic [1:0] so = `NOCPROF_GRP(gy, gx).l2_router_req_valid_out[d]
                ? (`NOCPROF_GRP(gy, gx).l2_router_req_ready_in[d]
                   ? (`NOCPROF_GRP(gy, gx).l2_router_req_out[d].payload.write ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
              if (si != l2q_st[g][d][0]) begin
                $fwrite(l2_f_req[g], "S %0d 0 %0d %0d %0d\n", d, l2q_start[g][d][0], cycle_q, l2q_st[g][d][0]);
                l2q_st[g][d][0] <= si; l2q_start[g][d][0] <= cycle_q;
              end
              if (so != l2q_st[g][d][1]) begin
                $fwrite(l2_f_req[g], "S %0d 1 %0d %0d %0d\n", d, l2q_start[g][d][1], cycle_q, l2q_st[g][d][1]);
                l2q_st[g][d][1] <= so; l2q_start[g][d][1] <= cycle_q;
              end
              if (si >= 2)
                $fwrite(l2_f_req[g], "P %0d 0 %0d %0d %0h %0d\n", d, cycle_q,
                  `NOCPROF_GRP(gy, gx).l2_router_req_in[d].payload.write,
                  `NOCPROF_GRP(gy, gx).l2_router_req_in[d].payload.addr,
                  `NOCPROF_GRP(gy, gx).l2_router_req_in[d].hdr.src_id);
              if (so >= 2)
                $fwrite(l2_f_req[g], "P %0d 1 %0d %0d %0h %0d\n", d, cycle_q,
                  `NOCPROF_GRP(gy, gx).l2_router_req_out[d].payload.write,
                  `NOCPROF_GRP(gy, gx).l2_router_req_out[d].payload.addr,
                  `NOCPROF_GRP(gy, gx).l2_router_req_out[d].hdr.src_id);
            end

            begin : l2_rsp
              automatic logic [1:0] pi = `NOCPROF_GRP(gy, gx).l2_router_rsp_valid_in[d]
                ? (`NOCPROF_GRP(gy, gx).l2_router_rsp_ready_out[d] ? 2'd2 : 2'd1) : 2'd0;
              automatic logic [1:0] po = `NOCPROF_GRP(gy, gx).l2_router_rsp_valid_out[d]
                ? (`NOCPROF_GRP(gy, gx).l2_router_rsp_ready_in[d] ? 2'd2 : 2'd1) : 2'd0;
              if (pi != l2p_st[g][d][0]) begin
                $fwrite(l2_f_resp[g], "S %0d 0 %0d %0d %0d\n", d, l2p_start[g][d][0], cycle_q, l2p_st[g][d][0]);
                l2p_st[g][d][0] <= pi; l2p_start[g][d][0] <= cycle_q;
              end
              if (po != l2p_st[g][d][1]) begin
                $fwrite(l2_f_resp[g], "S %0d 1 %0d %0d %0d\n", d, l2p_start[g][d][1], cycle_q, l2p_st[g][d][1]);
                l2p_st[g][d][1] <= po; l2p_start[g][d][1] <= cycle_q;
              end
              if (pi >= 2)
                $fwrite(l2_f_resp[g], "P %0d 0 %0d %0d\n", d, cycle_q,
                  `NOCPROF_GRP(gy, gx).l2_router_rsp_in[d].hdr.src_id);
              if (po >= 2)
                $fwrite(l2_f_resp[g], "P %0d 1 %0d %0d\n", d, cycle_q,
                  `NOCPROF_GRP(gy, gx).l2_router_rsp_out[d].hdr.src_id);
            end
          end
        end
      end
    end
  end

  // End-of-sim flush: also covers a pending deferred close (closing_q) so a session that fell mid-close at $finish still gets its files flushed/closed.
  final begin
    if (files_open_q || closing_q) close_session_files();
  end

  `undef NOCPROF_GRP
  `undef NOCPROF_TILE

`endif // NOC_PROFILING

`endif // TARGET_VERILATOR
`endif // TARGET_SYNTHESIS

endmodule
