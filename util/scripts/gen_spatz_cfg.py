#!/usr/bin/env python3
import os, re, argparse, hashlib, sys, pathlib

PLACEHOLDER_RE = re.compile(r"\$\{([A-Za-z0-9_]+)\}")

def read(path): return pathlib.Path(path).read_text()
def write_if_changed(path, data):
    p = pathlib.Path(path)
    old = p.read_text() if p.exists() else None
    if old == data:
        print(f"[gen_hjson] up-to-date: {path}")
        return
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(data)
    tmp.replace(p)
    print(f"[gen_hjson] wrote: {path}")

def bool_str(v):
    # Accept 0/1, true/false, yes/no; output 'true'/'false' for HJSON
    s = str(v).strip().lower()
    return "true" if s in ("1","true","yes","on") else "false"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    tmpl = read(args.template)

    # Auto-discover placeholders in the template
    names = set(PLACEHOLDER_RE.findall(tmpl))

    # Build dynamic values that depend on others
    num_cores = int(os.environ.get("num_cores", "4"))
    cores_array = ",".join(['{ $ref: "#/compute_core_template" }'] * num_cores)

    # Convert spatz_fpu_en -> spatz_fpu_bool for HJSON
    spatz_fpu_bool = bool_str(os.environ.get("spatz_fpu_en", "0"))

    # Memory map defaults if not provided
    dram_addr      = int(os.environ.get("dram_addr",      str(0x80000000)))
    dram_len       = int(os.environ.get("dram_len",       str(0x20000000)))
    uncached_addr  = int(os.environ.get("uncached_addr",  str(0xC0000000)))
    uncached_len   = int(os.environ.get("uncached_len",   str(0x20000000)))

    # Build the substitution dictionary
    values = {
        "cores_array": cores_array,
        "num_cores":   str(num_cores),
        "spatz_fpu_bool": spatz_fpu_bool,
        "dram_addr":   str(dram_addr),
        "dram_len":    str(dram_len),
        "uncached_addr": str(uncached_addr),
        "uncached_len":  str(uncached_len),
    }

    # Copy through any other env vars used in template
    for name in names:
        if name in values:
            continue
        envv = os.environ.get(name)
        if envv is None:
            print(f"[gen_hjson] ERROR: required variable '{name}' not in environment", file=sys.stderr)
            sys.exit(2)
        values[name] = envv

    # Perform substitution
    def repl(m): return values[m.group(1)]
    out = PLACEHOLDER_RE.sub(repl, tmpl)

    write_if_changed(args.out, out)

if __name__ == "__main__":
    main()
