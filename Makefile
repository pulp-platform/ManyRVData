# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich


###############
#  Directory  #
###############
SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CACHEPOOL_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$CACHEPOOL_DIR)

# Software root (toolchain.mk depends on this)
SOFTWARE_DIR ?= ${CACHEPOOL_DIR}/software

# Host compilers (for DPI, simulators, tools)
CXX ?= /usr/pack/gcc-11.2.0-af/linux-x64/bin/g++
CC  ?= /usr/pack/gcc-11.2.0-af/linux-x64/bin/gcc
CXX_PATH ?= $(shell realpath -P $(CXX))
CC_PATH  ?= $(shell realpath -P $(CC))
GCC_LIB  ?= /usr/pack/gcc-11.2.0-af/linux-x64/lib64

# Tools
CMAKE  ?= cmake
PYTHON ?= python3.6

# -------- Toolchain (exports GCC/LLVM/Spike/Bender install dirs) --------
include toolchain.mk

###############
#  Directory  #
###############

## Hardware related
HARDWARE_DIR          ?= ${CACHEPOOL_DIR}/hardware
DEP_DIR               ?= ${HARDWARE_DIR}/deps
### Spatz related
SPATZ_DIR             ?= ${DEP_DIR}/spatz
SPZ_CLS_DIR           ?= ${SPATZ_DIR}/hw/system/spatz_cluster
### DramSys
DRAMSYS_DIR           ?= ${DEP_DIR}/dram_rtl_sim
DRAMSYS_LIB_PATH      ?= ${DRAMSYS_DIR}/dramsys_lib/DRAMSys/build/lib
DRAMSYS_RES_PATH      ?= ${DRAMSYS_DIR}/dramsys_lib/DRAMSys/configs

## Software subpaths
SPATZ_SW_DIR          ?= ${SPATZ_DIR}/sw

## Simulation related
SIM_DIR               ?= ${CACHEPOOL_DIR}/sim
SIMLIB_DIR            ?= ${SIM_DIR}/simlib              # local c lib for simulation
SNLIB_DIR             ?= ${SPATZ_DIR}/hw/ip/snitch_test/src
BOOTLIB_DIR           := ${SPZ_CLS_DIR}/test
WORK_DIR              := ${SIM_DIR}/work
SIMBIN_DIR            := ${SIM_DIR}/bin
DPI_PATH              := ${HARDWARE_DIR}/tb/dpi
DPI_LIB               ?= work-dpi

## Bender usage (binary comes from toolchain.mk install)
BENDER                ?= ${BENDER_INSTALL_DIR}/bender
# Guarded to avoid failing before bender is installed
CACHE_PATH            := $(shell [ -x "$(BENDER)" ] && $(BENDER) path insitu-cache || true)

# Configurations
CFG_DIR               ?= ${CACHEPOOL_DIR}/config
config             		?= cachepool_512

# Compiler choice for SW cmake
COMPILER              ?= llvm

############
#  Bender  #
############
# Optional sanity target to ensure the right bender version is installed
BENDER_VERSION ?= 0.28.1
.PHONY: bender check-bender
bender: $(BENDER_INSTALL_DIR)/bender
check-bender:
	@if [ -x "$(BENDER)" ]; then \
	  req="bender $(BENDER_VERSION)"; \
	  current="$$($(BENDER) --version)"; \
	  if [ "$$(printf '%s\n' "$${req}" "$${current}" | sort -V | head -n1)" != "$${req}" ]; then \
	    echo "Existing bender is older than $(BENDER_VERSION); reinstalling..."; \
	    rm -rf $(BENDER_INSTALL_DIR); \
	    $(MAKE) bender; \
	  fi \
	else \
	  $(MAKE) bender; \
	fi

# Project-level Bender op
.PHONY: checkout
checkout: bender
	${BENDER} checkout

#################
# Prerequisites #
#################

# Export make vars so Python sees them (simple and robust)
.EXPORT_ALL_VARIABLES:

config_mk       := $(abspath $(CACHEPOOL_DIR)/config/config.mk)
HJSON_TEMPLATE  := $(CFG_DIR)/cachepool.hjson.tmpl
HJSON_OUT       := $(CFG_DIR)/cachepool.hjson

include $(config_mk)

.PHONY: gen-spatz-cfg
gen-spatz-cfg: $(config_mk) $(HJSON_TEMPLATE) ${CACHEPOOL_DIR}/util/scripts/gen_spatz_cfg.py
	@mkdir -p $(CFG_DIR)
	@python3 ${CACHEPOOL_DIR}/util/scripts/gen_spatz_cfg.py --template $(HJSON_TEMPLATE) --out $(HJSON_OUT)


# Initialize submodules
.PHONY: init
init:
	git submodule update --init --recursive --jobs=8

