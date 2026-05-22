# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

onerror {resume}

quietly set group_path $1
quietly set parent_grp $3

# Add waves for remote xbar
for {set p 0}  {$p < $2} {incr p} {
	onerror {resume}

	quietly set xbar_path ${group_path}/gen_remote_tile_xbar[$p]/i_tile_remote_xbar

	add wave -noupdate -group "${parent_grp}" -group remote_xbar[$p] ${xbar_path}/*
}

add wave -noupdate -group "${parent_grp}" -group refill_xbar -group req_xbar ${group_path}/i_refill_xbar/i_req_xbar/*
add wave -noupdate -group "${parent_grp}" -group refill_xbar -group rsp_xbar ${group_path}/i_refill_xbar/i_rsp_xbar/*

add wave -noupdate -group "${parent_grp}" -group Internal ${group_path}/*
