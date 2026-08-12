#include "hal_timer.h"
#include "hal_interrupt.h"
#include "hal_platform.h"

#include "xtmrctr_l.h"

static volatile u32 g_ticks_100ms;
static volatile u8 g_dot_visible;

static void timer_isr(void *callback_ref)
{
    u32 csr;

    (void)callback_ref;
    csr = XTmrCtr_GetControlStatusReg(HAL_TIMER_BASEADDR, XTC_TIMER_0);
    XTmrCtr_SetControlStatusReg(HAL_TIMER_BASEADDR, XTC_TIMER_0,
                                csr | XTC_CSR_INT_OCCURED_MASK);

    ++g_ticks_100ms;
    if ((g_ticks_100ms % 5u) == 0u) {
        g_dot_visible ^= 1u;
    }
}

void hal_timer_init_100ms(void)
{
    g_ticks_100ms = 0u;
    g_dot_visible = 1u;

    XTmrCtr_SetControlStatusReg(HAL_TIMER_BASEADDR, XTC_TIMER_0, 0u);
    XTmrCtr_SetLoadReg(HAL_TIMER_BASEADDR, XTC_TIMER_0, HAL_TIMER_100MS_TICKS - 1u);
    XTmrCtr_LoadTimerCounterReg(HAL_TIMER_BASEADDR, XTC_TIMER_0);
    XTmrCtr_SetControlStatusReg(HAL_TIMER_BASEADDR, XTC_TIMER_0,
                                XTC_CSR_ENABLE_INT_MASK |
                                XTC_CSR_AUTO_RELOAD_MASK |
                                XTC_CSR_DOWN_COUNT_MASK |
                                XTC_CSR_ENABLE_TMR_MASK);

    hal_interrupt_connect((u8)HAL_INTR_ID_TIMER, timer_isr, 0);
}

u32 hal_timer_ticks_100ms(void)
{
    return g_ticks_100ms;
}

u8 hal_timer_dot_visible(void)
{
    return g_dot_visible;
}
