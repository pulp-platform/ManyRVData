# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich

# Base Directory
SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CACHEPOOL_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$CACHEPOOL_DIR)
CXX   := /usr/pack/gcc-11.2.0-af/linux-x64/bin/g++
CC    := /usr/pack/gcc-11.2.0-af/linux-x64/bin/gcc

# Directoriy Path
PYTHON                ?= python3.6

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

## Toolchain related
TOOLCHAIN_DIR         ?= ${SOFTWARE_DIR}/toolchain
INSTALL_PREFIX        ?= install
INSTALL_DIR           ?= ${ROOT_DIR}/${INSTALL_PREFIX}
GCC_INSTALL_DIR       ?= ${INSTALL_DIR}/riscv-gcc
ISA_SIM_INSTALL_DIR   ?= ${INSTALL_DIR}/riscv-isa-sim
LLVM_INSTALL_DIR      ?= ${INSTALL_DIR}/llvm
HALIDE_INSTALL_DIR    ?= ${INSTALL_DIR}/halide
BENDER_INSTALL_DIR    ?= ${INSTALL_DIR}/bender
VERILATOR_INSTALL_DIR ?= ${INSTALL_DIR}/verilator
RISCV_TESTS_DIR       ?= ${ROOT_DIR}/${SOFTWARE_DIR}/riscv-tests

## Software related
SOFTWARE_DIR          ?= ${CACHEPOOL_DIR}/software
SPATZ_SW_DIR          ?= ${SPATZ_DIR}/sw

## Simulation related
SIM_DIR               ?= ${CACHEPOOL_DIR}/sim
### local c lib for simulation
SIMLIB_DIR            ?= ${SIM_DIR}/simlib
### Snitch testbench c lib for simulation
SNLIB_DIR             ?= ${SPATZ_DIR}/hw/ip/snitch_test/src
### Spatz bootrom c lib for simulation
BOOTLIB_DIR           := ${SPZ_CLS_DIR}/test
### QuestaSim work directory
WORK_DIR              := ${SIM_DIR}/work
SIMBIN_DIR            := ${SIM_DIR}/bin
DPI_PATH              := ${HARDWARE_DIR}/tb/dpi
DPI_LIB               ?= work-dpi

## Bender
BENDER                ?= ${BENDER_INSTALL_DIR}/bender
CACHE_PATH            := $(shell $(BENDER) path insitu-cache)

## SpyGlass
LINT_PATH 						?= ${CACHEPOOL_DIR}/util/lint
SNPS_SG 							?= spyglass-2022.06

# Configurations
CFG_DIR               ?= ${CACHEPOOL_DIR}/cfg
CFG                   ?= cachepool.hjson

# Tools
COMPILER              ?= llvm

# Version needs to be larger than 3.28
CMAKE                 ?= cmake

CXX 									?= /usr/pack/gcc-11.2.0-af/linux-x64/bin/g++
CC  									?= /usr/pack/gcc-11.2.0-af/linux-x64/bin/gcc

# Default value for ETH users only, GCC and CXX needs to be higher than 11.2.0
CXX_PATH              ?= $(shell realpath -P $(CXX))
CC_PATH               ?= $(shell realpath -P $(CC))
GCC_LIB               ?= /usr/pack/gcc-11.2.0-af/linux-x64/lib64

############
#  Bender  #
############

BENDER_VERSION = 0.28.1

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

checkout: bender
	${BENDER} checkout


###############
#  Toolchain  #
###############

toolchain: checkout download tc-llvm tc-riscv-gcc

.PHONY: download
download: ${TOOLCHAIN_DIR}/riscv-gnu-toolchain ${TOOLCHAIN_DIR}/llvm-project ${TOOLCHAIN_DIR}/riscv-opcodes ${TOOLCHAIN_DIR}/riscv-isa-sim ${TOOLCHAIN_DIR}/dtc


