# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for Tile $1
onerror {resume}

set group_path $1

# Add waves for remote xbar
for {set p 0}  {$p < $2} {incr p} {
	onerror {resume}

	set xbar_path ${group_path}/gen_remote_tile_xbar[$p]/i_tile_remote_xbar

	add wave -noupdate -group Group -group remote_xbar[$p] ${xbar_path}/*
}

add wave -noupdate -group Group -group refill_xbar -group req_xbar ${group_path}/i_refill_xbar/i_req_xbar/*
add wave -noupdate -group Group -group refill_xbar -group rsp_xbar ${group_path}/i_refill_xbar/i_rsp_xbar/*


add wave -noupdate -group Group -group Internal ${group_path}/*
