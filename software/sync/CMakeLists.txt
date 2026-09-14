# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

add_spatz_test_zeroParam(spin-lock spin-lock/main.c)
add_spatz_test_zeroParam(mcs-lock mcs-lock/main.c)
add_spatz_test_zeroParam(partial_barrier partial_barrier/main.c)# SOCMIPO
add_spatz_test_zeroParam(spatz-lock-handoff spatz-lock-handoff/main.c)
add_spatz_test_zeroParam(false-sharing false-sharing/main.c)
