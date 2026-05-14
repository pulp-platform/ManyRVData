# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}
quietly WaveActivateNextPane {} 0

# --- Configuration Variables ---
set cluster_path    /tb_cachepool/i_cluster_wrapper/i_cluster
set NUM_GROUPS      4  ;# Change this variable to match your total number of groups
set NUM_CORES       4  ;# Assuming 4 cores per tile based on original script

# Add the cluster probe
add wave /tb_cachepool/cluster_probe

# Cluster
do sim/scripts/vsim_cluster.tcl ${cluster_path}

# Iterate through all groups
for {set g 0} {$g < $NUM_GROUPS} {incr g} {
    set group_wp_path   ${cluster_path}/gen_group[$g]/i_group
    set group_path      ${group_wp_path}/i_group

    # 1. Plot all GroupWP levels of all groups
    add wave -noupdate -group "GroupWP_$g" ${group_wp_path}/* 

    do sim/scripts/vsim_group.tcl ${group_path} 5

    # Conditional plotting based on the group
    if {$g <= 1} {
        # 2. Call to plot tile 0 and tile 3 for Group 0 only
        foreach tile {0 1 2 3} {
            set tile_path ${group_path}/gen_tiles[$tile]/gen_tile
            do sim/scripts/vsim_tile.tcl $tile $g ${tile_path}
            
            # 3. Plot all cores in the plotted tile
            for {set core 0} {$core < $NUM_CORES} {incr core} {
                set core_path ${tile_path}/i_tile/gen_core[$core]
                # Pass an empty string to indicate NO parent group
                do sim/scripts/vsim_core.tcl $g $tile $core ${core_path} ""
            }
        }
    } else {
        # 4. Plot core 0 in tile 0 of other groups
        set tile 0
        set core 0
        set tile_path ${group_path}/gen_tiles[$tile]/gen_tile
        set core_path ${tile_path}/i_tile/gen_core[$core]
        
        do sim/scripts/vsim_core.tcl $g $tile $core ${core_path} "GroupWP_$g"
    }
    # set group_wp_path   ${cluster_path}/gen_group[1]/i_group
    # set group_path      ${group_wp_path}/i_group
    # set tile_path ${group_path}/gen_tiles[2]/gen_tile
    # do sim/scripts/vsim_tile.tcl 2 ${tile_path}
}

# Add DRAM waves once at the end
for {set ch 0} {$ch < 4} {incr ch} {
    add wave -noupdate -group "DramSys_$ch" /tb_cachepool/gen_dram[$ch]/i_axi_dram_sim/*
}