# ETH-only quick tool switch (softlink prebuilt toolchains)
.PHONY: quick-tool
quick-tool:
	ln -sf /usr/scratch2/calanda/diyou/toolchain/cachepool-32b/install $(CACHEPOOL_DIR)/install

# Build bootrom and spatz (depends on opcodes repo being present)
.PHONY: generate
generate: update_opcodes gen-spatz-cfg
	$(MAKE) -C $(SPZ_CLS_DIR) generate bootrom SPATZ_CLUSTER_CFG=${CFG_DIR}/cachepool.hjson

.PHONY: cache-init
cache-init:
ifneq ($(CACHE_PATH),)
	cd ${CACHE_PATH} && source sourceme.sh
else
	@echo "insitu-cache path unavailable (bender not installed yet?)"
endif

###########
# DramSys #
###########
USE_DRAMSYS ?= 1
VSIM_FLAGS :=
VSIM_BENDER =

## Build DramSys
.PHONY: dram-build
dram-build:
	$(MAKE) -BC ${DRAMSYS_DIR} -j8 dramsys CXX=$(CXX) CC=$(CC)

############
# Modelsim #
############

QUESTA_VER ?= questa-2023.4-zr
VSIM        = ${QUESTA_VER} vsim
VLOG        = ${QUESTA_VER} vlog
VSIM_HOME   = /usr/pack/${QUESTA_VER}/questasim

# fesvr is built locally into work dir; needs dtc/spike path
FESVR          ?= ${SIM_DIR}/work
FESVR_VERSION  ?= c663ea20a53f4316db8cb4d591b1c8e437f4a0c4

VSIM_FLAGS += -sv_lib $(SIM_DIR)/${DPI_LIB}/cachepool_dpi
VSIM_FLAGS += -t 1ps
VSIM_FLAGS += -voptargs=+acc
VSIM_FLAGS += -suppress vsim-3999

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -override_timescale 1ns/1ps
VLOG_FLAGS += -suppress 2583
VLOG_FLAGS += -suppress 13314
VLOG_FLAGS += -64

# ------------------------
# Compile-time definitions
# ------------------------

VLOG_DEFS = -DCACHEPOOL

# Cluster configuration
VLOG_DEFS += -DNUM_TILES=$(num_tiles)
VLOG_DEFS += -DNUM_CORES=$(num_cores)
VLOG_DEFS += -DDATA_WIDTH=$(data_width)
VLOG_DEFS += -DADDR_WIDTH=$(addr_width)

# Tile configuration
VLOG_DEFS += -DNUM_CORES_PER_TILE=$(num_cores_per_tile)
VLOG_DEFS += -DREFILL_DATA_WIDTH=$(refill_data_width)

# L1 Data Cache
VLOG_DEFS += -DL1D_CACHELINE_WIDTH=$(l1d_cacheline_width)
VLOG_DEFS += -DL1D_SIZE=$(l1d_size)
VLOG_DEFS += -DL1D_BANK_FACTOR=$(l1d_bank_factor)
VLOG_DEFS += -DL1D_COAL_WINDOW=$(l1d_coal_window)
VLOG_DEFS += -DL1D_NUM_WAY=$(l1d_num_way)
VLOG_DEFS += -DL1D_TILE_SIZE=$(l1d_tile_size)
VLOG_DEFS += -DL1D_TAG_DATA_WIDTH=$(l1d_tag_data_width)
# derived (no spaces so vlog gets one arg)
VLOG_DEFS += -DL1D_NUM_BANKS=$(l1d_num_banks)
VLOG_DEFS += -DL1D_DEPTH=$(l1d_depth)

# CachePool CC / core cluster
VLOG_DEFS += -DSPATZ_FPU_EN=$(spatz_fpu_en)
VLOG_DEFS += -DSPATZ_NUM_FPU=$(spatz_num_fpu)
VLOG_DEFS += -DSPATZ_NUM_IPU=$(spatz_num_ipu)
VLOG_DEFS += -DSPATZ_MAX_TRANS=$(spatz_max_trans)
VLOG_DEFS += -DSNITCH_MAX_TRANS=$(snitch_max_trans)

# AXI configuration
VLOG_DEFS += -DAXI_USER_WIDTH=$(axi_user_width)

# L2 / main memory
VLOG_DEFS += -DL2_CHANNEL=$(l2_channel)
VLOG_DEFS += -DL2_BANK_WIDTH=$(l2_bank_width)
VLOG_DEFS += -DL2_INTERLEAVE=$(l2_interleave)

# Peripherals / memory map
VLOG_DEFS += -DSTACK_ADDR=$(stack_addr)
VLOG_DEFS += -DSTACK_HW_SIZE=$(stack_hw_size)
VLOG_DEFS += -DSTACK_HW_DEPTH=$(stack_hw_depth)
VLOG_DEFS += -DSTACK_TOT_SIZE=$(stack_tot_size)
VLOG_DEFS += -DPERIPH_START_ADDR=$(periph_start_addr)
VLOG_DEFS += -DBOOT_ADDR=$(boot_addr)
VLOG_DEFS += -DUART_ADDR=$(uart_addr)


