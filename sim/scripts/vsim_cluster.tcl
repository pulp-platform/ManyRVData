# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Cluster
onerror {resume}

quietly set cluster_path $1
quietly set hbm0_path ${cluster_path}/gen_l2_refill_mesh/gen_hbm_west[0]

# Bootrom
add wave -noupdate -group Cluster -group BootROM ${cluster_path}/i_bootrom/*

add wave -noupdate -group Cluster -group BootROM -group Converter ${cluster_path}/i_reqrsp_to_reg_bootrom/*


# Peripheral
add wave -noupdate -group Cluster -group Periph -group PeriReg ${cluster_path}/i_cachepool_cluster_peripheral/*

add wave -noupdate -group Cluster -group Periph -group PeriXBar ${cluster_path}/i_peri_xbar/*

if {[llength [find instances -nodu ${hbm0_path}/gen_hbm0_demux/i_hbm0_dram_reqrsp_to_axi]] > 0} {
    add wave -noupdate -group Cluster -group Periph -group reqrsp2axi ${hbm0_path}/gen_hbm0_demux/i_hbm0_dram_reqrsp_to_axi/*
}
if {[llength [find instances -nodu ${hbm0_path}/gen_hbm0_demux/i_hbm0_reqrsp_demux]] > 0} {
    add wave -noupdate -group Cluster -group Periph -group demux ${hbm0_path}/gen_hbm0_demux/i_hbm0_reqrsp_demux/*
}
if {[llength [find instances -nodu ${hbm0_path}/gen_hbm0_demux/i_hbm0_peri_dw]] > 0} {
    add wave -noupdate -group Cluster -group Periph -group dw_conv ${hbm0_path}/gen_hbm0_demux/i_hbm0_peri_dw/*
}


# Barrier
add wave -noupdate -group Barrier -group Global ${cluster_path}/i_cluster_barrier/*


# L2 NoC
# HBM chimneys sit at the West/East edges of the L2 refill mesh, up to
# 8 channels per side (16 total). Loop over all 16 and stop each side
# independently on its first missing index, since the exact channel
# count depends on the config.
quietly set west_done 0
quietly set east_done 0
for {set idx 0} {$idx < 16} {incr idx} {
    if {$idx < 8} {
        if {$west_done} { continue }
        quietly set side "west"
        quietly set gy   $idx
    } else {
        if {$east_done} { continue }
        quietly set side "east"
        quietly set gy   [expr {$idx - 8}]
    }
    quietly set hbm_chimney_path ${cluster_path}/gen_l2_refill_mesh/gen_hbm_${side}[${gy}]/i_hbm_chimney
    if {[catch {add wave -noupdate -group Cluster -group L2NoC -group HBM_${side}${gy}_chimney ${hbm_chimney_path}/*}]} {
        if {$idx < 8} {
            quietly set west_done 1
        } else {
            quietly set east_done 1
        }
    }
}

# Others
add wave -noupdate -group Cluster -group Internal ${cluster_path}/*


