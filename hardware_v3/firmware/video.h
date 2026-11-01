// The colours, as the v2 firmware's video.h has them (storage.c uses them).
#ifndef VIDEO_H
#define VIDEO_H

enum { COLOUR_WHITE, COLOUR_GREEN, COLOUR_AMBER, COLOUR_COUNT };
extern const char *const colour_names[COLOUR_COUNT];

#endif
