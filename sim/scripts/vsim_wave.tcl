# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}
quietly WaveActivateNextPane {} 0

# Add the cluster probe
add wave /tb_cachepool/cluster_probe

# Add cluster waves
add wave -noupdate -group Cluster /tb_cachepool/i_cluster_wrapper/i_cluster/*

do sim/scripts/vsim_tile.tcl 0

# Add all cores in Tile 0
for {set core 0}  {$core < 4} {incr core} {
    do sim/scripts/vsim_core.tcl 0 $core
}
