# AES-128 GCM Full-Pipeline Design Summary

## Purpose

This directory contains an experimental AES-128 GCM core with a full-pipeline AES datapath.
The current default structure is a single packet pipeline:

- One AES-128 full pipeline.
- One GCM packet context.
- One GHASH engine.
- One input stream and one output stream.
- A packet mode bit selects encrypt/TX or decrypt/RX per packet.

This matches the intended packet-level half-duplex/sequential communication model. Packets are not
processed by independent TX/RX GCM engines. Instead, the wrapper or upstream FIFO presents one packet
job at a time, and the core returns the result on the same output stream in the same order.

## Current Top-Level Structure

Default top module:

- `rtl/aes128_gcm_packet_pipeline_top.sv`

Packet mode:

- `pkt_decrypt = 0`: encrypt/TX packet.
- `pkt_decrypt = 1`: decrypt/RX packet.

Unified input:

- `pkt_start`
- `pkt_decrypt`
- `in_valid`
- `in_ready`
- `in_data[31:0]`

Unified output:

- `out_valid`
- `out_ready`
- `out_data[31:0]`
- `out_decrypt`

Status:

- `busy`
- `done`
- `tag_match`
- `auth_fail`
- `irq_tx_done`
- `irq_rx_done`
- `irq_rx_auth_fail`

The core itself does not contain a multi-packet FIFO. If a packet arrives while `busy=1`, the upstream
logic should hold it until `in_ready`/`busy` allow the next job. This is intentional because packet
ordering is preserved by the handshake boundary.

## Internal AES Usage

AES-CTR encryption and decryption both use AES encryption. For each packet, the GCM context sends five
AES jobs into the full pipeline:

- `E(K, 0)` for GHASH subkey `H`.
- `E(K, nonce || 1)` for final tag mask.
- `E(K, nonce || 2)` for payload block 0 keystream.
- `E(K, nonce || 3)` for payload block 1 keystream.
- `E(K, nonce || 4)` for payload block 2 keystream.

The AES pipeline returns results after a fixed latency. A metadata pipeline carries only the AES request
type (`REQ_H`, `REQ_TAG_MASK`, `REQ_KS0`, `REQ_KS1`, `REQ_KS2`). A TX/RX direction tag is no longer
needed because only one packet context is active.

## AES Pipeline

Core module:

- `rtl/aes128_full_pipeline_bram_core.sv`

The AES datapath is expanded across all 10 AES rounds.
Each round has:

- 16 synchronous S-box ROM lookups.
- ShiftRows.
- MixColumns for rounds 1 through 9.
- AddRoundKey.

The final round omits MixColumns.

S-box module:

- `rtl/aes_sbox_bram_sync.sv`

The S-box is written as a 256 x 8 synchronous ROM with BRAM-style synthesis attributes.

## Latency And Throughput

AES behavior:

- AES input acceptance: up to one 128-bit block per clock.
- AES latency: 20 clocks after request acceptance.
- AES steady-state throughput: up to one block per clock.

GCM packet behavior:

- AES keystream generation is pipelined.
- GHASH is still sequential.
- A full packet still waits for GHASH completion before output.
- Complete GCM packet throughput is therefore still limited by GHASH, not by AES.

Metadata alignment:

- AES output appears 20 clocks after request acceptance.
- Metadata is captured at `meta_pipe[0]` on the acceptance edge.
- Therefore the metadata pipe has 21 entries and uses `meta_pipe[20]` at AES output time.

## Packet Format

Input format:

- Encrypt/TX input: 16 words = AAD 16B + plaintext 48B.
- Decrypt/RX input: 20 words = AAD 16B + ciphertext 48B + received tag 16B.

Output format:

- Encrypt/TX output: 20 words = AAD 16B + ciphertext 48B + computed tag 16B.
- Decrypt/RX output: 20 words = AAD 16B + plaintext 48B + computed tag 16B.

If decrypt authentication fails:

- `auth_fail` is asserted.
- `tag_match` is deasserted.
- Payload output is cleared to zero.

## File Roles

- `rtl/aes_pkg.sv`
  - AES helper functions, including S-box byte table and GF arithmetic helpers.
- `rtl/aes_sbox_bram_sync.sv`
  - Synchronous 256 x 8 S-box ROM, written for BRAM-style inference.
- `rtl/aes_shiftrows.sv`
  - AES ShiftRows transform.
- `rtl/aes_mixcolumns.sv`
  - AES MixColumns transform.
