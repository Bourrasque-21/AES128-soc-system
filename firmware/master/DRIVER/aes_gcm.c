#include "aes_gcm.h"
#include "hal_interrupt.h"
#include "hal_platform.h"

#include "xil_io.h"

#define AES_CONTROL_OFFSET       0x000u
#define AES_STATUS_OFFSET        0x004u
#define AES_KEY_OFFSET           0x010u
#define AES_IN_OFFSET            0x020u
#define AES_OUT_OFFSET           0x080u

#define AES_CTL_TX_START         0x00000001u
#define AES_CTL_RX_START         0x00000002u
#define AES_CTL_APPLY_KEY        0x00000004u
#define AES_CTL_CLEAR_STATUS     0x00000008u

#define AES_WAIT_TIMEOUT         20000000u

static volatile u32 g_irq_status_latch;
static volatile u32 g_irq_count;

static void aes_write(u32 offset, u32 value)
{
    Xil_Out32(HAL_AES_BASEADDR + offset, value);
}

static u32 aes_read(u32 offset)
{
    return Xil_In32(HAL_AES_BASEADDR + offset);
}

static void aes_clear_status(void)
{
    aes_write(AES_CONTROL_OFFSET, AES_CTL_CLEAR_STATUS);
}

static void aes_isr(void *callback_ref)
{
    u32 status;

    (void)callback_ref;
    status = aes_gcm_status();
    g_irq_status_latch |= status;
    ++g_irq_count;

    if ((status & (AES_GCM_ST_TX_DONE |
                   AES_GCM_ST_RX_DONE |
                   AES_GCM_ST_RX_AUTH_FAIL |
                   AES_GCM_ST_OP_TIMEOUT |
                   AES_GCM_ST_KEY_BUSY)) != 0u) {
        aes_clear_status();
    }
}

static int aes_wait_idle(void)
{
    u32 timeout = AES_WAIT_TIMEOUT;

    while ((aes_gcm_status() & AES_GCM_ST_OP_BUSY) != 0u) {
        if (--timeout == 0u) {
            return 0;
        }
    }

    return 1;
}

static int aes_wait_done(u32 done_mask, u32 *final_status)
{
    u32 timeout = AES_WAIT_TIMEOUT;
    u32 status;

    do {
        status = aes_gcm_status() | g_irq_status_latch;

        if ((status & AES_GCM_ST_OP_TIMEOUT) != 0u) {
            if (final_status != 0) {
                *final_status = status;
            }
            aes_clear_status();
            return 0;
        }

        if ((status & done_mask) != 0u) {
            if (final_status != 0) {
                *final_status = status;
            }
            aes_clear_status();
            return 1;
        }
    } while (--timeout != 0u);

    if (final_status != 0) {
        *final_status = aes_gcm_status() | g_irq_status_latch;
    }
    return 0;
}

void aes_gcm_init(void)
{
    g_irq_status_latch = 0u;
    g_irq_count = 0u;
    aes_clear_status();
    hal_interrupt_connect((u8)HAL_INTR_ID_AES, aes_isr, 0);
}

u32 aes_gcm_status(void)
{
    return aes_read(AES_STATUS_OFFSET);
}

u32 aes_gcm_take_irq_status(void)
{
    u32 status = g_irq_status_latch;

    g_irq_status_latch = 0u;
    return status;
}

int aes_gcm_set_key(const u32 key_words[4])
{
    unsigned int i;
    u32 status = 0u;

    if (!aes_wait_idle()) {
        return 0;
    }

    g_irq_status_latch = 0u;
    aes_clear_status();
    for (i = 0u; i < 4u; ++i) {
        aes_write(AES_KEY_OFFSET + (i * 4u), key_words[i]);
    }

    aes_write(AES_CONTROL_OFFSET, AES_CTL_APPLY_KEY);
    if (!aes_wait_idle()) {
        return 0;
    }

    status = aes_gcm_status() | g_irq_status_latch;
    return ((status & AES_GCM_ST_KEY_LOADED) != 0u) &&
           ((status & AES_GCM_ST_KEY_BUSY) == 0u);
}

int aes_gcm_encrypt_packet(const u32 plain_words[AES_GCM_WORDS_PLAIN],
                           u32 encrypted_words[AES_GCM_WORDS_PACKET],
                           u32 *final_status)
{
    unsigned int i;
    u32 status = 0u;

    if (!aes_wait_idle()) {
        return 0;
    }

    g_irq_status_latch = 0u;
    aes_clear_status();
    for (i = 0u; i < AES_GCM_WORDS_PLAIN; ++i) {
        aes_write(AES_IN_OFFSET + (i * 4u), plain_words[i]);
    }

    aes_write(AES_CONTROL_OFFSET, AES_CTL_TX_START);
    if (!aes_wait_done(AES_GCM_ST_TX_DONE, &status)) {
        if (final_status != 0) {
            *final_status = status;
        }
        return 0;
    }

    for (i = 0u; i < AES_GCM_WORDS_PACKET; ++i) {
        encrypted_words[i] = aes_read(AES_OUT_OFFSET + (i * 4u));
    }

    if (final_status != 0) {
        *final_status = status;
    }
    return 1;
}

int aes_gcm_decrypt_packet(const u32 encrypted_words[AES_GCM_WORDS_PACKET],
                           u32 plain_words[AES_GCM_WORDS_PACKET],
                           u32 *final_status)
{
    unsigned int i;
    u32 status = 0u;

    if (!aes_wait_idle()) {
        return 0;
    }

    g_irq_status_latch = 0u;
    aes_clear_status();
    for (i = 0u; i < AES_GCM_WORDS_PACKET; ++i) {
        aes_write(AES_IN_OFFSET + (i * 4u), encrypted_words[i]);
    }

    aes_write(AES_CONTROL_OFFSET, AES_CTL_RX_START);
    if (!aes_wait_done(AES_GCM_ST_RX_DONE, &status)) {
        if (final_status != 0) {
            *final_status = status;
        }
        return 0;
    }

    for (i = 0u; i < AES_GCM_WORDS_PACKET; ++i) {
        plain_words[i] = aes_read(AES_OUT_OFFSET + (i * 4u));
    }

    if (final_status != 0) {
        *final_status = status;
    }

    return ((status & AES_GCM_ST_RX_AUTH_FAIL) == 0u) &&
           ((status & AES_GCM_ST_RX_TAG_MATCH) != 0u);
}
