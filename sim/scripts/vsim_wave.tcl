# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}
quietly WaveActivateNextPane {} 0

set cluster_path    /tb_cachepool/i_cluster_wrapper/i_cluster
set group_path      ${cluster_path}/gen_group/i_group

# Add the cluster probe
add wave /tb_cachepool/cluster_probe

# Cluster
do sim/scripts/vsim_cluster.tcl ${cluster_path}

# Group
# add wave -noupdate -group Group ${group_path}/*
do sim/scripts/vsim_group.tcl ${group_path} 5

# Tile and Core
for {set tile 0}  {$tile < 4} {incr tile} {
    set tile_path ${group_path}/gen_tiles[$tile]

    do sim/scripts/vsim_tile.tcl $tile ${tile_path}
    # Add all cores in Tile 0
    for {set core 0}  {$core < 4} {incr core} {
        set core_path       ${tile_path}/i_tile/gen_core[$core]
        do sim/scripts/vsim_core.tcl $tile $core ${core_path}
    }

    for {set ch 0}  {$ch < 4} {incr ch} {
        add wave -noupdate -group DramSys$ch /tb_cachepool/gen_dram[$ch]/i_axi_dram_sim/*
    }
}

