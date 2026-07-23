# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich


########################
##  CachePool flavor  ##
########################

# Choose a CachePool flavor.
# Check the README for more details
ifndef config
  ifdef CACHEPOOL_CONFIGURATION
    config := $(CACHEPOOL_CONFIGURATION)
  else
    # Default configuration, if neither `config` nor `CACHEPOOL_CONFIGURATION` was found
    config := cachepool
  endif
endif

include $(CACHEPOOL_DIR)/config/$(config).mk

#####################
##  DRAM Type       ##
#####################

# DRAM type used by DRAMSys and to auto-set refill_data_width.
# Supported values: DDR3, DDR4, LPDDR4, HBM2
dram_type ?= HBM2

# Auto-derive default refill data width from dram_type.
# HBM variants: 512b (3600*16/1000 = 57.6B/cyc)
# DDR variants: 128b (1866*8/1000 = 15B/cyc)
ifeq ($(dram_type),HBM2)
  refill_data_width_default := 512
else ifeq ($(dram_type),LPDDR4)
  refill_data_width_default := 256
else
  refill_data_width_default := 128
endif

#########################
##  CachePool Cluster  ##
#########################

# Number of groups
num_groups ?= 1

# X dimension of the group mesh (Y = num_groups / num_groups_x)
num_groups_x ?= 1

# Number of tiles
num_tiles_per_group ?= 4
num_tiles = $(shell echo $$(( $(num_groups) * $(num_tiles_per_group))))

# Intra-group remote ports per core (to other tiles in the same group)
num_lg_ports_per_core ?= 1

# Number of cores
num_cores_per_tile ?= 4
num_cores ?= $(shell echo $$(( $(num_tiles) * $(num_cores_per_tile))))

# Inter-group remote ports per core (to remote groups, via the L1 NoC)
num_rg_ports_per_core ?= 0

# NoC router channels per tile (concentrates each tile's inter-group traffic)
num_noc_ports_per_tile ?= 1

# Core datawidth
data_width ?= 32

# Core addrwidth
addr_width ?= 32

# Bootrom datawidth
bootrom_data_width ?= 32


######################
##  CachePool Tile  ##
######################

# Refill interconnection data width (auto-derived from dram_type; override in flavor files)
refill_data_width ?= $(refill_data_width_default)

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
l1d_tag_data_width ?= 52

### Derieved parameters, do NOT change ###
# L1 data cache number of banks per tile
l1d_num_banks := $(shell echo $$(( $(num_cores_per_tile) * $(l1d_num_way) * $(l1d_bank_factor) )))

# L1 data cache number of cacheline
l1d_depth     := $(shell echo $$(( $(l1d_tile_size) * 8192 / $(l1d_cacheline_width) )))


####################
##  CachePool CC  ##
####################
# Spatz fpu support?
spatz_fpu_en ?= 1

# Spatz number of FPU
spatz_num_fpu ?= 4

# Spatz number of IPU
spatz_num_ipu ?= 4

# Spatz max outstanding transactions
spatz_max_trans ?= 32

# Snitch/FPU max outstanding transactions
snitch_max_trans ?= 16


#########################
##  AXI configuration  ##
#########################

# axi_user_width sets the AXI 'user' field that carries refill_user_t over the
# cache->L2 AXI.  Hard requirement: axi_user_width >= $bits(refill_user_t).
# This floor is now enforced in RTL by ASSERT_INIT(CheckAxiUserFitsRefillUser)
# in cachepool_cluster.sv, and the cluster zero-extends refill_user_t onto the
# (wider) AXI user port at the reqrsp_to_axi call site.
#
#   refill_user_t = bank_id(BankIDWidth) + tile_id(TileIDWidth)
#                 + cache_info_t + burst_req_t
#   cache_info_t  = {for_write_pend, depth, way}   -- NOTE: NO tile_id inside.
#
# So refill_user_t carries TileIDWidth exactly ONCE.  The values below are
# deliberately conservative headroom, not an exact fit: the per-tile adjustment
# adds 2*(idx_width(NumTiles)-1) bits, and cachepool_pkg.sv:163 then adds a
# further clog2(NumTiles) (SpatzAxiUserWidth = AXI_USER_WIDTH + clog2(NumTiles)),
# so the tile term ends up over-provisioned.  This is harmless: no RTL reads any
# AXI user bit above $bits(refill_user_t)-1.
# (An earlier version of this comment claimed cache_info_t held a second
#  TileIDWidth copy and therefore doubled idx_width(NumTiles) -- it does not;
#  the 2x factor is just slack, kept as-is for headroom.)
#
# Do NOT let axi_user_width drop below $bits(refill_user_t): the MSB of bank_id
# (or higher tile_id) would be truncated on the AXI loopback and refill
# responses would route back to the wrong slv port (e.g. bank_id=4 aliases to
# bank_id=0, sending cb=3's refill response to the icache bypass slot, making
# cb=3 hang).  The ASSERT_INIT above catches this at elaboration.

ifeq ($(num_tiles),1)
  axi_user_tile_adj := 0
else ifeq ($(num_tiles),2)
  axi_user_tile_adj := 0
else ifeq ($(num_tiles),4)
  axi_user_tile_adj := 2
else ifeq ($(num_tiles),8)
  axi_user_tile_adj := 4
else ifeq ($(num_tiles),16)
  axi_user_tile_adj := 6
else
  $(error num_tiles=$(num_tiles) not handled by axi_user_width formula; add a case in config.mk)
endif

# Base widths for NumTiles=1 (= reference values, verified working).
ifeq ($(l1d_cacheline_width),512)
  axi_user_base := 18
else ifeq ($(l1d_cacheline_width),256)
  axi_user_base := 19
else ifeq ($(l1d_cacheline_width),128)
  axi_user_base := 22
endif

axi_user_width := $(shell echo $$(( $(axi_user_base) + $(axi_user_tile_adj) )))

#####################
##  L2 Main Memory ##
#####################

# DRAM base address and size (hex: 0x8000_0000, 0x2000_0000)
dram_addr ?= 2147483648
dram_len  ?= 536870912

# Uncached region base address and size (hex: 0xC000_0000, 0x2000_0000)
uncached_addr ?= 3221225472
uncached_len  ?= 536870912

# L2 number of channels
l2_channel ?= 4

# L2 bank width (DRAM width, change with care)
l2_bank_width ?= 512

# L2 interleaving factor (in order of bank_width)
l2_interleave ?= 16


##################
##  Peripherals ##
##################
# Stack start address (32'hBFFF_F800)
stack_addr ?= 3221223424

# Hardware stack size (in Byte)
stack_hw_size ?= 1024

# Stack size (total, including share and private, 32'h800)
stack_tot_size ?= 2048

### Derieved parameters, do NOT change ###
# Hardware stack depth
stack_hw_depth := $(shell echo $$(( $(stack_hw_size) * 8 / $(data_width) )))

# Total stack depth
stack_tot_depth := $(shell echo $$(( $(stack_tot_size) * 8 / $(data_width) )))

# Peripheral start address (32'hC000_0000)
periph_start_addr ?= 3221225472

# Boot address (32'h1000)
boot_addr ?= 4096

# UART address (32'hC001_0000)
uart_addr ?= 3221291008
