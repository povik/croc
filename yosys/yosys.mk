# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# Tools
YOSYS    ?= yosys

# Directories
# directory of the path to the last called Makefile (this one)
YOSYS_DIR 		:= $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
YOSYS_OUT		:= $(YOSYS_DIR)/out
YOSYS_WORK		:= $(YOSYS_DIR)/WORK
YOSYS_REPORTS	:= $(YOSYS_DIR)/reports

# Project variables
include $(TECH_DIR)/technology.mk
include $(YOSYS_DIR)/project-synth.mk

TOP_DESIGN		?= croc_chip
RTL_NAME		?= croc

PICKLE_OUT		:= $(YOSYS_DIR)/../pickle

VLOG_FILES  	:= $(PICKLE_OUT)/$(RTL_NAME)_sv2v.v
NETLIST			:= $(YOSYS_OUT)/$(RTL_NAME)_yosys.v
NETLIST_DEBUG	:= $(YOSYS_OUT)/$(RTL_NAME)_debug_yosys.v

## Synthesize netlist using Yosys
yosys: $(NETLIST)

synth: $(NETLIST)

$(NETLIST) $(NETLIST_DEBUG): $(VLOG_FILES)
	@mkdir -p $(YOSYS_OUT)
	@mkdir -p $(YOSYS_WORK)
	@mkdir -p $(YOSYS_REPORTS)
	VLOG_FILES="$(VLOG_FILES)" \
	TOP_DESIGN="$(TOP_DESIGN)" \
	PROJ_NAME="$(RTL_NAME)" \
	WORK="$(YOSYS_WORK)" \
	BUILD="$(YOSYS_OUT)" \
	REPORTS="$(YOSYS_REPORTS)" \
	NETLIST="$(NETLIST)" \
	$(YOSYS) -c $(YOSYS_DIR)/scripts/yosys_synthesis.tcl \
		2>&1 | TZ=UTC gawk '{ print strftime("[%Y-%m-%d %H:%M %Z]"), $$0 }' \
		| tee "$(YOSYS_DIR)/$(RTL_NAME).log" \
		| grep -E "\[.*\] [0-9\.]+ Executing";

clean:
	rm -rf $(YOSYS_OUT)
	rm -rf $(YOSYS_WORK)
	rm -rf $(YOSYS_REPORTS) 
	rm -f $(YOSYS_OUT_DIR)/*.log

.PHONY: clean yosys synth
