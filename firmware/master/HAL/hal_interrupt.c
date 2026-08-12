#include "hal_interrupt.h"
#include "hal_platform.h"

#include "xintc_l.h"

void hal_interrupt_init(void)
{
    Xil_ExceptionInit();
    XIntc_MasterDisable(HAL_INTC_BASEADDR);
    XIntc_AckIntr(HAL_INTC_BASEADDR, 0xFFFFFFFFu);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XIntc_DeviceInterruptHandler,
                                 (void *)HAL_INTC_BASEADDR);
}

void hal_interrupt_connect(u8 interrupt_id, XInterruptHandler handler, void *callback_ref)
{
    XIntc_RegisterHandler(HAL_INTC_BASEADDR, interrupt_id, handler, callback_ref);
    XIntc_AckIntr(HAL_INTC_BASEADDR, (u32)1u << interrupt_id);
    XIntc_EnableIntr(HAL_INTC_BASEADDR, (u32)1u << interrupt_id);
}

void hal_interrupt_enable_global(void)
{
    XIntc_MasterEnable(HAL_INTC_BASEADDR);
    Xil_ExceptionEnable();
}

void hal_interrupt_ack(u8 interrupt_id)
{
    XIntc_AckIntr(HAL_INTC_BASEADDR, (u32)1u << interrupt_id);
}
