// The COMP80 v2 board's pins (hardware_v2/tools/design.py, GPIO_USE, must agree).
#ifndef BOARD_H
#define BOARD_H

#define PIN_UART_TX   0     // serial console on the debug header, 115200 baud
#define PIN_UART_RX   1

#define SD_SPI        spi1
#define PIN_SD_MISO   8     // DAT0
#define PIN_SD_CS     9     // DAT3
#define PIN_SD_SCK    10    // CLK
#define PIN_SD_MOSI   11    // CMD

// HDMI on the HSTX port, GPIO12-19 = HSTX bits 0-7, through 270R each:
//   12/13 TMDS data 2 +/- (red), 14/15 data 1 (green), 16/17 data 0 (blue),
//   18/19 the TMDS clock
#define HSTX_BIT_D2   0
#define HSTX_BIT_D1   2
#define HSTX_BIT_D0   4
#define HSTX_BIT_CK   6

#define PIN_USBH_DP   20    // keyboard, PIO-USB; D- is the next pin
#define PIN_HALT_LED  25

#endif
