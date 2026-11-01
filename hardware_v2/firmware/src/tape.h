// The cassette: WAV files in the format the MAME driver reads and writes
// (16-bit mono at 44.1 kHz; any PCM WAV plays).  The COMP80's tape interface
// hands the Z80 one decoded logic level each way, so a tape here is that level
// against time: played back through a Schmitt trigger into IN 00, and OUT 20's
// level recorded as a square wave.
#ifndef TAPE_H
#define TAPE_H

#include <stdbool.h>
#include <stdint.h>

// Open file, as the firmware's storage layer or the host test supplies it.
typedef struct {
    int (*read)(void *buf, int n);          // bytes read, 0 at the end
    int (*write)(const void *buf, int n);   // bytes written
    bool (*seek)(uint32_t pos);
    void (*close)(void);
} tape_file;

enum { TAPE_STOPPED, TAPE_PLAYING, TAPE_RECORDING };

// Start playing an open WAV file at Z80 time now.  False if it isn't a PCM WAV.
bool tape_play(const tape_file *f, uint64_t now);
// Start recording into an open, empty file at Z80 time now.
void tape_record(const tape_file *f, uint64_t now);
// Stop, finishing a recording; closes the file.
void tape_stop(uint64_t now);
int tape_state(void);
// Seconds into the tape, for the status line.
uint32_t tape_seconds(uint64_t now);
// Call now and then while recording, so silence gets written too.
void tape_poll(uint64_t now);

#endif
