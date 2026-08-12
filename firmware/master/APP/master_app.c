#include "master_app.h"

#include "aes_gcm.h"
#include "board_io.h"
#include "console_uart.h"
#include "hal_interrupt.h"
#include "hal_platform.h"
#include "hal_timer.h"
#include "link_uart.h"
#include "protocol.h"

#include "string.h"
#include "xil_printf.h"

#define RX_FRAME_TIMEOUT_TICKS      3u
#define LINK_RESPONSE_TIMEOUT_TICKS 30u
#define HEARTBEAT_PERIOD_TICKS      10u
#define FND_SCAN_DELAY_CYCLES       2500u
#define CONSOLE_LINE_SIZE           80u

#define MASTER_DBG_RESP_OK          0x80u
#define MASTER_DBG_SLAVE_ERROR      0x40u
#define MASTER_DBG_KEY_PENDING      0x20u
#define MASTER_DBG_LOCAL_ERROR      0x10u

typedef enum {
    RX_WAIT_SOF0 = 0,
    RX_WAIT_SOF1,
    RX_READ_FRAME
} rx_state_t;

static const u32 g_initial_key[4] = {
    0x00010203u, 0x04050607u, 0x08090A0Bu, 0x0C0D0E0Fu
};

static const u32 g_session_keys[8][4] = {
    {0x00112233u, 0x44556677u, 0x8899AABBu, 0xCCDDEEFFu},
    {0x10213243u, 0x54657687u, 0x98A9BABBu, 0xDCEDFE0Fu},
    {0xFFEEDDCCu, 0xBBAA9988u, 0x77665544u, 0x33221100u},
    {0x0F1E2D3Cu, 0x4B5A6978u, 0x8796A5B4u, 0xC3D2E1F0u},
    {0x13579BDFu, 0x2468ACE0u, 0x55AA55AAu, 0xAA55AA55u},
    {0xA0A1A2A3u, 0xA4A5A6A7u, 0xA8A9AAABu, 0xACADAEAFu},
    {0xC001D00Du, 0x1234ABCDu, 0x55AA33CCu, 0x0BADF00Du},
    {0xDEADBEEFu, 0xCAFEBABEu, 0x01234567u, 0x89ABCDEFu}
};

static rx_state_t g_rx_state;
static u32 g_rx_words[AES_GCM_WORDS_PACKET];
static u32 g_rx_byte_index;
static u32 g_rx_last_byte_tick;

static u16 g_display_counter;
static u32 g_last_tick;
static u32 g_nonce_hi;
static u32 g_nonce_lo = 1u;
static u32 g_last_valid_response_tick;
static u8 g_tx_seen;

static u8 g_remote_led_value;
static u8 g_last_switch_value;
static u8 g_last_slave_status;
static u8 g_last_response_command;
static u8 g_response_blink_ticks;
static u32 g_link_error_flags;
static u32 g_auth_fail_count;
static u32 g_rx_frame_count;
static u32 g_tx_frame_count;

static u32 g_active_key[4];
static u32 g_pending_key[4];
static u16 g_active_key_epoch;
static u16 g_pending_key_epoch;
static u8 g_key_update_pending;
static u8 g_pending_key_slot;

static char g_line[CONSOLE_LINE_SIZE];
static u32 g_line_len;

static u8 lower_ch(u8 ch)
{
    if ((ch >= 'A') && (ch <= 'Z')) {
        return (u8)(ch + ('a' - 'A'));
    }
    return ch;
}

static int str_eq_ci(const char *a, const char *b)
{
    while ((*a != '\0') && (*b != '\0')) {
        if (lower_ch((u8)*a) != lower_ch((u8)*b)) {
            return 0;
        }
        ++a;
        ++b;
    }
    return (*a == '\0') && (*b == '\0');
}

static int starts_with_ci(const char *text, const char *prefix)
{
    while (*prefix != '\0') {
        if (lower_ch((u8)*text) != lower_ch((u8)*prefix)) {
            return 0;
        }
        ++text;
        ++prefix;
    }
    return 1;
}

