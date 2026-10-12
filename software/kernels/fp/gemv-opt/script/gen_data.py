#!/usr/bin/env python3
# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>
# Author: Diyou Shen <dishen@iis.ee.ethz.ch>

# Generates the GEMV y = A * x for one of two kernel modes, picked by the
# config's `mode`. Both run with tile-private L1 and xbar offset 8, where the
# controller is addr[8 +: log2(C)] (C = cores per tile = controllers per
# tile), and core k of a tile only ever reads 256 B blocks of its own
# controller k, so an m4 vector load is one whole block of one controller.
#
# Every core owns ROWS = 16 * lmul consecutive rows of A over all N columns,
# so no reduction is needed. The output is data/<config name>.h, so configs
# for different modes and cluster shapes build side by side.
#
# hot: A is stored as rows of NT + 1 chunks of C blocks (NT = active tiles),
#
#   A_mem[block row b][chunk T][controller k][64 floats]
#
# A block holds 4 / lmul consecutive columns of the core. Chunk NT of each row
# is left empty, so a tile's consecutive blocks are (NT + 1) chunks apart. That
# stride spreads the tiles over all HBM channels (1 KiB interleave) and walks
# the low set-index bits through every value, so A stays resident in L1.
#
# cold: each group g reads only HBM channel chan_of_group[g], picked against
# the refill-mesh routes so that no mesh link carries more than one channel's
# traffic. A is stored in stripes of `channels` KiB, one 1 KiB slot per
# channel; a group's column (C * T blocks of 256 B, T = tiles per group) fills
# its channel's slot in C * T / 4 consecutive stripes. Core q of the group
# (q = t * C + k) owns block q % 4 of stripe q / 4 of every column (lmul 4).
# Each tile then only reaches a few sets of its controllers, which is fine for
# a single cold iteration.
#
# x is replicated into every core's own controller, 64 entries per block, in
# the same scheme as A. y uses the column-0 position of each core.

import numpy as np
import torch
import argparse
import pathlib
import hjson

np.random.seed(42)
torch.manual_seed(42)

# Hardware layout constants
LINE_FLOATS = 16                        # 512 b cacheline
CTRL_FLOATS = 64                        # 256 B block per controller
SLOT_FLOATS = 256                       # 1 KiB HBM channel interleave


def fmt_list(vals):
    return "{" + ", ".join(str(v) for v in vals) + "}"


def fmt_rows(rows, used):
    # Only the first `used` entries of each row carry data; the rest is left to
    # C's implicit zero-initialisation.
    out = []
    for r in rows:
        out.append("{" + ", ".join(fmt_list(r[i].reshape(-1)) for i in range(used)) + "}")
    return "{\n" + ",\n".join(out) + "}"


