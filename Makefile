# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich


SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CACHEPOOL_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$CACHEPOOL_DIR)

# Include configuration
# config_mk = $(abspath $(ROOT_DIR)/config/config.mk)
# include $(config_mk)

# Directories
INSTALL_PREFIX        ?= install
SOFTWARE_DIR          ?= ${CACHEPOOL_DIR}/software
TOOLCHAIN_DIR 				?= ${SOFTWARE_DIR}/toolchain
SPATZ_DIR        			?= $(CACHEPOOL_DIR)/hardware/deps/spatz


INSTALL_DIR           ?= ${ROOT_DIR}/${INSTALL_PREFIX}
GCC_INSTALL_DIR       ?= ${INSTALL_DIR}/riscv-gcc
ISA_SIM_INSTALL_DIR   ?= ${INSTALL_DIR}/riscv-isa-sim
LLVM_INSTALL_DIR      ?= ${INSTALL_DIR}/llvm
HALIDE_INSTALL_DIR    ?= ${INSTALL_DIR}/halide
BENDER_INSTALL_DIR    ?= ${INSTALL_DIR}/bender
VERILATOR_INSTALL_DIR ?= ${INSTALL_DIR}/verilator
RISCV_TESTS_DIR       ?= ${ROOT_DIR}/${SOFTWARE_DIR}/riscv-tests

# Tools
COMPILER ?= llvm

CMAKE ?= cmake
# CC and CXX are Makefile default variables that are always defined in a Makefile. Hence, overwrite
# the variable if it is only defined by the Makefile (its origin in the Makefile's default).
ifeq ($(origin CC),default)
  CC  ?= gcc
endif
ifeq ($(origin CXX),default)
  CXX ?= g++
endif
BENDER_VERSION = 0.28.1


# Initialize, setup the toolchain for Spatz
init:
	git submodule update --init --recursive --jobs=8
	ln -sf /usr/scratch2/calanda/diyou/flamingo/spatz-mx/spatz/install $(SPATZ_DIR)/install

# Bender
bender: check-bender
check-bender:
	@if [ -x $(BENDER_INSTALL_DIR)/bender ]; then \
		req="bender $(BENDER_VERSION)"; \
		current="$$($(BENDER_INSTALL_DIR)/bender --version)"; \
		if [ "$$(printf '%s\n' "$${req}" "$${current}" | sort -V | head -n1)" != "$${req}" ]; then \
			rm -rf $(BENDER_INSTALL_DIR); \
		fi \
	fi
	@$(MAKE) -C $(ROOT_DIR) $(BENDER_INSTALL_DIR)/bender

$(BENDER_INSTALL_DIR)/bender:
	mkdir -p $(BENDER_INSTALL_DIR) && cd $(BENDER_INSTALL_DIR) && \
	curl --proto '=https' --tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- $(BENDER_VERSION)

.PHONY: rm-spatz
rm-spatz:
	source /home/dishen/saferm.sh $(SPATZ_DIR)


# Build bootrom and spatz
.PHONY: generate
generate: update_opcodes
	make -C $(SPATZ_DIR)/hw/system/spatz_cluster generate;


# QuestaSim
VSIM      = questa-2021.3-kgf vsim
VLOG      = questa-2021.3-kgf vlog
VSIM_HOME = /usr/pack/questa-2021.3-kgf/questasim

VSIM_FLAGS += -t 1ps
VSIM_FLAGS += -voptargs=+acc
VSIM_FLAGS += -suppress vsim-3999
VSIM_FLAGS += -do "log -r /*; run -a"

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -override_timescale 1ns/1ps
VLOG_FLAGS += -suppress 2583
VLOG_FLAGS += -suppress 13314
VLOG_FLAGS += -64

USE_CACHE ?= 1
USE_PRINT ?= 1
ENABLE_CACHEPOOL_TESTS ?= 1


#############
#  Opcodes  #
#############

.PHONY: update_opcodes
update_opcodes: clean-opcodes ${TOOLCHAIN_DIR}/riscv-opcodes ${TOOLCHAIN_DIR}/riscv-opcodes/encoding.h ${SPATZ_DIR}/hw/ip/snitch/src/riscv_instr.sv

clean-opcodes:
	rm -rf ${TOOLCHAIN_DIR}/riscv-opcodes

${TOOLCHAIN_DIR}/riscv-opcodes: ${TOOLCHAIN_DIR}/riscv-opcodes.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/mp-17/riscv-opcodes.git
	cd ${TOOLCHAIN_DIR}/riscv-opcodes &&                 \
		git checkout `cat ../riscv-opcodes.version` && \
		git submodule update --init --recursive --jobs=8 .

${SPATZ_DIR}hw/ip/snitch/src/riscv_instr.sv: ${TOOLCHAIN_DIR}/riscv-opcodes
	MY_OPCODES=$(OPCODES) make -C ${TOOLCHAIN_DIR}/riscv-opcodes inst.sverilog
	mv ${TOOLCHAIN_DIR}/riscv-opcodes/inst.sverilog $@

${TOOLCHAIN_DIR}/riscv-opcodes/encoding.h:
	MY_OPCODES=$(OPCODES) make -C ${TOOLCHAIN_DIR}/riscv-opcodes all
	cp ${TOOLCHAIN_DIR}/riscv-opcodes/encoding_out.h $@



############
# Modelsim #
############
# Currently highjack the simulation flow from spatz
.PHONY: sw
sw:
	make -BC ${SPATZ_DIR}/hw/system/spatz_cluster sw DEFS="-t cachepool" \
		USE_CACHE=${USE_CACHE} ENABLE_PRINT=${USE_PRINT} RUNTIME_DIR=${CACHEPOOL_DIR}/software \
		ENABLE_CACHEPOOL_TESTS=${ENABLE_CACHEPOOL_TESTS} CACHEPOOL_DIR=${CACHEPOOL_DIR} BUILD_DIR=${CACHEPOOL_DIR}/software


.PHONY: vsim
vsim:
	make -BC ${SPATZ_DIR}/hw/system/spatz_cluster sw.vsim DEFS="-t cachepool" \
		USE_CACHE=${USE_CACHE} ENABLE_PRINT=${USE_PRINT} RUNTIME_DIR=${CACHEPOOL_DIR}/software BIN_DIR=${CACHEPOOL_DIR} \
		ENABLE_CACHEPOOL_TESTS=${ENABLE_CACHEPOOL_TESTS} CACHEPOOL_DIR=${CACHEPOOL_DIR} BUILD_DIR=${CACHEPOOL_DIR}/software
# 	rm -rf bin
# 	mkdir -p bin
# 	cp -r ${SPATZ_DIR}/hw/system/spatz_cluster/bin/* bin/
