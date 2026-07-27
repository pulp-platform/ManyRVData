#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# noc_profiling_to_vis4mesh.py -- converts the per-router NoC logs emitted by
# hardware/tb/cachepool_noc_profiling.sv (noc_profiling/*.log,
# +define+NOC_PROFILING) into a Vis4Mesh (util/vis4mesh) upload directory:
# meta.json, nodes.json, flat.json, edge_prefix_sum/<slice>.json.
#
# Distinct from util/scripts/noc_perfetto_gen.py (reads cachepool_monitor.sv's
# per-session CSVs, coarser granularity) and util/scripts/visualize_noc.py
# (static matplotlib congestion plot) -- this one is Vis4Mesh-specific and
# reads the cycle-accurate router logs instead. Like those two, --level
# distinguishes L1 (inter-group cache-access mesh, router_g*_{req,resp}.log)
# from L2 (DRAM-refill mesh, l2_router_g*_{req,resp}.log).
#
# ---------------------------------------------------------------------------
# Common ground, read this first:
# ---------------------------------------------------------------------------
# An edge's "value" array is NOT simply a channel vector.
# src/controller/module/filtermsg.ts's aggregate_data() indexes it as a fixed
# cross-product transfer_type x hop_unit x msg_type x channel, sized off
# src/data/classification.ts's hardcoded TransferTypesInOrder (4) and
# MsgTypesInOrder (4) arrays -- NOT driven by meta.json, so those two
# dimensions can't be shrunk. num_hop_units is ALSO effectively hardcoded to
# 4 in practice: src/filterbar/numhops.ts's UI (and filtermsg.ts's own
# default truth table) only ever offers hop buckets "0".."3", so anything
# other than 4 leaves some hop_unit buckets with no matching filter checkbox
# (silently dropped, not an error, but pointless -- so this script pins
# num_hop_units=4 to match). We don't track real path-hop-distance per flit
# (would need src/dst reconstruction), so every count uses a single fixed
# hop_unit=0 and transfer_type=0 ("mesh_send"/TX) slot -- the NoC-#-Hops and
# "Filter by NoC Msg Type" (Transfer Type) filters are consequently not
# meaningful yet (everything always falls in "0-0" / "TX").
#
# msg_type IS used meaningfully, though: MsgTypesInOrder = ["*mem.DataReadyRsp"
# (idx0), "*mem.ReadReq" (idx1), "*mem.WriteDoneRsp" (idx2), "*mem.WriteReq"
# (idx3)], each mapped via MsgGroupsMap to group "Read" (idx0,1) or "Write"
# (idx2,3) -- there is NO msg_type mapped to "Others", so a genuine response
# can only be approximated as "Read" or "Write" for THIS filter's purposes
# (separate from flat.json's "group" field below, which correctly labels
# response rows "Others" since that path isn't constrained the same way).
# Each real sub-type is routed to the closest-matching slot:
#   MSG_IDX_FOR_SUBCH = {read: 1 ("*mem.ReadReq"), write: 3 ("*mem.WriteReq"),
#                         resp: 0 ("*mem.DataReadyRsp")}
# IMPORTANT: earlier versions of this script placed EVERY sub-type at the
# same fixed msg_type slot (always "Read") to satisfy this required-but-
# unused dimension. That made the graph/link view's own Read/Write/Others
# filter checkboxes (src/filterbar/insttype.ts, same truth table
# aggregate_data() consults) reclassify 100% of all traffic as "Read"
# regardless of its real type -- unchecking "Read" zeroed every link, and
# nothing ever showed under "Write". Splitting by MSG_IDX_FOR_SUBCH fixes
# that; the "channel" dimension (see per-level notes) now carries ONLY
# physical-link/origin identity, not sub-type -- cleanly separating the two
# concerns instead of conflating them as before.
#
# Node/edge ids are Y-FLIPPED from CachePool's own row-major group id
# (g = gy*NumGroupsX+gx) before being written out: vis4mesh's grid renderer
# (src/graph/abstractlayer.ts) places row 0 (id // width) at the TOP of the
# canvas, but CachePool's own gy=0 is meant to render at the BOTTOM, so the
# emitted id uses display row (NumGroupsY-1-gy) instead of gy. This only
# affects the numbers written to nodes.json/edge_prefix_sum -- log parsing
# still keys off the real (unflipped) group id in the log filenames.
#
# ---------------------------------------------------------------------------
# --level l1 (default) / l1-origin: inter-group L1/cache-access mesh.
# ---------------------------------------------------------------------------
# One node per GROUP. Every group-to-group mesh edge (N/E/S/W) is actually
# NumTilesPerGroup*NumNoCPortsPerTile PARALLEL PHYSICAL LINKS fanned in
# through a shared xbar (one req + one resp network each -- see
# cachepool_group_noc_wrapper.sv's i_req_router/i_rsp_router arrays). Rather
# than summing all of those into one aggregate edge weight (hiding per-link
# imbalance), each physical link becomes its own Vis4Mesh CHANNEL:
# src/graph/graph.ts's get_links() renders edge.channelWeights as separate
# side-by-side "physical lanes" (isPhysical/base_lane_width), and
# src/filterbar/channel.ts's group auto-inference is explicitly written for
# "..._T<tile>_C<port>"-style labels -- this is the feature this data is
# shaped for. `noc_port` (the flat tile*NumNoCPortsPerTile+port id, the FIRST
# token on every router_g*.log line) is that physical-link identity.
# --level l1-origin uses the same topology, but the channel dimension is the
# ORIGINATING group (hdr.src_id.x/y, stamped once at injection and never
# rewritten by relay hops) instead of the physical link.
# The "local"/eject port (portidx 4 in the logs) is tile<->router injection,
# not a mesh edge, and is skipped.
#
# ---------------------------------------------------------------------------
# --level l2 / l2-origin: DRAM-refill mesh.
# ---------------------------------------------------------------------------
# Exactly one req + one resp router PER GROUP (no tile/port fan-out), so
# --level l2 uses a single physical-link channel (per your original "one
# channel" request) -- but still separates read/write/resp via msg_type (see
# above), so the graph-view filter checkboxes work correctly even with one
# channel. l2_router_g*.log has no per-link demux prefix (nothing to demux)
# and, since the L2 mesh uses SOURCE ROUTING (l2_noc_hdr_t) rather than XY,
# no dst x/y -- just cycle/wen/addr/src_id.
#
# The RTL's own comment names the West-boundary HBM channels "ejection
# points" (cachepool_cluster.sv's gen_hbm_west: one HBM channel chimney per
# row, attached at column gx=0's West port; gen_hbm_east symmetric on the
# right -- North/South boundaries are dead-ended, no chimney). To render
# these as real spatial nodes (not just a color on the boundary groups), the
# grid gains one extra column on each side: width becomes NumGroupsX+2,
# groups shift to columns 1..NumGroupsX, column 0 holds West HBM channels
# (ids 0..NumGroupsY-1) and the far column holds East HBM channels (ids
# NumGroupsY..2*NumGroupsY-1) -- L2_CHANNEL = 2*NumGroupsY. --level l2-origin
# breaks each edge down by originating endpoint (group or HBM channel)
# instead of one aggregate weight, using hdr.src_id -- NOTE this is a
# COLUMN-major id (gx*NumGroupsY+gy, see decode_l2_src_id), different from
# CachePool's own row-major group id used everywhere else.
#
# Usage:
#   noc_profiling_to_vis4mesh.py --level l1 --num-groups-x 4 --num-groups-y 4 \
#     --num-tiles-per-group 4 --num-noc-ports-per-tile 4 \
#     [--input-dir noc_profiling] [--output-dir util/vis4mesh/visdata/cachepool-l1] \
#     [--slice-cycles 500] [--clk-freq 500]
#   noc_profiling_to_vis4mesh.py --level l2 --num-groups-x 4 --num-groups-y 4 \
#     [--input-dir noc_profiling] [--output-dir util/vis4mesh/visdata/cachepool-l2] \
#     [--slice-cycles 500] [--clk-freq 500]

