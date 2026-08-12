# UART master/slave RTL demo

Runtime-key AES-GCM 코어 기반 self-contained RTL 통합 데모.

## 구조

- `rtl/common/`: master와 slave가 공유하는 UART, frame, FIFO RTL
- `rtl/master/`: command 생성, response 검증, key-update 제어
- `rtl/slave/`: 인증된 command 처리, response 및 key-update ACK 생성
- `tb/`: master/slave UART link 통합 테스트
- `report/`: 통합 testbench 검증 결과
- UART frame: `A5 5A` SOF + 80-byte GCM packet
- Key update: active key로 요청 및 ACK 인증 후 양쪽 endpoint를 새 epoch key로 전환함
