#ifndef HAL_TIMER_H
#define HAL_TIMER_H

#include "xil_types.h"

void hal_timer_init_100ms(void);
u32 hal_timer_ticks_100ms(void);
u8 hal_timer_dot_visible(void);

#endif
