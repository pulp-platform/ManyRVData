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

#########################
##  CachePool Cluster  ##
#########################

# Number of tiles
num_tiles ?= 1

num_remote_ports_per_tile ?= 1

# Number of cores
num_cores ?= 4

# Core datawidth
data_width ?= 32

# Core addrwidth
addr_width ?= 32


######################
##  CachePool Tile  ##
######################

# Number of cores per CachePool tile
num_cores_per_tile ?= 4

# Refill interconnection data width
refill_data_width ?= 128

##### L1 Data Cache #####

# L1 data cacheline width (in Bit)
l1d_cacheline_width ?= 512

# L1 data cache size (in KiB)
l1d_size ?= 256

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

# axi_user_width must be >= $bits(refill_user_t).
# refill_user_t = bank_id(3) + tile_id(W) + cache_info_t(*) + burst_req_t(3),
# where cache_info_t contains TWO copies of TileIDWidth (the field itself
# plus a nested copy inside cache_info_t).  So adding a tile multiplies
# idx_width(NumTiles) by 2.
#
# Base values below assume NumTiles=1 (idx_width=1).  We add a per-tile
# adjustment of 2 * (idx_width(NumTiles) - 1) bits for larger configs.
#
# If axi_user_width is too small, the MSB of bank_id (or higher tile_id)
# gets truncated on the AXI loopback and refill responses get routed back
# to the wrong slv port (e.g. bank_id=4 aliases to bank_id=0, sending
# cb=3's refill response to the icache bypass slot, making cb=3 hang).

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
