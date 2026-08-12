#ifndef CONSOLE_UART_H
#define CONSOLE_UART_H

#include "xil_types.h"

void console_uart_init(void);
int console_uart_getc(u8 *ch);
void console_uart_putc(u8 ch);
void console_uart_puts(const char *text);
u32 console_uart_error_flags(void);
void console_uart_clear_errors(void);

#endif