import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROUTER_LOG_RE = re.compile(r'router_g(\d+)_(req|resp)\.log$')
L2_ROUTER_LOG_RE = re.compile(r'l2_router_g(\d+)_(req|resp)\.log$')

# floo_pkg.sv direction encoding (North=y+, East=x+, South=y-, West=x-).
DIR_DELTA = {0: (0, 1), 1: (1, 0), 2: (0, -1), 3: (-1, 0)}
EAST = 1
WEST = 3

CH_REQ_READ, CH_REQ_WRITE, CH_RESP = 0, 1, 2
SUB_CHANNELS = (CH_REQ_READ, CH_REQ_WRITE, CH_RESP)

# Mirrors src/data/classification.ts's hardcoded domains -- these sizes are
# NOT read from meta.json by the frontend, so they must match exactly.
NUM_TRANSFER_TYPES = 4   # TransferTypesInOrder.length
NUM_MSG_TYPES = 4        # MsgTypesInOrder.length
NUM_HOP_UNITS = 4         # matches the hardcoded 4-checkbox NoC-#-Hops filter UI
FIXED_TRANSFER_IDX = 0    # "mesh_send" / TX
FIXED_HOP_IDX = 0          # no real per-flit hop-distance tracking (yet)
# MsgTypesInOrder index for each real sub-type -- see module docstring.
MSG_IDX_FOR_SUBCH = {CH_REQ_READ: 1, CH_REQ_WRITE: 3, CH_RESP: 0}


def neighbor(g, portidx, gx_count, gy_count):
    gy, gx = divmod(g, gx_count)
    dx, dy = DIR_DELTA[portidx]
    nx, ny = gx + dx, gy + dy
    if 0 <= nx < gx_count and 0 <= ny < gy_count:
        return ny * gx_count + nx
    return None


def display_id(g, gx_count, gy_count, col_offset=0, width=None):
    """Y-flip: vis4mesh renders row 0 (id // width) at the top; we want
    gy=0 (CachePool's own row-major group id) at the bottom. col_offset/width
    let --level l2 shift group columns right to make room for the HBM
    column at 0."""
    gy, gx = divmod(g, gx_count)
    w = width if width is not None else gx_count
    return (gy_count - 1 - gy) * w + (gx + col_offset)


def write_json(path, obj):
    with open(path, 'w') as f:
        json.dump(obj, f)


def new_subch_vecs(link_channels):
    """Per-edge accumulator: one [link_channels]-length vector per sub-type."""
    return {sc: [0] * link_channels for sc in SUB_CHANNELS}


