#!/usr/bin/env python3
# check_ci.py
# Scans a CachePool RTL simulation log for failures and exits non-zero if any
# are found, allowing CI to detect test failures.
#
# Failure conditions:
#   - Any line containing FAIL or [FAIL] (case-insensitive)
#   - Any line matching "error <N>" where N is non-zero

import re
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: check_ci.py <logfile>")
        sys.exit(1)

    logfile = sys.argv[1]

    # Matches "error <integer>" anywhere in a line, captured as group 1.
    error_val_re = re.compile(r'\berror\s+(\d+)\b', re.IGNORECASE)
    # Matches FAIL or [FAIL] anywhere in a line.
    fail_re = re.compile(r'\bFAIL\b', re.IGNORECASE)

    failures = []

    with open(logfile, 'r') as f:
        for lineno, line in enumerate(f, 1):
            stripped = line.rstrip()

            # Check for explicit FAIL keyword.
            if fail_re.search(stripped):
                failures.append((lineno, stripped))
                continue

            # Check for "error <N>" with N != 0.
            for m in error_val_re.finditer(stripped):
                if int(m.group(1)) != 0:
                    failures.append((lineno, stripped))
                    break

    if failures:
        print(f"CI FAILED: {len(failures)} failure(s) detected:")
        for lineno, line in failures:
            print(f"  line {lineno}: {line}")
        sys.exit(1)
    else:
        print("CI PASSED: no failures detected.")
        sys.exit(0)

if __name__ == '__main__':
    main()
