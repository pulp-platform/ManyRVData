# Copyright 2020 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.13)

# Allow spatzBenchmarks to be built as a standalone library.
if (CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../cmake)
    set(CMAKE_TOOLCHAIN_FILE toolchain-gcc CACHE STRING "Toolchain to use")

    project(Benchmarks LANGUAGES C ASM)
    include(SnitchUtilities)

    # Build the runtime.
    add_subdirectory(${SPATZ_DIR}/sw/snRuntime snRuntime)
endif()

include_directories(include)
include_directories(${SNRUNTIME_INCLUDE_DIRS})

add_compile_options(-O3 -g -ffunction-sections)



# Macro to generate golden values
macro(add_spatz_test_zeroParam name file)
    set(target_name ${name})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    # target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name})
endmacro()

macro(add_spatz_test_oneParam name file param1)
    set(target_name ${name}_M${param1})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC DATAHEADER="data/data_${param1}.h")
endmacro()

macro(add_spatz_test_twoParam name file param1 param2)
    set(target_name ${name}_M${param1}_N${param2})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC DATAHEADER="data/data_${param1}_${param2}.h")
endmacro()

macro(add_spatz_test_threeParam name file param1 param2 param3)
    set(target_name ${name}_M${param1}_N${param2}_K${param3})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC DATAHEADER="data/data_${param1}_${param2}_${param3}.h")
endmacro()




# Benchmark library
add_library(benchmark benchmark/benchmark.c)
add_library(spin_lock benchmark/spin_lock.c)
add_library(mcs_lock benchmark/mcs_lock.c)

add_compile_options(-O3 -g -ffunction-sections)
add_compile_options(-DELEN=64)

include_directories(include)
include_directories(${SNRUNTIME_INCLUDE_DIRS})

# Kernels
## Vector Kernels
add_library(fdotp-32b fdotp-32b/kernel/fdotp.c)
add_library(idotp-32b idotp-32b/kernel/idotp.c)
add_library(fmatmul-32b fmatmul-32b/kernel/fmatmul.c)


## RLC
# (kernel sources are compiled into the test executable via main.c's textual
#  #include, so no per-kernel libraries are needed here; rlc.c requires the
#  per-variant DATAHEADER define, which a shared library target cannot get.)

# Tests
enable_testing()
set(SNITCH_TEST_PREFIX cachepool-)

## RLC
add_spatz_test_zeroParam(spin-lock spin-lock/main.c)
add_spatz_test_zeroParam(partial_barrier partial_barrier/main.c)# SOCMIPO
add_spatz_test_zeroParam(partial_barrier_benchmark partial_barrier_benchmark/main.c)# SOCMIPO
add_spatz_test_zeroParam(mcs-lock mcs-lock/main.c)
add_spatz_test_zeroParam(byte-enable byte-enable/main.c)
add_spatz_test_zeroParam(cache-line-rw-smoke cache-line-rw-smoke/main.c)
add_spatz_test_zeroParam(minimal-tile0-repro minimal-tile0-repro/main.c)
add_spatz_test_zeroParam(v12-race v12-race/main.c)
add_spatz_test_zeroParam(lrsc-forward-progress lrsc-forward-progress/main.c)
add_spatz_test_zeroParam(cache-test-scalar cache-test-scalar/main.c)
add_spatz_test_zeroParam(cache-test-vector cache-test-vector/main.c)
add_spatz_test_zeroParam(cache-mix-smoke cache-mix-smoke/main.c)
add_spatz_test_zeroParam(cache-mix-pressure cache-mix-pressure/main.c)
add_spatz_test_zeroParam(cache-rlc-mimic cache-rlc-mimic/main.c)
add_spatz_test_zeroParam(cache-vector-rw cache-vector-rw/main.c)
add_spatz_test_zeroParam(cache-coverage cache-coverage/main.c)
add_spatz_test_zeroParam(cache-coverage-min cache-coverage-min/main.c)

# add_snitch_test(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c)
# add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 1000)
# add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 2044 100)
add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 300)
add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 100)
add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 10)
# TC2 multi-user peak rate: 48 UEs, 800 B packets (data_48_800_*.h)
add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300)
add_spatz_test_threeParam(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 1000)

