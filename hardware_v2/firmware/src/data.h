// Fonts and the built-in ROM (data.c is made by tools/make_data.py).
#ifndef DATA_H
#define DATA_H

#include <stdint.h>

extern const uint8_t font_ascii[64][8];
extern const uint8_t font_gfx[64][10];
extern const uint8_t rom_burp[3072];

#endif
