# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# get environment variables
source [file join [file dirname [info script]] yosys_common.tcl]

# constraints file
set abc_constr [file join [file dirname [info script]] ../src/abc.constr]

# ABC script without DFF optimizations
set abc_combinational_script [file join [file dirname [info script]] abc-opt.script]

# process abc file (written to WORK directory)
set abc_comb_script   [processAbcScript $abc_combinational_script]

# read library files
foreach file $lib_list {
	yosys read_liberty -lib "$file"
}

# read design
foreach file $vlog_files {
	yosys read_verilog -sv "$file"
}

# blackbox requested modules
if { [info exists ::env(YOSYS_BLACKBOX_MODULES)] } {
    foreach sel $::env(YOSYS_BLACKBOX_MODULES) {
        puts "Blackboxing the module ${sel}"
        yosys select -list {*}$sel
	    yosys blackbox {*}$sel
        yosys setattr -set keep_hierarchy 1 {*}$sel
    }
}

# preserve hierarchy of selected modules/instances
if { [info exists ::env(YOSYS_KEEP_HIER_INST)] } {
    foreach sel $::env(YOSYS_KEEP_HIER_INST) {
        puts "Keeping hierarchy of selection: $sel"
        yosys select -list {*}$sel
        yosys setattr -set keep_hierarchy 1 {*}$sel
    }
}

# map dont_touch attribute commonly applied to output-nets of async regs to keep
yosys attrmap -rename dont_touch keep
# copy the keep attribute to their driving cells (retain on net for debugging)
yosys attrmvcp -copy -attr keep


# -----------------------------------------------------------------------------
# this section heavily borrows from the yosys synth command:
# synth - check
yosys hierarchy -check -top $top_design
yosys proc
yosys tee -q -o "${report_dir}/${proj_name}_initial.rpt" stat

# synth - coarse:
# yosys synth -run coarse -noalumacc
yosys opt_expr
yosys opt_clean
yosys check
yosys opt -noff
yosys fsm
yosys opt
yosys tee -q -o "${report_dir}/${proj_name}_initial_opt.rpt" stat
yosys wreduce 
yosys peepopt
yosys opt_clean
yosys opt -full
yosys booth
yosys alumacc
yosys share
yosys opt
yosys memory
yosys opt -fast

yosys opt_dff -sat -nodffe -nosdff
yosys share
yosys opt -full
yosys clean -purge

yosys write_verilog -norename ${work_dir}/${proj_name}_abstract.yosys.v
yosys tee -q -o "${report_dir}/${proj_name}_abstract.rpt" stat -tech cmos

yosys techmap
yosys opt -fast
yosys clean -purge


# -----------------------------------------------------------------------------
yosys tee -q -o "${report_dir}/${proj_name}_generic.rpt" stat -tech cmos
yosys tee -q -o "${report_dir}/${proj_name}_generic.json" stat -json -tech cmos

if {[envVarValid "YOSYS_FLATTEN_HIER"]} {
	yosys flatten
}

yosys clean -purge


# -----------------------------------------------------------------------------
# rename DFFs from the driven signal
yosys rename -wire -suffix _reg t:*DFF*
yosys select -write ${report_dir}/${proj_name}_registers.rpt t:*DFF*
# rename all other cells
yosys autoname t:*DFF* %n
yosys clean -purge

# print paths to important instances
yosys select -write ${report_dir}/${proj_name}_registers.rpt t:*DFF*
set report [open ${report_dir}/${proj_name}_instances.rpt "w"]
close $report
if { [info exists ::env(YOSYS_REPORT_INSTS)] } {
    foreach sel $::env(YOSYS_REPORT_INSTS) {
        yosys tee -q -a ${report_dir}/${proj_name}_instances.rpt  select -list {*}$sel
    }
}

yosys tee -q -o "${report_dir}/${proj_name}_pre_tech.rpt" stat -tech cmos
yosys tee -q -o "${report_dir}/${proj_name}_pre_tech.json" stat -json -tech cmos


# -----------------------------------------------------------------------------
# mapping to technology

puts "Using combinational-only abc optimizations"
yosys dfflibmap -liberty "$tech_cells"
yosys abc -liberty "$tech_cells" -D $period_ps -script $abc_comb_script -constr $abc_constr -showtmp

yosys clean -purge


# -----------------------------------------------------------------------------
# prep for openROAD
yosys write_verilog -norename -noexpr -attr2comment ${build_dir}/${proj_name}_yosys_debug.v

yosys splitnets -ports -format __v
yosys setundef -zero
yosys clean -purge

yosys hilomap -singleton -hicell {*}[split ${tech_tiehi} " "] -locell {*}[split ${tech_tielo} " "]

# final reports
yosys tee -q -o "${report_dir}/${proj_name}_synth.rpt" check
yosys tee -q -o "${report_dir}/${proj_name}_area.rpt" stat -top $top_design {*}$liberty_args
yosys tee -q -o "${report_dir}/${proj_name}_area_logic.rpt" stat -top $top_design -liberty "$tech_cells"

# final netlist
yosys write_verilog -noattr -noexpr -nohex -nodec $netlist