# RLC variant with explicit producer/consumer core counts (thread-scaling runs).
# RLC AM mode: grant-based transport-block assembly (RLC_TB_MODE=1) instead of
# the legacy copy-to-fixed-destination path. `verify` builds with the planner
# self-check, which runs the scalar reference alongside the vectorised planner
# and counts divergences.
macro(add_spatz_test_rlc_am_wq name file param1 param2 param3 pcore ccore grant verify)
    set(target_name ${name}_M${param1}_N${param2}_K${param3}_P${pcore}_C${ccore}_am_G${grant}_wq)
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC
        DATAHEADER="data/data_${param1}_${param2}_${param3}.h"
        PRODUCER_CORE_NUM=${pcore} CONSUMER_CORE_NUM=${ccore}
        RLC_TB_MODE=1 RLC_GRANT_BYTES=${grant} RLC_AM_WORKQ=1)
    if(${verify})
        target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC
            RLC_PLAN_VERIFY=1 RLC_SELF_CHECK=1)
    endif()
endmacro()

macro(add_spatz_test_rlc_am name file param1 param2 param3 pcore ccore grant verify)
    set(target_name ${name}_M${param1}_N${param2}_K${param3}_P${pcore}_C${ccore}_am_G${grant})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC
        DATAHEADER="data/data_${param1}_${param2}_${param3}.h"
        PRODUCER_CORE_NUM=${pcore} CONSUMER_CORE_NUM=${ccore}
        RLC_TB_MODE=1 RLC_GRANT_BYTES=${grant})
    if(${verify})
        # Diff the vectorised planner against the scalar reference, and decode
        # every assembled transport block back to check the execute stage.
        target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC
            RLC_PLAN_VERIFY=1 RLC_SELF_CHECK=1)
    endif()
endmacro()

macro(add_spatz_test_rlc name file param1 param2 param3 pcore ccore)
    set(target_name ${name}_M${param1}_N${param2}_K${param3}_P${pcore}_C${ccore})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC
        DATAHEADER="data/data_${param1}_${param2}_${param3}.h"
        PRODUCER_CORE_NUM=${pcore} CONSUMER_CORE_NUM=${ccore})
endmacro()
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 2 2)
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 2 4)
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 4 4)
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 2 8)
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 4 8)

# --- AM transport-block assembly -------------------------------------------
# TC1 single entity: one owner plans, the other consumers help execute the
# same transport block -- the case that needs intra-entity parallelism.
add_spatz_test_rlc_am(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 100 2 2 8192 1)
add_spatz_test_rlc_am(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 100 2 4 8192 0)
# TC2 multi entity.
add_spatz_test_rlc_am(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 2 2 8192 1)
add_spatz_test_rlc_am(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 4 8 8192 0)
# Small grant -> segmentation on nearly every grant.
add_spatz_test_rlc_am(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 100 2 4 1024 1)

# Scalar-planner control: same scan algorithm, RVV primitives swapped for their
# plain-C twins (RLC_PLAN_VECTOR=0). Executes no vector instruction in the
# planner at all, so it separates "my algorithm is wrong" from "my RVV is wrong"
# in one run.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_novec
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_novec
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_novec PUBLIC
    DATAHEADER="data/data_1_1350_100.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_PLAN_IMPL=0 RLC_SELF_CHECK=1)

# Bisect ladder for the scan planner. RLC_PLAN_VECTOR is a bitmask over the
# planner's primitives (1 maps, 2 prefix-sum, 4 first-crossing); each has an
# RVV form and a plain-C twin with identical semantics. Running these isolates
# a vector-execution failure to one primitive without needing a PC trace.
macro(add_rlc_am_bisect suffix vecmask)
    set(tn multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_${suffix})
    add_snitch_test(${tn} multi_producer_single_consumer_double_linked_list/main.c)
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${tn} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${tn} PUBLIC
        DATAHEADER="data/data_1_1350_100.h"
        PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
        RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1
        RLC_PLAN_IMPL=1 RLC_PLAN_VECTOR=${vecmask})
endmacro()
add_rlc_am_bisect(scanC 0)   # scan planner, every primitive in plain C
add_rlc_am_bisect(v1    1)   # + maps only
add_rlc_am_bisect(v2    2)   # + prefix-sum only
# WARNING: v4 emits vmsgtu.vx and vmerge.vvm. Spatz's RTL decodes both and
# implements neither, so a pass here on any simulator that models them says
# nothing about hardware -- on Spatz they would corrupt silently.
add_rlc_am_bisect(v4    4)   # + first-crossing only

