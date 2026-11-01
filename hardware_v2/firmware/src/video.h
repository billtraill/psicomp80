// HDMI out: 640 x 480 at 60 Hz from the HSTX port, showing the COMP80's
// 64 x 32 character screen with each 6 x 10 character cell drawn 10 x 15.
#ifndef VIDEO_H
#define VIDEO_H

#include <stdint.h>

enum { COLOUR_WHITE, COLOUR_GREEN, COLOUR_AMBER, COLOUR_COUNT };
extern const char *const colour_names[COLOUR_COUNT];

// Start the HSTX output and its DMA (core 0: the DMA interrupt runs there).
void video_init(void);
// The 2 KB of screen memory to show (the COMP80's at 8000, or the menu's).
void video_source(const uint8_t *screen);
void video_colour(int c);
// Redraw the characters that changed since last time (core 1 calls this).
void video_update(void);

#endif
