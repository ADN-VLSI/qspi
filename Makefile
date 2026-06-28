export SHELL=/bin/bash

.DEFAULT_GOAL := sim

TOP := rx_packer_tb

ROOT_DIR  := $(CURDIR)
BUILD_DIR := $(ROOT_DIR)/build
LOG_DIR   := $(ROOT_DIR)/log

FILES += $(ROOT_DIR)/source/qspi_pkg.sv

# third party
FILES += $(ROOT_DIR)/third_party/s25fs256s.v

# rest of source, but EXCLUDE the package (already added)
FILES += $(shell find $(ROOT_DIR)/source -name "*.sv")

# testbench
FILES += $(shell find $(ROOT_DIR)/tb -name "*.sv")

EWLH := | grep -iE "error:|warning:|" --color=auto

.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR)
	@echo -e "\033[1;33mCleaned build directory:\033[0m $(BUILD_DIR)"

.PHONY: clean_full
clean_full:
	@make -s clean
	@rm -rf $(LOG_DIR)
	@echo -e "\033[1;33mCleaned log directory:\033[0m $(LOG_DIR)"

$(BUILD_DIR) $(LOG_DIR):
	@mkdir -p $@
	@echo "*" > $@/.gitignore
	@echo -e "\033[1;33mCreated directory:\033[0m $@"

.PHONY: sim
sim:
	@make -s clean
	@make -s $(BUILD_DIR)
	@make -s $(LOG_DIR)
	@echo -e "\033[1;33mStarting simulation for top-level module:\033[0m $(TOP)"
	@cd $(BUILD_DIR) && xvlog -sv -d SPEEDSIM $(FILES) -log $(LOG_DIR)/xvlog_$(shell date +%Y%m%d_%H%M%S).log $(EWLH)
	@cd $(BUILD_DIR) && xelab $(TOP) -debug all -s snap_$(TOP) -log $(LOG_DIR)/xelab_$(TOP)_$(shell date +%Y%m%d_%H%M%S).log $(EWLH)
	@cd $(BUILD_DIR) && xsim snap_$(TOP) -runall -log $(LOG_DIR)/xsim_$(TOP)_$(shell date +%Y%m%d_%H%M%S).log $(EWLH)
