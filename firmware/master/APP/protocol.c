#include "protocol.h"

void protocol_build_plain(u32 words[AES_GCM_WORDS_PLAIN],
                          u8 command,
                          u8 flags,
                          u16 arg,
                          u8 led_value,
                          u8 switch_value,
                          u8 status,
                          u32 nonce_hi,
                          u32 nonce_lo)
{
    unsigned int i;

    for (i = 0u; i < AES_GCM_WORDS_PLAIN; ++i) {
        words[i] = 0u;
    }

    words[0] = ((u32)PROTO_VERSION << 24) |
               ((u32)PROTO_SLAVE_ID << 16) |
               (u32)PROTO_MASTER_ID;
    words[1] = PROTO_MASTER_TX_FIXED_IV;
    words[2] = nonce_hi;
    words[3] = nonce_lo;
    words[4] = ((u32)command << 24) |
               ((u32)flags << 16) |
               (u32)arg;
    words[5] = ((u32)led_value << 24) |
               ((u32)switch_value << 16) |
               ((u32)status << 8);
}

void protocol_put_key_update(u32 words[AES_GCM_WORDS_PLAIN],
                             u16 key_epoch,
                             const u32 key_words[4])
{
    words[4] = ((u32)CMD_KEY_UPDATE << 24) |
               ((u32)FLAG_RESPONSE << 16) |
               (u32)key_epoch;
    words[5] = key_words[0];
    words[6] = key_words[1];
    words[7] = key_words[2];
    words[8] = key_words[3];
}

void protocol_parse_payload(const u32 words[AES_GCM_WORDS_PACKET],
                            protocol_payload_t *payload)
{
    payload->command = (u8)((words[4] >> 24) & 0xFFu);
    payload->flags = (u8)((words[4] >> 16) & 0xFFu);
    payload->arg = (u16)(words[4] & 0xFFFFu);
    payload->led_value = (u8)((words[5] >> 24) & 0xFFu);
    payload->switch_value = (u8)((words[5] >> 16) & 0xFFu);
    payload->status = (u8)((words[5] >> 8) & 0xFFu);
}

const char *protocol_command_name(u8 command)
{
    switch (command) {
    case CMD_HEARTBEAT:
        return "HEARTBEAT";
    case CMD_COUNTER_UPDATE:
        return "COUNTER_UPDATE";
    case CMD_LED_CONTROL:
        return "LED_CONTROL";
    case CMD_READ_SW_REQUEST:
        return "READ_SW_REQUEST";
    case CMD_SW_RESPONSE:
        return "SW_RESPONSE";
    case CMD_KEY_UPDATE:
        return "KEY_UPDATE";
    case CMD_KEY_UPDATE_ACK:
        return "KEY_UPDATE_ACK";
    default:
        return "UNKNOWN";
    }
}