def build_value(subch_vecs, link_channels, value_len):
    """Places each sub-type's link/origin-indexed vector at ITS OWN
    msg_type slot (MSG_IDX_FOR_SUBCH), all at the fixed transfer/hop slot."""
    vec = [0] * value_len
    for sc, link_vec in subch_vecs.items():
        msg_idx = MSG_IDX_FOR_SUBCH[sc]
        base = ((FIXED_TRANSFER_IDX * NUM_HOP_UNITS + FIXED_HOP_IDX) * NUM_MSG_TYPES
                + msg_idx) * link_channels
        vec[base:base + link_channels] = link_vec
    return vec


def convert_l1(args):
    gx_count, gy_count = args.num_groups_x, args.num_groups_y
    num_groups = gx_count * gy_count
    num_tiles = args.num_tiles_per_group
    num_ports = args.num_noc_ports_per_tile
    if num_tiles is None or num_ports is None:
        print('--level l1 requires --num-tiles-per-group and --num-noc-ports-per-tile',
              file=sys.stderr)
        sys.exit(1)
    link_channels = num_tiles * num_ports  # physical links per mesh edge
    value_len = NUM_TRANSFER_TYPES * NUM_HOP_UNITS * NUM_MSG_TYPES * link_channels

    router_files = sorted(glob.glob(os.path.join(args.input_dir, 'router_g*_*.log')))
    if not router_files:
        print(f'no router_g*_{{req,resp}}.log found in {args.input_dir} '
              f'(did the sim run with +define+NOC_PROFILING and num_rg_ports_per_core > 0?)',
              file=sys.stderr)
        sys.exit(1)

    # edge_counts[(slice, g_src, g_dst)] = {sub_ch: [link_channels]}
    edge_counts = defaultdict(lambda: new_subch_vecs(link_channels))
    for path in router_files:
        m = ROUTER_LOG_RE.search(os.path.basename(path))
        if not m:
            continue
        g_src = int(m.group(1))
        is_resp = m.group(2) == 'resp'
        with open(path, 'r', errors='replace') as f:
            for line in f:
                tok = line.split()
                if len(tok) < 2:
                    continue
                noc_port = int(tok[0])  # flat tile*num_ports+port physical-link id
                body = tok[1:]
                if body[0] != 'P':
                    continue
                portidx = int(body[1])
                if portidx == 4:
                    continue
                io = int(body[2])
                if io != 1:  # only count the OUTPUT ("so") handshake once per hop
                    continue
                cyc = int(body[3])
                slc = cyc // args.slice_cycles
                if is_resp:
                    sub_ch = CH_RESP
                else:
                    wen = int(body[4])
                    sub_ch = CH_REQ_WRITE if wen else CH_REQ_READ
                g_dst = neighbor(g_src, portidx, gx_count, gy_count)
                if g_dst is None:
                    continue  # boundary router edge with nothing wired beyond it
                edge_counts[(slc, g_src, g_dst)][sub_ch][noc_port] += 1

    if not edge_counts:
        print('no accepted mesh-direction flits found in the logs -- '
              'router/tile traces are legitimately empty when '
              'NumRemoteGroupPortCore == 0 (single-group build)', file=sys.stderr)

    max_slice = max((k[0] for k in edge_counts), default=0)

    topology = []
    for g in range(num_groups):
        for portidx in range(4):
            g_dst = neighbor(g, portidx, gx_count, gy_count)
            if g_dst is not None:
                topology.append((g, g_dst))

    os.makedirs(args.output_dir, exist_ok=True)
    edge_dir = os.path.join(args.output_dir, 'edge_prefix_sum')
    os.makedirs(edge_dir, exist_ok=True)

    slice_seconds = args.slice_cycles / (args.clk_freq * 1e6)
    channel_labels = [f"T{t}_C{n}" for t in range(num_tiles) for n in range(num_ports)]
    channel_groups = [
        {"name": f"Tile {t}", "channels": list(range(t * num_ports, (t + 1) * num_ports))}
        for t in range(num_tiles)
    ]
    write_json(os.path.join(args.output_dir, 'meta.json'), {
        "width": str(gx_count),
        "height": str(gy_count),
        "slice": f"{slice_seconds:.9f}",
        "elapse": str(max_slice + 1),
        "hops_per_unit": "1",
        "num_hop_units": str(NUM_HOP_UNITS),
        "num_channels": link_channels,
        "channel_labels": channel_labels,
        "channel_groups": channel_groups,
    })

    nodes = []
    for g in range(num_groups):
        gy, gx = divmod(g, gx_count)
        nodes.append({
            "id": display_id(g, gx_count, gy_count),
            "label": f"G{g}",
            "detail": f"Group[{gx},{gy}]",
        })
    write_json(os.path.join(args.output_dir, 'nodes.json'), nodes)

    empty = new_subch_vecs(link_channels)
    for slc in range(max_slice + 1):
        edges = []
        for (g_src, g_dst) in topology:
            subch_vecs = edge_counts.get((slc, g_src, g_dst), empty)
            edges.append({
                "source": display_id(g_src, gx_count, gy_count),
                "target": display_id(g_dst, gx_count, gy_count),
                "value": build_value(subch_vecs, link_channels, value_len),
            })
        write_json(os.path.join(edge_dir, f'{slc}.json'), edges)

    # flat.json -- one summary row per (slice, sub-channel), summed across
    # physical links. "group" must be one of
    # src/data/classification.ts's fixed MsgGroupsDomain
    # (["Translation","Read","Write","Others"]) or the stacked timebar chart
    # silently drops it (not in its z-domain).
    type_meta = {
        CH_REQ_READ: ("ReqRead", "Read", "D"),
        CH_REQ_WRITE: ("ReqWrite", "Write", "D"),
        CH_RESP: ("Resp", "Others", "D"),
    }
    per_slice_sub_totals = defaultdict(lambda: {sc: 0 for sc in SUB_CHANNELS})
    for (slc, g_src, g_dst), subch_vecs in edge_counts.items():
        for sc, link_vec in subch_vecs.items():
            per_slice_sub_totals[slc][sc] += sum(link_vec)
    max_flits = max((sum(d.values()) for d in per_slice_sub_totals.values()), default=0)

    flat = []
    for slc in range(max_slice + 1):
        totals = per_slice_sub_totals.get(slc, {sc: 0 for sc in SUB_CHANNELS})
        for sc in SUB_CHANNELS:
            type_name, group_name, doc = type_meta[sc]
            flat.append({
                "id": slc, "type": type_name, "group": group_name, "doc": doc,
                "count": totals[sc], "max_flits": max_flits,
                "hop_units": 0, "transfer_type": 0,
            })
    write_json(os.path.join(args.output_dir, 'flat.json'), flat)

    total_flits = sum(sum(v) for d in edge_counts.values() for v in d.values())
    print(f'wrote {args.output_dir}: {num_groups} nodes ({gx_count}x{gy_count}), '
          f'{len(topology)} directed mesh edges, {max_slice + 1} time slices '
          f'({args.slice_cycles} cyc/slice), {total_flits} accepted flits total, '
          f'{link_channels} physical links/edge, value[] length {value_len}')


