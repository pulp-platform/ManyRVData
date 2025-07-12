# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}
quietly WaveActivateNextPane {} 0

# Add the cluster probe
add wave /tb_cachepool/cluster_probe

# Add cluster waves
# for {set port 0}  {$port < 4} {incr port} {
#     add wave -noupdate -group Cluster -group ReqRsp$port /tb_cachepool/i_cluster_wrapper/i_cluster/gen_output_axi[$port]/i_reqrsp2axi/*
# }
add wave -noupdate -group Cluster -group xbar /tb_cachepool/i_cluster_wrapper/i_cluster/i_cluster_xbar/*
add wave -noupdate -group Cluster /tb_cachepool/i_cluster_wrapper/i_cluster/*

do sim/scripts/vsim_tile.tcl 0

# Add all cores in Tile 0
for {set core 0}  {$core < 4} {incr core} {
    do sim/scripts/vsim_core.tcl 0 $core
}

for {set ch 0}  {$ch < 4} {incr ch} {
    add wave -noupdate -group DramSys$ch -group upsizer tb_cachepool/gen_dram[$ch]/i_axi_dram_sim/i_axi_dw_converter/*
    add wave -noupdate -group DramSys$ch /tb_cachepool/gen_dram[$ch]/i_axi_dram_sim/*
}