static const char *skip_spaces(const char *text)
{
    while ((*text == ' ') || (*text == '\t')) {
        ++text;
    }
    return text;
}

static int hex_digit(u8 ch, u8 *value)
{
    if ((ch >= '0') && (ch <= '9')) {
        *value = (u8)(ch - '0');
        return 1;
    }
    if ((ch >= 'a') && (ch <= 'f')) {
        *value = (u8)(10u + ch - 'a');
        return 1;
    }
    if ((ch >= 'A') && (ch <= 'F')) {
        *value = (u8)(10u + ch - 'A');
        return 1;
    }
    return 0;
}

static int parse_hex_u8(const char *text, u8 *value)
{
    u8 hi;
    u8 lo;

    text = skip_spaces(text);
    if (!hex_digit((u8)text[0], &hi)) {
        return 0;
    }
    if (!hex_digit((u8)text[1], &lo)) {
        *value = hi;
        return 1;
    }

    *value = (u8)((hi << 4) | lo);
    return 1;
}

static u8 selected_key_slot_from_switch(void)
{
    return (u8)((board_io_read_switches() >> 1) & 0x07u);
}

static void copy_key(u32 dst[4], const u32 src[4])
{
    unsigned int i;

    for (i = 0u; i < 4u; ++i) {
        dst[i] = src[i];
    }
}

static void rx_reset(void)
{
    unsigned int i;

    g_rx_state = RX_WAIT_SOF0;
    g_rx_byte_index = 0u;
    for (i = 0u; i < AES_GCM_WORDS_PACKET; ++i) {
        g_rx_words[i] = 0u;
    }
}

static void next_nonce(u32 *hi, u32 *lo)
{
    *hi = g_nonce_hi;
    *lo = g_nonce_lo;

    ++g_nonce_lo;
    if (g_nonce_lo == 0u) {
        ++g_nonce_hi;
    }
}

static int send_frame_words(const u32 words[AES_GCM_WORDS_PACKET])
{
    unsigned int i;

    if (!link_uart_send_byte(PROTO_SOF0) || !link_uart_send_byte(PROTO_SOF1)) {
        g_link_error_flags |= MASTER_DBG_LOCAL_ERROR;
        return 0;
    }

    for (i = 0u; i < AES_GCM_WORDS_PACKET; ++i) {
        if (!link_uart_send_byte((u8)((words[i] >> 24) & 0xFFu)) ||
            !link_uart_send_byte((u8)((words[i] >> 16) & 0xFFu)) ||
            !link_uart_send_byte((u8)((words[i] >> 8) & 0xFFu)) ||
            !link_uart_send_byte((u8)(words[i] & 0xFFu))) {
            g_link_error_flags |= MASTER_DBG_LOCAL_ERROR;
            return 0;
        }
    }

    ++g_tx_frame_count;
    g_tx_seen = 1u;
    return 1;
}

static int should_print_request(u8 command)
{
    return (command == CMD_READ_SW_REQUEST);
}

static int send_plain_packet(u8 command,
                             u8 flags,
                             u16 arg,
                             u8 led_value,
                             const u32 key_update_words[4],
                             u16 key_epoch,
                             u8 verbose)
{
    u32 plain[AES_GCM_WORDS_PLAIN];
    u32 encrypted[AES_GCM_WORDS_PACKET];
    u32 aes_status = 0u;
    u32 nonce_hi;
    u32 nonce_lo;

    if (g_key_update_pending && (command != CMD_KEY_UPDATE)) {
        return 0;
    }

    next_nonce(&nonce_hi, &nonce_lo);
    protocol_build_plain(plain, command, flags, arg, led_value, 0u, 0u,
                         nonce_hi, nonce_lo);

    if (command == CMD_KEY_UPDATE) {
        protocol_put_key_update(plain, key_epoch, key_update_words);
    }

    if (!aes_gcm_encrypt_packet(plain, encrypted, &aes_status)) {
        if (verbose) {
            xil_printf("FAIL: AES encrypt failed, status=0x%x\r\n", aes_status);
        }
        g_link_error_flags |= MASTER_DBG_LOCAL_ERROR;
        return 0;
    }

    if (!send_frame_words(encrypted)) {
        if (verbose) {
            xil_printf("FAIL: UART frame TX failed, status=0x%x\r\n", link_uart_status());
        }
        return 0;
    }

    if (verbose && should_print_request(command)) {
        xil_printf("TX %s flags=0x%x arg=0x%x led=0x%x\r\n",
                   protocol_command_name(command), flags, arg, led_value);
    }
    return 1;
}

