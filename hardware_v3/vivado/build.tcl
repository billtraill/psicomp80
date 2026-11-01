# Build the COMP80 v3 bitstream and its flash image with Vivado, in non-project
# mode.  From this folder:
#
#   vivado -mode batch -source build.tcl
#
# Needs ../build (sh ../tools/fetch.sh) and ../firmware/firmware.hex (make -C
# ../firmware).  Writes out/comp80v3.bit, out/comp80v3.mcs and the reports.
set part xc7a100tfgg484-1
set here [file dirname [file normalize [info script]]]
set root [file normalize $here/..]
file mkdir $here/out
cd $here/out

# the memory images $readmemh loads, where synthesis looks for them
file copy -force $root/rtl/font.hex font.hex
file copy -force $root/firmware/firmware.hex firmware.hex
file copy -force $root/build/usb_hid_host/src/usb_hid_host_rom.hex usb_hid_host_rom.hex

read_verilog [list \
    $root/rtl/top.v $root/rtl/comp80_machine.v $root/rtl/tv80c.v $root/rtl/video.v \
    $root/rtl/hdmi_out.v $root/rtl/soc.v $root/rtl/spi_master.v \
    $root/build/tv80/rtl/core/tv80_core.v $root/build/tv80/rtl/core/tv80_alu.v \
    $root/build/tv80/rtl/core/tv80_mcode.v $root/build/tv80/rtl/core/tv80_reg.v \
    $root/build/picorv32/picorv32.v \
    $root/rtl/dp_out.v $root/rtl/dp_comp80_source.v $root/rtl/dp_transceivers.v \
    $root/build/DisplayPort_Verilog/src/main_stream_processing.v \
    $root/build/DisplayPort_Verilog/src/idle_pattern_inserter.v \
    $root/build/DisplayPort_Verilog/src/insert_training_pattern.v \
    $root/build/DisplayPort_Verilog/src/scrambler_all_channels.v \
    $root/build/DisplayPort_Verilog/src/scrambler_reset_inserter.v \
    $root/build/DisplayPort_Verilog/src/skew_channels.v \
    $root/build/DisplayPort_Verilog/src/auxch/channel_managemnt.v \
    $root/build/DisplayPort_Verilog/src/auxch/aux_channel.v \
    $root/build/DisplayPort_Verilog/src/auxch/aux_interface.v \
    $root/build/DisplayPort_Verilog/src/auxch/dp_aux_messages.v \
    $root/build/DisplayPort_Verilog/src/auxch/dp_register_decode.v \
    $root/build/DisplayPort_Verilog/src/auxch/edid_decode.v \
    $root/build/DisplayPort_Verilog/src/auxch/hotplug_decode.v \
    $root/build/DisplayPort_Verilog/src/auxch/link_signal_mgmt.v \
    $root/build/DisplayPort_Verilog/src/artix7/transceiver.v \
    $root/build/DisplayPort_Verilog/src/artix7/gtx_tx_reset_controller.v \
    $root/build/DisplayPort_Verilog/src/test_streams/insert_main_stream_attrbutes_one_channel.v]
read_verilog -sv [list $root/build/usb_hid_host/src/usb_hid_host.v $root/build/usb_hid_host/src/usb_hid_host_rom.v]
read_xdc $root/rtl/comp80v3.xdc

synth_design -top top -part $part
report_utilization -file utilisation_synth.txt
opt_design
place_design
phys_opt_design
route_design
report_utilization -file utilisation.txt
report_timing_summary -file timing.txt
report_drc -file drc.txt
write_bitstream -force comp80v3.bit
# the flash image: 16 MB IS25LP128F on SPI x4
write_cfgmem -force -format mcs -size 16 -interface SPIx4 -loadbit "up 0x0 comp80v3.bit" comp80v3.mcs
puts "done: see out/timing.txt (worst negative slack must not be negative)"
