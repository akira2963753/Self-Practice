#======================================================
# Synopsys Design Compiler Synthesis Scripts
#======================================================
# Author : Marco
#======================================================
# Set 90 nm Library Path
#======================================================
set search_path       "/usr/cad/CBDK_TSMC90G_Arm_v1.1/Lib90 $search_path"
set target_library    "slow.db fast.db typical.db tpzn90gv3bc.db tpzn90gv3wc.db"
set link_library      "* $target_library dw_foundation.sldb"
set symbol_library    "tsmc090.sdb"
set synthetic_library "dw_foundation.sldb"

#======================================================
# Create File Path && Global Setting
#======================================================
set DESIGN "CDC"

sh mkdir -p Netlist
sh mkdir -p Report
sh mkdir -p Work 

define_design_lib $DESIGN -path Work

set hdlin_auto_save_templates true
set hdlin_check_no_latch true 
set verilogout_no_tri true
set sh_enable_line_editing true
history keep 1000
alias h history
set sh_continue_on_error false
set compile_preserve_subdesign_interfaces true

#======================================================
#  Import Design
#======================================================

analyze -f sverilog -vcs "-f file.f"
elaborate $DESIGN
current_design $DESIGN

#======================================================
#  Set Clock
#======================================================
set CYCLE1 15.5
set CYCLE2 18.3
set C1_DLY  [expr 0.5*$CYCLE1]
set C2_DLY [expr 0.5*$CYCLE2]

create_clock -name clk1 -period $CYCLE1 [get_ports clk1]
create_clock -name clk2 -period $CYCLE2 [get_ports clk2]

set_dont_touch [all_clocks]
set_ideal_network [all_clocks]

set_input_delay $C1_DLY -clock clk1 [all_inputs]
set_output_delay $C1_DLY -clock clk1 [get_ports ready]
set_output_delay $C2_DLY -clock clk2 [get_ports out]
set_output_delay $C2_DLY -clock clk2 [get_ports out_valid]

set_input_delay 0 -clock clk1 clk1
set_input_delay 0 -clock clk2 clk2
set_input_delay 0 -clock clk1 rst_n 
set_input_delay 0 -clock clk2 rst_n

set_load 0.05 [get_ports ready]
set_load 20 [get_ports out]
set_load 20 [get_ports out_valid]

# False Path
set_false_path -from [get_clocks clk1] -to [get_clocks clk2]
set_false_path -from [get_clocks clk2] -to [get_clocks clk1]

#======================================================
#  Compile & Optimization
#======================================================
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

current_design sync_r2w
compile
set_dont_touch sync_r2w

current_design sync_w2r
compile
set_dont_touch sync_w2r

current_design $DESIGN
compile_ultra -inc

#======================================================
#  Report & Output
#======================================================
current_design $DESIGN
report_timing > Report/${DESIGN}_syn.timing
report_area > Report/${DESIGN}_syn.area

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true

change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

remove_unconnected_ports -blast_buses [get_cells -hierarchical *]
set verilogout_higher_designs_first true
write -format ddc      -hierarchy -output "./Netlist/${DESIGN}.ddc"
write -format verilog  -hierarchy -output "./Netlist/${DESIGN}_SYN.v"
write_sdf ./Netlist/${DESIGN}_SYN.sdf
write_sdc ./Netlist/${DESIGN}_SYN.sdc

report_timing
report_area
