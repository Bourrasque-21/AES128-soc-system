module aes128_demo_master_top #(
    parameter logic [7:0]   VERSION            = 8'h01,
    parameter logic [7:0]   MASTER_DEVICE_ID   = 8'h10,
    parameter logic [7:0]   SLAVE_TARGET_ID    = 8'h20,
    parameter logic [15:0]  MASTER_SOURCE_ID   = 16'h0010,
    parameter logic [127:0] INITIAL_MASTER_KEY = 128'h000102030405060708090a0b0c0d0e0f,
    parameter logic [31:0]  TX_FIXED_IV        = 32'h01010001,
    parameter int           CLK_FREQ           = 100_000_000,
    parameter int           UART_BAUD_RATE     = 921_600,
    parameter int           FRAME_TIMEOUT_CYCLES = CLK_FREQ / 100
) (
    input  logic         clk,
    input  logic         rst,

    input  logic         uart_rx,
    output logic         uart_tx,

    input  logic         send_heartbeat,
    input  logic         send_counter,
    input  logic         send_led_control,
    input  logic         send_read_sw,
    input  logic         send_key_update,
    input  logic [15:0]  counter_value,
    input  logic [7:0]   led_value,
    input  logic [127:0] new_session_key,
    input  logic [15:0]  new_key_epoch,

    output logic         tx_busy_any,
    output logic         rx_response_valid,
    output logic         key_update_done,
    output logic         key_update_pending,
    output logic         auth_error_latched,
    output logic [15:0]  active_key_epoch,
    output logic [7:0]   last_response_command,
    output logic [7:0]   last_response_status,
    output logic [7:0]   last_switch_value
);
    localparam int PACKET_WORDS = 20;
    localparam int TX_IN_WORDS  = 16;
    localparam int PACKET_BYTES = 80;
    localparam int PACKET_BITS  = 640;

    localparam logic [7:0] CMD_HEARTBEAT       = 8'h00;
    localparam logic [7:0] CMD_COUNTER_UPDATE  = 8'h01;
    localparam logic [7:0] CMD_LED_CONTROL     = 8'h02;
    localparam logic [7:0] CMD_READ_SW_REQUEST = 8'h03;
    localparam logic [7:0] CMD_SW_RESPONSE     = 8'h04;
    localparam logic [7:0] CMD_KEY_UPDATE      = 8'h05;
    localparam logic [7:0] CMD_KEY_UPDATE_ACK  = 8'h06;

    localparam int FLAG_COUNTER_VALID = 0;
    localparam int FLAG_LED_VALID     = 1;
    localparam int FLAG_RESPONSE      = 2;

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_LOAD,
        RX_START,
        RX_FEED,
        RX_DRAIN,
        RX_PROCESS
    } rx_state_t;

    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_FEED,
        TX_DRAIN,
        TX_LOAD_FRAME
    } tx_state_t;

    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;
    logic       uart_rx_framing_error;
    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;

    logic [PACKET_BITS-1:0] rx_packet_bits;
    logic rx_packet_valid;
    logic sof_detected;
    logic frame_receiving;
    logic rx_frame_timeout;
    logic [PACKET_BITS-1:0] rx_fifo_packet_shadow;
    logic [6:0] rx_fifo_write_idx;
    logic rx_fifo_write_active;
    logic rx_fifo_push;
    logic rx_fifo_pop;
    logic [7:0] rx_fifo_push_data;
    logic [7:0] rx_fifo_pop_data;
    logic rx_fifo_full;
    logic rx_fifo_empty;
    logic [6:0] rx_byte_idx;
    logic rx_fifo_overrun_error;

    logic tx_frame_load;
    logic [PACKET_BITS-1:0] tx_packet_bits;
    logic tx_frame_busy;
    logic tx_frame_done;

    logic tx_start;
    logic tx_in_valid;
    logic tx_in_ready;
    logic [31:0] tx_in_data;
    logic tx_out_valid;
    logic tx_out_ready;
    logic [31:0] tx_out_data;
    logic tx_busy;
    logic tx_done;
    logic tx_tag_match;
    logic tx_auth_fail;

    logic rx_start;
    logic rx_in_valid;
    logic rx_in_ready;
    logic [31:0] rx_in_data;
    logic rx_out_valid;
    logic rx_out_ready;
    logic [31:0] rx_out_data;
    logic rx_busy;
    logic rx_done;
    logic rx_tag_match;
    logic rx_auth_fail;
    logic [2:0] aes_irq_sources;
    logic       aes_irq_tx_done;
    logic       aes_irq_rx_done;
    logic       aes_irq_rx_auth_fail;
    logic       aes_irq;

    logic [31:0] rx_packet_words [0:PACKET_WORDS-1];
    logic [31:0] rx_plain_words  [0:PACKET_WORDS-1];
    logic [31:0] tx_plain_words  [0:TX_IN_WORDS-1];

    rx_state_t rx_state;
    tx_state_t tx_state;
    logic [4:0] rx_word_idx;
    logic [4:0] rx_out_idx;
    logic [4:0] tx_word_idx;
    logic [4:0] tx_out_idx;

    logic [63:0]  tx_packet_counter;
    logic [127:0] active_key;
    logic [127:0] pending_key;
    logic [15:0]  pending_key_epoch;
    logic [127:0] requested_key;
    logic [15:0]  requested_key_epoch;
    logic         key_update_tx_accept_pulse;
    logic         key_update_commit_pulse;

    wire [7:0]  rx_command       = rx_plain_words[4][31:24];
    wire [15:0] rx_response_epoch = rx_plain_words[4][15:0];
    wire [7:0]  rx_target_id     = rx_plain_words[0][23:16];
    wire        rx_for_master    = (rx_target_id == MASTER_DEVICE_ID) || (rx_target_id == 8'hFF);
    wire        rx_tag_ok        = rx_tag_match && !rx_auth_fail;

    assign rx_in_data   = rx_packet_words[rx_word_idx];
    assign tx_in_data   = tx_plain_words[tx_word_idx];
    assign rx_in_valid  = (rx_state == RX_FEED);
    assign rx_out_ready = (rx_state == RX_DRAIN);
    assign tx_in_valid  = (tx_state == TX_FEED);
    assign tx_out_ready = (tx_state == TX_DRAIN);
    assign rx_fifo_push = rx_fifo_write_active && !rx_fifo_full;
    assign rx_fifo_pop  = (rx_state == RX_LOAD) && !rx_fifo_empty;
    assign tx_busy_any  = (tx_state != TX_IDLE) || tx_busy || tx_frame_busy;

    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (UART_BAUD_RATE)
    ) u_uart_top (
        .clk       (clk),
        .rst_n     (~rst),
        .tx_data   (uart_tx_data),
        .tx_valid  (uart_tx_valid),
        .tx_ready  (uart_tx_ready),
        .tx        (uart_tx),
        .rx        (uart_rx),
        .rx_data   (uart_rx_data),
        .rx_valid  (uart_rx_valid),
        .rx_framing_error (uart_rx_framing_error)
    );

    uart_frame_rx #(
        .PACKET_BYTES (80),
        .SOF          (16'hA55A),
        .FRAME_TIMEOUT_CYCLES (FRAME_TIMEOUT_CYCLES)
    ) u_frame_rx (
        .clk          (clk),
        .rst          (rst),
        .rx_data      (uart_rx_data),
        .rx_valid     (uart_rx_valid),
        .framing_error (uart_rx_framing_error),
        .packet_bits  (rx_packet_bits),
        .packet_valid (rx_packet_valid),
        .sof_detected (sof_detected),
        .frame_timeout (rx_frame_timeout),
        .receiving    (frame_receiving)
    );

    fifo #(
        .DEPTH   (256),
        .D_WIDTH (8)
    ) u_rx_byte_fifo (
        .clk       (clk),
        .rst       (rst),
        .push      (rx_fifo_push),
        .pop       (rx_fifo_pop),
        .push_data (rx_fifo_push_data),
        .pop_data  (rx_fifo_pop_data),
        .full      (rx_fifo_full),
        .empty     (rx_fifo_empty)
    );

    uart_frame_tx #(
        .PACKET_BYTES (80),
        .SOF          (16'hA55A)
    ) u_frame_tx (
        .clk           (clk),
        .rst           (rst),
        .load          (tx_frame_load),
        .packet_bits   (tx_packet_bits),
        .uart_tx_ready (uart_tx_ready),
        .uart_tx_data  (uart_tx_data),
        .uart_tx_valid (uart_tx_valid),
        .busy          (tx_frame_busy),
        .done_pulse    (tx_frame_done)
    );

    aes128_gcm_duplex_packet_top u_aes128_gcm_duplex (
        .clk              (clk),
        .rst_n            (~rst),
        .tx_key           (active_key),
        .rx_key           (active_key),
        .tx_start         (tx_start),
        .tx_in_valid      (tx_in_valid),
        .tx_in_ready      (tx_in_ready),
        .tx_in_data       (tx_in_data),
        .tx_out_valid     (tx_out_valid),
        .tx_out_ready     (tx_out_ready),
        .tx_out_data      (tx_out_data),
        .tx_busy          (tx_busy),
        .tx_done          (tx_done),
        .tx_tag_match     (tx_tag_match),
        .tx_auth_fail     (tx_auth_fail),
        .rx_start         (rx_start),
        .rx_in_valid      (rx_in_valid),
        .rx_in_ready      (rx_in_ready),
        .rx_in_data       (rx_in_data),
        .rx_out_valid     (rx_out_valid),
        .rx_out_ready     (rx_out_ready),
        .rx_out_data      (rx_out_data),
        .rx_busy          (rx_busy),
        .rx_done          (rx_done),
        .rx_tag_match     (rx_tag_match),
        .rx_auth_fail     (rx_auth_fail),
        .irq_sources      (aes_irq_sources),
        .irq_tx_done      (aes_irq_tx_done),
        .irq_rx_done      (aes_irq_rx_done),
        .irq_rx_auth_fail (aes_irq_rx_auth_fail),
        .irq              (aes_irq)
    );

    function automatic [7:0] packet_byte_from_bits(
        input logic [PACKET_BITS-1:0] packet,
        input int idx
    );
        packet_byte_from_bits = packet[PACKET_BITS-1-(idx*8) -: 8];
    endfunction

    always_comb begin
        rx_fifo_push_data = packet_byte_from_bits(rx_fifo_packet_shadow, rx_fifo_write_idx);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active_key         <= INITIAL_MASTER_KEY;
            active_key_epoch   <= 16'h0000;
            pending_key        <= INITIAL_MASTER_KEY;
            pending_key_epoch  <= 16'h0000;
            key_update_pending <= 1'b0;
        end else begin
            if (key_update_tx_accept_pulse) begin
                pending_key        <= requested_key;
                pending_key_epoch  <= requested_key_epoch;
                key_update_pending <= 1'b1;
            end

            if (key_update_commit_pulse) begin
                active_key         <= pending_key;
                active_key_epoch   <= pending_key_epoch;
                key_update_pending <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_fifo_packet_shadow <= '0;
            rx_fifo_write_idx     <= '0;
            rx_fifo_write_active  <= 1'b0;
            rx_fifo_overrun_error <= 1'b0;
        end else begin
            rx_fifo_overrun_error <= 1'b0;
            if (rx_packet_valid) begin
                if (!rx_fifo_write_active) begin
                    rx_fifo_packet_shadow <= rx_packet_bits;
                    rx_fifo_write_idx     <= '0;
                    rx_fifo_write_active  <= 1'b1;
                end else begin
                    rx_fifo_overrun_error <= 1'b1;
                end
            end else if (rx_fifo_write_active && !rx_fifo_full) begin
                if (rx_fifo_write_idx == PACKET_BYTES - 1) begin
                    rx_fifo_write_idx    <= '0;
                    rx_fifo_write_active <= 1'b0;
                end else begin
                    rx_fifo_write_idx <= rx_fifo_write_idx + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state              <= RX_IDLE;
            rx_word_idx           <= '0;
            rx_out_idx            <= '0;
            rx_byte_idx           <= '0;
            rx_start              <= 1'b0;
            rx_response_valid     <= 1'b0;
            key_update_done       <= 1'b0;
            key_update_commit_pulse <= 1'b0;
            auth_error_latched    <= 1'b0;
            last_response_command <= 8'h00;
            last_response_status  <= 8'h00;
            last_switch_value     <= 8'h00;
            for (int i = 0; i < PACKET_WORDS; i++) begin
                rx_packet_words[i] <= 32'h00000000;
                rx_plain_words[i]  <= 32'h00000000;
            end
        end else begin
            rx_start                <= 1'b0;
            rx_response_valid       <= 1'b0;
            key_update_done         <= 1'b0;
            key_update_commit_pulse <= 1'b0;
            if (uart_rx_framing_error || rx_fifo_overrun_error || rx_frame_timeout) begin
                auth_error_latched <= 1'b1;
            end

            unique case (rx_state)
                RX_IDLE: begin
                    if (!rx_fifo_empty) begin
                        rx_byte_idx <= '0;
                        for (int i = 0; i < PACKET_WORDS; i++) begin
                            rx_packet_words[i] <= 32'h00000000;
                        end
                        rx_state <= RX_LOAD;
                    end
                end

                RX_LOAD: begin
                    if (rx_fifo_pop) begin
                        unique case (rx_byte_idx[1:0])
                            2'd0: rx_packet_words[rx_byte_idx[6:2]][31:24] <= rx_fifo_pop_data;
                            2'd1: rx_packet_words[rx_byte_idx[6:2]][23:16] <= rx_fifo_pop_data;
                            2'd2: rx_packet_words[rx_byte_idx[6:2]][15:8]  <= rx_fifo_pop_data;
                            default: rx_packet_words[rx_byte_idx[6:2]][7:0] <= rx_fifo_pop_data;
                        endcase

                        if (rx_byte_idx == PACKET_BYTES - 1) begin
                            rx_word_idx <= '0;
                            rx_byte_idx <= '0;
                            rx_state    <= RX_START;
                        end else begin
                            rx_byte_idx <= rx_byte_idx + 1'b1;
                        end
                    end
                end

                RX_START: begin
                    rx_start    <= 1'b1;
                    rx_word_idx <= '0;
                    rx_state    <= RX_FEED;
                end

                RX_FEED: begin
                    if (rx_in_ready) begin
                        if (rx_word_idx == PACKET_WORDS - 1) begin
                            rx_out_idx <= '0;
                            rx_state   <= RX_DRAIN;
                        end else begin
                            rx_word_idx <= rx_word_idx + 1'b1;
                        end
                    end
                end

                RX_DRAIN: begin
                    if (rx_out_valid) begin
                        rx_plain_words[rx_out_idx] <= rx_out_data;
                        if (rx_out_idx == PACKET_WORDS - 1) begin
                            rx_state <= RX_PROCESS;
                        end else begin
                            rx_out_idx <= rx_out_idx + 1'b1;
                        end
                    end
                end

                RX_PROCESS: begin
                    if (rx_tag_ok && rx_for_master) begin
                        rx_response_valid     <= 1'b1;
                        auth_error_latched    <= 1'b0;
                        last_response_command <= rx_command;
                        last_response_status  <= rx_plain_words[5][15:8];
                        last_switch_value     <= rx_plain_words[5][23:16];

                        if ((rx_command == CMD_KEY_UPDATE_ACK) &&
                            key_update_pending &&
                            (rx_response_epoch == pending_key_epoch)) begin
                            key_update_commit_pulse <= 1'b1;
                            key_update_done         <= 1'b1;
                        end
                    end else if (!rx_tag_ok) begin
                        auth_error_latched <= 1'b1;
                    end

                    rx_state <= RX_IDLE;
                end

                default: begin
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state                   <= TX_IDLE;
            tx_word_idx                <= '0;
            tx_out_idx                 <= '0;
            tx_start                   <= 1'b0;
            tx_frame_load              <= 1'b0;
            tx_packet_counter          <= 64'd1;
            tx_packet_bits             <= '0;
            key_update_tx_accept_pulse <= 1'b0;
            requested_key              <= INITIAL_MASTER_KEY;
            requested_key_epoch        <= 16'h0000;
            for (int i = 0; i < TX_IN_WORDS; i++) begin
                tx_plain_words[i] <= 32'h00000000;
            end
        end else begin
            tx_start                   <= 1'b0;
            tx_frame_load              <= 1'b0;
            key_update_tx_accept_pulse <= 1'b0;

            unique case (tx_state)
                TX_IDLE: begin
                    if (!tx_frame_busy) begin
                        if (send_key_update && !key_update_pending) begin
                            tx_plain_words[0] <= {VERSION, SLAVE_TARGET_ID, MASTER_SOURCE_ID};
                            tx_plain_words[1] <= TX_FIXED_IV;
                            tx_plain_words[2] <= tx_packet_counter[63:32];
                            tx_plain_words[3] <= tx_packet_counter[31:0];
                            tx_plain_words[4] <= {CMD_KEY_UPDATE, 8'h00, new_key_epoch};
                            tx_plain_words[5] <= new_session_key[127:96];
                            tx_plain_words[6] <= new_session_key[95:64];
                            tx_plain_words[7] <= new_session_key[63:32];
                            tx_plain_words[8] <= new_session_key[31:0];
                            for (int i = 9; i < TX_IN_WORDS; i++) begin
                                tx_plain_words[i] <= 32'h00000000;
                            end
                            requested_key              <= new_session_key;
                            requested_key_epoch        <= new_key_epoch;
                            key_update_tx_accept_pulse <= 1'b1;
                            tx_packet_counter          <= tx_packet_counter + 1'b1;
                            tx_word_idx                <= '0;
                            tx_state                   <= TX_START;
                        end else if (send_counter) begin
                            tx_plain_words[0] <= {VERSION, SLAVE_TARGET_ID, MASTER_SOURCE_ID};
                            tx_plain_words[1] <= TX_FIXED_IV;
                            tx_plain_words[2] <= tx_packet_counter[63:32];
                            tx_plain_words[3] <= tx_packet_counter[31:0];
                            tx_plain_words[4] <= {CMD_COUNTER_UPDATE, 8'h01, counter_value};
                            tx_plain_words[5] <= 32'h00000000;
                            for (int i = 6; i < TX_IN_WORDS; i++) begin
                                tx_plain_words[i] <= 32'h00000000;
                            end
                            tx_packet_counter <= tx_packet_counter + 1'b1;
                            tx_word_idx       <= '0;
                            tx_state          <= TX_START;
                        end else if (send_led_control) begin
                            tx_plain_words[0] <= {VERSION, SLAVE_TARGET_ID, MASTER_SOURCE_ID};
                            tx_plain_words[1] <= TX_FIXED_IV;
                            tx_plain_words[2] <= tx_packet_counter[63:32];
                            tx_plain_words[3] <= tx_packet_counter[31:0];
                            tx_plain_words[4] <= {CMD_LED_CONTROL, 8'h02, 16'h0000};
                            tx_plain_words[5] <= {led_value, 24'h000000};
                            for (int i = 6; i < TX_IN_WORDS; i++) begin
                                tx_plain_words[i] <= 32'h00000000;
                            end
                            tx_packet_counter <= tx_packet_counter + 1'b1;
                            tx_word_idx       <= '0;
                            tx_state          <= TX_START;
                        end else if (send_read_sw) begin
                            tx_plain_words[0] <= {VERSION, SLAVE_TARGET_ID, MASTER_SOURCE_ID};
                            tx_plain_words[1] <= TX_FIXED_IV;
                            tx_plain_words[2] <= tx_packet_counter[63:32];
                            tx_plain_words[3] <= tx_packet_counter[31:0];
                            tx_plain_words[4] <= {CMD_READ_SW_REQUEST, 8'h04, 16'h0000};
                            tx_plain_words[5] <= 32'h00000000;
                            for (int i = 6; i < TX_IN_WORDS; i++) begin
                                tx_plain_words[i] <= 32'h00000000;
                            end
                            tx_packet_counter <= tx_packet_counter + 1'b1;
                            tx_word_idx       <= '0;
                            tx_state          <= TX_START;
                        end else if (send_heartbeat) begin
                            tx_plain_words[0] <= {VERSION, SLAVE_TARGET_ID, MASTER_SOURCE_ID};
                            tx_plain_words[1] <= TX_FIXED_IV;
                            tx_plain_words[2] <= tx_packet_counter[63:32];
                            tx_plain_words[3] <= tx_packet_counter[31:0];
                            tx_plain_words[4] <= {CMD_HEARTBEAT, 8'h00, 16'h0000};
                            tx_plain_words[5] <= 32'h00000000;
                            for (int i = 6; i < TX_IN_WORDS; i++) begin
                                tx_plain_words[i] <= 32'h00000000;
                            end
                            tx_packet_counter <= tx_packet_counter + 1'b1;
                            tx_word_idx       <= '0;
                            tx_state          <= TX_START;
                        end
                    end
                end

                TX_START: begin
                    tx_start    <= 1'b1;
                    tx_word_idx <= '0;
                    tx_state    <= TX_FEED;
                end

                TX_FEED: begin
                    if (tx_in_ready) begin
                        if (tx_word_idx == TX_IN_WORDS - 1) begin
                            tx_out_idx <= '0;
                            tx_state   <= TX_DRAIN;
                        end else begin
                            tx_word_idx <= tx_word_idx + 1'b1;
                        end
                    end
                end

                TX_DRAIN: begin
                    if (tx_out_valid) begin
                        tx_packet_bits[PACKET_BITS-1-(tx_out_idx*32) -: 32] <= tx_out_data;
                        if (tx_out_idx == PACKET_WORDS - 1) begin
                            tx_state <= TX_LOAD_FRAME;
                        end else begin
                            tx_out_idx <= tx_out_idx + 1'b1;
                        end
                    end
                end

                TX_LOAD_FRAME: begin
                    if (!tx_frame_busy) begin
                        tx_frame_load <= 1'b1;
                        tx_state      <= TX_IDLE;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end
endmodule
