// The microSD card's files:
//   /COMP80/ROMS/*.ROM     ROM images (3072 bytes; 0000-0BFF)
//   /COMP80/TAPES/*.WAV    cassette tapes
//   /COMP80/COMP80.CFG     settings, as KEY=VALUE lines
#ifndef STORAGE_H
#define STORAGE_H

#include <stdbool.h>
#include <stdint.h>

#include "tape.h"

#define MAX_FILES 64
#define NAME_LEN 40

typedef struct {
    char rom[NAME_LEN];      // file in /COMP80/ROMS, or "" for the built-in BURP
    bool expansion;
    uint32_t clock;
    int colour;
} settings;

bool storage_mount(void);
bool storage_ready(void);
// Names in a folder ending in ext (".ROM", ".WAV"), sorted; returns how many.
int storage_list(const char *dir, const char *ext, char names[][NAME_LEN], int max);
// Read a whole file; returns its length or -1.
int storage_read(const char *path, uint8_t *buf, int max);
void storage_load_settings(settings *s);
bool storage_save_settings(const settings *s);
// Open a tape for playing or a new one for recording, as tape.c's file.
bool storage_open_tape(const char *name, bool write, tape_file *f);
// A tape name not yet used: TAPE01.WAV, TAPE02.WAV, ...
void storage_new_tape_name(char out[NAME_LEN]);

#endif
