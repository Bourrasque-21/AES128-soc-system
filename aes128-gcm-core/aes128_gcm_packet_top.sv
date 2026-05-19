module aes128_gcm_packet_top (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        decrypt,
    input  logic [127:0] key,

    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] in_data,

    output logic        out_valid,
    input  logic        out_ready,
    output logic [31:0] out_data,

    output logic        busy,
    output logic        done,
    output logic        tag_match,
    output logic        auth_fail
);
    typedef enum logic [4:0] {
        P_IDLE,
        P_INPUT,
        P_AES_H_START,
        P_AES_H_WAIT,
        P_AES_J0_START,
        P_AES_J0_WAIT,
        P_GHASH_AAD_START,
        P_GHASH_AAD_WAIT,
        P_AES_PAYLOAD_START,
        P_AES_PAYLOAD_WAIT,
        P_GHASH_PAYLOAD_START,
        P_GHASH_PAYLOAD_WAIT,
        P_GHASH_LEN_START,
        P_GHASH_LEN_WAIT,
        P_OUTPUT
    } packet_state_t;

    localparam logic [127:0] ZERO_BLOCK   = 128'h0;
    localparam logic [127:0] LENGTH_BLOCK = {64'd128, 64'd384};

    packet_state_t state;

    logic         decrypt_reg;
    logic [4:0]   in_count;
    logic [4:0]   out_count;
    logic [1:0]   payload_index;
    logic [127:0] aad_block;
    logic [127:0] payload_in  [0:2];
    logic [127:0] payload_out [0:2];
    logic [127:0] tag_in_block;
    logic [127:0] tag_reg;
    logic [127:0] h_reg;
    logic [127:0] tag_mask_reg;
    logic [127:0] ghash_y_reg;
    logic [127:0] hash_block_reg;
    logic [95:0]  nonce;
    logic [127:0] aes_plaintext;
    logic [127:0] aes_ciphertext;
    logic         aes_start;
    logic         aes_busy;
    logic         aes_done;
    logic [127:0] ghash_data_in;
    logic [127:0] ghash_y_in;
    logic [127:0] ghash_y_out;
    logic         ghash_start;
    logic         ghash_busy;
    logic         ghash_done;
    logic [127:0] final_tag;
    logic [4:0]   input_last_word;
    integer       reset_idx;

    aes128_core u_aes128_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (aes_start),
        .plaintext  (aes_plaintext),
        .key        (key),
        .ciphertext (aes_ciphertext),
        .busy       (aes_busy),
        .done       (aes_done)
    );

    ghash_engine_seq u_ghash_engine_seq (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (ghash_start),
        .h       (h_reg),
        .data_in (ghash_data_in),
        .y_in    (ghash_y_in),
        .y_out   (ghash_y_out),
        .busy    (ghash_busy),
        .done    (ghash_done)
    );

    // AAD[127:96] is protocol metadata. AAD[95:0] carries the 96-bit GCM IV.
    assign nonce = aad_block[95:0];
    assign input_last_word = decrypt_reg ? 5'd19 : 5'd15;
    assign aes_start = (state == P_AES_H_START) ||
                       (state == P_AES_J0_START) ||
                       (state == P_AES_PAYLOAD_START);
    assign ghash_start = (state == P_GHASH_AAD_START) ||
                         (state == P_GHASH_PAYLOAD_START) ||
                         (state == P_GHASH_LEN_START);
    assign in_ready  = (state == P_INPUT);
    assign out_valid = (state == P_OUTPUT);
    assign busy      = (state != P_IDLE);
    assign done      = (state == P_OUTPUT) && out_valid && out_ready && (out_count == 5'd19);
    assign final_tag = tag_mask_reg ^ ghash_y_out;

    always_comb begin
        aes_plaintext = ZERO_BLOCK;
        unique case (state)
            P_AES_H_START: begin
                aes_plaintext = ZERO_BLOCK;
            end

            P_AES_J0_START: begin
                aes_plaintext = {nonce, 32'h00000001};
            end

            P_AES_PAYLOAD_START: begin
                aes_plaintext = {nonce, 32'h00000002 + {30'h0, payload_index}};
            end

            default: begin
                aes_plaintext = ZERO_BLOCK;
            end
        endcase
    end

    always_comb begin
        ghash_data_in = 128'h0;
        ghash_y_in    = 128'h0;
        unique case (state)
            P_GHASH_AAD_START: begin
                ghash_data_in = aad_block;
                ghash_y_in    = 128'h0;
            end

            P_GHASH_PAYLOAD_START: begin
                ghash_data_in = hash_block_reg;
                ghash_y_in    = ghash_y_reg;
            end

            P_GHASH_LEN_START: begin
                ghash_data_in = LENGTH_BLOCK;
                ghash_y_in    = ghash_y_reg;
            end

            default: begin
                ghash_data_in = 128'h0;
                ghash_y_in    = 128'h0;
            end
        endcase
    end

    always_comb begin
        out_data = 32'h00000000;
        unique case (out_count)
            5'd0:  out_data = aad_block[127:96];
            5'd1:  out_data = aad_block[95:64];
            5'd2:  out_data = aad_block[63:32];
            5'd3:  out_data = aad_block[31:0];
            5'd4:  out_data = payload_out[0][127:96];
            5'd5:  out_data = payload_out[0][95:64];
            5'd6:  out_data = payload_out[0][63:32];
            5'd7:  out_data = payload_out[0][31:0];
            5'd8:  out_data = payload_out[1][127:96];
            5'd9:  out_data = payload_out[1][95:64];
            5'd10: out_data = payload_out[1][63:32];
            5'd11: out_data = payload_out[1][31:0];
            5'd12: out_data = payload_out[2][127:96];
            5'd13: out_data = payload_out[2][95:64];
            5'd14: out_data = payload_out[2][63:32];
            5'd15: out_data = payload_out[2][31:0];
            5'd16: out_data = tag_reg[127:96];
            5'd17: out_data = tag_reg[95:64];
            5'd18: out_data = tag_reg[63:32];
            5'd19: out_data = tag_reg[31:0];
            default: out_data = 32'h00000000;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= P_IDLE;
            decrypt_reg    <= 1'b0;
            in_count       <= 5'd0;
            out_count      <= 5'd0;
            payload_index  <= 2'd0;
            aad_block      <= 128'h0;
            tag_in_block   <= 128'h0;
            tag_reg        <= 128'h0;
            h_reg          <= 128'h0;
            tag_mask_reg   <= 128'h0;
            ghash_y_reg    <= 128'h0;
            hash_block_reg <= 128'h0;
            tag_match      <= 1'b0;
            auth_fail      <= 1'b0;
            for (reset_idx = 0; reset_idx < 3; reset_idx = reset_idx + 1) begin
                payload_in[reset_idx]  <= 128'h0;
                payload_out[reset_idx] <= 128'h0;
            end
        end else begin
            unique case (state)
                P_IDLE: begin
                    if (start) begin
                        decrypt_reg    <= decrypt;
                        in_count       <= 5'd0;
                        out_count      <= 5'd0;
                        payload_index  <= 2'd0;
                        aad_block      <= 128'h0;
                        tag_in_block   <= 128'h0;
                        tag_reg        <= 128'h0;
                        h_reg          <= 128'h0;
                        tag_mask_reg   <= 128'h0;
                        ghash_y_reg    <= 128'h0;
                        hash_block_reg <= 128'h0;
                        tag_match      <= 1'b0;
                        auth_fail      <= 1'b0;
                        for (reset_idx = 0; reset_idx < 3; reset_idx = reset_idx + 1) begin
                            payload_in[reset_idx]  <= 128'h0;
                            payload_out[reset_idx] <= 128'h0;
                        end
                        state <= P_INPUT;
                    end
                end

                P_INPUT: begin
                    if (in_valid && in_ready) begin
                        unique case (in_count)
                            5'd0:  aad_block[127:96]      <= in_data;
                            5'd1:  aad_block[95:64]       <= in_data;
                            5'd2:  aad_block[63:32]       <= in_data;
                            5'd3:  aad_block[31:0]        <= in_data;
                            5'd4:  payload_in[0][127:96]  <= in_data;
                            5'd5:  payload_in[0][95:64]   <= in_data;
                            5'd6:  payload_in[0][63:32]   <= in_data;
                            5'd7:  payload_in[0][31:0]    <= in_data;
                            5'd8:  payload_in[1][127:96]  <= in_data;
                            5'd9:  payload_in[1][95:64]   <= in_data;
                            5'd10: payload_in[1][63:32]   <= in_data;
                            5'd11: payload_in[1][31:0]    <= in_data;
                            5'd12: payload_in[2][127:96]  <= in_data;
                            5'd13: payload_in[2][95:64]   <= in_data;
                            5'd14: payload_in[2][63:32]   <= in_data;
                            5'd15: payload_in[2][31:0]    <= in_data;
                            5'd16: tag_in_block[127:96]   <= in_data;
                            5'd17: tag_in_block[95:64]    <= in_data;
                            5'd18: tag_in_block[63:32]    <= in_data;
                            5'd19: tag_in_block[31:0]     <= in_data;
                            default: begin
                            end
                        endcase

                        if (in_count == input_last_word) begin
                            in_count <= 5'd0;
                            state    <= P_AES_H_START;
                        end else begin
                            in_count <= in_count + 5'd1;
                        end
                    end
                end

                P_AES_H_START: begin
                    state <= P_AES_H_WAIT;
                end

                P_AES_H_WAIT: begin
                    if (aes_done) begin
                        h_reg <= aes_ciphertext;
                        state <= P_AES_J0_START;
                    end
                end

                P_AES_J0_START: begin
                    state <= P_AES_J0_WAIT;
                end

                P_AES_J0_WAIT: begin
                    if (aes_done) begin
                        tag_mask_reg  <= aes_ciphertext;
                        payload_index <= 2'd0;
                        state         <= P_GHASH_AAD_START;
                    end
                end

                P_GHASH_AAD_START: begin
                    state <= P_GHASH_AAD_WAIT;
                end

                P_GHASH_AAD_WAIT: begin
                    if (ghash_done) begin
                        ghash_y_reg <= ghash_y_out;
                        state       <= P_AES_PAYLOAD_START;
                    end
                end

                P_AES_PAYLOAD_START: begin
                    state <= P_AES_PAYLOAD_WAIT;
                end

                P_AES_PAYLOAD_WAIT: begin
                    if (aes_done) begin
                        payload_out[payload_index] <= payload_in[payload_index] ^ aes_ciphertext;
                        hash_block_reg <= decrypt_reg ? payload_in[payload_index] :
                                                        (payload_in[payload_index] ^ aes_ciphertext);
                        state <= P_GHASH_PAYLOAD_START;
                    end
                end

                P_GHASH_PAYLOAD_START: begin
                    state <= P_GHASH_PAYLOAD_WAIT;
                end

                P_GHASH_PAYLOAD_WAIT: begin
                    if (ghash_done) begin
                        ghash_y_reg <= ghash_y_out;
                        if (payload_index == 2'd2) begin
                            state <= P_GHASH_LEN_START;
                        end else begin
                            payload_index <= payload_index + 2'd1;
                            state         <= P_AES_PAYLOAD_START;
                        end
                    end
                end

                P_GHASH_LEN_START: begin
                    state <= P_GHASH_LEN_WAIT;
                end

                P_GHASH_LEN_WAIT: begin
                    if (ghash_done) begin
                        tag_reg <= final_tag;
                        if (decrypt_reg) begin
                            tag_match <= (final_tag == tag_in_block);
                            auth_fail <= (final_tag != tag_in_block);
                            if (final_tag != tag_in_block) begin
                                payload_out[0] <= 128'h0;
                                payload_out[1] <= 128'h0;
                                payload_out[2] <= 128'h0;
                            end
                        end else begin
                            tag_match <= 1'b1;
                            auth_fail <= 1'b0;
                        end
                        out_count <= 5'd0;
                        state     <= P_OUTPUT;
                    end
                end

                P_OUTPUT: begin
                    if (out_valid && out_ready) begin
                        if (out_count == 5'd19) begin
                            out_count <= 5'd0;
                            state     <= P_IDLE;
                        end else begin
                            out_count <= out_count + 5'd1;
                        end
                    end
                end

                default: begin
                    state <= P_IDLE;
                end
            endcase
        end
    end
endmodule
