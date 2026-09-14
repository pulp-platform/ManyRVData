# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

add_library(fdotp-32b fdotp-32b/kernel/fdotp.c)
add_library(fmatmul-32b fmatmul-32b/kernel/fmatmul.c)

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
