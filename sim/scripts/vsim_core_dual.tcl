# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Create group for a dual-CC Core Complex (2 Snitch harts sharing 1 Spatz).
# Not a mechanical mirror of vsim_core.tcl's single-CC dump: cachepool_cc_dual
# has a different internal structure (2x gen_snitch, 1 shared i_spatz, plus
# the lock/acc_mux), so this covers both harts' top-level Snitch signals, the
# shared Spatz, and the ownership lock/mux state, rather than replicating
# every internal Snitch/Spatz signal group per hart.
onerror {resume}
quietly WaveActivateNextPane {} 0

quietly set core_path ${4}/gen_dual
quietly set name g_${1}_t_${2}_c_${3}

quietly set parent_grp [list]
if {$argc > 4 && "${5}" != ""} {
    quietly lappend parent_grp -group ${5}
}
if {$argc > 5 && "${6}" != ""} {
    quietly lappend parent_grp -group ${6}
}

# Lock/switch state: which host owns Spatz, and the acc_mux fake-completion state.
add wave -noupdate {*}$parent_grp -group ${name} -group Lock ${core_path}/i_cachepool_cc_dual/i_spatz_lock/*
add wave -noupdate {*}$parent_grp -group ${name} -group AccMux ${core_path}/i_cachepool_cc_dual/i_acc_mux/*

for {set h 0} {$h < 2} {incr h} {
    quietly set snitch_path ${core_path}/i_cachepool_cc_dual/gen_snitch[${h}]/i_snitch

    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} -radix unsigned ${snitch_path}/hart_id_i

    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} -divider Instructions
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/inst_addr_o
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/inst_data_i
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/inst_valid_o
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/inst_ready_i

    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} -divider Load/Store
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/data_req_o
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/data_rsp_i

    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} -divider Accelerator
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_qreq_o
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_qrsp_i
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_qvalid_o
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_qready_i
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_prsp_i
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_pvalid_i
    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} ${snitch_path}/acc_pready_o

    add wave -noupdate {*}$parent_grp -group ${name} -group Host${h} -group Internal ${snitch_path}/*
}

quietly set spatz_path ${core_path}/i_cachepool_cc_dual/i_spatz

add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/issue_valid_i
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/issue_ready_o
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/issue_req_i
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/issue_rsp_o
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/rsp_valid_o
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/rsp_ready_i
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/rsp_o
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/spatz_mem_req_o
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/spatz_mem_req_valid_o
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/spatz_mem_req_ready_i
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/spatz_mem_rsp_i
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz ${spatz_path}/spatz_mem_rsp_valid_i

add wave -noupdate {*}$parent_grp -group ${name} -group Spatz -group VLSU ${spatz_path}/i_vlsu/*
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz -group VSLDU ${spatz_path}/i_vsldu/*
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz -group VFU ${spatz_path}/i_vfu/*
add wave -noupdate {*}$parent_grp -group ${name} -group Spatz -group Controller ${spatz_path}/i_controller/*

add wave -noupdate {*}$parent_grp -group ${name} -group Internal ${core_path}/i_cachepool_cc_dual/*