def convert_l1_origin(args):
    """Same L1 mesh topology as --level l1, but channels break down each
    edge's traffic by ORIGINATING group instead of by physical link -- i.e.
    "how much of this link's traffic came from group N", not "which
    tile/port carried it". Uses hdr.src_id.x/y, which every router_g*.log P
    line already carries: it's stamped once at injection
    (cachepool_group_noc_wrapper.sv's packed_req[...].hdr.src_id =
    group_xy_id_i) and never rewritten as floo_router relays the flit
    through intermediate hops, so it identifies the true original sender
    even many hops away -- not just the previous relay.
    """
    gx_count, gy_count = args.num_groups_x, args.num_groups_y
    num_groups = gx_count * gy_count
    link_channels = num_groups  # channel = origin group
    value_len = NUM_TRANSFER_TYPES * NUM_HOP_UNITS * NUM_MSG_TYPES * link_channels

    router_files = sorted(glob.glob(os.path.join(args.input_dir, 'router_g*_*.log')))
    if not router_files:
        print(f'no router_g*_{{req,resp}}.log found in {args.input_dir} '
              f'(did the sim run with +define+NOC_PROFILING and num_rg_ports_per_core > 0?)',
              file=sys.stderr)
        sys.exit(1)

    # edge_counts[(slice, g_link_src, g_link_dst)] = {sub_ch: [num_groups]}.
    # g_link_src/g_link_dst are the two ends of the PHYSICAL LINK (adjacent
    # groups); the origin_group index within each vector is who actually
    # sent the flit, which may be several hops further away.
    edge_counts = defaultdict(lambda: new_subch_vecs(link_channels))
    for path in router_files:
        m = ROUTER_LOG_RE.search(os.path.basename(path))
        if not m:
            continue
        g_link_src = int(m.group(1))
        is_resp = m.group(2) == 'resp'
        with open(path, 'r', errors='replace') as f:
            for line in f:
                tok = line.split()
                if len(tok) < 2:
                    continue
                body = tok[1:]
                if body[0] != 'P':
                    continue
                portidx = int(body[1])
                if portidx == 4:
                    continue
                io = int(body[2])
                if io != 1:  # only count the OUTPUT ("so") handshake once per hop
                    continue
                cyc = int(body[3])
                slc = cyc // args.slice_cycles
                if is_resp:
                    sub_ch = CH_RESP
                    src_x, src_y = int(body[6]), int(body[7])
                else:
                    wen = int(body[4])
                    sub_ch = CH_REQ_WRITE if wen else CH_REQ_READ
                    src_x, src_y = int(body[8]), int(body[9])
                g_link_dst = neighbor(g_link_src, portidx, gx_count, gy_count)
                if g_link_dst is None:
                    continue  # boundary router edge with nothing wired beyond it
                origin_group = src_y * gx_count + src_x
                edge_counts[(slc, g_link_src, g_link_dst)][sub_ch][origin_group] += 1

    if not edge_counts:
        print('no accepted mesh-direction flits found in the logs -- '
              'router/tile traces are legitimately empty when '
              'NumRemoteGroupPortCore == 0 (single-group build)', file=sys.stderr)

    max_slice = max((k[0] for k in edge_counts), default=0)

    topology = []
    for g in range(num_groups):
        for portidx in range(4):
            g_dst = neighbor(g, portidx, gx_count, gy_count)
            if g_dst is not None:
                topology.append((g, g_dst))

    os.makedirs(args.output_dir, exist_ok=True)
    edge_dir = os.path.join(args.output_dir, 'edge_prefix_sum')
    os.makedirs(edge_dir, exist_ok=True)

    slice_seconds = args.slice_cycles / (args.clk_freq * 1e6)
    channel_labels = [f"From_G{og}" for og in range(num_groups)]
    channel_groups = [{"name": f"From G{og}", "channels": [og]} for og in range(num_groups)]
    write_json(os.path.join(args.output_dir, 'meta.json'), {
        "width": str(gx_count),
        "height": str(gy_count),
        "slice": f"{slice_seconds:.9f}",
        "elapse": str(max_slice + 1),
        "hops_per_unit": "1",
        "num_hop_units": str(NUM_HOP_UNITS),
        "num_channels": link_channels,
        "channel_labels": channel_labels,
        "channel_groups": channel_groups,
    })

    nodes = []
    for g in range(num_groups):
        gy, gx = divmod(g, gx_count)
        nodes.append({
            "id": display_id(g, gx_count, gy_count),
            "label": f"G{g}",
            "detail": f"Group[{gx},{gy}]",
        })
    write_json(os.path.join(args.output_dir, 'nodes.json'), nodes)

    empty = new_subch_vecs(link_channels)
    for slc in range(max_slice + 1):
        edges = []
        for (g_src, g_dst) in topology:
            subch_vecs = edge_counts.get((slc, g_src, g_dst), empty)
            edges.append({
                "source": display_id(g_src, gx_count, gy_count),
                "target": display_id(g_dst, gx_count, gy_count),
                "value": build_value(subch_vecs, link_channels, value_len),
            })
        write_json(os.path.join(edge_dir, f'{slc}.json'), edges)

    # flat.json -- one summary row per (slice, sub-channel), summed across
    # origin groups.
    type_meta = {
        CH_REQ_READ: ("ReqRead", "Read", "D"),
        CH_REQ_WRITE: ("ReqWrite", "Write", "D"),
        CH_RESP: ("Resp", "Others", "D"),
    }
    per_slice_sub_totals = defaultdict(lambda: {sc: 0 for sc in SUB_CHANNELS})
    for (slc, g_src, g_dst), subch_vecs in edge_counts.items():
        for sc, link_vec in subch_vecs.items():
            per_slice_sub_totals[slc][sc] += sum(link_vec)
    max_flits = max((sum(d.values()) for d in per_slice_sub_totals.values()), default=0)

    flat = []
    for slc in range(max_slice + 1):
        totals = per_slice_sub_totals.get(slc, {sc: 0 for sc in SUB_CHANNELS})
        for sc in SUB_CHANNELS:
            type_name, group_name, doc = type_meta[sc]
            flat.append({
                "id": slc, "type": type_name, "group": group_name, "doc": doc,
                "count": totals[sc], "max_flits": max_flits,
                "hop_units": 0, "transfer_type": 0,
            })
    write_json(os.path.join(args.output_dir, 'flat.json'), flat)

    total_flits = sum(sum(v) for d in edge_counts.values() for v in d.values())
    print(f'wrote {args.output_dir}: {num_groups} nodes ({gx_count}x{gy_count}), '
          f'{len(topology)} directed mesh edges, {max_slice + 1} time slices '
          f'({args.slice_cycles} cyc/slice), {total_flits} accepted flits total, '
          f'{num_groups} origin channels, value[] length {value_len}')


