# Runtime-key AES-128 GCM core

Runtime-key 입력 기반 full-duplex AES-128 GCM RTL.

- 16-byte AAD + 48-byte payload + 16-byte tag의 80-byte packet
- 독립 TX encrypt / RX decrypt-authenticate engine
- TX/RX runtime key input
- 8-bit/clock sequential GF(2^128) multiplier
- TX done, RX done, RX authentication-failure IRQ source
- 인증 실패 시 RX payload zeroization

Top module: `aes128_gcm_duplex_packet_top`

컴파일 순서: `filelist_core.f`에 정의함.
