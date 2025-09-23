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
# --- AXI user width derived from L1D cacheline width ---
# supported widths only
ifneq ($(filter $(l1d_cacheline_width),128 256 512),$(l1d_cacheline_width))
  $(error l1d_cacheline_width must be one of {128,256,512} (got $(l1d_cacheline_width)))
endif

ifeq ($(l1d_cacheline_width),512)
  axi_user_width := 17
else ifeq ($(l1d_cacheline_width),256)
  axi_user_width := 19
else ifeq ($(l1d_cacheline_width),128)
  axi_user_width := 21
endif

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