${TOOLCHAIN_DIR}/riscv-gnu-toolchain: ${TOOLCHAIN_DIR}/riscv-gnu-toolchain.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/pulp-platform/pulp-riscv-gnu-toolchain.git riscv-gnu-toolchain
	cd ${TOOLCHAIN_DIR}/riscv-gnu-toolchain &&           \
		git checkout `cat ../riscv-gnu-toolchain.version` && \
		git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/llvm-project: ${TOOLCHAIN_DIR}/llvm-project.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/mp-17/llvm-project.git
	cd ${TOOLCHAIN_DIR}/llvm-project &&                  \
		git checkout `cat ../llvm-project.version` && \
		git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/riscv-opcodes: ${TOOLCHAIN_DIR}/riscv-opcodes.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/mp-17/riscv-opcodes.git
	cd ${TOOLCHAIN_DIR}/riscv-opcodes &&                 \
		git checkout `cat ../riscv-opcodes.version` && \
		git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/riscv-isa-sim: ${TOOLCHAIN_DIR}/riscv-isa-sim.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/riscv-software-src/riscv-isa-sim.git
	cd ${TOOLCHAIN_DIR}/riscv-isa-sim &&                 \
		git checkout `cat ../riscv-isa-sim.version` && \
		git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/dtc:
	mkdir -p ${TOOLCHAIN_DIR}/dtc
	cd ${TOOLCHAIN_DIR}/dtc && wget -c https://git.kernel.org/pub/scm/utils/dtc/dtc.git/snapshot/dtc-1.7.0.tar.gz
	cd ${TOOLCHAIN_DIR}/dtc && tar xf dtc-1.7.0.tar.gz

tc-riscv-gcc: ${TOOLCHAIN_DIR}/riscv-gnu-toolchain
	mkdir -p $(GCC_INSTALL_DIR)
	cd ${TOOLCHAIN_DIR}/riscv-gnu-toolchain && rm -rf build && mkdir -p build && cd build && \
	../configure --prefix=$(GCC_INSTALL_DIR) --with-arch=rv32imaf --with-abi=ilp32f --with-cmodel=medlow --enable-multilib && \
	$(MAKE) MAKEINFO=true -j4

tc-llvm: ${TOOLCHAIN_DIR}/llvm-project
	mkdir -p $(LLVM_INSTALL_DIR)
	cd ${TOOLCHAIN_DIR}/llvm-project && mkdir -p build && cd build; \
	$(CMAKE) \
		-DCMAKE_INSTALL_PREFIX=$(LLVM_INSTALL_DIR) \
		-DCMAKE_CXX_COMPILER=g++-11.2.0 \
		-DCMAKE_C_COMPILER=gcc-11.2.0 \
		-DLLVM_OPTIMIZED_TABLEGEN=True \
		-DLLVM_ENABLE_PROJECTS="clang;lld" \
		-DLLVM_TARGETS_TO_BUILD="RISCV" \
		-DLLVM_DEFAULT_TARGET_TRIPLE=riscv32-unknown-elf \
		-DLLVM_ENABLE_LLD=False \
		-DLLVM_APPEND_VC_REV=ON \
		-DCMAKE_BUILD_TYPE=Release \
		../llvm && \
	make -j8 all && \
	make install

tc-riscv-isa-sim: ${TOOLCHAIN_DIR}/riscv-isa-sim ${TOOLCHAIN_DIR}/dtc
	mkdir -p $(ISA_SIM_INSTALL_DIR)
	cd ${TOOLCHAIN_DIR}/dtc/dtc-1.7.0 && make install PREFIX=$(ISA_SIM_INSTALL_DIR)
	cd ${ISA_SIM_INSTALL_DIR} && rm -rf build && mkdir -p build && cd build && \
	PATH=$(ISA_SIM_INSTALL_DIR)/bin:$(PATH) ../configure --prefix=$(ISA_SIM_INSTALL_DIR) && \
	$(MAKE) MAKEINFO=true -j4 install


#############
#  Opcodes  #
#############

.PHONY: update_opcodes
update_opcodes: clean-opcodes ${TOOLCHAIN_DIR}/riscv-opcodes ${TOOLCHAIN_DIR}/riscv-opcodes/encoding.h ${SPATZ_DIR}/hw/ip/snitch/src/riscv_instr.sv

