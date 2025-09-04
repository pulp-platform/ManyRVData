# Copyright 2025 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Diyou Shen, ETH Zurich


SIM_DIR        ?= $(CACHEPOOL_DIR)/sim
WORK_DIR       ?= $(SIM_DIR)/work
SIMBIN_DIR     ?= $(SIM_DIR)/bin
DPI_PATH       ?= $(CACHEPOOL_DIR)/hardware/tb/dpi
DPI_LIB        ?= work-dpi
TOP            ?= tb_cachepool
VLT_TOP        ?= $(TOP)

# ----------------
# Questa toolpaths
# ----------------
QUESTA_VER ?= questa-2023.4-zr
VSIM        = ${QUESTA_VER} vsim
VLOG        = ${QUESTA_VER} vlog
VSIM_HOME   = /usr/pack/${QUESTA_VER}/questasim

# -----------
# VSIM flags
# -----------
VSIM_FLAGS += -sv_lib $(SIM_DIR)/${DPI_LIB}/cachepool_dpi
VSIM_FLAGS += -t 1ps
VSIM_FLAGS += -voptargs=+acc
VSIM_FLAGS += -suppress vsim-3999

VLOG_FLAGS += -svinputport=compat
VLOG_FLAGS += -override_timescale 1ns/1ps
VLOG_FLAGS += -suppress 2583
VLOG_FLAGS += -suppress 13314
VLOG_FLAGS += -64

# Optional DRAMSys hookup (kept here since it's sim-only)
USE_DRAMSYS ?= 1
ifeq ($(USE_DRAMSYS),1)
  VSIM_BENDER += -t DRAMSYS
  VSIM_FLAGS  += +DRAMSYS_RES=$(DRAMSYS_RES_PATH)
  VSIM_FLAGS  += -sv_lib $(DRAMSYS_LIB_PATH)/libsystemc
  VSIM_FLAGS  += -sv_lib $(DRAMSYS_LIB_PATH)/libDRAMSys_Simulator
endif

# ----------
# FESVR shim
# ----------
FESVR         ?= ${SIM_DIR}/work
FESVR_VERSION ?= c663ea20a53f4316db8cb4d591b1c8e437f4a0c4