def layout_a_hot(mat, tiles, cpt, lmul):
    m, n = mat.shape
    rows = LINE_FLOATS * lmul
    cols_per_blk = CTRL_FLOATS // rows
    a_mem = np.zeros((n // cols_per_blk, tiles + 1, cpt, CTRL_FLOATS), dtype=np.float32)
    for core in range(tiles * cpt):
        t, k = core // cpt, core % cpt
        r0 = core * rows
        for j in range(n):
            off = (j % cols_per_blk) * rows
            a_mem[j // cols_per_blk, t, k, off:off + rows] = mat[r0:r0 + rows, j]
    return a_mem


def layout_x_hot(vec, tiles, cpt):
    n = vec.shape[0]
    x_mem = np.zeros((n // CTRL_FLOATS, tiles + 1, cpt, CTRL_FLOATS), dtype=np.float32)
    for b in range(n // CTRL_FLOATS):
        x_mem[b, :tiles, :, :] = vec[b * CTRL_FLOATS:(b + 1) * CTRL_FLOATS]
    return x_mem


def layout_a_cold(mat, groups, cpg, channels, chan_of_group):
    m, n = mat.shape
    spc = cpg // 4            # stripes per column
    a_mem = np.zeros((n * spc, channels, 4, CTRL_FLOATS), dtype=np.float32)
    for core in range(groups * cpg):
        g, q = core // cpg, core % cpg
        r0 = core * CTRL_FLOATS
        for j in range(n):
            a_mem[j * spc + q // 4, chan_of_group[g], q % 4, :] = mat[r0:r0 + CTRL_FLOATS, j]
    return a_mem


def layout_x_cold(vec, groups, cpg, channels, chan_of_group):
    n = vec.shape[0]
    spc = cpg // 4
    x_mem = np.zeros((n // CTRL_FLOATS * spc, channels, 4, CTRL_FLOATS), dtype=np.float32)
    for g in range(groups):
        for q in range(cpg):
            for b in range(n // CTRL_FLOATS):
                x_mem[b * spc + q // 4, chan_of_group[g], q % 4, :] = \
                    vec[b * CTRL_FLOATS:(b + 1) * CTRL_FLOATS]
    return x_mem


def emit_header_file(cfg_name, **kwargs):
    file_path = pathlib.Path(__file__).parent.parent / "data"
    emit_str = (
        "// Copyright 2025 ETH Zurich and University of Bologna.\n"
        + "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
        + "// SPDX-License-Identifier: Apache-2.0\n\n"
        + "// This file was generated automatically.\n\n"
    )

    file = file_path / (cfg_name + ".h")
    emit_str += emit_gemv_layer(**kwargs)
    with file.open("w") as f:
        f.write(emit_str)


def emit_gemv_layer(name="gemv", **kwargs):
    m, n = kwargs["M"], kwargs["N"]
    groups, lmul = kwargs["groups"], kwargs["lmul"]
    mode, channels = kwargs["mode"], kwargs["channels"]
    cpt, tpg = kwargs["cores_per_tile"], kwargs["tiles_per_group"]
    chan_of_group = kwargs["chan_of_group"]
    a_mem, x_mem, result = kwargs["A"], kwargs["B"], kwargs["result"]
    if mode == "cold":
        # One 1 KiB slot per channel; any slot may carry data
        used = channels
        row = f"[{channels}][{SLOT_FLOATS}]"
        y_rows = cpt * tpg // 4
    else:
        # One chunk per active tile plus one empty chunk
        used = groups * tpg
        row = f"[{used + 1}][{cpt * CTRL_FLOATS}]"
        y_rows = 1

    # Every array starts on a 16 KiB boundary, so the 1 KiB slot index of an
    # address equals its HBM channel modulo the channel count.
    attr = '__attribute__((section(".pdcp_src"), aligned(16384), used))'

    layer_str = ""
    layer_str += '#include "layer.h"\n\n'
    layer_str += f"gemv_layer {name}_l = {{\n"
    layer_str += f"\t.M = {m},\n"
    layer_str += f"\t.N = {n},\n"
    layer_str += f'\t.dtype = FP{kwargs["prec"]},\n'
    layer_str += f"\t.groups = {groups},\n"
    layer_str += f"\t.lmul = {lmul},\n"
    layer_str += f"\t.mode = GEMV_MODE_{mode.upper()},\n"
    layer_str += f"\t.channels = {channels},\n"
    layer_str += f"\t.cores_per_tile = {cpt},\n"
    layer_str += f"\t.tiles_per_group = {tpg},\n"
    layer_str += "};\n\n\n"

    layer_str += (
        f"static const uint32_t {name}_chan_of_group [{len(chan_of_group)}] = "
        + fmt_list(chan_of_group) + ";\n\n\n"
    )
    layer_str += (
        f"static float {name}_A_dram [{a_mem.shape[0]}]{row} {attr} = "
        + fmt_rows(a_mem, used)
        + ";\n\n\n"
    )
    layer_str += (
        f"static float {name}_B_dram [{x_mem.shape[0]}]{row} {attr} = "
        + fmt_rows(x_mem, used)
        + ";\n\n\n"
    )
    layer_str += f"static float {name}_Y_dram [{y_rows}]{row} {attr};\n\n\n"
    layer_str += (
        f'static float {name}_result [{m}] __attribute__((section(".pdcp_src"), used)) = '
        + fmt_list(result)
        + ";\n"
    )

    return layer_str


def main():

    parser = argparse.ArgumentParser(description="Generate data for kernels")
    parser.add_argument(
        "-c",
        "--cfg",
        type=pathlib.Path,
        required=True,
        help="Select param config file kernel",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Set verbose")

    args = parser.parse_args()

    with args.cfg.open() as f:
        param = hjson.loads(f.read())

    m, n = param["M"], param["N"]
    groups, lmul = param["groups"], param["lmul"]
    mode = param.get("mode", "hot")
    cpt = param.get("cores_per_tile", 4)
    tpg = param.get("tiles_per_group", 4)
    channels = param.get("channels", 0)
    chan_of_group = param.get("chan_of_group", [0])
    tiles = groups * tpg
    cpg = cpt * tpg

    if param["prec"] != 32:
        raise ValueError("gemv-opt only supports prec 32")
    if lmul not in (1, 2, 4):
        raise ValueError("lmul must be 1, 2 or 4")
    if m != tiles * cpt * LINE_FLOATS * lmul:
        raise ValueError(f"M must be groups * {cpg * LINE_FLOATS} * lmul")
    if n % CTRL_FLOATS != 0:
        raise ValueError(f"N must be a multiple of {CTRL_FLOATS}")
    if mode not in ("hot", "cold"):
        raise ValueError("mode must be hot or cold")
    if mode == "cold":
        if lmul != 4 or cpg % 4 != 0:
            raise ValueError("cold mode needs lmul 4 and a multiple of 4 cores per group")
        if len(chan_of_group) < groups or len(set(chan_of_group[:groups])) != groups \
                or max(chan_of_group[:groups]) >= channels:
            raise ValueError("chan_of_group must give each active group its own channel")

    mat_A = torch.randn((m, n), requires_grad=False, dtype=torch.float32)
    vec_B = torch.randn((n,), requires_grad=False, dtype=torch.float32)
    result = torch.matmul(mat_A, vec_B)

    if mode == "cold":
        a_mem = layout_a_cold(mat_A.numpy(), groups, cpg, channels, chan_of_group)
        x_mem = layout_x_cold(vec_B.numpy(), groups, cpg, channels, chan_of_group)
    else:
        a_mem = layout_a_hot(mat_A.numpy(), tiles, cpt, lmul)
        x_mem = layout_x_hot(vec_B.numpy(), tiles, cpt)

    kwargs = {
        "A": a_mem,
        "B": x_mem,
        "result": result.numpy(),
        "M": m,
        "N": n,
        "prec": param["prec"],
        "groups": groups,
        "lmul": lmul,
        "mode": mode,
        "channels": channels,
        "cores_per_tile": cpt,
        "tiles_per_group": tpg,
        "chan_of_group": chan_of_group,
    }

    emit_header_file(args.cfg.stem, **kwargs)


if __name__ == "__main__":
    main()
