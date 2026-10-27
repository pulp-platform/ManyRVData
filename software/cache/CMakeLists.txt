# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

add_spatz_test_zeroParam(byte-enable byte-enable/main.c)
add_spatz_test_zeroParam(cache-line-rw-smoke cache-line-rw-smoke/main.c)
add_spatz_test_zeroParam(cache-test-scalar cache-test-scalar/main.c)
add_spatz_test_zeroParam(cache-test-vector cache-test-vector/main.c)
add_spatz_test_zeroParam(cache-mix-smoke cache-mix-smoke/main.c)
add_spatz_test_zeroParam(cache-mix-pressure cache-mix-pressure/main.c)
add_spatz_test_zeroParam(cache-rlc-mimic cache-rlc-mimic/main.c)
add_spatz_test_zeroParam(cache-vector-rw cache-vector-rw/main.c)
add_spatz_test_zeroParam(cache-coverage cache-coverage/main.c)
add_spatz_test_zeroParam(cache-coverage-min cache-coverage-min/main.c)

# Private-partition flush: cache-fold-flush_<fold>_x<xbar>_<KiB>
foreach(v "tile;0;6;512" "tile;0;0;512" "tile;0;6;128" "group;1;6;512" "shared;2;6;512")
    list(GET v 0 fname)
    list(GET v 1 fold)
    list(GET v 2 xbar)
    list(GET v 3 kib)
    set(ff_name cache-fold-flush_${fname}_x${xbar}_${kib})
    add_spatz_test_zeroParam(${ff_name} cache-fold-flush/main.c)
    target_compile_definitions(${SNITCH_TEST_BIN_PREFIX}${SNITCH_TEST_PREFIX}${ff_name} PUBLIC
        FF_FOLD=${fold} FF_XBAR=${xbar} FF_KIB=${kib})
endforeach()
