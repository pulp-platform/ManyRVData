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

add_subdirectory(${SNITCH_SOFTWARE_DIR}/snRuntime snRuntime)
# add_subdirectory(${SPATZ_SOFTWARE_DIR}/riscvTests riscvTests)
# add_subdirectory(${SPATZ_SOFTWARE_DIR}/spatzBenchmarks spatzBenchmarks)

option(ENABLE_CACHEPOOL_TESTS "Enable CachePool tests for spatz" OFF)
if (ENABLE_CACHEPOOL_TESTS)
    message(STATUS "Adding CachePool tests")
    add_subdirectory(${CACHEPOOL_DIR}/software/tests CachePoolTests)
endif()
