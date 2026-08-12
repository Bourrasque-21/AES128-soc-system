#ifndef LINK_UART_H
#define LINK_UART_H

#include "xil_types.h"

#define LINK_UART_ST_TX_ACCEPT       0x00000001u
#define LINK_UART_ST_RX_AVAILABLE    0x00000008u
#define LINK_UART_ST_FRAMING_ERROR   0x00000080u
#define LINK_UART_ST_RX_OVERRUN      0x00000100u
#define LINK_UART_ST_TX_OVERRUN      0x00000200u
#define LINK_UART_ST_ERROR_MASK      0x00000380u

void link_uart_init(void);
u32 link_uart_status(void);
int link_uart_send_byte(u8 ch);
int link_uart_getc(u8 *ch);
void link_uart_send_break_clear(void);
u32 link_uart_take_errors(void);
void link_uart_drain_rx(void);

#endif