clean-opcodes:
	rm -rf ${TOOLCHAIN_DIR}/riscv-opcodes

${SPATZ_DIR}hw/ip/snitch/src/riscv_instr.sv: ${TOOLCHAIN_DIR}/riscv-opcodes
	MY_OPCODES=$(OPCODES) make -C ${TOOLCHAIN_DIR}/riscv-opcodes inst.sverilog
	mv ${TOOLCHAIN_DIR}/riscv-opcodes/inst.sverilog $@

${TOOLCHAIN_DIR}/riscv-opcodes/encoding.h:
	MY_OPCODES=$(OPCODES) make -C ${TOOLCHAIN_DIR}/riscv-opcodes all
	cp ${TOOLCHAIN_DIR}/riscv-opcodes/encoding_out.h $@


#################
# Prerequisites #
#################

# Initialize, setup the toolchain for Spatz
init:
	git submodule update --init --recursive --jobs=8

quick-tool:
	ln -sf /usr/scratch2/calanda/diyou/toolchain/cachepool-32b/install $(CACHEPOOL_DIR)/install

# Build bootrom and spatz
.PHONY: generate
generate: update_opcodes
	make -C $(SPZ_CLS_DIR) generate bootrom SPATZ_CLUSTER_CFG=${CFG_DIR}/${CFG}

.PHONY: cache-init
cache-init:
	cd ${CACHE_PATH} && source sourceme.sh


###########
# DramSys #
###########

# Options
USE_DRAMSYS ?= 1

ifeq ($(USE_DRAMSYS),1)
	VSIM_BENDER += -t DRAMSYS
	VSIM_FLAGS += +DRAMSYS_RES=$(DRAMSYS_RES_PATH)
	VSIM_FLAGS += -sv_lib $(DRAMSYS_LIB_PATH)/libsystemc
	VSIM_FLAGS += -sv_lib $(DRAMSYS_LIB_PATH)/libDRAMSys_Simulator
endif

## Build DramSys
dram-build:
	make -BC ${DRAMSYS_DIR} -j8 dramsys CXX=$(CXX) CC=$(CC)


############
# Modelsim #
############
# QuestaSim
QUESTA_VER ?= questa-2023.4-zr
VSIM        = ${QUESTA_VER} vsim
VLOG        = ${QUESTA_VER} vlog
VSIM_HOME   = /usr/pack/${QUESTA_VER}/questasim

# fesvr is being installed here
FESVR          ?= ${SIM_DIR}/work
FESVR_VERSION  ?= c663ea20a53f4316db8cb4d591b1c8e437f4a0c4

VSIM_FLAGS += -sv_lib $(SIM_DIR)/${DPI_LIB}/cachepool_dpi
VSIM_FLAGS += -t 1ps
VSIM_FLAGS += -voptargs=+acc
VSIM_FLAGS += -suppress vsim-3999
VSIM_FLAGS += -do "log -r /*; source ${SIM_DIR}/scripts/vsim_wave.tcl; run -a"

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -override_timescale 1ns/1ps
VLOG_FLAGS += -suppress 2583
VLOG_FLAGS += -suppress 13314
VLOG_FLAGS += -64

ENABLE_CACHEPOOL_TESTS ?= 1

VSIM_BENDER   += -t test -t rtl -t simulation -t spatz -t spatz_test -t snitch_test -t cachepool

