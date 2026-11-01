// USB Power Delivery and DisplayPort alternate mode on J7, through the FUSB302B.
#ifndef PD_H
#define PD_H

enum { PD_DETACHED, PD_POWERING, PD_CONTRACT, PD_IDENTITY, PD_SVIDS, PD_MODES, PD_ENTERING, PD_STATUS,
       PD_CONFIGURING, PD_DP };

void pd_init(void);
// Call often. busy: the COMP80 is timing-sensitive (a tape is running), so put
// off the slow checks for a monitor.
void pd_poll(int busy);
const char *pd_state_name(void);
int pd_hpd(void);

#endif