static int send_heartbeat(u8 verbose)
{
    return send_plain_packet(CMD_HEARTBEAT, FLAG_RESPONSE, 0u,
                             0u, 0, 0u, verbose);
}

static int send_counter_update(u8 verbose)
{
    return send_plain_packet(CMD_COUNTER_UPDATE,
                             FLAG_COUNTER_VALID | FLAG_RESPONSE,
                             g_display_counter,
                             g_remote_led_value,
                             0, 0u, verbose);
}

static int send_led_control(u8 led_value, u8 verbose)
{
    g_remote_led_value = led_value;
    return send_plain_packet(CMD_LED_CONTROL,
                             FLAG_LED_VALID | FLAG_RESPONSE,
                             g_display_counter,
                             g_remote_led_value,
                             0, 0u, verbose);
}

static int send_switch_read(u8 verbose)
{
    return send_plain_packet(CMD_READ_SW_REQUEST,
                             FLAG_RESPONSE,
                             g_display_counter,
                             g_remote_led_value,
                             0, 0u, verbose);
}

static int send_key_update(u8 slot)
{
    if (g_key_update_pending) {
        xil_printf("KEY_UPDATE already pending: epoch=%d slot=%d\r\n",
                   (int)g_pending_key_epoch, (int)g_pending_key_slot);
        return 0;
    }
    if (g_active_key_epoch == 0xFFFFu) {
        xil_printf("FAIL: key epoch reached 0xffff\r\n");
        return 0;
    }

    slot &= 0x07u;
    g_pending_key_epoch = (u16)(g_active_key_epoch + 1u);
    g_pending_key_slot = slot;
    copy_key(g_pending_key, g_session_keys[slot]);

    if (!send_plain_packet(CMD_KEY_UPDATE,
                           FLAG_RESPONSE,
                           g_pending_key_epoch,
                           g_remote_led_value,
                           g_pending_key,
                           g_pending_key_epoch,
                           1u)) {
        return 0;
    }

    g_key_update_pending = 1u;
    xil_printf("KEY_UPDATE sent: slot=%d pending_epoch=%d\r\n",
               (int)slot, (int)g_pending_key_epoch);
    return 1;
}

static void commit_pending_key(void)
{
    copy_key(g_active_key, g_pending_key);
    if (aes_gcm_set_key(g_active_key)) {
        g_active_key_epoch = g_pending_key_epoch;
        g_key_update_pending = 0u;
        xil_printf("KEY_UPDATE_ACK accepted: active_epoch=%d slot=%d\r\n",
                   (int)g_active_key_epoch, (int)g_pending_key_slot);
    } else {
        g_link_error_flags |= MASTER_DBG_LOCAL_ERROR;
        xil_printf("FAIL: AES key apply failed after KEY_UPDATE_ACK\r\n");
    }
}

