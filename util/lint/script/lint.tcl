set PROJECT   cachepool_cluster_wrapper
set TIMESTAMP [exec date +%Y%m%d_%H%M%S]

new_project sg_projects/${PROJECT}_${TIMESTAMP}
current_methodology $env(SPYGLASS_HOME)/GuideWare/latest/block/rtl_handoff

# Read the RTL
read_file -type sourcelist tmp/files

set_option enableSV09 yes
set_option allow_module_override yes
set_option designread_disable_flatten no
set_option nopreserve yes
set_option top cachepool_cluster_wrapper

# Do not elaborate some problematic FPU modules
set_option stop fpnew_sdotp_multi
set_option stop fpnew_fma_multi
set_option stop tc_sram_impl
set_option stop tc_sram
set_option stop fpnew_opgroup_block
set_option stop fpnew_noncomp

# Read constraints
current_design cachepool_cluster_wrapper
set_option sdc2sgdc yes
sdc_data -file sdc/func.sdc

# Link Design
compile_design

#
# Waivers
#

# Input [] declared but not read.
waive -rule "W240"
# Input [] not connected.
waive -rule "W287b"
# Variable [] set but not read.
waive -rule "W528"
# Signal [] is being assigned multiple times in the same block.
waive -rule "W415a"
# Bit-width mismatch between function call argument [] and function input [].
waive -rule "STARC05-2.1.3.1"
# Initial assignment for [] is ignored by synthesis.
waive -rule "SYNTH_89"
# Based number [] contains a dont care.
waive -rule "W467"
# Rhs width with shift is less than lhs width.
waive -rule "W486"
# For operator [] left expression width should match right expression width.
waive -rule "W116"
waive -rule "W362"
# Unsigned element [] passed to the $unsigned() function call.
waive -rule "WRN_1024"
# Enable pin EN on Flop [] (master RTL_FDCE) is always disabled (tied low)
waive -rule "FlopEConst"
# Return type width is less than return value width.
waive -rule "W416"
# Assert not synthesizable
waive -rule "SYNTH_5064"

# W123 "read but never set" on coalescer_resp/bypass_resp in cachepool_cache_ctrl:
# FALSE POSITIVE. Both are the slv_rsp_o OUTPUT of i_bypass_xbar (reqrsp_xbar),
# bound via the '{bypass_resp, coalescer_resp} array-of-struct aggregate. The xbar
# drives slv_rsp_o fully (reqrsp_xbar.sv: assign slv_rsp_o[port] = core_rsp[port]),
# so .data/.meta/.write ARE set; SpyGlass W123 cannot trace the driver through the
# aggregate port binding. Scoped to the DU so genuine W123 elsewhere still report.
waive -du "cachepool_cache_ctrl" -rule "W123"
# W123 on decoder_req_i.* in spatz_decoder: third-party Spatz dep, not owned/modified
# here (per instruction). Scoped to the DU so our-RTL W123 still report.
waive -du "spatz_decoder" -rule "W123"

# Set lint_rtl goal and run
current_goal lint/lint_rtl
run_goal

# Create a link to the results
exec rm -rf sg_projects/${PROJECT}
exec ln -sf ${PROJECT}_${TIMESTAMP} sg_projects/${PROJECT}

# Ciao!
exit -save
