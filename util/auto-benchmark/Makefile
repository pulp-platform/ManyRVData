# ===============================
# Simple CachePool batch runner
# ===============================
# Usage:
#   make run-all
#   make run-all CONFIGS="cachepool_fpu_512 cachepool_fpu_256" KERNELS="DOTP FFT"
#   make run-one CONFIG=cachepool_fpu_512 KERNEL=DOTP
#
# It runs:
#   make clean generate vsim config=<CONFIG>
#   ./sim/bin/cachepool_cluster.vsim ./software/build/CachePoolTests/<KERNEL>
#
# Logs go to logs/<timestamp>/<config>/<kernel>.log

# -------- User-defined lists --------
CONFIGS ?= cachepool_fpu_512 cachepool_fpu_256 cachepool_fpu_128
KERNELS ?= DOTP FFT MATMUL  # or pass via command line

# -------- Internal paths --------
ROOT_PATH := ../..
SIM_CMD  	:= $(ROOT_PATH)/sim/bin/cachepool_cluster.vsim
SW_PATH  	:= $(ROOT_PATH)/software/build/CachePoolTests
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
LOG_DIR		:= logs/$(TIMESTAMP)

# -----------------------------------
.PHONY: run-all run-one build-% run-%-% clean

# Build hardware+software for a config
build-%:
	@echo "==== Building for $* ===="
	@make -c $(ROOT_PATH) clean generate vsim config=$*

# Run one kernel on one config (assumes built)
run-%-%:
	@mkdir -p $(LOG_DIR)/$*
	@echo "==== Running: config=$* kernel=$** ===="
	@$(SIM_CMD) $(SW_PATH)/$** | tee $(LOG_DIR)/$*/$**.log

# Run all configs/kernels
run-all:
	@mkdir -p $(LOG_DIR)
	@for cfg in $(CONFIGS); do \
		echo "==== Building $$cfg ===="; \
		make --c $(ROOT_PATH)  s clean generate vsim config=$$cfg; \
		for k in $(KERNELS); do \
			echo "---- Running $$cfg / $$k ----"; \
			mkdir -p $(LOG_DIR); \
			mkdir -p $(LOG_DIR)/$$cfg; \
			$(SIM_CMD) $(SW_PATH)/$$k | tee $(LOG_DIR)/$$cfg/$$k.log; \
		done; \
	done
	@ln -sfn "$(abspath $(LOG_DIR))" logs/latest
	@echo "Logs saved under $(LOG_DIR) (also linked as logs/latest)"

# Run just one kernel/config pair
run-one:
	@[ -n "$(CONFIG)" ] || (echo "Missing CONFIG"; exit 1)
	@[ -n "$(KERNEL)" ] || (echo "Missing KERNEL"; exit 1)
	@make -c $(ROOT_PATH) -s clean generate vsim config=$(CONFIG)
	@mkdir -p $(LOG_DIR)
	@mkdir -p $(LOG_DIR)/$(CONFIG)
	@$(SIM_CMD) $(SW_PATH)/$(KERNEL) | tee $(LOG_DIR)/$(CONFIG)/$(KERNEL).log

clean:
	@rm -rf logs/latest
	@echo "Cleaned logs symlink"
	@rm -rf *.tdb *.ini transcript sim
	@echo "Cleaned simulation tmp files"

clean-all: clean
	@rm -rf logs/*
	@echo "Cleaned all logs"
