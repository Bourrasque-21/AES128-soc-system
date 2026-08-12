# AES128 SoC System

AES-128 GCM RTL, UART master/slave 데모, MicroBlaze 펌웨어 및 Vivado 구성 파일을
통합 관리함.

## 디렉터리 구성

| 경로 | 내용 |
| --- | --- |
| `aes128-gcm-core/` | runtime-key AES-128 GCM full-duplex RTL |
| `system-demo/` | UART master/slave RTL과 통합 testbench |
| `firmware/master/` | MicroBlaze master 애플리케이션 C 소스 |
| `hardware/master/` | MicroBlaze block design과 master XDC |
| `hardware/slave/` | slave XDC |
| `experimental/aes128-gcm-full-pipeline/` | BRAM S-box 기반 AES-GCM pipeline RTL과 testbench |

## AES-128 GCM 코어

Top module: `aes128_gcm_duplex_packet_top`

- AES-128 encryption
- GCM encrypt/decrypt 및 tag 검증
- 독립 TX/RX packet engine
- TX/RX runtime key 입력
- 16-byte AAD, 48-byte payload, 16-byte tag
- 인증 실패 시 RX payload clear
- TX done, RX done, RX authentication-failure IRQ

컴파일 순서: `aes128-gcm-core/filelist_core.f`에 정의함.

## UART master/slave 데모

`system-demo/`에 다음 module을 포함함.

- Master: `aes128_demo_master_top`
- Slave: `aes128_demo_slave_top`
- Testbench: `tb_key_update_master_slave`

- UART frame: 2-byte SOF `A5 5A` + 80-byte GCM packet
- 지원 command: heartbeat, counter update, LED control, switch read, session-key update

## MicroBlaze master 구성

`hardware/master/design_1.bd`에 MicroBlaze와 다음 peripheral을 연결함.

- AES-128 GCM AXI-Lite IP
- UART AXI-Lite IP
- GPIO/FND/LED AXI-Lite IP
- AXI Timer
- AXI Interrupt Controller
- Local BRAM

`firmware/master/`: 해당 hardware platform용 master 애플리케이션 소스.

## Pipeline RTL

기본 top module: `aes128_gcm_packet_pipeline_top`

하나의 AES full pipeline과 하나의 GCM packet context를 사용하며 packet 단위로
encrypt/decrypt mode를 선택함.

세부 구조 및 합성 수치: `experimental/aes128-gcm-full-pipeline/report/`에 정리함.