static void process_plain_response(const u32 plain[AES_GCM_WORDS_PACKET],
                                   u32 aes_status)
{
    protocol_payload_t payload;

    (void)aes_status;
    protocol_parse_payload(plain, &payload);
    g_last_response_command = payload.command;
    g_last_slave_status = payload.status;
    g_last_switch_value = payload.switch_value;
    g_last_valid_response_tick = hal_timer_ticks_100ms();
    g_response_blink_ticks = 2u;

    if (payload.status != 0u) {
        xil_printf("SLAVE STATUS ERROR: cmd=%s status=0x%x\r\n",
                   protocol_command_name(payload.command), payload.status);
    }

    if (payload.command == CMD_SW_RESPONSE) {
        xil_printf("SW_RESPONSE: sw=0x%x status=0x%x\r\n",
                   payload.switch_value, payload.status);
    } else if (payload.command == CMD_KEY_UPDATE_ACK) {
        if (g_key_update_pending && (payload.arg == g_pending_key_epoch)) {
            commit_pending_key();
        } else {
            g_link_error_flags |= MASTER_DBG_LOCAL_ERROR;
            xil_printf("Unexpected KEY_UPDATE_ACK: arg=0x%x pending=%d epoch=0x%x\r\n",
                       payload.arg, (int)g_key_update_pending, g_pending_key_epoch);
        }
    }
}

static void process_received_frame(void)
{
    u32 plain[AES_GCM_WORDS_PACKET];
    u32 aes_status = 0u;
    int ok;

    ++g_rx_frame_count;
    ok = aes_gcm_decrypt_packet(g_rx_words, plain, &aes_status);
    if (ok) {
        process_plain_response(plain, aes_status);
    } else {
        ++g_auth_fail_count;
        g_last_slave_status |= SLAVE_STATUS_AUTH_FAIL;
        g_link_error_flags |= MASTER_DBG_LOCAL_ERROR;
        xil_printf("FAIL: slave packet auth failed, aes_status=0x%x\r\n", aes_status);
    }
}

static void process_link_rx(void)
{
    u8 ch;
    u32 word_index;
    u32 now = hal_timer_ticks_100ms();
    u32 errors = link_uart_take_errors();

    if (errors != 0u) {
        g_link_error_flags |= errors;
        rx_reset();
        xil_printf("LINK UART ERROR: 0x%x\r\n", errors);
    }

    while (link_uart_getc(&ch)) {
        now = hal_timer_ticks_100ms();

        switch (g_rx_state) {
        case RX_WAIT_SOF0:
            if (ch == PROTO_SOF0) {
                g_rx_state = RX_WAIT_SOF1;
            }
            break;

        case RX_WAIT_SOF1:
            if (ch == PROTO_SOF1) {
                rx_reset();
                g_rx_state = RX_READ_FRAME;
                g_rx_last_byte_tick = now;
            } else if (ch == PROTO_SOF0) {
                g_rx_state = RX_WAIT_SOF1;
            } else {
                g_rx_state = RX_WAIT_SOF0;
            }
            break;

        case RX_READ_FRAME:
            g_rx_last_byte_tick = now;
            word_index = g_rx_byte_index >> 2;
            g_rx_words[word_index] = (g_rx_words[word_index] << 8) | (u32)ch;
            ++g_rx_byte_index;

            if (g_rx_byte_index >= AES_GCM_FRAME_BYTES) {
                g_rx_state = RX_WAIT_SOF0;
                g_rx_byte_index = 0u;
                process_received_frame();
                rx_reset();
            }
            break;

        default:
            rx_reset();
            break;
        }
    }
}

static void check_rx_watchdog(void)
{
    u32 now = hal_timer_ticks_100ms();

    if ((g_rx_state == RX_READ_FRAME) &&
        ((now - g_rx_last_byte_tick) > RX_FRAME_TIMEOUT_TICKS)) {
        g_link_error_flags |= SLAVE_STATUS_BYTE_TIMEOUT;
        xil_printf("RX watchdog: partial frame discarded at byte=%d\r\n",
                   (int)g_rx_byte_index);
        rx_reset();
    }
}

