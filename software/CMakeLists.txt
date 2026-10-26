# Copyright 2020 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.13)

set(SNITCH_SOFTWARE_DIR ${RUNTIME_DIR})
set(SPATZ_SOFTWARE_DIR ${SPATZ_SW_DIR})

list(APPEND CMAKE_MODULE_PATH ${SNITCH_SOFTWARE_DIR}/cmake)
set(CMAKE_TOOLCHAIN_FILE toolchain-llvm)
set(SNITCH_RUNTIME snRuntime-cluster CACHE STRING "")

project(snitch_cluster LANGUAGES C ASM)
include(SnitchUtilities)

enable_testing()

# Set here (not just in snRuntime/CMakeLists.txt) so sibling directories
# added below, e.g. software/tests, also see this define -- add_compile_definitions
# is a directory property and does not propagate to sibling add_subdirectory trees.
set(NUM_SCALAR_PER_CORE "1" CACHE STRING "Snitch harts sharing one Spatz per Core Complex")
add_compile_definitions(SNRT_NUM_SCALAR_PER_CORE=${NUM_SCALAR_PER_CORE})

# Memory system shape from config.mk, for kernels that lay data out for it
set(L2_CHANNEL "4" CACHE STRING "Number of HBM channels")
set(L2_INTERLEAVE "16" CACHE STRING "HBM channel interleave, in L2 bank words")
set(L2_BANK_WIDTH "512" CACHE STRING "L2 bank word width in bits")
set(L1D_CACHELINE_WIDTH "512" CACHE STRING "L1D cacheline width in bits")
add_compile_definitions(
  SNRT_L2_CHANNEL=${L2_CHANNEL}
  SNRT_L2_INTERLEAVE=${L2_INTERLEAVE}
  SNRT_L2_BANK_WIDTH=${L2_BANK_WIDTH}
  SNRT_L1D_CACHELINE_WIDTH=${L1D_CACHELINE_WIDTH})

add_subdirectory(${SNITCH_SOFTWARE_DIR}/snRuntime snRuntime)
# add_subdirectory(${SPATZ_SOFTWARE_DIR}/riscvTests riscvTests)
# add_subdirectory(${SPATZ_SOFTWARE_DIR}/spatzBenchmarks spatzBenchmarks)

option(ENABLE_CACHEPOOL_TESTS "Enable CachePool tests for spatz" OFF)
if (ENABLE_CACHEPOOL_TESTS)
    message(STATUS "Adding CachePool tests")
    # Shared macros (add_spatz_test_*) and common libraries (benchmark,
    # spin_lock, mcs_lock); must be included before the group subdirectories
    # below, since they use these macros/libraries in their own CMakeLists.
    include(${CACHEPOOL_DIR}/software/cmake/CachePoolTests.cmake)

    add_subdirectory(${CACHEPOOL_DIR}/software/cache cache)
    add_subdirectory(${CACHEPOOL_DIR}/software/sync sync)
    add_subdirectory(${CACHEPOOL_DIR}/software/kernels/fp kernels_fp)
    add_subdirectory(${CACHEPOOL_DIR}/software/kernels/int kernels_int)
    add_subdirectory(${CACHEPOOL_DIR}/software/control control)
    add_subdirectory(${CACHEPOOL_DIR}/software/rlc rlc)
    add_subdirectory(${CACHEPOOL_DIR}/software/tests CachePoolTests)
endif()
