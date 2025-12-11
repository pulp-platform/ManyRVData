# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Tile $1
onerror {resume}

set tile_path $2

# Add waves for tcdm_mapper and csrs
add wave -noupdate -group tile[$1] -group CSR ${tile_path}/i_tile/i_snitch_cluster_peripheral/*
# add wave -noupdate -group tile[$1] -group axi2reqrsp ${tile_path}/i_axi2reqrsp/*
# Add waves for xbars
add wave -noupdate -group tile[$1] -group narrow_xbar ${tile_path}/i_tile/i_axi_narrow_xbar/*
add wave -noupdate -group tile[$1] -group wide_xbar ${tile_path}/i_tile/i_axi_wide_xbar/*

# Add waves for cache controller
for {set c 0}  {$c < 4} {incr c} {
	onerror {resume}

	set cache_path ${tile_path}/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller

	add wave -noupdate -group tile[$1] -group cache[$c] -group amo ${tile_path}/i_tile/gen_cache_connect[$c]/gen_cache_amo_connect[4]/gen_amo/i_cache_amo/*

	add wave -noupdate -group tile[$1] -group cache[$c] -group coalescer  ${cache_path}/i_par_coalescer_for_spatz/gen_extend_window/i_par_coalescer_extend_window/i_par_coalescer/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group core			  ${cache_path}/i_insitu_cache_tcdm_wrapper/i_insitu_cache_core/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl0	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[0]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl1	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[1]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl2	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[2]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl3	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[3]/i_access_ctrl_for_meta/*
	
	add wave -noupdate -group tile[$1] -group cache[$c] -group Internal   ${cache_path}/*
}

for {set c 0} {$c < 5} {incr c} {
  add wave -noupdate -group tile[$1] -group cache_xbar -group xbar[$c]	${tile_path}/i_tile/gen_cache_xbar[$c]/i_cache_xbar/*
}

# Add waves for remaining signals
add wave -noupdate -group tile[$1] -group Internal ${tile_path}/i_tile/*
