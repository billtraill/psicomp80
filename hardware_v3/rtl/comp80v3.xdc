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
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVDS_25} [get_ports {dp_aux_p}]   ;# DisplayPort AUX+ (SBU1)
set_property -dict {PACKAGE_PIN A1 IOSTANDARD LVDS_25} [get_ports {dp_aux_n}]   ;# DisplayPort AUX- (SBU2)
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS25} [get_ports {pd_scl}]   ;# FUSB302 I2C clock
set_property -dict {PACKAGE_PIN D1 IOSTANDARD LVCMOS25} [get_ports {pd_sda}]   ;# FUSB302 I2C data
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS25} [get_ports {pd_int_n}]   ;# FUSB302 interrupt
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS25} [get_ports {vbus_en}]   ;# Monitor VBUS switch on
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS25} [get_ports {vbus_flt_n}]   ;# Monitor VBUS fault
# GTP transceiver pins (bank 216) and their 135 MHz reference
set_property PACKAGE_PIN D7 [get_ports {dp_tx_p[0]}]   ;# J7 TX1+
set_property PACKAGE_PIN C7 [get_ports {dp_tx_n[0]}]   ;# J7 TX1-
set_property PACKAGE_PIN B6 [get_ports {dp_tx_p[1]}]   ;# J7 RX1+
set_property PACKAGE_PIN A6 [get_ports {dp_tx_n[1]}]   ;# J7 RX1-
set_property PACKAGE_PIN D5 [get_ports {dp_tx_p[2]}]   ;# J7 TX2+
set_property PACKAGE_PIN C5 [get_ports {dp_tx_n[2]}]   ;# J7 TX2-
set_property PACKAGE_PIN B4 [get_ports {dp_tx_p[3]}]   ;# J7 RX2+
set_property PACKAGE_PIN A4 [get_ports {dp_tx_n[3]}]   ;# J7 RX2-
set_property PACKAGE_PIN F6 [get_ports {dp_refclk_p}]   ;# 135 MHz reference+
set_property PACKAGE_PIN E6 [get_ports {dp_refclk_n}]   ;# 135 MHz reference-

create_clock -period 10.000 -name clk100 [get_ports clk100]
# the USB core, the system clock and the pixel clock only meet through synchronisers
set_clock_groups -asynchronous -group [get_clocks -of_objects [get_pins pll/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins pll/CLKOUT1]] \
    -group [get_clocks -of_objects [get_pins mmcm/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins dp/gtp/*/TXOUTCLK]]
create_clock -period 7.407 -name dp_refclk [get_ports dp_refclk_p]
set_property PULLDOWN true [get_ports {usb_dp usb_dm}]
set_property PULLUP true [get_ports btn_reset_n]
# hamsternz's AUX channel and link management run from clk100, as on his boards
set_clock_groups -asynchronous -group [get_clocks clk100] -group [get_clocks -of_objects [get_pins pll/CLKOUT0]]
