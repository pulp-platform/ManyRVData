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

all: $(PKG) $(TOP) $(CDEF)

$(PKG): $(SCHEMA)
	$(PYTHON3) $(REGTOOL) -r -t $(dir $@) $<
$(TOP): $(SCHEMA)
	$(PYTHON3) $(REGTOOL) -r -t $(dir $@) $<

%.h: $(SCHEMA)
	$(PYTHON3) $(REGTOOL) -D -o $@ $<
	$(CLANG_FORMAT) -i $@
