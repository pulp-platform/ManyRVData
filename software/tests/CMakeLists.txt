# Copyright 2020 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

add_spatz_test_zeroParam(minimal-tile0-repro minimal-tile0-repro/main.c)
add_spatz_test_zeroParam(load-store load-store/main.c)
add_spatz_test_zeroParam(partial_barrier_benchmark partial_barrier_benchmark/main.c)# SOCMIPO
add_spatz_test_zeroParam(bandwidth bandwidth/main.c)
