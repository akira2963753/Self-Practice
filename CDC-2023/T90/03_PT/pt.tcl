# specify parameters
set DESIGN "CDC"

#Step 1 Read in the design data, which includes a gate-level netlist and associated logic libraries.
set search_path "../02_SYN/Netlist /usr/cad/CBDK_TSMC90G_Arm_v1.1/Lib90 $search_path"

# Use the slow (ss) corner for worst-case setup STA
set link_path "* slow.db"

# Read Design
read_verilog ${DESIGN}_SYN.v
current_design $DESIGN
link_design $DESIGN

read_sdc ../02_SYN/Netlist/${DESIGN}_SYN.sdc

#Step 6 Specify case and mode analysis settings.
#Step 7 Back-annotate delay and parasitics.
read_sdf ../02_SYN/Netlist/${DESIGN}_SYN.sdf

# set_annotated_check 
foreach_in_collection x [get_cells -hierarchical *wq1_rptr_reg*] {
  set_annotated_check 0 -setup -from [get_object_name $x]/CK -to [get_object_name $x]/D -clock rise
  set_annotated_check 0 -hold  -from [get_object_name $x]/CK -to [get_object_name $x]/D -clock rise
}

foreach_in_collection x [get_cells -hierarchical *rq1_wptr_reg*] {
  set_annotated_check 0 -setup -from [get_object_name $x]/CK -to [get_object_name $x]/D -clock rise
  set_annotated_check 0 -hold  -from [get_object_name $x]/CK -to [get_object_name $x]/D -clock rise
}

write_sdf ${DESIGN}_SYN_pt.sdf
#Step 8 (Optional) Apply variation.
#Step 9 Specify power information
#Step 10 (Optional) Specify options and data for signal integrity analysis.
#Step 11 (Optional) Apply options for specific design techniques.
#Step 12 Check the design data and analysis setup.
check_timing

#Step 13 Perform a full timing analysis and examine the results.
report_timing

#Step 14 (Optional) Perform ECO to fix timing violations and recover power.
#Step 15 Save the PrimeTime session.
#save_session