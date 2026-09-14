#!/bin/bash
# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Sources the environment needed for the CachePool build on the ETH IIS CI runners.
# Replaces `make quick-tool`'s symlink: GCC_INSTALL_DIR/LLVM_INSTALL_DIR/BENDER_INSTALL_DIR/
# ISA_SIM_INSTALL_DIR are derived from INSTALL_DIR via `?=` in toolchain.mk, so exporting
# INSTALL_DIR here is sufficient - no PATH changes needed, the runner already provides
# bender/clang/cmake/python/pip/gcc on PATH.

export INSTALL_DIR=/home/dishen/cachepool-32b/install

# Python deps for hardware code generation (make generate) - venv instead of uv,
# to match the existing local dev flow.
# python3.12 (not the default python3) is required: floogen needs Python >=3.10.
PYTHON=python3.12
export PYTHON
$PYTHON -m venv cachepool
source cachepool/bin/activate
python3 -m pip install --quiet --upgrade pip
python3 -m pip install --quiet -r requirements.txt

# floogen (FlooNoC code generator) is pulled in via bender, not requirements.txt -
# install it editable into this venv so `floogen` on PATH resolves here.
make install-floogen PYTHON=python3 --no-print-directory