# Payload-verification target sized to FINISH on RTL. RTL runs the AM path at
# ~52 cycles/s, so the K100 checked build cannot reach EOC inside an hour. This
# uses the 10-packet header and drops RLC_PLAN_VERIFY (the planner is already
# cleared by the host test and by GVSoC's vector-vs-reference pass), keeping
# only RLC_SELF_CHECK -- the transport-block decode. That is the one question
# GVSoC can no longer answer, since its cross-core shared-data path is unsound.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M1_N1350_K10_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K10_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K10_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_1_1350_10.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

# Multi-entity AM, sized to complete on RTL. Eight entities over 24 packets
# exercises what TC2 does and TC1 cannot -- several entities per owner, the
# one-open-grant-per-owner rule, and the ownership partition -- at a twentieth
# of TC2's work. RLC_SELF_CHECK only, for the same reason as the tbchk target.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M8_N1350_K24_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M8_N1350_K24_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M8_N1350_K24_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_8_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

# Entity-count control: 48 entities at M8's 24-packet workload. Separates
# "many entities" from "deep queues". If this passes while TC2 (48 entities,
# 300 packets) does not, the cost is queue depth -- i.e. the gather -- not the
# entity count; if it also wedges, entity count is implicated on its own.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M48_N1350_K24_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N1350_K24_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N1350_K24_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_48_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

# Smallest payload check that can finish on RTL. The AM path simulates at
# ~39 cycles/s measured, so even K10 does not reach EOC in an hour. Four
# packets fit one grant (4 x 1363 = 5452 < 8192), giving 4 PDUs and ~5.4 k
# byte-compares in the verifier -- minutes, not hours.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M1_N1350_K4_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K4_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K4_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_1_1350_4.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

# Same multi-entity pair with the bitmap work queue (RLC_AM_WORKQ=1). The
# non-wq sweep visits EVERY entity per step and helpers spin, so cost scales
# as packets x entities: K4/M1 took 10 min, K8/M8 exceeded 60. That makes
# multi-entity RTL infeasible without the queue, which skips idle entities
# entirely -- so F5 is the enabler here, not an optimisation.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M8_N1350_K8_P2_C2_am_G8192_wqchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M8_N1350_K8_P2_C2_am_G8192_wqchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M8_N1350_K8_P2_C2_am_G8192_wqchk PUBLIC
    DATAHEADER="data/data_8_1350_8.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_AM_WORKQ=1)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M48_N1350_K8_P2_C2_am_G8192_wqchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N1350_K8_P2_C2_am_G8192_wqchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N1350_K8_P2_C2_am_G8192_wqchk PUBLIC
    DATAHEADER="data/data_48_1350_8.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_AM_WORKQ=1)

# Multi-entity pair sized for RTL. The K24 rungs extrapolate to ~62 min against
# a 60 min cap (K4 took 10 min for 4 packets), so they cannot answer anything.
# 8 packets is ~21 min. Entity count is held as the variable, matching the
# GVSoC ladder's axis, at a workload RTL can actually finish.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M8_N1350_K8_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M8_N1350_K8_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M8_N1350_K8_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_8_1350_8.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M48_N1350_K8_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N1350_K8_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N1350_K8_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_48_1350_8.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

# Segmentation under test. The K4/G8192 payload check passed on RTL but
# reported segments=0: four 1360 B SDUs fit inside one 8192 B grant, so the
# whole SI / SO / partial-cursor / cross-grant-so_next path never ran. At
# G1024 a 1360 B SDU cannot fit any grant whole, so every SDU must split and
# so_next chaining becomes the thing under test.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M1_N1350_K4_P2_C2_am_G1024_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K4_P2_C2_am_G1024_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K4_P2_C2_am_G1024_tbchk PUBLIC
    DATAHEADER="data/data_1_1350_4.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=1024 RLC_SELF_CHECK=1)

