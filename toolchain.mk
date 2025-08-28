# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich

###############
# toolchain.mk
###############
# Owns: toolchain download/build/install targets and their paths.
# Assumes these are already defined by the including Makefile:
#   - CACHEPOOL_DIR
#   - SOFTWARE_DIR
#   - CMAKE (>= 3.28)
# Exports (for the main Makefile and CMake):
#   - INSTALL_DIR, GCC_INSTALL_DIR, LLVM_INSTALL_DIR, ISA_SIM_INSTALL_DIR, BENDER_INSTALL_DIR

# ---------- Directories ----------
TOOLCHAIN_DIR         ?= ${SOFTWARE_DIR}/toolchain
INSTALL_PREFIX        ?= install
INSTALL_DIR           ?= ${CACHEPOOL_DIR}/${INSTALL_PREFIX}

# Tool installs (exported)
GCC_INSTALL_DIR       ?= ${INSTALL_DIR}/riscv-gcc
LLVM_INSTALL_DIR      ?= ${INSTALL_DIR}/llvm
ISA_SIM_INSTALL_DIR   ?= ${INSTALL_DIR}/riscv-isa-sim
BENDER_INSTALL_DIR    ?= ${INSTALL_DIR}/bender

# Optional helpers
RISCV_TESTS_DIR       ?= ${SOFTWARE_DIR}/riscv-tests

# ---------- Fetch sources ----------
.PHONY: toolchain download
toolchain: download tc-llvm tc-riscv-gcc

download: ${TOOLCHAIN_DIR}/riscv-gnu-toolchain \
          ${TOOLCHAIN_DIR}/llvm-project \
          ${TOOLCHAIN_DIR}/riscv-opcodes \
          ${TOOLCHAIN_DIR}/riscv-isa-sim \
          ${TOOLCHAIN_DIR}/dtc

${TOOLCHAIN_DIR}/riscv-gnu-toolchain: ${TOOLCHAIN_DIR}/riscv-gnu-toolchain.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/pulp-platform/pulp-riscv-gnu-toolchain.git riscv-gnu-toolchain
	cd ${TOOLCHAIN_DIR}/riscv-gnu-toolchain && \
	  git checkout `cat ../riscv-gnu-toolchain.version` && \
	  git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/llvm-project: ${TOOLCHAIN_DIR}/llvm-project.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/mp-17/llvm-project.git
	cd ${TOOLCHAIN_DIR}/llvm-project && \
	  git checkout `cat ../llvm-project.version` && \
	  git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/riscv-opcodes: ${TOOLCHAIN_DIR}/riscv-opcodes.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/mp-17/riscv-opcodes.git
	cd ${TOOLCHAIN_DIR}/riscv-opcodes && \
	  git checkout `cat ../riscv-opcodes.version` && \
	  git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/riscv-isa-sim: ${TOOLCHAIN_DIR}/riscv-isa-sim.version
	mkdir -p ${TOOLCHAIN_DIR}
	cd ${TOOLCHAIN_DIR} && git clone https://github.com/riscv-software-src/riscv-isa-sim.git
	cd ${TOOLCHAIN_DIR}/riscv-isa-sim && \
	  git checkout `cat ../riscv-isa-sim.version` && \
	  git submodule update --init --recursive --jobs=8 .

${TOOLCHAIN_DIR}/dtc:
	mkdir -p ${TOOLCHAIN_DIR}/dtc
	cd ${TOOLCHAIN_DIR}/dtc && wget -c https://git.kernel.org/pub/scm/utils/dtc/dtc.git/snapshot/dtc-1.7.0.tar.gz
	cd ${TOOLCHAIN_DIR}/dtc && tar xf dtc-1.7.0.tar.gz

# ---------- Build toolchains ----------
.PHONY: tc-riscv-gcc tc-llvm tc-riscv-isa-sim

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
	    -DLLVM_OPTIMIZED_TABLEGEN=True \
	    -DLLVM_ENABLE_PROJECTS="clang;lld" \
	    -DLLVM_TARGETS_TO_BUILD="RISCV" \
	    -DLLVM_DEFAULT_TARGET_TRIPLE=riscv32-unknown-elf \
	    -DLLVM_ENABLE_LLD=False \
	    -DLLVM_APPEND_VC_REV=ON \
	    -DCMAKE_BUILD_TYPE=Release \
	    ../llvm && \
	  $(MAKE) -j8 all && \
	  $(MAKE) install

tc-riscv-isa-sim: ${TOOLCHAIN_DIR}/riscv-isa-sim ${TOOLCHAIN_DIR}/dtc
	mkdir -p $(ISA_SIM_INSTALL_DIR)
	$(MAKE) -C ${TOOLCHAIN_DIR}/dtc/dtc-1.7.0 -j install PREFIX=$(ISA_SIM_INSTALL_DIR)
	cd ${TOOLCHAIN_DIR}/riscv-isa-sim && rm -rf build && mkdir -p build && cd build && \
	  PATH=$(ISA_SIM_INSTALL_DIR)/bin:$(PATH) ../configure --prefix=$(ISA_SIM_INSTALL_DIR) && \
	  $(MAKE) MAKEINFO=true -j4 install

# ---------- Bender installer ----------
# This installs bender; project usage is defined in the main Makefile.
BENDER_VERSION ?= 0.28.1
.PHONY: bender
bender: $(BENDER_INSTALL_DIR)/bender

$(BENDER_INSTALL_DIR)/bender:
	mkdir -p $(BENDER_INSTALL_DIR) && cd $(BENDER_INSTALL_DIR) && \
	  curl --proto '=https' --tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- $(BENDER_VERSION)

# ---------- Opcodes convenience (optional) ----------
OPCODES ?=
.PHONY: update_opcodes clean-opcodes
clean-opcodes:
	rm -rf ${TOOLCHAIN_DIR}/riscv-opcodes

update_opcodes: clean-opcodes ${TOOLCHAIN_DIR}/riscv-opcodes
	@echo "Opcodes repo is ready: ${TOOLCHAIN_DIR}/riscv-opcodes"
