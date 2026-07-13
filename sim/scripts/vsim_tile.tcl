# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Tile $1
onerror {resume}

quietly set tile_path  $3
quietly set parent_grp $4

# --- Configuration Variables ---
# NrTCDMPortsPerCore: 4 Spatz ports + 1 Snitch port
quietly set NUM_XBARS   5
quietly set SNITCH_IDX  [expr {$NUM_XBARS - 1}]

# Add waves for tcdm_mapper and csrs
# add wave -noupdate -group ${parent_grp} -group tile[$1] -group Barrier ${tile_path}/i_tile/i_snitch_barrier/*
# add wave -noupdate -group ${parent_grp} -group tile[$1] -group axi2reqrsp ${tile_path}/i_axi2reqrsp/*
# Add waves for xbars
add wave -noupdate -group ${parent_grp} -group tile[$1] -group narrow_xbar ${tile_path}/i_tile/i_axi_narrow_xbar/*
add wave -noupdate -group ${parent_grp} -group tile[$1] -group wide_xbar ${tile_path}/i_tile/i_axi_wide_xbar/*

add wave -noupdate -group ${parent_grp} -group tile[$1] -group Barrier ${tile_path}/i_tile/i_cachepool_tile_barrier/*

# Add waves for private L1 (LP1 = per-core HPDcache, in cachepool_l1_ctrl).
# One instance per core; NumLP1CacheCtrl == NumL1CtrlTile (= num_cores_per_tile),
# so this reuses the same loop bound as the shared cache below. onerror/resume
# tolerates over-iteration for configs with fewer cores per tile.
for {set c 0}  {$c < 4} {incr c} {
	onerror {resume}

	quietly set lp1_path ${tile_path}/i_tile/gen_lp1_cache[$c]/i_lp1_cache
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group hpdcache   ${lp1_path}/i_l1_hpdcache/core_req_i
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group hpdcache   ${lp1_path}/i_l1_hpdcache/core_req_ready_o
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group hpdcache   ${lp1_path}/i_l1_hpdcache/core_rsp_valid_o
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group hpdcache   ${lp1_path}/i_l1_hpdcache/core_rsp_o
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group hpdcache   ${lp1_path}/i_l1_hpdcache/*


	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group ctrl   ${lp1_path}/i_l1_hpdcache/hpdcache_ctrl_i/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group ctrl_pe   ${lp1_path}/i_l1_hpdcache/hpdcache_ctrl_i/hpdcache_ctrl_pe_i/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group wbuf   ${lp1_path}/i_l1_hpdcache/gen_wbuf/hpdcache_wbuf_i/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group coalescer  ${lp1_path}/i_l1_req_coalescer/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group lp1[$c] -group Internal   ${lp1_path}/*
}

# Add waves for cache controller
for {set c 0}  {$c < 4} {incr c} {
	onerror {resume}

	quietly set cache_path ${tile_path}/i_tile/gen_l1_cache_ctrl[$c]/i_l1_controller

	# [Phase 2 / WI-3] The L2-side spatz_cache_amo is now one instance per L2
	# controller on the single cacheline port (gen_cache_connect[$c]/i_cache_amo),
	# replacing the old per-plane gen_cache_amo_connect[SNITCH_IDX]/gen_amo nesting.
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group amo ${tile_path}/i_tile/gen_cache_connect[$c]/i_cache_amo/*

	# [LP1] The per-L2 Spatz coalescer (i_par_coalescer_for_spatz) was removed in the
	# insitu fork (the private L1 coalesces upstream now), so this path no longer exists.
	# add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group coalescer  ${cache_path}/i_par_coalescer_for_spatz/gen_extend_window/i_par_coalescer_extend_window/i_par_coalescer/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group core			  ${cache_path}/i_insitu_cache_tcdm_wrapper/i_insitu_cache_core/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group meta_ctrl0	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[0]/i_access_ctrl_for_meta/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group meta_ctrl1	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[1]/i_access_ctrl_for_meta/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group meta_ctrl2	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[2]/i_access_ctrl_for_meta/*
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group meta_ctrl3	${cache_path}/i_insitu_cache_tcdm_wrapper/gen_cache_banks[3]/i_access_ctrl_for_meta/*
	
	add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache[$c] -group Internal   ${cache_path}/*
}

for {set c 0} {$c < $NUM_XBARS} {incr c} {
  add wave -noupdate -group ${parent_grp} -group tile[$1] -group cache_xbar -group xbar[$c]	${tile_path}/i_tile/gen_cache_xbar[$c]/gen_remote_group_slice/i_cache_xbar/*
}

# Add waves for remaining signals
add wave -noupdate -group ${parent_grp} -group tile[$1] -group Internal ${tile_path}/i_tile/*
