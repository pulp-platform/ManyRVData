# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich

#########################
##  CachePool Cluster  ##
#########################

# Number of groups
num_groups ?= 2

# 1×2 mesh
num_groups_x ?= 1

# Number of tiles
num_tiles_per_group ?= 4

# Number of cores
num_cores_per_tile  ?= 4

# Core datawidth
data_width ?= 32

# Core addrwidth
addr_width ?= 32

num_remote_ports_per_tile ?= 1

num_rg_ports_per_core ?= 1

num_noc_ports_per_tile ?= 1


######################
##  CachePool Tile  ##
######################

##### L1 Data Cache #####

# L1 data cacheline width (in Bit)
l1d_cacheline_width ?= 512

# L1 data cache banking factor (how many banks per core?)
l1d_bank_factor ?= 1

# L1 coalecsing window
l1d_coal_window ?= 2

# L1 data cache number of ways per
l1d_num_way ?= 4

# L1 data cache size per tile (KiB)
l1d_tile_size ?= 256

# L1 data cache tag width (TODO: should be calcualted)
l1d_tag_data_width ?= 92

# L1 data-bank micro-architecture (1=on, 0=off).
# Production cache  = folded(1) + hash-way(1) + fwd-buffer(1).
# Unfolded "conventional" cache = folded(0) + hash-way(0) + fwd-buffer(0).
# Constraints (enforced by RTL elaboration asserts):
#   - folded (l1d_use_folded=1) REQUIRES l1d_use_hash_way=1
#   - fwd-buffer (l1d_use_fwd_buf=1) REQUIRES l1d_use_hash_way=1
# l1d_fold_way_group=0 => auto (min(4, ways)).
l1d_use_folded     ?= 1
l1d_fold_way_group ?= 0
l1d_use_hash_way   ?= 1
l1d_use_fwd_buf    ?= 1

####################
##  CachePool CC  ##
####################
# Spatz fpu support?
spatz_fpu_en ?= 0

# Spatz number of FPU
spatz_num_fpu ?= 0

# Spatz number of IPU
spatz_num_ipu ?= 4

# Spatz max outstanding transactions
spatz_max_trans ?= 32

# Snitch/FPU max outstanding transactions
snitch_max_trans ?= 16


#####################
##  L2 Main Memory ##
#####################
# DRAM type (selects DRAMSys config and sets default refill_data_width)
dram_type ?= HBM2

# L2 number of channels
l2_channel ?= 4

# L2 bank width (DRAM width, change with care)
l2_bank_width ?= 512

# L2 interleaving factor (in order of bank_width)
l2_interleave ?= 16


##################
##  Peripherals ##
##################
# Hardware stack size (in Byte)
stack_hw_size ?= 1024

# Stack size (total, including share and private, 32'h800)
stack_tot_size ?= 2048
