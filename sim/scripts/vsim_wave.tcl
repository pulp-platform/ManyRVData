# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}
quietly WaveActivateNextPane {} 0

# --- Configuration Variables ---
quietly set cluster_path    /tb_cachepool/i_cluster_wrapper/i_cluster
quietly set NUM_GROUPS      4  ;# Total number of groups
quietly set NUM_GROUPS_X    2  ;# X dimension of group mesh (NUM_GROUPS_Y = NUM_GROUPS / NUM_GROUPS_X)
quietly set NUM_TILES       4  ;# Tiles per group
quietly set NUM_CORES       4  ;# Cores per tile

# Add the cluster probe
add wave /tb_cachepool/cluster_probe

# Cluster
do sim/scripts/vsim_cluster.tcl ${cluster_path}

# Iterate through all groups using 2D coordinates
for {set g 0} {$g < $NUM_GROUPS} {incr g} {
    quietly set gy [expr {$g % $NUM_GROUPS_X}]
    quietly set gx [expr {$g / $NUM_GROUPS_X}]
    quietly set group_wp_path   ${cluster_path}/gen_group_y[${gy}]/gen_group_x[${gx}]/i_group
    quietly set group_path      ${group_wp_path}/i_group
    quietly set gwp_name        "GroupWP_Y${gy}_X${gx}"

    # 1. Plot GroupWP signals for this group
    add wave -noupdate -group "${gwp_name}" -group L2Mesh -group Chimney ${group_wp_path}/i_l2_mgr_chimney/*
    add wave -noupdate -group "${gwp_name}" -group L2Mesh -group ReqRouter ${group_wp_path}/i_l2_req_router/*
    add wave -noupdate -group "${gwp_name}" -group L2Mesh -group RspRouter ${group_wp_path}/i_l2_rsp_router/*

    add wave -noupdate -group "${gwp_name}" -group WP_Internal ${group_wp_path}/*


    # 2. Plot Group-level signals nested inside GroupWP (always, all groups)
    do sim/scripts/vsim_group.tcl ${group_path} 5 "${gwp_name}"

    # 3. Plot all tiles and cores for the diagonal groups: (0,0) always,
    #    and (1,1) if the mesh has at least 2 columns and 2 rows
    if {($gx == 0 && $gy == 0) || ($gx == 0 && $gy == 1 && $NUM_GROUPS_X >= 2)} {
        for {set tile 0} {$tile < $NUM_TILES} {incr tile} {
            quietly set tile_path ${group_path}/gen_tiles[${tile}]/gen_tile
            do sim/scripts/vsim_tile.tcl $tile $g ${tile_path} "${gwp_name}"

            # 4. Plot all cores grouped under their tile
            for {set core 0} {$core < $NUM_CORES} {incr core} {
                quietly set core_path ${tile_path}/i_tile/gen_core[${core}]
                do sim/scripts/vsim_core.tcl $g $tile $core ${core_path} "${gwp_name}" "tile[${tile}]"
            }
        }
    }
}

# Add DRAM waves once at the end
for {set ch 0} {$ch < 4} {incr ch} {
    add wave -noupdate -group "DramSys_$ch" /tb_cachepool/gen_dram[$ch]/i_axi_dram_sim/*
}
