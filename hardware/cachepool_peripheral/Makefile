# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Noah Huetter <huettern@iis.ee.ethz.ch>

ROOTDIR=../..
REGTOOL=`$(ROOTDIR)/install/bender/bender path register_interface`/vendor/lowrisc_opentitan/util/regtool.py
PYTHON3=$(shell which python)
CLANG_FORMAT=$(shell which clang-format-10.0.1)

SCHEMA=cachepool_peripheral_reg.hjson

PKG=cachepool_peripheral_reg_pkg.sv
TOP=cachepool_peripheral_reg_top.sv
CDEF=$(ROOTDIR)/software/snRuntime/include/cachepool_peripheral.h

# Number of per-core LP1 (private-L1) CMO register slots.  MUST be >= the total
# core count of the target config, or cores with cid >= this value spin forever
# on LP1_CMO_STATUS (their slot is never decoded) -> cluster barrier deadlock.
# The top-level `make update-periph-reg` overrides this with the current
# config's num_cores; the default here is a safe max (256 = full 16g) for a
# standalone `make -C hardware/cachepool_peripheral`.
NUM_LP1_CMO_REGS ?= 256
REGGEN_PARAMS := -p NumLp1CmoRegs=$(NUM_LP1_CMO_REGS)

all: $(PKG) $(TOP) $(CDEF)

$(PKG): $(SCHEMA)
	$(PYTHON3) $(REGTOOL) $(REGGEN_PARAMS) -r -t $(dir $@) $<
$(TOP): $(SCHEMA)
	$(PYTHON3) $(REGTOOL) $(REGGEN_PARAMS) -r -t $(dir $@) $<

%.h: $(SCHEMA)
	$(PYTHON3) $(REGTOOL) $(REGGEN_PARAMS) -D -o $@ $<
	$(CLANG_FORMAT) -i $@
