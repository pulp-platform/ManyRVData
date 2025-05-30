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
macro(add_spatz_test_oneParam name file param1)
    set(target_name ${name}_M${param1})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark ${SNITCH_RUNTIME})
    target_compile_definitions(test-${SNITCH_TEST_PREFIX}${target_name} PUBLIC DATAHEADER="data/data_${param1}.h")
endmacro()


# Benchmark library
add_library(benchmark benchmark/benchmark.c)

add_compile_options(-O3 -g -ffunction-sections)
add_compile_options(-DELEN=64)

include_directories(include)
include_directories(${SNRUNTIME_INCLUDE_DIRS})

# Kernels
## Vector Kernels
add_library(sp-fdotp sp-fdotp/kernel/fdotp.c)
## RLC
add_library(debug_print multi_producer_single_consumer_double_linked_list/kernel/debug.c)
add_library(llist multi_producer_single_consumer_double_linked_list/kernel/llist.c)
add_library(mm multi_producer_single_consumer_double_linked_list/kernel/mm.c)
add_library(rlc multi_producer_single_consumer_double_linked_list/kernel/rlc.c)

# Tests
enable_testing()
set(SNITCH_TEST_PREFIX cachepool-)

## RLC
add_snitch_test(spin-lock  spin-lock/main.c)

add_snitch_test(multi_producer_single_consumer_double_linked_list multi_producer_single_consumer_double_linked_list/main.c)

## Vector

add_spatz_test_oneParam(sp-fdotp sp-fdotp/main.c 1024)
add_spatz_test_oneParam(sp-fdotp sp-fdotp/main.c 8192)


