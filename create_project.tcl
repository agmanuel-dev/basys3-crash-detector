set root [file dirname [file normalize [info script]]]
create_project crash_detector [file join $root build vivado] -part xc7a35tcpg236-1 -force
add_files [list [file join $root top.v] [file join $root adxl345_spi.v] [file join $root ClkDiv_5Hz.v] [file join $root display_ctrl.v] [file join $root oled_controller_full.v] [file join $root spi_master_oled.v]]
add_files -fileset constrs_1 [file join $root Basys3.xdc]
set_property top top [current_fileset]
update_compile_order -fileset sources_1
