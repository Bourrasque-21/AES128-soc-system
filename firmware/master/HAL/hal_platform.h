#ifndef HAL_PLATFORM_H
#define HAL_PLATFORM_H

#include "xparameters.h"
#include "xil_types.h"

#ifndef XPAR_XINTC_0_BASEADDR
#define XPAR_XINTC_0_BASEADDR XPAR_MICROBLAZE_0_AXI_INTC_BASEADDR
#endif

#ifndef XPAR_AXI_TIMER_0_BASEADDR
#error "AXI_TIMER_0 is required."
#endif

#ifndef XPAR_AXI_UARTLITE_0_BASEADDR
#error "AXI_UARTLITE_0 is required for the PC console."
#endif

#ifndef XPAR_AES_128_GCM_0_BASEADDR
#error "AES_128_GCM_0 is required."
#endif

#ifndef XPAR_UART_0_BASEADDR
#error "UART_0 is required for the board-to-board link."
#endif

#ifndef XPAR_GPIO_COUNTER_0_BASEADDR
#error "GPIO_COUNTER_0 is required."
#endif

#ifndef XPAR_GPIO_COUNTER_1_BASEADDR
#error "GPIO_COUNTER_1 is required."
#endif

#ifndef XPAR_GPIO_COUNTER_2_BASEADDR
#error "GPIO_COUNTER_2 is required."
#endif

#define HAL_INTC_BASEADDR        XPAR_XINTC_0_BASEADDR
#define HAL_TIMER_BASEADDR       XPAR_AXI_TIMER_0_BASEADDR
#define HAL_PC_UART_BASEADDR     XPAR_AXI_UARTLITE_0_BASEADDR
#define HAL_AES_BASEADDR         XPAR_AES_128_GCM_0_BASEADDR
#define HAL_LINK_UART_BASEADDR   XPAR_UART_0_BASEADDR
#define HAL_GPIOA_BASEADDR       XPAR_GPIO_COUNTER_0_BASEADDR
#define HAL_GPIOB_BASEADDR       XPAR_GPIO_COUNTER_1_BASEADDR
#define HAL_GPIOC_BASEADDR       XPAR_GPIO_COUNTER_2_BASEADDR

#ifndef HAL_INTR_ID_AES
#ifdef XPAR_FABRIC_AES_128_GCM_0_INTR
#define HAL_INTR_ID_AES          XPAR_FABRIC_AES_128_GCM_0_INTR
#else
#define HAL_INTR_ID_AES          0u
#endif
#endif

#ifndef HAL_INTR_ID_TIMER
#ifdef XPAR_FABRIC_AXI_TIMER_0_INTR
#define HAL_INTR_ID_TIMER        XPAR_FABRIC_AXI_TIMER_0_INTR
#else
#define HAL_INTR_ID_TIMER        1u
#endif
#endif

#ifndef HAL_INTR_ID_PC_UART
#ifdef XPAR_FABRIC_AXI_UARTLITE_0_INTR
#define HAL_INTR_ID_PC_UART      XPAR_FABRIC_AXI_UARTLITE_0_INTR
#else
#define HAL_INTR_ID_PC_UART      2u
#endif
#endif

#ifndef HAL_INTR_ID_LINK_UART
#ifdef XPAR_FABRIC_UART_0_INTR
#define HAL_INTR_ID_LINK_UART    XPAR_FABRIC_UART_0_INTR
#else
#define HAL_INTR_ID_LINK_UART    3u
#endif
#endif

#define HAL_CPU_CLOCK_HZ         100000000u
#define HAL_TIMER_100MS_TICKS    (HAL_CPU_CLOCK_HZ / 10u)

#endif
