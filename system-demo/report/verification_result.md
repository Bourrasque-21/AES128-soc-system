# UART Master/Slave Integration Verification

## Simulation

Integrated testbench:

```text
system-demo/tb/tb_key_update_master_slave.sv
```

The test instantiates:

```text
aes128_demo_master_top
aes128_demo_slave_top
```

The UART TX/RX lines are cross-connected in simulation.

## Covered Scenario

1. Master sends a counter update with the initial fixed key.
2. Slave decrypts the packet and updates FND payload value to `0x1234`.
3. Slave sends a normal authenticated response.
4. Master sends `CMD_KEY_UPDATE` carrying a 128-bit new session key.
5. Slave authenticates the command, stages the key, sends `CMD_KEY_UPDATE_ACK`,
   and then switches to epoch 1.
6. Master authenticates the ACK and switches to epoch 1.
7. Master sends another counter update with the new session key.
8. Slave decrypts it and updates FND payload value to `0xBEEF`.
9. Master requests switch data and receives `0x5A`.

## Result

```text
PASS: AES-128 GCM UART master/slave key-update integration test passed
```
