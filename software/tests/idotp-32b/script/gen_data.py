#!/usr/bin/env python3
# Integer dot-product data generator (signed, fixed-precision MAC with wrap)
# Values limited to [-100, 100] to reduce overflow risk.

import numpy as np
import argparse
import pathlib
import hjson

np.random.seed(42)

def array_to_cstr(a):
    a = np.asarray(a).reshape(-1)
    return "{" + ", ".join(str(int(x)) for x in a) + "}"

def twos_wrap(x: int, bits: int) -> int:
    mask = (1 << bits) - 1
    x &= mask
    sign_bit = 1 << (bits - 1)
    return x - (1 << bits) if (x & sign_bit) else x

def c_int_type(bits: int) -> str:
    assert bits in (8, 16, 32, 64)
    return f"int{bits}_t"

def emit_dotp_layer(name="dotp", **kwargs) -> str:
    A = kwargs["A"]; B = kwargs["B"]; result = kwargs["result"]
    m = kwargs["M"]; prec = kwargs["prec"]

    etype = c_int_type(prec)
    layer_str = ""
    layer_str += '#include "layer.h"\n'
    layer_str += "#include <stdint.h>\n\n"
    layer_str += f'dotp_layer {name}_l __attribute__((section(".pdcp_src"))) = {{\n'
    layer_str += f"\t.M = {m},\n"
    layer_str += f"\t.dtype = INT{prec},\n"
    layer_str += "};\n\n"

    layer_str += (
        f'static {etype} {name}_A_dram[{m}] __attribute__((section(".data"))) = '
        + array_to_cstr(A) + ";\n\n"
    )
    layer_str += (
        f'static {etype} {name}_B_dram[{m}] __attribute__((section(".data"))) = '
        + array_to_cstr(B) + ";\n\n"
    )
    layer_str += (
        f'static {etype} {name}_result_golden __attribute__((section(".data"))) = '
        + str(int(result)) + ";\n\n"
    )
    layer_str += f"{etype} result[4] __attribute__((section(\".data\"))) = {{0}};\n\n"
    return layer_str

def emit_header_file(**kwargs):
    file_path = pathlib.Path(__file__).parent.parent / "data"
    file_path.mkdir(parents=True, exist_ok=True)
    file = file_path / (f"data_{kwargs['M']}.h")
    header  = "// This file was generated automatically.\n\n"
    header += emit_dotp_layer(**kwargs)
    with file.open("w") as f:
        f.write(header)

def rand_int_signed(shape, lo, hi):
    return np.random.randint(lo, hi + 1, size=shape, dtype=np.int64)

def dotp_wrap_same_width(a: np.ndarray, b: np.ndarray, bits: int) -> int:
    s = 0
    for ai, bi in zip(a.tolist(), b.tolist()):
        prod = twos_wrap(int(ai) * int(bi), bits)
        s = twos_wrap(s + prod, bits)
    return s

def main():
    parser = argparse.ArgumentParser(description="Generate signed-integer dotp data")
    parser.add_argument("-c", "--cfg", type=pathlib.Path, required=True,
                        help="HJSON config with M and prec (8/16/32/64)")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    with args.cfg.open() as f:
        param = hjson.loads(f.read())

    M    = int(param["M"])
    prec = int(param["prec"])  # 8/16/32/64

    # Fixed safe range
    lo, hi = -100, 100
    A = rand_int_signed((M,), lo, hi)
    B = rand_int_signed((M,), lo, hi)
    result = dotp_wrap_same_width(A, B, prec)

    if args.verbose:
        print(f"[gen] M={M} prec={prec} range=[{lo},{hi}]")
        print(f"[gen] A[:8]={A[:8]}  B[:8]={B[:8]}")
        print(f"[gen] golden={result}")

    emit_header_file(name="dotp", A=A, B=B, result=result, M=M, prec=prec)

if __name__ == "__main__":
    main()
