#ifndef PROTOCOL_H
#define PROTOCOL_H

#include "aes_gcm.h"
#include "xil_types.h"

#define PROTO_SOF0                 0xA5u
#define PROTO_SOF1                 0x5Au

#define PROTO_VERSION              0x01u
#define PROTO_MASTER_ID            0x0010u
#define PROTO_SLAVE_ID             0x20u
#define PROTO_MASTER_TX_FIXED_IV   0x01020001u

#define CMD_HEARTBEAT              0x00u
#define CMD_COUNTER_UPDATE         0x01u
#define CMD_LED_CONTROL            0x02u
#define CMD_READ_SW_REQUEST        0x03u
#define CMD_SW_RESPONSE            0x04u
#define CMD_KEY_UPDATE             0x05u
#define CMD_KEY_UPDATE_ACK         0x06u

#define FLAG_COUNTER_VALID         0x01u
#define FLAG_LED_VALID             0x02u
#define FLAG_RESPONSE              0x04u
#define FLAG_ERROR                 0x08u

#define SLAVE_STATUS_AUTH_FAIL     0x01u
#define SLAVE_STATUS_UART_FRAME    0x02u
#define SLAVE_STATUS_FIFO_OVERRUN  0x04u
#define SLAVE_STATUS_WATCHDOG      0x08u
#define SLAVE_STATUS_PACKET_ERROR  0x10u
#define SLAVE_STATUS_BYTE_TIMEOUT  0x20u
#define SLAVE_STATUS_KEY_PENDING   0x40u

typedef struct {
    u8 command;
    u8 flags;
    u16 arg;
    u8 led_value;
    u8 switch_value;
    u8 status;
} protocol_payload_t;

void protocol_build_plain(u32 words[AES_GCM_WORDS_PLAIN],
                          u8 command,
                          u8 flags,
                          u16 arg,
                          u8 led_value,
                          u8 switch_value,
                          u8 status,
                          u32 nonce_hi,
                          u32 nonce_lo);
void protocol_put_key_update(u32 words[AES_GCM_WORDS_PLAIN],
                             u16 key_epoch,
                             const u32 key_words[4]);
void protocol_parse_payload(const u32 words[AES_GCM_WORDS_PACKET],
                            protocol_payload_t *payload);
const char *protocol_command_name(u8 command);

#endif
