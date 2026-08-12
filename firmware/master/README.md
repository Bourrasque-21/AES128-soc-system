# MicroBlaze master firmware

MicroBlaze용 AES-GCM UART master 애플리케이션 소스.

- `APP/`: protocol, command, response 및 session-key update
- `DRIVER/`: AES-GCM, board I/O, console UART, link UART 접근 계층
- `HAL/`: platform, interrupt, timer 초기화
- `main.c`: 애플리케이션 진입점

의존 항목: BSP `xparameters.h`, Xilinx standalone driver.
