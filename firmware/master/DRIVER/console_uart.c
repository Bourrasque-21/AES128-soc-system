#include "console_uart.h"
#include "hal_interrupt.h"
#include "hal_platform.h"

#include "xuartlite_l.h"

#define CONSOLE_RX_RING_SIZE 128u

static volatile u8 g_rx_ring[CONSOLE_RX_RING_SIZE];
static volatile u16 g_rx_head;
static volatile u16 g_rx_tail;
static volatile u32 g_error_flags;

static u16 ring_next(u16 value)
{
    ++value;
    if (value >= CONSOLE_RX_RING_SIZE) {
        value = 0u;
    }
    return value;
}

static void ring_push(u8 ch)
{
    u16 next = ring_next(g_rx_head);

    if (next == g_rx_tail) {
        g_error_flags |= 0x80000000u;
        return;
    }

    g_rx_ring[g_rx_head] = ch;
    g_rx_head = next;
}

static void console_uart_isr(void *callback_ref)
{
    u32 status;
    u32 guard = 64u;

    (void)callback_ref;
    status = XUartLite_GetStatusReg(HAL_PC_UART_BASEADDR);
    if ((status & (XUL_SR_PARITY_ERROR | XUL_SR_FRAMING_ERROR | XUL_SR_OVERRUN_ERROR)) != 0u) {
        g_error_flags |= status;
        XUartLite_SetControlReg(HAL_PC_UART_BASEADDR,
                                XUL_CR_FIFO_RX_RESET | XUL_CR_ENABLE_INTR);
    }

    while (!XUartLite_IsReceiveEmpty(HAL_PC_UART_BASEADDR) && (guard != 0u)) {
        ring_push(XUartLite_RecvByte(HAL_PC_UART_BASEADDR));
        --guard;
    }
}

void console_uart_init(void)
{
    g_rx_head = 0u;
    g_rx_tail = 0u;
    g_error_flags = 0u;

    XUartLite_SetControlReg(HAL_PC_UART_BASEADDR,
                            XUL_CR_FIFO_RX_RESET | XUL_CR_FIFO_TX_RESET);
    XUartLite_EnableIntr(HAL_PC_UART_BASEADDR);
    hal_interrupt_connect((u8)HAL_INTR_ID_PC_UART, console_uart_isr, 0);
}

int console_uart_getc(u8 *ch)
{
    if (g_rx_head == g_rx_tail) {
        if (!XUartLite_IsReceiveEmpty(HAL_PC_UART_BASEADDR)) {
            console_uart_isr(0);
        }
    }

    if (g_rx_head == g_rx_tail) {
        return 0;
    }

    *ch = g_rx_ring[g_rx_tail];
    g_rx_tail = ring_next(g_rx_tail);
    return 1;
}

void console_uart_putc(u8 ch)
{
    XUartLite_SendByte(HAL_PC_UART_BASEADDR, ch);
}

void console_uart_puts(const char *text)
{
    while (*text != '\0') {
        console_uart_putc((u8)*text);
        ++text;
    }
}

u32 console_uart_error_flags(void)
{
    return g_error_flags;
}

void console_uart_clear_errors(void)
{
    g_error_flags = 0u;
    XUartLite_SetControlReg(HAL_PC_UART_BASEADDR,
                            XUL_CR_FIFO_RX_RESET | XUL_CR_ENABLE_INTR);
}
