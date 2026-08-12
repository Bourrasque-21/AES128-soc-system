#include "link_uart.h"
#include "hal_interrupt.h"
#include "hal_platform.h"

#include "xil_io.h"

#define UART_STATUS_OFFSET      0x00u
#define UART_TXDATA_OFFSET      0x04u
#define UART_RXDATA_OFFSET      0x08u
#define UART_IRQ_ENABLE_OFFSET  0x0Cu

#define UART_CTL_CLEAR_STATUS   0x00000001u
#define UART_CTL_CLEAR_RX_FIFO  0x00000002u
#define UART_CTL_CLEAR_TX_FIFO  0x00000004u

#define UART_IRQ_RX             0x00000001u
#define UART_IRQ_TX_DONE        0x00000002u
#define UART_IRQ_ERROR          0x00000004u

#define LINK_RX_RING_SIZE       512u
#define LINK_TX_TIMEOUT         2000000u

static volatile u8 g_rx_ring[LINK_RX_RING_SIZE];
static volatile u16 g_rx_head;
static volatile u16 g_rx_tail;
static volatile u32 g_error_latch;

static u16 ring_next(u16 value)
{
    ++value;
    if (value >= LINK_RX_RING_SIZE) {
        value = 0u;
    }
    return value;
}

static void ring_push(u8 ch)
{
    u16 next = ring_next(g_rx_head);

    if (next == g_rx_tail) {
        g_error_latch |= 0x80000000u;
        return;
    }

    g_rx_ring[g_rx_head] = ch;
    g_rx_head = next;
}

u32 link_uart_status(void)
{
    return Xil_In32(HAL_LINK_UART_BASEADDR + UART_STATUS_OFFSET);
}

static void link_uart_isr(void *callback_ref)
{
    u32 status;
    u32 guard = 128u;

    (void)callback_ref;
    status = link_uart_status();
    if ((status & LINK_UART_ST_ERROR_MASK) != 0u) {
        g_error_latch |= (status & LINK_UART_ST_ERROR_MASK);
        Xil_Out32(HAL_LINK_UART_BASEADDR + UART_STATUS_OFFSET, UART_CTL_CLEAR_STATUS);
    }

    while (((link_uart_status() & LINK_UART_ST_RX_AVAILABLE) != 0u) && (guard != 0u)) {
        ring_push((u8)(Xil_In32(HAL_LINK_UART_BASEADDR + UART_RXDATA_OFFSET) & 0xFFu));
        --guard;
    }
}

void link_uart_init(void)
{
    g_rx_head = 0u;
    g_rx_tail = 0u;
    g_error_latch = 0u;

    Xil_Out32(HAL_LINK_UART_BASEADDR + UART_IRQ_ENABLE_OFFSET, 0u);
    Xil_Out32(HAL_LINK_UART_BASEADDR + UART_STATUS_OFFSET,
              UART_CTL_CLEAR_STATUS | UART_CTL_CLEAR_RX_FIFO | UART_CTL_CLEAR_TX_FIFO);
    Xil_Out32(HAL_LINK_UART_BASEADDR + UART_IRQ_ENABLE_OFFSET,
              UART_IRQ_RX | UART_IRQ_ERROR);
    hal_interrupt_connect((u8)HAL_INTR_ID_LINK_UART, link_uart_isr, 0);
}

int link_uart_send_byte(u8 ch)
{
    u32 timeout = LINK_TX_TIMEOUT;

    while ((link_uart_status() & LINK_UART_ST_TX_ACCEPT) == 0u) {
        if (--timeout == 0u) {
            g_error_latch |= LINK_UART_ST_TX_OVERRUN;
            return 0;
        }
    }

    Xil_Out32(HAL_LINK_UART_BASEADDR + UART_TXDATA_OFFSET, (u32)ch);
    return 1;
}

int link_uart_getc(u8 *ch)
{
    if (g_rx_head == g_rx_tail) {
        link_uart_isr(0);
    }

    if (g_rx_head == g_rx_tail) {
        return 0;
    }

    *ch = g_rx_ring[g_rx_tail];
    g_rx_tail = ring_next(g_rx_tail);
    return 1;
}

void link_uart_send_break_clear(void)
{
    g_rx_head = 0u;
    g_rx_tail = 0u;
    Xil_Out32(HAL_LINK_UART_BASEADDR + UART_STATUS_OFFSET,
              UART_CTL_CLEAR_STATUS | UART_CTL_CLEAR_RX_FIFO | UART_CTL_CLEAR_TX_FIFO);
}

u32 link_uart_take_errors(void)
{
    u32 errors = g_error_latch;

    g_error_latch = 0u;
    return errors;
}

void link_uart_drain_rx(void)
{
    u8 ch;
    u32 guard = 1024u;

    while ((guard != 0u) && link_uart_getc(&ch)) {
        --guard;
    }
}
