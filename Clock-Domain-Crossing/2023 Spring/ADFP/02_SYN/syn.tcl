#======================================================
# Synopsys Design Compiler Synthesis Scripts 
#======================================================

#======================================================
# Set ADFP Library Path
#======================================================
set search_path    "/usr/cad/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/CCS/ \
                    /usr/cad/ADFP/Executable_Package/Collaterals/IP/stdio/N16ADFP_StdIO/NLDM/ \
                    /usr/cad/ADFP/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/NLDM/ \
                    $search_path .\
                    "

set target_library "N16ADFP_StdCellff0p88v125c_ccs.db \
                    N16ADFP_StdCellff0p88vm40c_ccs.db \
                    N16ADFP_StdCellss0p72v125c_ccs.db \
                    N16ADFP_StdCellss0p72vm40c_ccs.db \
                    N16ADFP_StdCelltt0p8v25c_ccs.db \
                    N16ADFP_StdIOff0p88v1p98v125c.db \
                    N16ADFP_StdIOff0p88v1p98vm40c.db \
                    N16ADFP_StdIOss0p72v1p62v125c.db \
                    N16ADFP_StdIOss0p72v1p62vm40c.db \
                    N16ADFP_StdIOtt0p8v1p8v25c.db \
                    N16ADFP_SRAM_ff0p88v0p88v125c_100a.db \
                    N16ADFP_SRAM_ff0p88v0p88vm40c_100a.db \
                    N16ADFP_SRAM_ss0p72v0p72v125c_100a.db \
                    N16ADFP_SRAM_ss0p72v0p72vm40c_100a.db \
                    N16ADFP_SRAM_tt0p8v0p8v25c_100a.db \
                    "

set link_library "* $target_library dw_foundation.sldb"
set symbol_library "generic.sdb"
set synthetic_library "dw_foundation.sldb"

#======================================================
# Create File Path && Global Setting
#======================================================
set DESIGN "CDC"

sh mkdir -p Netlist
sh mkdir -p Report
sh mkdir -p Work 

define_design_lib $DESIGN -path Work

# Save the templates module (parameterized) 
set hdlin_auto_save_templates true
# Check for latch
set hdlin_check_no_latch true 
# Avoid the tri-state and replace with wire
set verilogout_no_tri true
# Enable line editing in the shell
set sh_enable_line_editing true
# Save the history of the shell
history keep 1000
alias h history
# Stop program on error
set sh_continue_on_error false
# Preserve the subdesign interfaces
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
# Instance Independent
uniquify
# Fix the multiple port nets (Insert Buffer)
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

# Compile the subdesign
current_design sync_r2w
compile
set_dont_touch sync_r2w

current_design sync_w2r
compile
set_dont_touch sync_w2r

# Compile the main design
current_design $DESIGN
compile_ultra

#======================================================
#  Report & Output
#======================================================
current_design $DESIGN
report_timing > Report/${DESIGN}_syn.timing
report_area   > Report/${DESIGN}_syn.area

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
# write_sdf -version 3.0 -context verilog ./Netlist/${DESIGN}_SYN.sdf
write_sdc ./Netlist/${DESIGN}_SYN.sdc -version 1.8

report_timing
report_area

foreach_in_collection x [get_cell */wq1_rptr_reg*] {
  set_annotated_check -0 -setup -from [get_object_name $x]/CP -to [get_object_name $x]/D -clock rise
  set_annotated_check -0 -hold  -from [get_object_name $x]/CP -to [get_object_name $x]/D -clock rise
}

foreach_in_collection x [get_cell */rq1_wptr_reg*] {
  set_annotated_check -0 -setup -from [get_object_name $x]/CP -to [get_object_name $x]/D -clock rise
  set_annotated_check -0 -hold  -from [get_object_name $x]/CP -to [get_object_name $x]/D -clock rise
}

write_sdf -version 3.0 -context verilog ./Netlist/${DESIGN}_SYN_pt.sdf

check_timing
