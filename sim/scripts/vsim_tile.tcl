# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Tile $1
onerror {resume}

# Add waves for tcdm_mapper and csrs
add wave -noupdate -group tile[$1] -group CSR /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_snitch_cluster_peripheral/*
add wave -noupdate -group tile[$1] -group axi2reqrsp /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[0]/i_axi2reqrsp/*
# Add waves for xbars
add wave -noupdate -group tile[$1] -group narrow_xbar /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_axi_narrow_xbar/*
add wave -noupdate -group tile[$1] -group wide_xbar /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_axi_wide_xbar/*

# Add waces for cache controller
for {set c 0}  {$c < 4} {incr c} {
	onerror {resume}

	add wave -noupdate -group tile[$1] -group cache[$c] -group amo /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_cache_connect[$c]/gen_cache_amo_connect[4]/gen_amo/i_cache_amo/*

	add wave -noupdate -group tile[$1] -group cache[$c] -group coalescer  /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_par_coalescer_for_spatz/gen_extend_window/i_par_coalescer_extend_window/i_par_coalescer/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group core			  /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/i_insitu_cache_core/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl0	/tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/gen_cache_banks[0]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl1	/tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/gen_cache_banks[1]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl2	/tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/gen_cache_banks[2]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group meta_ctrl3	/tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/gen_cache_banks[3]/i_access_ctrl_for_meta/*
	
	add wave -noupdate -group tile[$1] -group cache[$c] -group Internal   /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/*
}

for {set c 0} {$c < 5} {incr c} {
  add wave -noupdate -group tile[$1] -group cache_xbar -group xbar[$c]	/tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_cache_xbar[$c]/i_cache_xbar/*
}

# Add waves for remaining signals
add wave -noupdate -group tile[$1] -group Internal /tb_cachepool/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/*
