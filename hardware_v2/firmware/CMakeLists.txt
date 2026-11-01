# COMP80 v2 firmware, for the RP2350A on the hardware_v2 board.
#
#   cmake -B build -DPICO_SDK_PATH=/path/to/pico-sdk && cmake --build build
#
# writes build/comp80v2.uf2. Pico SDK 2.2 (with its TinyUSB submodule), and
# Pico-PIO-USB and FatFs, which are fetched from GitHub unless
# PICO_PIO_USB_PATH and FATFS_PATH point at copies.
cmake_minimum_required(VERSION 3.13)

set(PICO_BOARD pico2)          # the same RP2350A, 12 MHz crystal and 4 MB flash
set(PICO_PLATFORM rp2350-arm-s)
include(pico_sdk_import.cmake)
project(comp80v2 C CXX ASM)
set(CMAKE_C_STANDARD 11)
pico_sdk_init()

include(FetchContent)
if(NOT PICO_PIO_USB_PATH)
    FetchContent_Declare(pico_pio_usb GIT_REPOSITORY https://github.com/sekigon-gonnoc/Pico-PIO-USB.git
                         GIT_TAG b186e36bea0f3bcc2ee94ca1fa81e7f71281443a)    # 0.7.3
    FetchContent_Populate(pico_pio_usb)
    set(PICO_PIO_USB_PATH ${pico_pio_usb_SOURCE_DIR})
endif()
if(NOT FATFS_PATH)
    FetchContent_Declare(fatfs GIT_REPOSITORY https://github.com/abbrev/fatfs.git
                         GIT_TAG ab992fcf2926b8a1ee3f0a8f9cefb6584174100d)    # R0.16
    FetchContent_Populate(fatfs)
    set(FATFS_PATH ${fatfs_SOURCE_DIR})
endif()

add_subdirectory(${PICO_PIO_USB_PATH} pico_pio_usb)

# FatFs's ff.h includes "ffconf.h" from its own folder first, so build a copy
# of it next to our ffconf.h
set(FF ${CMAKE_BINARY_DIR}/fatfs)
foreach(f ff.c ff.h ffunicode.c diskio.h)
    configure_file(${FATFS_PATH}/source/${f} ${FF}/${f} COPYONLY)
endforeach()
configure_file(src/ffconf.h ${FF}/ffconf.h COPYONLY)

add_executable(comp80v2
    src/main.c
    src/z80.c
    src/comp80.c
    src/mm57109.c
    src/tape.c
    src/data.c
    src/video.c
    src/keyboard.c
    src/sdcard.c
    src/storage.c
    src/menu.c
    ${FF}/ff.c
    ${FF}/ffunicode.c
    ${PICO_TINYUSB_PATH}/src/portable/raspberrypi/pio_usb/hcd_pio_usb.c
)
target_include_directories(comp80v2 PRIVATE src ${FF})
target_compile_options(comp80v2 PRIVATE -Wall -O2)
target_compile_definitions(comp80v2 PRIVATE
    PICO_DEFAULT_UART=0 PICO_DEFAULT_UART_TX_PIN=0 PICO_DEFAULT_UART_RX_PIN=1
    PICO_XOSC_STARTUP_DELAY_MULTIPLIER=64
    PICO_FLASH_SIZE_BYTES=4194304)
target_link_libraries(comp80v2
    pico_stdlib pico_multicore pico_util
    hardware_dma hardware_spi hardware_pll hardware_clocks hardware_vreg hardware_irq
    tinyusb_host pico_pio_usb)
pico_enable_stdio_uart(comp80v2 1)
pico_enable_stdio_usb(comp80v2 0)
pico_add_extra_outputs(comp80v2)
