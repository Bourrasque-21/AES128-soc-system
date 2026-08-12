#ifndef BOARD_IO_H
#define BOARD_IO_H

#include "xil_types.h"

void board_io_init(void);
u8 board_io_read_switches(void);
void board_io_set_leds(u8 value);
void board_io_refresh_fnd_hex(u16 value, u8 dot_visible);
void board_io_blank_fnd(void);
void board_io_delay_cycles(u32 cycles);

#endif
