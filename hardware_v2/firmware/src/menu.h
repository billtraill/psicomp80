// The set-up screen (F1): which ROM, memory, clock and colour, and the
// cassette.  It draws in the COMP80's own character set.
#ifndef MENU_H
#define MENU_H

#include <stdbool.h>

#include "storage.h"

extern settings cfg;

// Power the COMP80 on with the current settings (loads the ROM from the card).
void power_on(void);
// Run the set-up screen until it's closed; the COMP80 is paused meanwhile.
void menu_run(bool tapes_only);
// A message on the screen for a moment, for when there's no card at power-on.
void menu_message(const char *line1, const char *line2);

#endif