ENABLE_CACHEPOOL_TESTS ?= 1

# Bender targets
VSIM_BENDER   += -t test -t rtl -t simulation -t spatz -t cachepool_test -t cachepool

# Include the simulation makefile
include sim/sim.mk

######
# SW #
######

.PHONY: clean.sw
clean.sw:
	rm -rf ${SOFTWARE_DIR}/build

.PHONY: sw
sw: clean.sw
	echo ${SOFTWARE_DIR}
	mkdir -p ${SOFTWARE_DIR}/build
	cd ${SOFTWARE_DIR}/build && ${CMAKE} \
	  -DENABLE_CACHEPOOL_TESTS=${ENABLE_CACHEPOOL_TESTS} \
	  -DCACHEPOOL_DIR=$(CACHEPOOL_DIR) \
	  -DRUNTIME_DIR=${SOFTWARE_DIR} \
	  -DSPATZ_SW_DIR=$(SPATZ_SW_DIR) \
	  -DLLVM_PATH=${LLVM_INSTALL_DIR} \
	  -DGCC_PATH=${GCC_INSTALL_DIR} \
	  -DPYTHON=${PYTHON} \
	  -DBUILD_TESTS=ON .. && $(MAKE)

.PHONY: vsim
vsim: dpi ${SIMBIN_DIR}/cachepool_cluster.vsim
	echo ${SOFTWARE_DIR}
	mkdir -p ${SOFTWARE_DIR}/build
	cd ${SOFTWARE_DIR}/build && ${CMAKE} \
	  -DENABLE_CACHEPOOL_TESTS=${ENABLE_CACHEPOOL_TESTS} \
	  -DCACHEPOOL_DIR=$(CACHEPOOL_DIR) \
	  -DRUNTIME_DIR=${SOFTWARE_DIR} \
	  -DSPATZ_SW_DIR=$(SPATZ_SW_DIR) \
	  -DLLVM_PATH=${LLVM_INSTALL_DIR} \
	  -DGCC_PATH=${GCC_INSTALL_DIR} \
	  -DPYTHON=${PYTHON} \
	  -DSNITCH_SIMULATOR=${SIMBIN_DIR}/cachepool_cluster.vsim \
	  -DBUILD_TESTS=ON .. && $(MAKE)

.PHONY: clean
clean: clean.sw clean.vsim

########
# Lint #
########

LINT_PATH ?= ${CACHEPOOL_DIR}/util/lint
SNPS_SG   ?= spyglass-2024.09

.PHONY: lint
lint: ${LINT_PATH}/tmp/files ${LINT_PATH}/sdc/func.sdc ${LINT_PATH}/script/lint.tcl
	cd ${LINT_PATH} && $(SNPS_SG) sg_shell -tcl ${LINT_PATH}/script/lint.tcl

${LINT_PATH}/tmp/files:
	mkdir -p ${LINT_PATH}/tmp
	@if [ ! -x "$(BENDER)" ]; then echo "bender not installed; run 'make bender'"; exit 1; fi
	${BENDER} script verilator -t rtl -t spatz -t cachepool -t dramsys --define COMMON_CELLS_ASSERTS_OFF > ${LINT_PATH}/tmp/files


########
# Help #
########
.PHONY: help
help:
	@echo ""
	@echo "--------------------------------------------------------------------------------------------------------"
	@echo "CachePool Main Makefile"
	@echo "--------------------------------------------------------------------------------------------------------"
	@echo "Initialization:"
	@echo ""
	@echo "*init*:       clone the git submodules"
	@echo "*toolchain*:  build the necessary toolchains (LLVM/GCC/Spike)"
	@echo "*quick-tool*: *ETH Member Only* soft link to prebuilt toolchains"
	@echo "*generate*:   generate the Spatz package, bootrom and opcodes"
	@echo "*dram-build*: build DRAMSys for simulation"
	@echo ""
	@echo "SW Build:"
	@echo ""
	@echo "*clean.sw*:   remove the current software build"
	@echo "*sw*:         generate the latest kernel build (will overwrite the previous build)"
	@echo ""
	@echo "Simulation:"
	@echo ""
	@echo "*clean.vsim*: remove the current hardware build"
	@echo "*vsim*:       build both the software and hardware (not overwriting prev build by default)"
	@echo "              USE_DRAMSYS=1 to use DRAMSys (default 1)"
	@echo ""
	@echo "Lint:"
	@echo "*lint*:       run SpyGlass lint (requires bender + SpyGlass in PATH)"
	@echo ""
	@echo "--------------------------------------------------------------------------------------------------------"
	@echo "Settings"
	@echo "*CMAKE*:      CMake version needs to be >= 3.28 for DRAMSys"
	@echo ""