def convert_l2(args):
    gx_count, gy_count = args.num_groups_x, args.num_groups_y
    num_groups = gx_count * gy_count
    link_channels = 1  # single physical link per group, per your "one channel" request
    value_len = NUM_TRANSFER_TYPES * NUM_HOP_UNITS * NUM_MSG_TYPES * link_channels
    # +1 column each side: West HBM channels (cachepool_cluster.sv's
    # gen_hbm_west, ids 0..NumGroupsY-1) at column 0, East HBM channels
    # (gen_hbm_east, ids NumGroupsY..2*NumGroupsY-1) at the far right --
    # L2_CHANNEL = 2*NumGroupsY, split evenly between the two boundaries.
    grid_width = gx_count + 2

    router_files = sorted(glob.glob(os.path.join(args.input_dir, 'l2_router_g*_*.log')))
    if not router_files:
        print(f'no l2_router_g*_{{req,resp}}.log found in {args.input_dir} '
              f'(did the sim run with +define+NOC_PROFILING?)', file=sys.stderr)
        sys.exit(1)

    # edge_counts[(slice, g_src, g_dst_or_hbm_key)] = {sub_ch: [1]}
    edge_counts = defaultdict(lambda: new_subch_vecs(link_channels))

    def hbm_key(side, gy):
        return ('hbm', side, gy)  # side: 'W' or 'E'

    for path in router_files:
        m = L2_ROUTER_LOG_RE.search(os.path.basename(path))
        if not m:
            continue
        g_src = int(m.group(1))
        gy_src, gx_src = divmod(g_src, gx_count)
        is_resp = m.group(2) == 'resp'
        with open(path, 'r', errors='replace') as f:
            for line in f:
                tok = line.split()
                if len(tok) < 2 or tok[0] != 'P':
                    continue
                portidx = int(tok[1])
                io = int(tok[2])
                if io != 1:  # only count the OUTPUT ("so") handshake once per hop
                    continue
                cyc = int(tok[3])
                slc = cyc // args.slice_cycles
                if is_resp:
                    sub_ch = CH_RESP
                else:
                    wen = int(tok[4])
                    sub_ch = CH_REQ_WRITE if wen else CH_REQ_READ
                g_dst = neighbor(g_src, portidx, gx_count, gy_count)
                if g_dst is not None:
                    edge_counts[(slc, g_src, g_dst)][sub_ch][0] += 1
                elif portidx == WEST and gx_src == 0:
                    # West-boundary link with no group neighbor -> that row's
                    # West HBM channel chimney (gen_hbm_west).
                    edge_counts[(slc, g_src, hbm_key('W', gy_src))][sub_ch][0] += 1
                elif portidx == EAST and gx_src == gx_count - 1:
                    # East-boundary link -> that row's East HBM channel
                    # chimney (gen_hbm_east). North/South boundaries are
                    # dead-ended (no chimney) and drop here.
                    edge_counts[(slc, g_src, hbm_key('E', gy_src))][sub_ch][0] += 1

    if not edge_counts:
        print('no accepted L2 mesh-direction flits found in the logs', file=sys.stderr)

    max_slice = max((k[0] for k in edge_counts), default=0)

    # Topology: ordinary group-group mesh edges, plus one group->HBM edge per
    # row from each boundary column (gx=0 -> West, gx=gx_count-1 -> East).
    topology = []
    for g in range(num_groups):
        for portidx in range(4):
            g_dst = neighbor(g, portidx, gx_count, gy_count)
            if g_dst is not None:
                topology.append((g, g_dst))
    for gy in range(gy_count):
        g_west = gy * gx_count
        g_east = gy * gx_count + (gx_count - 1)
        topology.append((g_west, hbm_key('W', gy)))
        topology.append((g_east, hbm_key('E', gy)))

    os.makedirs(args.output_dir, exist_ok=True)
    edge_dir = os.path.join(args.output_dir, 'edge_prefix_sum')
    os.makedirs(edge_dir, exist_ok=True)

    slice_seconds = args.slice_cycles / (args.clk_freq * 1e6)
    write_json(os.path.join(args.output_dir, 'meta.json'), {
        "width": str(grid_width),
        "height": str(gy_count),
        "slice": f"{slice_seconds:.9f}",
        "elapse": str(max_slice + 1),
        "hops_per_unit": "1",
        "num_hop_units": str(NUM_HOP_UNITS),
        "num_channels": link_channels,
        "channel_labels": ["L2Traffic"],
        "channel_groups": [{"name": "L2 Traffic", "channels": [0]}],
    })

    def hbm_id(side, gy):
        col = 0 if side == 'W' else grid_width - 1
        return (gy_count - 1 - gy) * grid_width + col

    nodes = []
    for g in range(num_groups):
        gy, gx = divmod(g, gx_count)
        nodes.append({
            "id": display_id(g, gx_count, gy_count, col_offset=1, width=grid_width),
            "label": f"G{g}",
            "detail": f"Group[{gx},{gy}]",
        })
    for gy in range(gy_count):
        nodes.append({
            "id": hbm_id('W', gy),
            "label": f"HBM{gy}",
            "detail": f"HBM channel {gy} (West)",
        })
        nodes.append({
            "id": hbm_id('E', gy),
            "label": f"HBM{gy_count + gy}",
            "detail": f"HBM channel {gy_count + gy} (East)",
        })
    write_json(os.path.join(args.output_dir, 'nodes.json'), nodes)

    def node_disp_id(key):
        if isinstance(key, tuple):
            return hbm_id(key[1], key[2])
        return display_id(key, gx_count, gy_count, col_offset=1, width=grid_width)

    empty = new_subch_vecs(link_channels)
    for slc in range(max_slice + 1):
        edges = []
        for (g_src, dst_key) in topology:
            subch_vecs = edge_counts.get((slc, g_src, dst_key), empty)
            edges.append({
                "source": node_disp_id(g_src),
                "target": node_disp_id(dst_key),
                "value": build_value(subch_vecs, link_channels, value_len),
            })
        write_json(os.path.join(edge_dir, f'{slc}.json'), edges)

    type_meta = {
        CH_REQ_READ: ("ReqRead", "Read", "D"),
        CH_REQ_WRITE: ("ReqWrite", "Write", "D"),
        CH_RESP: ("Resp", "Others", "D"),
    }
    per_slice_sub_totals = defaultdict(lambda: {sc: 0 for sc in SUB_CHANNELS})
    for (slc, g_src, dst_key), subch_vecs in edge_counts.items():
        for sc, link_vec in subch_vecs.items():
            per_slice_sub_totals[slc][sc] += sum(link_vec)
    max_flits = max((sum(d.values()) for d in per_slice_sub_totals.values()), default=0)

    flat = []
    for slc in range(max_slice + 1):
        totals = per_slice_sub_totals.get(slc, {sc: 0 for sc in SUB_CHANNELS})
        for sc in SUB_CHANNELS:
            type_name, group_name, doc = type_meta[sc]
            flat.append({
                "id": slc, "type": type_name, "group": group_name, "doc": doc,
                "count": totals[sc], "max_flits": max_flits,
                "hop_units": 0, "transfer_type": 0,
            })
    write_json(os.path.join(args.output_dir, 'flat.json'), flat)

    total_flits = sum(sum(v) for d in edge_counts.values() for v in d.values())
    print(f'wrote {args.output_dir}: {num_groups} group nodes + {2 * gy_count} HBM nodes '
          f'({grid_width}x{gy_count} grid), {len(topology)} directed edges, '
          f'{max_slice + 1} time slices ({args.slice_cycles} cyc/slice), '
          f'{total_flits} accepted flits total, 1 channel, value[] length {value_len}')


