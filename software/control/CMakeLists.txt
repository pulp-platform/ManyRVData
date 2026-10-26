# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Control algorithm kernels (see README.md). Each kernel lives in its
# own subdirectory with main.c, kernel/, script/ and data/; kernel sources are
# pulled into each test through main.c's #include, as in software/rlc.

# Binaries of this group are named ctrl-<name> instead of test-<name>.
set(SNITCH_TEST_BIN_PREFIX "ctrl-")

# ctrl-<name>_<data>_C<cores>[_<variant>]: <dir>/main.c built with
# data/data_<data>.h and ACTIVE_CORES = <cores>. Optional extra arguments:
# a variant suffix, then compile definitions for it.
macro(add_control_test name dir data cores)
    set(target_name ${name}_${data}_C${cores})
    set(extra_defs ${ARGN})
    if(extra_defs)
        list(GET extra_defs 0 variant)
        list(REMOVE_AT extra_defs 0)
        set(target_name ${target_name}_${variant})
    endif()
    add_snitch_test(${target_name} ${dir}/main.c)
    target_link_libraries(${SNITCH_TEST_BIN_PREFIX}${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(${SNITCH_TEST_BIN_PREFIX}${SNITCH_TEST_PREFIX}${target_name} PUBLIC
        DATAHEADER="data/data_${data}.h" ACTIVE_CORES=${cores} ${extra_defs})
    target_include_directories(${SNITCH_TEST_BIN_PREFIX}${SNITCH_TEST_PREFIX}${target_name} PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/common)
endmacro()

# Kernel 1: initial U/R and V/G products
add_control_test(uv-init uv-init 8_16_const 1)
add_control_test(uv-init uv-init 8_16_const 4)
add_control_test(uv-init uv-init 9_21 1)
add_control_test(uv-init uv-init 9_21 4)
add_control_test(uv-init uv-init 9_21 8)
foreach(cores 1 2 4 8 16)
    add_control_test(uv-init uv-init 64_128 ${cores})
endforeach()
# L1 variants (all-private): tile-folded banks, columns split across tiles
# above four cores; group-folded banks; bank-select offsets 6 and 7
foreach(xbar 6 7)
    foreach(cores 1 4 8 16)
        add_control_test(uv-init uv-init 64_128 ${cores} tile_x${xbar}
            L1D_FOLD=L1D_FOLD_TILE XBAR_OFFSET=${xbar})
    endforeach()
    foreach(cores 8 16)
        add_control_test(uv-init uv-init 64_128 ${cores} group_x${xbar}
            L1D_FOLD=L1D_FOLD_GROUP XBAR_OFFSET=${xbar})
    endforeach()
endforeach()

# Gain = ln(1 + P * G) and the selection of the winner
add_control_test(gain-select gain-select 63_37 1)
add_control_test(gain-select gain-select 63_37 4)
foreach(cores 1 2 4 8 16)
    add_control_test(gain-select gain-select 64_128 ${cores})
endforeach()

# The full algorithm (products, every iteration, finalization), one group
add_control_test(full full 9_21 1)
add_control_test(full full 9_21 4)
add_control_test(full full 63_37 4)
add_control_test(full full 63_37_mix 4)
foreach(cores 8 16)
    add_control_test(full full 64_128 ${cores})
endforeach()
# Shorter runs: a warm-up of 2 iterations, then 8, 16 or 32 measured
foreach(iters 8 16 32)
    foreach(cores 8 16)
        add_control_test(full full 64_128_i${iters}w ${cores})
    endforeach()
endforeach()
# Per-core phase profile of the iterations
foreach(cores 8 16)
    add_control_test(full full 64_128_i16w ${cores} prof IT_PROF=1)
endforeach()
# Cycles of the parts of the selection
add_control_test(full full 64_128_i16w 16 cprof IT_CPROF=1)

# Power update of the winner and finalization (one core)
add_control_test(power-update power-update 9_21 1)
add_control_test(power-update power-update 9_24 1)
add_control_test(power-update power-update 64_128 1)