# -------------
# DPI build
# -------------
dpi_target := $(patsubst ${DPI_PATH}/%.cpp,${SIM_DIR}/${DPI_LIB}/%.o,$(wildcard ${DPI_PATH}/*.cpp))

.PHONY: dpi
dpi: ${SIM_DIR}/${DPI_LIB}/cachepool_dpi.so

${SIM_DIR}/${DPI_LIB}/%.o: ${DPI_PATH}/%.cpp
	mkdir -p ${SIM_DIR}/${DPI_LIB}
	$(CXX) -shared -fPIC -std=c++11 -Bsymbolic -c $< -I$(VSIM_HOME)/include -o $@

${SIM_DIR}/${DPI_LIB}/cachepool_dpi.so: ${dpi_target}
	mkdir -p ${SIM_DIR}/${DPI_LIB}
	$(CXX) -shared -m64 -o ${SIM_DIR}/${DPI_LIB}/cachepool_dpi.so $^

# -----------------
# Build testbench
# -----------------
${WORK_DIR}/${FESVR_VERSION}_unzip:
	mkdir -p $(dir $@)
	wget -O $(dir $@)/${FESVR_VERSION} https://github.com/riscv/riscv-isa-sim/tarball/${FESVR_VERSION}
	tar xfm $(dir $@)${FESVR_VERSION} --strip-components=1 -C $(dir $@)
	touch $@

${WORK_DIR}/lib/libfesvr_vsim.a: ${WORK_DIR}/${FESVR_VERSION}_unzip
	cd $(dir $<)/ && PATH=${ISA_SIM_INSTALL_DIR}/bin:${PATH} CC=${CC_PATH} CXX=${CXX_PATH} ./configure --prefix `pwd`
	$(MAKE) -C $(dir $<) install-config-hdrs install-hdrs libfesvr.a
	mkdir -p $(dir $@)
	cp $(dir $<)libfesvr.a $@

${WORK_DIR}/compile.vsim.tcl: ${SNLIB_DIR}/rtl_lib.cc ${SNLIB_DIR}/common_lib.cc ${BOOTLIB_DIR}/bootdata.cc ${BOOTLIB_DIR}/bootrom.bin
	vlib $(dir $@)
	${BENDER} script vsim ${VSIM_BENDER} --vlog-arg="${VLOG_FLAGS} -work $(dir $@)" ${VLOG_DEFS} > $@
	echo '${VLOG} -work $(dir $@) ${SNLIB_DIR}/rtl_lib.cc ${SNLIB_DIR}/common_lib.cc ${BOOTLIB_DIR}/bootdata.cc -ccflags "-std=c++17 -I${BOOTLIB_DIR} -I${WORK_DIR}/include -I${SNLIB_DIR}"' >> $@
	echo '${VLOG} -work $(dir $@) ${BOOTLIB_DIR}/uartdpi/uartdpi.c -ccflags "-I${BOOTLIB_DIR}/uartdpi" -cpppath "${CXX_PATH}"' >> $@
	echo 'return 0' >> $@

# Wrapper script & GUI script
define QUESTASIM
	${VSIM} -c -do "source $<; quit" | tee $(dir $<)vsim.log
	@! grep -P "Errors: [1-9]*," $(dir $<)vsim.log
	@mkdir -p $(SIMBIN_DIR) $(SIMBIN_DIR)/logs
	@echo "#!/bin/bash" > $(SIMBIN_DIR)/cachepool_cluster.vsim
	@echo 'echo `realpath $$1` > ${SIMBIN_DIR}/logs/.rtlbinary' >> $(SIMBIN_DIR)/cachepool_cluster.vsim
	@echo '${VSIM} +permissive ${VSIM_FLAGS} -do "run -a" -work ${WORK_DIR} -c -ldflags "-Wl,-rpath,${GCC_LIB} -L${FESVR}/lib -lfesvr_vsim -lutil" $1 +permissive-off ++$$1 +PRELOAD=$$1' >> $(SIMBIN_DIR)/cachepool_cluster.vsim
	@chmod +x $(SIMBIN_DIR)/cachepool_cluster.vsim
	@echo "#!/bin/bash" > $(SIMBIN_DIR)/cachepool_cluster.vsim.gui
	@echo 'echo `realpath $$1` > ${SIMBIN_DIR}/logs/.rtlbinary' >> $(SIMBIN_DIR)/cachepool_cluster.vsim.gui
	@echo '${VSIM} +permissive ${VSIM_FLAGS} -do "log -r /*; source ${SIM_DIR}/scripts/vsim_wave.tcl; run -a" -work ${WORK_DIR} -ldflags "-Wl,-rpath,${GCC_LIB} -L${FESVR}/lib -lfesvr_vsim -lutil" $1 +permissive-off ++$$1 +PRELOAD=$$1' >> $(SIMBIN_DIR)/cachepool_cluster.vsim.gui
	@chmod +x $(SIMBIN_DIR)/cachepool_cluster.vsim.gui
endef

${SIMBIN_DIR}/cachepool_cluster.vsim: ${WORK_DIR}/compile.vsim.tcl ${WORK_DIR}/lib/libfesvr_vsim.a
	$(call QUESTASIM,$(TOP))

.PHONY: vsim
vsim: dpi ${SIMBIN_DIR}/cachepool_cluster.vsim

.PHONY: clean.vsim
clean.vsim:
	rm -rf ${WORK_DIR}/compile.vsim.tcl ${SIMBIN_DIR}/cachepool_cluster.vsim ${SIMBIN_DIR}/cachepool_cluster.vsim.gui ${SIM_DIR}/work-vsim \
	       ${SIM_DIR}/work-dpi ${WORK_DIR} vsim.wlf vish_stacktrace.vstf transcript modelsim.ini logs *.tdb *.vstf bin

