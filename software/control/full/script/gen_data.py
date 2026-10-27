#!/usr/bin/env python3
# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Generates data/<cfg>.h for the full control algorithm: the inputs (R1 and A
# with the padded row pitch of uv-init) and the expected P, ResAllocMap,
# UserResAllocMap and winner of every iteration from common/golden.py.

import argparse
import pathlib
import sys

import hjson
import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "common"))
import golden  # noqa: E402

LINE = 16


def pitch(k):
    lines = (k + LINE - 1) // LINE
    return LINE * (lines if lines % 2 else lines + 1)


def padded(a, lda):
    out = np.zeros((a.shape[0], lda), dtype=np.int64)
    out[:, :a.shape[1]] = a
    return out


def c_array(name, a, section=".data"):
    vals = ", ".join(str(int(v)) for v in np.asarray(a).flat)
    return (f'static int32_t {name}[{np.asarray(a).size}] '
            f'__attribute__((section("{section}"), aligned(64))) = {{{vals}}};\n\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True)
    args = parser.parse_args()
    cfg = hjson.loads(args.cfg.read_text())
    m, n = cfg["M"], cfg["N"]
    assert m <= 64 and n <= 128

    inp = golden.gen_inputs(m, n, cfg.get("seed", 1))
    if cfg.get("init", "random") == "mix":
        # every other row of R1 from [30, 50] (still inside [-50, 50]): those
        # U rows grow into the clamp, the others stay clear of it, so both
        # the skipped rows and the column fix-up are exercised
        rng = np.random.default_rng(cfg.get("seed", 1) + 1000)
        inp["R1"][0::2] = rng.integers(30, 51, size=inp["R1"][0::2].shape)
    ref = golden.control_algo(**inp, iters=cfg.get("iters"))
    win = np.zeros((n, 3), dtype=np.int64)
    for j, (w, k, gain) in enumerate(ref["winners"]):
        win[j] = (w, k, gain)

    out = ("// Copyright 2025 ETH Zurich and University of Bologna.\n"
           "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n"
           "// SPDX-License-Identifier: Apache-2.0\n\n"
           "// This file was generated automatically by script/gen_data.py.\n\n"
           "#include <stdint.h>\n\n"
           f"#define CTRL_M {m}\n#define CTRL_N {n}\n"
           f"#define CTRL_LDA_R1 {pitch(m)}\n#define CTRL_LDA_A {pitch(n)}\n"
           f"#define CTRL_ITERS {len(ref['winners'])}\n")
    if "warm_iters" in cfg:
        out += f"#define CTRL_WARM_ITERS {cfg['warm_iters']}\n"
    out += "\n"
    out += c_array("ctrl_R1", padded(inp["R1"], pitch(m)))
    out += c_array("ctrl_A", padded(inp["A"], pitch(n)))
    out += c_array("ctrl_R2_in", inp["R2"])
    for key in ["C", "D"]:
        out += c_array(f"ctrl_{key}", inp[key])
    out += c_array("ctrl_P_exp", ref["P"])
    out += c_array("ctrl_res_exp", ref["ResAllocMap"])
    out += c_array("ctrl_ua_exp", ref["UserResAllocMap"])
    out += c_array("ctrl_win_exp", win)

    dst = pathlib.Path(__file__).resolve().parents[1] / "data" / (args.cfg.stem + ".h")
    dst.write_text(out)


if __name__ == "__main__":
    main()