static void update_leds(void)
{
    u8 sw = board_io_read_switches();
    u8 led = (u8)(sw & 0x0Fu);
    u32 now = hal_timer_ticks_100ms();

    if (g_response_blink_ticks != 0u) {
        led |= MASTER_DBG_RESP_OK;
    }
    if (g_last_slave_status != 0u) {
        led |= MASTER_DBG_SLAVE_ERROR;
    }
    if (g_key_update_pending) {
        led |= MASTER_DBG_KEY_PENDING;
    }
    if ((g_link_error_flags != 0u) ||
        (g_auth_fail_count != 0u) ||
        (g_tx_seen && ((now - g_last_valid_response_tick) > LINK_RESPONSE_TIMEOUT_TICKS))) {
        led |= MASTER_DBG_LOCAL_ERROR;
    }

    board_io_set_leds(led);
}

static void print_help(void)
{
    xil_printf("\r\nCommands\r\n");
    xil_printf("  help | h        : print help\r\n");
    xil_printf("  status | s      : print master/slave state\r\n");
    xil_printf("  hb | p          : send HEARTBEAT now\r\n");
    xil_printf("  counter | c     : send COUNTER_UPDATE now\r\n");
    xil_printf("  read | r        : send READ_SW_REQUEST\r\n");
    xil_printf("  led XX          : set slave upper LEDs with hex byte\r\n");
    xil_printf("  key             : send KEY_UPDATE using SW[3:1] slot\r\n");
    xil_printf("  key N           : send KEY_UPDATE using slot 0..7\r\n");
    xil_printf("  clear           : clear local error counters\r\n");
    xil_printf("\r\nSwitch policy\r\n");
    xil_printf("  SW[0]=0 : heartbeat only, 1 packet/sec\r\n");
    xil_printf("  SW[0]=1 : counter update, 10 packets/sec\r\n");
    xil_printf("  SW[3:1] : session-key slot used by 'key'\r\n");
}

static void print_status(void)
{
    u8 sw = board_io_read_switches();

    xil_printf("\r\n[MASTER STATUS]\r\n");
    xil_printf("ticks=%d counter=0x%x sw=0x%x mode=%s key_slot=%d\r\n",
               (int)hal_timer_ticks_100ms(),
               g_display_counter,
               sw,
               ((sw & 0x01u) != 0u) ? "COUNTER_RUN" : "HEARTBEAT",
               (int)selected_key_slot_from_switch());
    xil_printf("tx_frames=%d rx_frames=%d last_cmd=%s slave_sw=0x%x slave_status=0x%x\r\n",
               (int)g_tx_frame_count,
               (int)g_rx_frame_count,
               protocol_command_name(g_last_response_command),
               g_last_switch_value,
               g_last_slave_status);
    xil_printf("key_epoch=%d pending=%d pending_epoch=%d pending_slot=%d\r\n",
               (int)g_active_key_epoch,
               (int)g_key_update_pending,
               (int)g_pending_key_epoch,
               (int)g_pending_key_slot);
    xil_printf("uart_errors=0x%x auth_fail_count=%d aes_status=0x%x console_err=0x%x\r\n",
               g_link_error_flags,
               (int)g_auth_fail_count,
               aes_gcm_status(),
               console_uart_error_flags());
}

static void clear_errors(void)
{
    g_link_error_flags = 0u;
    g_auth_fail_count = 0u;
    g_last_slave_status = 0u;
    console_uart_clear_errors();
    link_uart_send_break_clear();
    rx_reset();
    xil_printf("Local errors cleared.\r\n");
}