- `rtl/aes128_full_pipeline_bram_core.sv`
  - Full-pipeline AES-128 encryption engine.
- `rtl/gf128_mult_8bit_seq.sv`
  - 8-bit-per-clock GF(2^128) multiplier used by GHASH.
- `rtl/ghash_engine_seq.sv`
  - Sequential GHASH block engine.
- `rtl/aes128_gcm_packet_context.sv`
  - Single runtime-mode GCM packet context.
- `rtl/aes128_gcm_packet_pipeline_top.sv`
  - Current default top: one packet context plus one AES pipeline.
- `rtl/aes128_gcm_pipeline_context.sv`
  - Legacy parameterized TX/RX context kept for comparison.
- `rtl/aes128_gcm_shared_pipeline_top.sv`
  - Legacy dual-context shared-AES top kept for comparison.
- `tb/tb_aes128_full_pipeline_bram_core.sv`
  - AES-only known answer test.
- `tb/tb_aes128_gcm_packet_pipeline_top.sv`
  - Current single packet pipeline GCM test.
- `tb/tb_aes128_gcm_shared_pipeline_top.sv`
  - Legacy dual-context GCM test.
- `tb/filelist_gcm_packet_pipeline.f`
  - Current GCM simulation file list.
- `scripts/synth_aes128_gcm_full_pipeline.tcl`
  - Current OOC synthesis script targeting `aes128_gcm_packet_pipeline_top`.

## Verification Result

Vivado XSIM was run on May 23, 2026.

AES-only test:

```text
PASS: AES-128 BRAM S-box full pipeline core KAT passed
```

Single packet pipeline GCM test:

```text
PASS: AES-128 GCM single packet pipeline KAT passed
```

The GCM test covers:

- Encrypt/TX packet.
- Decrypt/RX packet.
- RX bad tag packet.
- Unified output stream mode stability.
- Known ciphertext/tag comparison.
- RX payload clear on authentication failure.
- IRQ count checks for TX done, RX done, and RX auth fail.

## Synthesis Snapshot

Vivado out-of-context synthesis was run for `xc7a35tcpg236-1` with a 100 MHz clock constraint.

Generated reports:

- `report/aes128_gcm_full_pipeline_synth_utilization.rpt`
- `report/aes128_gcm_full_pipeline_timing_summary.rpt`

Synthesis result:

- Errors: 0
- Critical warnings: 0
- Warnings: 1

Resource summary after synthesis:

- Slice LUTs: 3,437 / 20,800, 16.52%
- LUT as Logic: 3,433 / 20,800, 16.50%
- LUT as Memory: 4 / 9,600, 0.04%
- Slice Registers: 3,626 / 41,600, 8.72%
- Block RAM Tile: 40 / 50, 80.00%
- RAMB18: 80 / 100, 80.00%
- DSP: 0 / 90, 0.00%

Timing summary at 100 MHz:

- WNS: 3.596 ns
- TNS: 0.000 ns
- WHS: 0.259 ns
- THS: 0.000 ns
- Timing constraints met in synthesized OOC timing.

Comparison to the earlier dual-context structure:

- LUTs reduced from 4,762 to 3,437.
- Registers reduced from 5,724 to 3,626.
- RAMB18 stayed at 80 because BRAM use is dominated by the full AES S-box pipeline.

## Current Limitations

This version is simulation-verified and out-of-context synthesis-verified, but it has not gone through
full implementation, placement, routing, or board-level integration.

Important tradeoffs:

- Full AES pipeline still uses many S-box read ports.
- BRAM usage remains high: 80 RAMB18 blocks, or 40 of 50 block RAM tiles on `xc7a35tcpg236-1`.
- The design processes one packet job at a time. True simultaneous TX/RX packet processing is not the
  goal of this version.
- The key schedule is still computed from `FIXED_KEY`; runtime key update would require a key register,
  packet boundary control, and AES pipeline flush.
- GHASH is not fully pipelined, so complete GCM packet throughput does not equal pure AES pipeline
  throughput.

## Recommended Next Checks

1. Add a small packet/job FIFO wrapper if packets can arrive while the core is busy.
2. Run implementation after adding the real top-level wrapper and constraints.
3. Check whether the remaining BRAM budget is enough for UART FIFOs, MicroBlaze memory, or other demo logic.
4. If BRAM is too tight, try a half-pipeline or 4-S-box-per-round architecture.
5. If packet throughput is still limited by GHASH, consider 32-bit/clk or 64-bit/clk GHASH as a middle ground.
