#ifndef AES_GCM_H
#define AES_GCM_H

#include "xil_types.h"

#define AES_GCM_WORDS_PLAIN      16u
#define AES_GCM_WORDS_PACKET     20u
#define AES_GCM_FRAME_BYTES      80u

#define AES_GCM_ST_OP_BUSY       0x00000001u
#define AES_GCM_ST_TX_BUSY       0x00000002u
#define AES_GCM_ST_RX_BUSY       0x00000004u
#define AES_GCM_ST_TX_DONE       0x00000008u
#define AES_GCM_ST_RX_DONE       0x00000010u
#define AES_GCM_ST_RX_AUTH_FAIL  0x00000020u
#define AES_GCM_ST_TX_TAG_MATCH  0x00000040u
#define AES_GCM_ST_RX_TAG_MATCH  0x00000080u
#define AES_GCM_ST_KEY_LOADED    0x00000100u
#define AES_GCM_ST_KEY_BUSY      0x00000200u
#define AES_GCM_ST_OP_TIMEOUT    0x00000400u

void aes_gcm_init(void);
u32 aes_gcm_status(void);
u32 aes_gcm_take_irq_status(void);
int aes_gcm_set_key(const u32 key_words[4]);
int aes_gcm_encrypt_packet(const u32 plain_words[AES_GCM_WORDS_PLAIN],
                           u32 encrypted_words[AES_GCM_WORDS_PACKET],
                           u32 *final_status);
int aes_gcm_decrypt_packet(const u32 encrypted_words[AES_GCM_WORDS_PACKET],
                           u32 plain_words[AES_GCM_WORDS_PACKET],
                           u32 *final_status);

#endif