# Mirror arm: can a PASSING rung be BROKEN by layout? The M16 arm tested only
# whether a failure can be rescued. For an address-dependent corruption those
# are different questions, and only this one probes whether M32's success is a
# lucky layout rather than a property of 32 entities.
#   M32 keeps passing under both -> layout inert, entity count is real
#   M32 fails under either       -> success is layout-contingent
add_snitch_test(multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_padshift
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_padshift
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_padshift PUBLIC
    DATAHEADER="data/data_32_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_LAYOUT_PAD=320)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_entpad
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_entpad
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_entpad PUBLIC
    DATAHEADER="data/data_32_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_AM_ENT_PADDED=1)

# Three-way layout discriminator at a FIXED entity count (16, which fails).
#   padshift passes, entpad fails  -> pure layout sensitivity (not the kernel)
#   padshift fails, entpad passes  -> false sharing on rlc_am_ent (kernel bug)
#   both fail                      -> neither; look elsewhere
add_snitch_test(multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_pad0
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_pad0
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_pad0 PUBLIC
    DATAHEADER="data/data_16_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_padshift
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_padshift
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_padshift PUBLIC
    DATAHEADER="data/data_16_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_LAYOUT_PAD=320)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_entpad
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_entpad
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_entpad PUBLIC
    DATAHEADER="data/data_16_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_AM_ENT_PADDED=1)

# Entity-count bracket: 8 / 12 / 16 / 24 / 32 / 48 entities, all at 24 packets
# and 4 cores. A sharp flip implies a structure crossing a size boundary; a
# gradual one implies accumulation. Those are different bugs.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M12_N1350_K24_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M12_N1350_K24_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M12_N1350_K24_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_12_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M16_N1350_K24_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_16_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M24_N1350_K24_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M24_N1350_K24_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M24_N1350_K24_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_24_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

add_snitch_test(multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_tbchk
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_tbchk
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M32_N1350_K24_P2_C2_am_G8192_tbchk PUBLIC
    DATAHEADER="data/data_32_1350_24.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1)

# Scalar-copy control: identical in every respect except that the payload is
# moved with scalar byte stores instead of the e8/m8 vector copy. Isolates an
# alignment-sensitive vector copy from wrong offset arithmetic.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_scpy
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_scpy
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P2_C2_am_G8192_scpy PUBLIC
    DATAHEADER="data/data_1_1350_100.h"
    PRODUCER_CORE_NUM=2 CONSUMER_CORE_NUM=2
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_SELF_CHECK=1 RLC_DL_COPY_SCALAR=1)

# C=1 control. Dispatch follows the data header's core lists, so a genuine
# single-consumer run needs its own header (the *_CORE_NUM defines cannot
# shrink the list). Anything that reproduces here is not a concurrency bug.
add_snitch_test(multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P1_C1_am_G8192
                multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P1_C1_am_G8192
                      benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M1_N1350_K100_P1_C1_am_G8192 PUBLIC
    DATAHEADER="data/data_1_1350_100_p1c1.h"
    PRODUCER_CORE_NUM=1 CONSUMER_CORE_NUM=1
    RLC_TB_MODE=1 RLC_GRANT_BYTES=8192 RLC_PLAN_VERIFY=1 RLC_SELF_CHECK=1)

# ---------------------------------------------------------------------------
# Uplink (RLC_UL_MODE=1): receive -> scan -> reassemble -> deliver.
#
# The consumer set runs uplink slots instead of downlink assembly, so these are
# a separate ELF rather than a flag on the DL tests. The C1/C2/C3 ladder is the
# measurement that matters: the scan is serial by construction (an AMD header
# is 3 or 5 bytes depending on SI, so PDU i+1's offset needs PDU i parsed),
# reassembly is not, and the ratio bounds what more cores can buy. Consumers
# stay inside one tile because the TB arena is above the l1d_addr boundary and
# therefore tile-private.
# ---------------------------------------------------------------------------
macro(add_rlc_ul name source dataheader prod cons exec tb suffix)
  add_snitch_test(${name}_P${prod}_C${cons}_ul_${suffix} ${source})
  target_link_libraries(test-${SNITCH_TEST_PREFIX}${name}_P${prod}_C${cons}_ul_${suffix}
                        benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
  target_compile_definitions(test-${SNITCH_TEST_PREFIX}${name}_P${prod}_C${cons}_ul_${suffix} PUBLIC
      DATAHEADER="${dataheader}"
      PRODUCER_CORE_NUM=${prod} CONSUMER_CORE_NUM=${cons}
      RLC_UL_MODE=1 RLC_UL_EXEC=${exec} RLC_UL_TB_BYTES=${tb} RLC_SELF_CHECK=1)
endmacro()

# Consumer ladder, payload moved (RLC_UL_EXEC=0): 1, 2 and 3 reassembly cores.
add_rlc_ul(multi_producer_single_consumer_double_linked_list
           multi_producer_single_consumer_double_linked_list/main.c
           "data/data_1_1350_100_p1c1.h" 1 1 0 8192 copy)
add_rlc_ul(multi_producer_single_consumer_double_linked_list
           multi_producer_single_consumer_double_linked_list/main.c
           "data/data_1_1350_100.h" 2 2 0 8192 copy)
add_rlc_ul(multi_producer_single_consumer_double_linked_list
           multi_producer_single_consumer_double_linked_list/main.c
           "data/data_1_1350_100_p1c3.h" 1 3 0 8192 copy)

# Header-only control (RLC_UL_EXEC=1): payload is accounted for but never read,
# which is what a receiver handing payload to a DMA actually does. Diffing it
# against the copy build separates header-walk cost from payload traffic.
add_rlc_ul(multi_producer_single_consumer_double_linked_list
           multi_producer_single_consumer_double_linked_list/main.c
           "data/data_1_1350_100_p1c3.h" 1 3 1 8192 count)

# Segmenting build. The 8192 B block above is an accident of arithmetic: with
# 1360 B SDUs it holds exactly 6 whole SDUs with 2 bytes to spare, so it never
# segments -- and segmentation is the entire reason the scan is serial (a 5-byte
# header with SO appears only on MIDDLE/LAST). 3000 B forces a split in nearly
# every block, so the ladder above measures the scan on the traffic that
# actually justifies it.
add_rlc_ul(multi_producer_single_consumer_double_linked_list
           multi_producer_single_consumer_double_linked_list/main.c
           "data/data_1_1350_100_p1c3.h" 1 3 0 3000 seg)

# Same cases with the bitmap work queue (RLC_AM_WORKQ=1), so the scan-free path
# can be diffed against the plain one rather than replacing it.
add_spatz_test_rlc_am_wq(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 1 1350 100 2 4 8192 1)
add_spatz_test_rlc_am_wq(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 2 2 8192 1)
add_spatz_test_rlc_am_wq(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 4 8 8192 0)
# Large-config thread-scaling (GVSoC 64/256-core sweeps): all-cores-work variants.
# P16/C48 = 64 active (16x4); P48/C48 = 96 active (M48 ceiling); M256 P128/C128 = 256 active (64x4).
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 16 48)
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 48 800 300 48 48)
add_spatz_test_rlc(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c 256 800 300 128 128)
# TC2 with the payload self-check enabled (src vs tgt compare after the barrier)
add_snitch_test(multi_producer_single_consumer_double_linked_list_M48_N800_K300_sc multi_producer_single_consumer_double_linked_list/main.c)
target_link_libraries(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N800_K300_sc benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
target_compile_definitions(test-${SNITCH_TEST_PREFIX}multi_producer_single_consumer_double_linked_list_M48_N800_K300_sc PUBLIC DATAHEADER="data/data_48_800_300.h" RLC_SELF_CHECK=1)

## Vector
### Floating-Point
add_spatz_test_oneParam(fdotp-32b fdotp-32b/main.c 8192)
add_spatz_test_oneParam(fdotp-32b fdotp-32b/main.c 32768)
add_spatz_test_oneParam(fdotp-32b fdotp-32b/main.c 65536)

add_spatz_test_threeParam(gemv gemv/main.c 128 128 32)
add_spatz_test_threeParam(gemv gemv/main.c 256 128 32)
add_spatz_test_threeParam(gemv gemv/main.c 512 128 32)
add_spatz_test_threeParam(gemv gemv/main.c 1024 128 32)

add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 128 128 32)
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 256 128 32)
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 512 128 32)
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 1024 128 32)

add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 32 32 32)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 64 64 64)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 128 128 128)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 1024 32 32)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 1024 64 64)

add_spatz_test_twoParam(fft-32b fft-32b/main.c 256 4)
add_spatz_test_twoParam(fft-32b fft-32b/main.c 1024 4)
add_spatz_test_twoParam(fft-32b fft-32b/main.c 1024 16)

### Integer-Point
add_spatz_test_oneParam(idotp-32b idotp-32b/main.c 8192)
add_spatz_test_oneParam(idotp-32b idotp-32b/main.c 32768)


add_spatz_test_zeroParam(load-store load-store/main.c)

add_spatz_test_zeroParam(bandwidth bandwidth/main.c)
