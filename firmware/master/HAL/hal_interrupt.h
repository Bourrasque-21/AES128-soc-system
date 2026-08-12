#ifndef HAL_INTERRUPT_H
#define HAL_INTERRUPT_H

#include "xil_types.h"
#include "xil_exception.h"

void hal_interrupt_init(void);
void hal_interrupt_connect(u8 interrupt_id, XInterruptHandler handler, void *callback_ref);
void hal_interrupt_enable_global(void);
void hal_interrupt_ack(u8 interrupt_id);

#endif
