# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Cluster
onerror {resume}

set cluster_path $1

add wave -noupdate -group Cluster -group CSR ${cluster_path}/i_cachepool_cluster_peripheral/*

add wave -noupdate -group Cluster -group Internal ${cluster_path}/*

add wave -noupdate -group Barrier -group Global ${cluster_path}/i_cachepool_cluster_barrier/*