def decode_l2_src_id(src_id, num_groups, gy_count):
    """cachepool_cluster.sv assigns each group's L2 endpoint id as
    `gx * NumGroupsY + gy` (COLUMN-major -- different from CachePool's own
    row-major group id g=gy*NumGroupsX+gx used everywhere else!) and HBM
    chimneys ids NumGroups+HbmIdx (West: HbmIdx=gy, East: HbmIdx=NumGroupsY+gy;
    see cachepool_cluster.sv's gen_hbm_west/gen_hbm_east). Returns either
    ('group', flat_row_major_g) or ('hbm', 'W'|'E', gy)."""
    if src_id < num_groups:
        gx, gy = divmod(src_id, gy_count)
        return ('group', gy * (num_groups // gy_count) + gx)
    hbm_idx = src_id - num_groups
    if hbm_idx < gy_count:
        return ('hbm', 'W', hbm_idx)
    return ('hbm', 'E', hbm_idx - gy_count)


def convert_l2_origin(args):
    """Same L2 mesh topology as --level l2, but the weight is broken down by
    ORIGINATING endpoint (group or HBM channel) instead of summed into one
    aggregate -- uses hdr.src_id, stamped once at injection (each group's
    manager chimney or an HBM subordinate chimney) and never rewritten by
    relay hops, so it identifies the true origin even several hops away.
    Group chimneys are manager-port-only (can only ORIGINATE requests, never
    respond) and HBM chimneys are subordinate-port-only (can only respond,
    never originate a request) -- verified empirically against the logs:
    every req-file flit's src_id decodes to a group, every resp-file flit's
    decodes to an HBM channel. So origin=group implies read/write (an
    origin-group vector only ever has CH_REQ_READ/CH_REQ_WRITE populated),
    and origin=HBM implies CH_RESP -- not a coincidence, a topology
    invariant."""
    gx_count, gy_count = args.num_groups_x, args.num_groups_y
    num_groups = gx_count * gy_count
    link_channels = num_groups + 2 * gy_count  # every group + every HBM channel
    value_len = NUM_TRANSFER_TYPES * NUM_HOP_UNITS * NUM_MSG_TYPES * link_channels
    grid_width = gx_count + 2

    router_files = sorted(glob.glob(os.path.join(args.input_dir, 'l2_router_g*_*.log')))
    if not router_files:
        print(f'no l2_router_g*_{{req,resp}}.log found in {args.input_dir} '
              f'(did the sim run with +define+NOC_PROFILING?)', file=sys.stderr)
        sys.exit(1)

    def hbm_key(side, gy):
        return ('hbm', side, gy)

    def origin_channel(kind):
        if kind[0] == 'group':
            return kind[1]
        # kind = ('hbm', side, gy)
        return num_groups + (kind[2] if kind[1] == 'W' else gy_count + kind[2])

    # edge_counts[(slice, g_src_link, dst_key)] = {sub_ch: [link_channels]}
    edge_counts = defaultdict(lambda: new_subch_vecs(link_channels))
    for path in router_files:
        m = L2_ROUTER_LOG_RE.search(os.path.basename(path))
        if not m:
            continue
        g_src = int(m.group(1))
        gy_src, gx_src = divmod(g_src, gx_count)
        is_resp = m.group(2) == 'resp'
        with open(path, 'r', errors='replace') as f:
            for line in f:
                tok = line.split()
                if len(tok) < 2 or tok[0] != 'P':
                    continue
                portidx = int(tok[1])
                io = int(tok[2])
                if io != 1:
                    continue
                cyc = int(tok[3])
                slc = cyc // args.slice_cycles
                if is_resp:
                    sub_ch = CH_RESP
                else:
                    wen = int(tok[4])
                    sub_ch = CH_REQ_WRITE if wen else CH_REQ_READ
                # src_id is always the last token: req P line is
                # "P d io cyc wen addr src_id" (7 tokens), resp P line is
                # "P d io cyc src_id" (5 tokens).
                src_id = int(tok[-1])
                ch = origin_channel(decode_l2_src_id(src_id, num_groups, gy_count))
                g_dst = neighbor(g_src, portidx, gx_count, gy_count)
                if g_dst is not None:
                    edge_counts[(slc, g_src, g_dst)][sub_ch][ch] += 1
                elif portidx == WEST and gx_src == 0:
                    edge_counts[(slc, g_src, hbm_key('W', gy_src))][sub_ch][ch] += 1
                elif portidx == EAST and gx_src == gx_count - 1:
                    edge_counts[(slc, g_src, hbm_key('E', gy_src))][sub_ch][ch] += 1

    if not edge_counts:
        print('no accepted L2 mesh-direction flits found in the logs', file=sys.stderr)

    max_slice = max((k[0] for k in edge_counts), default=0)

    topology = []
    for g in range(num_groups):
        for portidx in range(4):
            g_dst = neighbor(g, portidx, gx_count, gy_count)
            if g_dst is not None:
                topology.append((g, g_dst))
    for gy in range(gy_count):
        g_west = gy * gx_count
        g_east = gy * gx_count + (gx_count - 1)
        topology.append((g_west, hbm_key('W', gy)))
        topology.append((g_east, hbm_key('E', gy)))

    os.makedirs(args.output_dir, exist_ok=True)
    edge_dir = os.path.join(args.output_dir, 'edge_prefix_sum')
    os.makedirs(edge_dir, exist_ok=True)

    slice_seconds = args.slice_cycles / (args.clk_freq * 1e6)
    channel_labels = [f"Req_From_G{og}" for og in range(num_groups)]
    channel_labels += [f"Resp_From_HBM{gy}" for gy in range(gy_count)]           # West, ids NumGroups..
    channel_labels += [f"Resp_From_HBM{gy_count + gy}" for gy in range(gy_count)]  # East
    channel_groups = [
        {"name": "Request (from Groups)", "channels": list(range(num_groups))},
        {"name": "Response (from HBM)", "channels": list(range(num_groups, link_channels))},
    ]
    write_json(os.path.join(args.output_dir, 'meta.json'), {
        "width": str(grid_width),
        "height": str(gy_count),
        "slice": f"{slice_seconds:.9f}",
        "elapse": str(max_slice + 1),
        "hops_per_unit": "1",
        "num_hop_units": str(NUM_HOP_UNITS),
        "num_channels": link_channels,
        "channel_labels": channel_labels,
        "channel_groups": channel_groups,
    })

    def hbm_id(side, gy):
        col = 0 if side == 'W' else grid_width - 1
        return (gy_count - 1 - gy) * grid_width + col

    nodes = []
    for g in range(num_groups):
        gy, gx = divmod(g, gx_count)
        nodes.append({
            "id": display_id(g, gx_count, gy_count, col_offset=1, width=grid_width),
            "label": f"G{g}",
            "detail": f"Group[{gx},{gy}]",
        })
    for gy in range(gy_count):
        nodes.append({"id": hbm_id('W', gy), "label": f"HBM{gy}",
                       "detail": f"HBM channel {gy} (West)"})
        nodes.append({"id": hbm_id('E', gy), "label": f"HBM{gy_count + gy}",
                       "detail": f"HBM channel {gy_count + gy} (East)"})
    write_json(os.path.join(args.output_dir, 'nodes.json'), nodes)

    def node_disp_id(key):
        if isinstance(key, tuple):
            return hbm_id(key[1], key[2])
        return display_id(key, gx_count, gy_count, col_offset=1, width=grid_width)

    empty = new_subch_vecs(link_channels)
    for slc in range(max_slice + 1):
        edges = []
        for (g_src, dst_key) in topology:
            subch_vecs = edge_counts.get((slc, g_src, dst_key), empty)
            edges.append({
                "source": node_disp_id(g_src),
                "target": node_disp_id(dst_key),
                "value": build_value(subch_vecs, link_channels, value_len),
            })
        write_json(os.path.join(edge_dir, f'{slc}.json'), edges)

    type_meta = {
        CH_REQ_READ: ("ReqRead", "Read", "D"),
        CH_REQ_WRITE: ("ReqWrite", "Write", "D"),
        CH_RESP: ("Resp", "Others", "D"),
    }
    per_slice_sub_totals = defaultdict(lambda: {sc: 0 for sc in SUB_CHANNELS})
    for (slc, g_src, dst_key), subch_vecs in edge_counts.items():
        for sc, link_vec in subch_vecs.items():
            per_slice_sub_totals[slc][sc] += sum(link_vec)
    max_flits = max((sum(d.values()) for d in per_slice_sub_totals.values()), default=0)

    flat = []
    for slc in range(max_slice + 1):
        totals = per_slice_sub_totals.get(slc, {sc: 0 for sc in SUB_CHANNELS})
        for sc in SUB_CHANNELS:
            type_name, group_name, doc = type_meta[sc]
            flat.append({
                "id": slc, "type": type_name, "group": group_name, "doc": doc,
                "count": totals[sc], "max_flits": max_flits,
                "hop_units": 0, "transfer_type": 0,
            })
    write_json(os.path.join(args.output_dir, 'flat.json'), flat)

    total_flits = sum(sum(v) for d in edge_counts.values() for v in d.values())
    print(f'wrote {args.output_dir}: {num_groups} group nodes + {2 * gy_count} HBM nodes '
          f'({grid_width}x{gy_count} grid), {len(topology)} directed edges, '
          f'{max_slice + 1} time slices ({args.slice_cycles} cyc/slice), '
          f'{total_flits} accepted flits total, {link_channels} origin channels, '
          f'value[] length {value_len}')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--level', choices=['l1', 'l1-origin', 'l2', 'l2-origin'], default='l1')
    ap.add_argument('--input-dir', default='noc_profiling',
                     help='directory with the *.log files (default: noc_profiling)')
    ap.add_argument('--output-dir', required=True,
                     help='Vis4Mesh dataset directory to write (upload this whole directory)')
    ap.add_argument('--num-groups-x', type=int, required=True)
    ap.add_argument('--num-groups-y', type=int, required=True)
    ap.add_argument('--num-tiles-per-group', type=int, default=None,
                     help='required for --level l1')
    ap.add_argument('--num-noc-ports-per-tile', type=int, default=None,
                     help='required for --level l1')
    ap.add_argument('--slice-cycles', type=int, default=500,
                     help='cycles per time slice bucket (default: 500)')
    ap.add_argument('--clk-freq', type=float, default=500.0,
                     help='clock frequency in MHz, for meta.json "slice" seconds-per-slice (default: 500)')
    args = ap.parse_args()

    if args.level == 'l1':
        convert_l1(args)
    elif args.level == 'l1-origin':
        convert_l1_origin(args)
    elif args.level == 'l2':
        convert_l2(args)
    else:
        convert_l2_origin(args)


if __name__ == '__main__':
    main()
