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

add_compile_options(-O3 -g -ffunction-sections)
add_compile_options(-DELEN=64)

include_directories(include)
include_directories(${SNRUNTIME_INCLUDE_DIRS})

macro(add_spatz_test_threeParam name file param1 param2 param3)
    set(target_name ${name}_M${param1}_N${param2}_K${param3})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC DATAHEADER="data/data_${param1}_${param2}_${param3}.h")
endmacro()


# Benchmark library
add_library(benchmark benchmark/benchmark.c)

# Kernels
add_library(debug_print multi_producer_single_consumer_double_linked_list/kernel/printf_lock.c)
add_library(llist multi_producer_single_consumer_double_linked_list/kernel/llist.c)
add_library(mm multi_producer_single_consumer_double_linked_list/kernel/mm.c)
add_library(rlc multi_producer_single_consumer_double_linked_list/kernel/rlc.c)

add_library(dp-fmatmul-4x4vl dp-fmatmul-4x4vl/kernel/dp-fmatmul.c)
add_library(gemv-col gemv-col/kernel/gemv.c)

# Tests
enable_testing()
set(SNITCH_TEST_PREFIX cachepool-)

add_snitch_test(spin-lock  spin-lock/main.c)

add_snitch_test(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c)

add_spatz_test_threeParam(gemv-col gemv-col/main.c 128 64 64)
add_spatz_test_threeParam(gemv-col gemv-col/main.c 128 128 64)
add_spatz_test_threeParam(gemv-col gemv-col/main.c 512 32 64)

add_spatz_test_threeParam(dp-fmatmul-4x4vl dp-fmatmul-4x4vl/main.c 16 16 16)
add_spatz_test_threeParam(dp-fmatmul-4x4vl dp-fmatmul-4x4vl/main.c 32 32 32)
add_spatz_test_threeParam(dp-fmatmul-4x4vl dp-fmatmul-4x4vl/main.c 64 64 64)
add_spatz_test_threeParam(dp-fmatmul-4x4vl dp-fmatmul-4x4vl/main.c 128 128 128)
