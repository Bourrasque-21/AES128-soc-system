# Board hardware files

## Master

- `master/design_1.bd`: MicroBlaze 기반 block design
- `master/Basys-3-Master.xdc`: master clock, UART, switch, button, LED, FND pin constraints

Block design에 MicroBlaze, local BRAM, AXI interconnect, AES-GCM, UART, GPIO,
timer 및 interrupt controller를 포함함.

## Slave

- `slave/Basys-3-Master.xdc`: slave clock, UART, switch, button, LED, FND pin constraints

Slave RTL top: `system-demo/rtl/slave/aes128_demo_slave_top.sv`
