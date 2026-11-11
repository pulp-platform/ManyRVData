# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

add_library(idotp-32b idotp-32b/kernel/idotp.c)

add_spatz_test_oneParam(idotp-32b idotp-32b/main.c 8192)
add_spatz_test_oneParam(idotp-32b idotp-32b/main.c 32768)

# Integer GEMV, ported from fp/gemv
add_spatz_test_threeParam(igemv igemv/main.c 128 128 32)
add_spatz_test_threeParam(igemv igemv/main.c 256 128 32)
add_spatz_test_threeParam(igemv igemv/main.c 512 128 32)
add_spatz_test_threeParam(igemv igemv/main.c 1024 128 32)

# The same kernels without the Spatz lock (KERNEL_LOCK=0): on a dual-thread Spatz they run on the
# split VRF. Targets get a `_free` suffix.
macro(add_spatz_test_threeParam_free name file param1 param2 param3)
    set(target_name ${name}_M${param1}_N${param2}_K${param3}_free)
    add_snitch_test(${target_name} ${file})
    target_link_libraries(${SNITCH_TEST_BIN_PREFIX}${SNITCH_TEST_PREFIX}${target_name} benchmark spin_lock mcs_lock ${SNITCH_RUNTIME})
    target_compile_definitions(${SNITCH_TEST_BIN_PREFIX}${SNITCH_TEST_PREFIX}${target_name} PUBLIC
        DATAHEADER="data/data_${param1}_${param2}_${param3}.h" KERNEL_LOCK=0)
endmacro()
add_spatz_test_threeParam_free(igemv igemv/main.c 128 128 32)
add_spatz_test_threeParam_free(igemv igemv/main.c 1024 128 32)

# Integer GEMM, ported from fp/fmatmul-32b
add_library(imatmul-32b imatmul-32b/kernel/imatmul.c)
add_spatz_test_threeParam(imatmul-32b imatmul-32b/main.c 32 32 32)
add_spatz_test_threeParam(imatmul-32b imatmul-32b/main.c 64 64 64)
add_spatz_test_threeParam(imatmul-32b imatmul-32b/main.c 128 128 128)
add_spatz_test_threeParam_free(imatmul-32b imatmul-32b/main.c 32 32 32)
add_spatz_test_threeParam_free(imatmul-32b imatmul-32b/main.c 64 64 64)
