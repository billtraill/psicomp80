// TinyUSB: host only, on root port 1 (PIO-USB, the keyboard's USB-A socket).
// The RP2350's own USB is left to its boot ROM, for loading firmware.
#ifndef TUSB_CONFIG_H
#define TUSB_CONFIG_H

#define CFG_TUSB_OS              OPT_OS_PICO
#define CFG_TUSB_RHPORT0_MODE    OPT_MODE_NONE
#define CFG_TUSB_RHPORT1_MODE    OPT_MODE_HOST
#define CFG_TUH_ENABLED          1
#define CFG_TUH_RPI_PIO_USB      1
#define BOARD_TUH_RHPORT         1
#define CFG_TUH_MAX_SPEED        OPT_MODE_FULL_SPEED

#define CFG_TUH_ENUMERATION_BUFSIZE 256
#define CFG_TUH_HUB              1      // a keyboard with its own hub
#define CFG_TUH_DEVICE_MAX       (CFG_TUH_HUB ? 4 : 1)
#define CFG_TUH_HID              4
#define CFG_TUH_HID_EPIN_BUFSIZE 64
#define CFG_TUH_HID_EPOUT_BUFSIZE 64

#endif
