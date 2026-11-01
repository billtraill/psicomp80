// A USB keyboard on the USB-A socket, through TinyUSB's host stack on PIO-USB.
// Core 1 runs the stack; keys reach core 0 through a queue, as the COMP80
// codes the web emulator's keyboard gives (letters in capitals, Return 0D,
// Backspace 08, Esc 1B, Ctrl+\ 1C) or one of the KEY_ codes below.
#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stdbool.h>
#include <stdint.h>

enum {
    KEY_F1 = 0x101, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
    KEY_UP = 0x120, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
};

void keyboard_init(void);       // core 1
void keyboard_task(void);       // core 1, as often as possible
bool keyboard_get(int *key);    // core 0
bool keyboard_connected(void);

#endif
