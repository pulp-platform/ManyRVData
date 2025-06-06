# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Tile $1
onerror {resume}

# Add waves for tcdm_mapper and csrs
add wave -noupdate -group tile[$1] -group Mapper /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_tcdm_mapper/*
add wave -noupdate -group tile[$1] -group CSR /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_snitch_cluster_peripheral/*

# Add waves for xbars
add wave -noupdate -group tile[$1] -group core_xbar 									/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_tcdm_interconnect/*
add wave -noupdate -group tile[$1] -group core_xbar -group req 				/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_tcdm_interconnect/gen_xbar/i_stream_xbar/*
add wave -noupdate -group tile[$1] -group dma_xbar 										/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/i_dma_interconnect/*

# Add waces for cache controller
for {set c 0}  {$c < 4} {incr c} {
	onerror {resume}
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller -group coalescer  /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_par_coalescer_for_spatz/gen_extend_window/i_par_coalescer_extend_window/i_par_coalescer/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller -group core			  /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/i_insitu_cache_tcdm_wrapper/i_insitu_cache_core/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller -group meta_ctrl0	/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/i_insitu_cache_tcdm_wrapper/gen_cache_banks[0]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller -group meta_ctrl1	/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/i_insitu_cache_tcdm_wrapper/gen_cache_banks[1]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller -group meta_ctrl2	/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/i_insitu_cache_tcdm_wrapper/gen_cache_banks[2]/i_access_ctrl_for_meta/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller -group meta_ctrl3	/tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/i_insitu_cache_tcdm_wrapper/i_insitu_cache_tcdm_wrapper/gen_cache_banks[3]/i_access_ctrl_for_meta/*
	
	add wave -noupdate -group tile[$1] -group cache[$c] -group controller 	 	 						  /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller/*

	add wave -noupdate -group tile[$1] -group cache[$c] -group xbar	-group req /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_cache_xbar[$c]/i_cache_xbar/i_req_xbar/*
	add wave -noupdate -group tile[$1] -group cache[$c] -group xbar	-group rsp /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_cache_xbar[$c]/i_cache_xbar/i_rsp_xbar/*
  add wave -noupdate -group tile[$1] -group cache[$c] -group xbar						 /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_cache_xbar[$c]/i_cache_xbar/*
}

# Add waves for atomic units
add wave -noupdate -group tile[$1] -group amo0_4 /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/gen_cache_connect[0]/gen_cache_amo[4]/i_cache_amo/*

# Add waves for remaining signals
add wave -noupdate -group tile[$1] /tb_bin/i_dut/i_cluster_wrapper/i_cluster/gen_tiles[$1]/i_tile/*