define QUESTASIM
	${VSIM} -c -do "source $<; quit" | tee $(dir $<)vsim.log
	@! grep -P "Errors: [1-9]*," $(dir $<)vsim.log
	@mkdir -p bin
	@echo "#!/bin/bash" > $@
	@echo 'echo `realpath $$1` > ${SIMBIN_DIR}/logs/.rtlbinary' >> $@
	@echo '${VSIM} +permissive ${VSIM_FLAGS} -work ${WORK_DIR} -c \
				-ldflags "-Wl,-rpath,${GCC_LIB} -L${FESVR}/lib -lfesvr_vsim -lutil" \
				$1 +permissive-off ++$$1 +PRELOAD=$$1' >> $@
	@chmod +x $@
	@echo "#!/bin/bash" > $@.gui
	@echo 'echo `realpath $$1` > ${SIMBIN_DIR}/logs/.rtlbinary' >> $@
	@echo '${VSIM} +permissive ${VSIM_FLAGS} -work ${WORK_DIR}  \
				-ldflags "-Wl,-rpath,${GCC_LIB} -L${FESVR}/lib -lfesvr_vsim -lutil" \
				$1 +permissive-off ++$$1 +PRELOAD=$$1' >> $@.gui
	@chmod +x $@.gui
endef

## DPI Build
dpi_target := $(patsubst ${DPI_PATH}/%.cpp,${SIM_DIR}/${DPI_LIB}/%.o,$(wildcard ${DPI_PATH}/*.cpp))

.PHONY: dpi
dpi: ${SIM_DIR}/${DPI_LIB}/cachepool_dpi.so

${SIM_DIR}/${DPI_LIB}/%.o: ${DPI_PATH}/%.cpp
	mkdir -p ${SIM_DIR}/${DPI_LIB}
	$(CXX) -shared -fPIC -std=c++11 -Bsymbolic -c $< -I$(VSIM_HOME)/include -o $@

${SIM_DIR}/${DPI_LIB}/cachepool_dpi.so: ${dpi_target}
	mkdir -p ${SIM_DIR}/${DPI_LIB}
	$(CXX) -shared -m64 -o ${SIM_DIR}/${DPI_LIB}/cachepool_dpi.so $^


## Questa Build
${WORK_DIR}/${FESVR_VERSION}_unzip:
	mkdir -p $(dir $@)
	wget -O $(dir $@)/${FESVR_VERSION} https://github.com/riscv/riscv-isa-sim/tarball/${FESVR_VERSION}
	tar xfm $(dir $@)${FESVR_VERSION} --strip-components=1 -C $(dir $@)
	touch $@

${WORK_DIR}/lib/libfesvr_vsim.a: ${WORK_DIR}/${FESVR_VERSION}_unzip
	cd $(dir $<)/ && PATH=${ISA_SIM_INSTALL_DIR}/bin:${PATH} CC=${CC_PATH} CXX=${CXX_PATH} ./configure --prefix `pwd`
	make -C $(dir $<) install-config-hdrs install-hdrs libfesvr.a
	mkdir -p $(dir $@)
	cp $(dir $<)libfesvr.a $@

${WORK_DIR}/compile.vsim.tcl: ${SNLIB_DIR}/rtl_lib.cc ${SNLIB_DIR}/common_lib.cc ${BOOTLIB_DIR}/bootdata.cc ${BOOTLIB_DIR}/bootrom.bin
	vlib $(dir $@)
	${BENDER} script vsim ${VSIM_BENDER} ${DEFS} --vlog-arg="${VLOG_FLAGS} -work $(dir $@) " > $@
	echo '${VLOG} -work $(dir $@) ${SNLIB_DIR}/rtl_lib.cc ${SNLIB_DIR}/common_lib.cc ${BOOTLIB_DIR}/bootdata.cc -ccflags "-std=c++17 -I${BOOTLIB_DIR} -I${WORK_DIR}/include -I${SNLIB_DIR}"' >> $@
	echo '${VLOG} -work $(dir $@) ${BOOTLIB_DIR}/uartdpi/uartdpi.c -ccflags "-I${BOOTLIB_DIR}/uartdpi" -cpppath "${CXX_PATH}"' >> $@
	echo 'return 0' >> $@

${SIMBIN_DIR}/cachepool_cluster.vsim: ${WORK_DIR}/compile.vsim.tcl ${WORK_DIR}/lib/libfesvr_vsim.a
	mkdir -p ${SIMBIN_DIR}/logs
	$(call QUESTASIM,tb_cachepool)

clean.vsim:
	rm -rf ${WORK_DIR}/compile.vsim.tcl ${SIMBIN_DIR}/cachepool_cluster.vsim ${SIMBIN_DIR}/cachepool_cluster.vsim.gui ${SIM_DIR}/work-vsim \
				 ${SIM_DIR}/work-dpi ${WORK_DIR} vsim.wlf vish_stacktrace.vstf transcript modelsim.ini logs *.tdb *.vstf bin

######
# SW #
######

## Delete sw/build
clean.sw:
	rm -rf ${SOFTWARE_DIR}/build

## Build SW into sw/build with the LLVM toolchain
.PHONY: sw
sw: clean.sw
	echo ${SOFTWARE_DIR}
	mkdir -p ${SOFTWARE_DIR}/build
	cd ${SOFTWARE_DIR}/build && ${CMAKE} \
	-DENABLE_CACHEPOOL_TESTS=${ENABLE_CACHEPOOL_TESTS} -DCACHEPOOL_DIR=$(CACHEPOOL_DIR) \
	-DRUNTIME_DIR=${SOFTWARE_DIR} -DSPATZ_SW_DIR=$(SPATZ_SW_DIR) \
	-DLLVM_PATH=${LLVM_INSTALL_DIR} -DGCC_PATH=${GCC_INSTALL_DIR} -DPYTHON=${PYTHON} -DBUILD_TESTS=ON .. && make


.PHONY: vsim
vsim: dpi ${SIMBIN_DIR}/cachepool_cluster.vsim
	echo ${SOFTWARE_DIR}
	mkdir -p ${SOFTWARE_DIR}/build
	cd ${SOFTWARE_DIR}/build && ${CMAKE} \
	-DENABLE_CACHEPOOL_TESTS=${ENABLE_CACHEPOOL_TESTS} -DCACHEPOOL_DIR=$(CACHEPOOL_DIR) \
	-DRUNTIME_DIR=${SOFTWARE_DIR} -DSPATZ_SW_DIR=$(SPATZ_SW_DIR) \
	-DLLVM_PATH=${LLVM_INSTALL_DIR} -DGCC_PATH=${GCC_INSTALL_DIR} -DPYTHON=${PYTHON} \
	-DSNITCH_SIMULATOR=${SIMBIN_DIR}/cachepool_cluster.vsim -DBUILD_TESTS=ON .. && make

.PHONY: clean
clean: clean.sw clean.vsim


############
# SPYGLASS #
############

SNPS_SG ?= spyglass-2024.09

.PHONY: lint ${LINT_PATH}/tmp/files
lint: ${LINT_PATH}/tmp/files ${LINT_PATH}/sdc/func.sdc ${LINT_PATH}/script/lint.tcl
	cd ${LINT_PATH} && $(SNPS_SG) sg_shell -tcl ${LINT_PATH}/script/lint.tcl

${LINT_PATH}/tmp/files: ${BENDER}
	mkdir -p ${LINT_PATH}/tmp
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
	@echo "*toolchain*:  build the necessary toochains, including LLVM and GCC"
	@echo "*quick-tool*: *ETH Member Only* soft link to prebuilt toolchains"
	@echo "*generate*:   generate the Spatz package, bootrom and opcodes"
	@echo "*dram-build*: build DramSys for simulation"
	@echo ""
	@echo "SW Build:"
	@echo ""
	@echo "*clean.sw*:   remove the current software build"
	@echo "*sw*:         generate the latest kernel build (will overwrite the previous build)"
	@echo ""
	@echo "Simulation:"
	@echo ""
	@echo "*clean.vsim*: remove the current hardware build"
	@echo "*vsim*:       build both the software and hardware (will not overwrite the previous build by default"
	@echo "              *USE_DRAMSYS*: set to 1 to use the DRAMSYS system (*1* by default)"
	@echo ""
	@echo "--------------------------------------------------------------------------------------------------------"
	@echo "Settings"
	@echo "*CMAKE*:      CMake version needs to be greater or equal to 3.28 for DRAMSyS"
	@echo ""

