# COMP80 v3 pins: made by tools/design.py from the board's tables; don't edit.
# Every bank's VCCO is 3.3 V. HDMI uses TMDS_33, which drives the display's
# 50 ohm terminations directly.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {clk100}]   ;# 100 MHz oscillator (bank 16 SRCC)
set_property -dict {PACKAGE_PIN A13 IOSTANDARD TMDS_33} [get_ports {tmds_p[0]}]   ;# HDMI data 0+ (blue)
set_property -dict {PACKAGE_PIN A14 IOSTANDARD TMDS_33} [get_ports {tmds_n[0]}]   ;# HDMI data 0-
set_property -dict {PACKAGE_PIN A15 IOSTANDARD TMDS_33} [get_ports {tmds_p[1]}]   ;# HDMI data 1+ (green)
set_property -dict {PACKAGE_PIN A16 IOSTANDARD TMDS_33} [get_ports {tmds_n[1]}]   ;# HDMI data 1-
set_property -dict {PACKAGE_PIN B15 IOSTANDARD TMDS_33} [get_ports {tmds_p[2]}]   ;# HDMI data 2+ (red)
set_property -dict {PACKAGE_PIN B16 IOSTANDARD TMDS_33} [get_ports {tmds_n[2]}]   ;# HDMI data 2-
set_property -dict {PACKAGE_PIN A18 IOSTANDARD TMDS_33} [get_ports {tmds_p[3]}]   ;# HDMI clock+
set_property -dict {PACKAGE_PIN A19 IOSTANDARD TMDS_33} [get_ports {tmds_n[3]}]   ;# HDMI clock-
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {usb_dp}]   ;# Keyboard USB D+
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports {usb_dm}]   ;# Keyboard USB D-
set_property -dict {PACKAGE_PIN J22 IOSTANDARD LVCMOS33} [get_ports {sd_sck}]   ;# microSD CLK
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS33} [get_ports {sd_mosi}]   ;# microSD CMD
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS33} [get_ports {sd_miso}]   ;# microSD DAT0
set_property -dict {PACKAGE_PIN M22 IOSTANDARD LVCMOS33} [get_ports {sd_cs_n}]   ;# microSD DAT3/CS
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS33} [get_ports {uart_tx}]   ;# Serial console out
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS33} [get_ports {led_halt}]   ;# HALT LED
set_property -dict {PACKAGE_PIN AB12 IOSTANDARD LVCMOS33} [get_ports {btn_reset_n}]   ;# RESET button (low when pressed)

create_clock -period 10.000 -name clk100 [get_ports clk100]
# the USB core, the system clock and the pixel clock only meet through synchronisers
set_clock_groups -asynchronous -group [get_clocks -of_objects [get_pins pll/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins pll/CLKOUT1]] \
    -group [get_clocks -of_objects [get_pins mmcm/CLKOUT0]]
set_property PULLDOWN true [get_ports {usb_dp usb_dm}]
set_property PULLUP true [get_ports btn_reset_n]
