# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

add_library(idotp-32b idotp-32b/kernel/idotp.c)

add_spatz_test_oneParam(idotp-32b idotp-32b/main.c 8192)
add_spatz_test_oneParam(idotp-32b idotp-32b/main.c 32768)
