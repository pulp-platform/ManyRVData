# Copyright 2020 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Shared test-registration macros and common libraries for all CachePool
# test groups (cache/, sync/, kernels/fp/, kernels/int/, rlc/, tests/).
# Included once from the top-level software/CMakeLists.txt, before any
# group's add_subdirectory(), so its macros/libraries are visible to them.

set(CACHEPOOL_TESTS_COMMON_DIR ${CACHEPOOL_DIR}/software/tests)

# All test groups' binaries land in one place, software/build/CachePoolTests/,
# same as before the cache/sync/kernels/rlc split -- CI (.gitlab-ci.yml) and
# util/auto-benchmark reference that fixed path regardless of which group
# CMakeLists.txt registered the test.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/CachePoolTests)

include_directories(${CACHEPOOL_TESTS_COMMON_DIR}/include)
include_directories(${SNRUNTIME_INCLUDE_DIRS})

add_compile_options(-O3 -g -ffunction-sections)
add_compile_options(-DELEN=64)

add_library(benchmark ${CACHEPOOL_TESTS_COMMON_DIR}/benchmark/benchmark.c)
add_library(spin_lock ${CACHEPOOL_TESTS_COMMON_DIR}/benchmark/spin_lock.c)
add_library(mcs_lock ${CACHEPOOL_TESTS_COMMON_DIR}/benchmark/mcs_lock.c)

enable_testing()
set(SNITCH_TEST_PREFIX "")

# Macro to generate golden values
macro(add_spatz_test_zeroParam name file)
    set(target_name ${name})
    add_snitch_test(${target_name} ${file})
    target_link_libraries(test-${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
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
