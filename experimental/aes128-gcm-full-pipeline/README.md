# AES-128 GCM full-pipeline experiment

BRAM S-box 및 AES full pipeline 기반 AES-GCM RTL.

기본 top module: `aes128_gcm_packet_pipeline_top`

- AES input throughput: 최대 1 block/clock
- AES latency: 20 clocks
- single packet context, encrypt/decrypt runtime mode
- GCM KAT testbench와 out-of-context 100 MHz synthesis script/report 포함
- 3,437 LUT, 3,626 registers, 80 RAMB18
- fixed key 사용
- single packet context 사용
- runtime key update 미포함
- 동시 TX/RX packet 처리 미포함
- 상세 구조 및 합성 결과: `report/design_summary.md`