static void handle_console_line(const char *line)
{
    u8 value;
    u8 slot;

    line = skip_spaces(line);
    if (*line == '\0') {
        return;
    }

    if (str_eq_ci(line, "h") || str_eq_ci(line, "help") || str_eq_ci(line, "?")) {
        print_help();
    } else if (str_eq_ci(line, "s") || str_eq_ci(line, "status")) {
        print_status();
    } else if (str_eq_ci(line, "p") || str_eq_ci(line, "hb") || str_eq_ci(line, "heartbeat")) {
        (void)send_heartbeat(1u);
    } else if (str_eq_ci(line, "c") || str_eq_ci(line, "counter")) {
        (void)send_counter_update(1u);
    } else if (str_eq_ci(line, "r") || str_eq_ci(line, "read")) {
        (void)send_switch_read(1u);
    } else if (starts_with_ci(line, "led")) {
        if (parse_hex_u8(line + 3, &value)) {
            (void)send_led_control(value, 1u);
        } else {
            xil_printf("Usage: led XX\r\n");
        }
    } else if (starts_with_ci(line, "key")) {
        line = skip_spaces(line + 3);
        if ((*line >= '0') && (*line <= '7')) {
            slot = (u8)(*line - '0');
        } else {
            slot = selected_key_slot_from_switch();
        }
        (void)send_key_update(slot);
    } else if (str_eq_ci(line, "clear")) {
        clear_errors();
    } else {
        xil_printf("Unknown command: %s\r\n", line);
        xil_printf("Type 'help'.\r\n");
    }
}

static void process_console(void)
{
    u8 ch;

    while (console_uart_getc(&ch)) {
        if ((ch == '\r') || (ch == '\n')) {
            g_line[g_line_len] = '\0';
            xil_printf("\r\n");
            handle_console_line(g_line);
            g_line_len = 0u;
            xil_printf("> ");
        } else if ((ch == 0x08u) || (ch == 0x7Fu)) {
            if (g_line_len != 0u) {
                --g_line_len;
            }
        } else if ((ch >= 0x20u) && (ch <= 0x7Eu)) {
            if (g_line_len < (CONSOLE_LINE_SIZE - 1u)) {
                g_line[g_line_len] = (char)ch;
                ++g_line_len;
            }
        }
    }
}

static void process_tick(u32 tick)
{
    u8 sw = board_io_read_switches();

    ++g_display_counter;

    if (g_response_blink_ticks != 0u) {
        --g_response_blink_ticks;
    }

    check_rx_watchdog();

    if (g_key_update_pending) {
        return;
    }

    if ((sw & 0x01u) != 0u) {
        (void)send_counter_update(0u);
    } else if ((tick % HEARTBEAT_PERIOD_TICKS) == 0u) {
        (void)send_heartbeat(0u);
    }
}

static void process_ticks(void)
{
    u32 now = hal_timer_ticks_100ms();

    while (g_last_tick != now) {
        ++g_last_tick;
        process_tick(g_last_tick);
    }
}

void master_app_init(void)
{
    hal_interrupt_init();
    board_io_init();
    board_io_blank_fnd();
    console_uart_init();
    link_uart_init();
    aes_gcm_init();
    hal_timer_init_100ms();

    copy_key(g_active_key, g_initial_key);
    (void)aes_gcm_set_key(g_active_key);

    rx_reset();
    g_last_tick = hal_timer_ticks_100ms();
    g_last_valid_response_tick = g_last_tick;
    hal_interrupt_enable_global();

    xil_printf("\r\nAES-128 GCM Master layered firmware\r\n");
    xil_printf("PC UART: 115200-8-N-1, Link UART: 921600-8-N-1\r\n");
    xil_printf("Interrupt IDs: AES=%d TIMER=%d PC_UART=%d LINK_UART=%d\r\n",
               (int)HAL_INTR_ID_AES,
               (int)HAL_INTR_ID_TIMER,
               (int)HAL_INTR_ID_PC_UART,
               (int)HAL_INTR_ID_LINK_UART);
    print_help();
    xil_printf("\r\n> ");
}

void master_app_run(void)
{
    while (1) {
        process_ticks();
        process_link_rx();
        process_console();
        update_leds();
        board_io_refresh_fnd_hex(g_display_counter, hal_timer_dot_visible());
        board_io_delay_cycles(FND_SCAN_DELAY_CYCLES);
    }
}
