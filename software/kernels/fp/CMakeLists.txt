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

# gemv-opt: the third parameter is the mode, then the config (see gemv-opt/README.md)
# cachepool_fpu_4g
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 4096 64 hot)
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 4096 64 cold)
# cachepool_fpu_16g
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 16384 64 hot)
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 16384 64 cold)
# cachepool_fpu_16g_tiny
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 4096 64 hottiny)
add_spatz_test_threeParam(gemv-opt gemv-opt/main.c 4096 64 coldtiny)

add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 64 64 64)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 128 128 128)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 1024 32 32)
add_spatz_test_threeParam(fmatmul-32b fmatmul-32b/main.c 1024 64 64)

add_spatz_test_twoParam(fft-32b fft-32b/main.c 256 4)
add_spatz_test_twoParam(fft-32b fft-32b/main.c 1024 4)
add_spatz_test_twoParam(fft-32b fft-32b/main.c 1024 16)
# TMP-DOTP-SWEEP begin
add_spatz_test_oneParam(fdotp-iso-b0 fdotp-32b/tmp_iso/main.c 8192)
target_include_directories(test-fdotp-iso-b0_M8192 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/fdotp-32b)
add_spatz_test_oneParam(fdotp-iso-b1 fdotp-32b/tmp_iso/main.c 8192)
target_include_directories(test-fdotp-iso-b1_M8192 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/fdotp-32b)
target_compile_definitions(test-fdotp-iso-b1_M8192 PUBLIC ISO_PART)
foreach(v
    "n1:DOTP_VRED=0;FDOTP_SEED=2;DOTP_XRED=1;ISO_NO_PART"
    "n2:DOTP_VRED=0;FDOTP_SEED=1;DOTP_XRED=0;ISO_NO_PART"
    "n3:DOTP_VRED=0;FDOTP_SEED=1;DOTP_XRED=1;ISO_NO_PART"
    "n4:DOTP_VRED=0;FDOTP_SEED=2;DOTP_XRED=0")
  string(REPLACE ":" ";" vl "${v}")
  list(GET vl 0 tag)
  list(REMOVE_AT vl 0)
  add_spatz_test_oneParam(fdotp-iso-${tag} fdotp-32b/main.c 8192)
  target_compile_definitions(test-fdotp-iso-${tag}_M8192 PUBLIC ${vl})
endforeach()
# TMP-DOTP-SWEEP end
