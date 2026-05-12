# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}
quietly WaveActivateNextPane {} 0

quietly set cluster_path    /tb_cachepool/i_cluster_wrapper/i_cluster
quietly set group_wp_path   ${cluster_path}/gen_group[0][0]/i_group
quietly set group_path      ${group_wp_path}/i_group
quietly set tile_path       ${group_path}/gen_tiles[0]/gen_tile


# Add the cluster probe
add wave /tb_cachepool/cluster_probe

do sim/scripts/vsim_cluster.tcl ${cluster_path}

do sim/scripts/vsim_tile.tcl 0 0 ${tile_path}
# Add all cores in Tile 0
for {set core 0}  {$core < 4} {incr core} {
    quietly set core_path       ${tile_path}/i_tile/gen_core[$core]
    do sim/scripts/vsim_core.tcl 0 0 $core ${core_path} ""
}

for {set ch 0}  {$ch < 4} {incr ch} {
    add wave -noupdate -group DramSys$ch /tb_cachepool/gen_dram[$ch]/i_axi_dram_sim/*
}

