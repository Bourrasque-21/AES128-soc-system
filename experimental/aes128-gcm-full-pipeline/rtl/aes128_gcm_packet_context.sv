module aes128_gcm_packet_context (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic         start_decrypt,

    input  logic         in_valid,
    output logic         in_ready,
    input  logic [31:0]  in_data,

    output logic         out_valid,
    input  logic         out_ready,
    output logic [31:0]  out_data,
    output logic         out_decrypt,

    output logic         busy,
    output logic         done,
    output logic         tag_match,
    output logic         auth_fail,

    output logic         aes_req_valid,
    input  logic         aes_req_ready,
    output logic [2:0]   aes_req_type,
    output logic [127:0] aes_req_block,

    input  logic         aes_resp_valid,
    input  logic [2:0]   aes_resp_type,
    input  logic [127:0] aes_resp_block
);
    typedef enum logic [3:0] {
        C_IDLE,
        C_INPUT,
        C_AES_REQ,
        C_WAIT_AES,
        C_GHASH_AAD_START,
        C_GHASH_AAD_WAIT,
        C_GHASH_PAYLOAD_START,
        C_GHASH_PAYLOAD_WAIT,
        C_GHASH_LEN_START,
        C_GHASH_LEN_WAIT,
        C_OUTPUT
    } ctx_state_t;

    localparam logic [2:0] REQ_H        = 3'd0;
    localparam logic [2:0] REQ_TAG_MASK = 3'd1;
    localparam logic [2:0] REQ_KS0      = 3'd2;
    localparam logic [2:0] REQ_KS1      = 3'd3;
    localparam logic [2:0] REQ_KS2      = 3'd4;

    localparam logic [127:0] ZERO_BLOCK   = 128'h0;
    localparam logic [127:0] LENGTH_BLOCK = {64'd128, 64'd384};

    ctx_state_t state;

    logic         mode_decrypt;
    logic [4:0]   in_count;
    logic [4:0]   out_count;
    logic [2:0]   req_count;
    logic [1:0]   payload_index;
    logic [4:0]   aes_result_mask;

    logic [127:0] aad_block;
    logic [127:0] payload_in  [0:2];
    logic [127:0] payload_out [0:2];
    logic [127:0] tag_in_block;
    logic [127:0] tag_reg;
    logic [127:0] h_reg;
    logic [127:0] tag_mask_reg;
    logic [127:0] ghash_y_reg;
    logic [95:0]  nonce;

    logic [127:0] ghash_data_in;
    logic [127:0] ghash_y_in;
    logic [127:0] ghash_y_out;
    logic         ghash_start;
    logic         ghash_busy;
    logic         ghash_done;
    logic [127:0] final_tag;
    logic [4:0]   input_last_word;

    integer reset_idx;

    assign nonce           = aad_block[95:0];
    assign input_last_word = mode_decrypt ? 5'd19 : 5'd15;

    assign in_ready      = (state == C_INPUT);
    assign out_valid     = (state == C_OUTPUT);
    assign out_decrypt   = mode_decrypt;
    assign busy          = (state != C_IDLE);
    assign done          = (state == C_OUTPUT) && out_valid && out_ready && (out_count == 5'd19);
    assign aes_req_valid = (state == C_AES_REQ);
    assign aes_req_type  = req_count;
    assign final_tag     = tag_mask_reg ^ ghash_y_out;
    assign ghash_start   = (state == C_GHASH_AAD_START) ||
                           (state == C_GHASH_PAYLOAD_START) ||
                           (state == C_GHASH_LEN_START);

    always_comb begin
        unique case (req_count)
            REQ_H:        aes_req_block = ZERO_BLOCK;
            REQ_TAG_MASK: aes_req_block = {nonce, 32'h00000001};
            REQ_KS0:      aes_req_block = {nonce, 32'h00000002};
            REQ_KS1:      aes_req_block = {nonce, 32'h00000003};
            REQ_KS2:      aes_req_block = {nonce, 32'h00000004};
            default:      aes_req_block = ZERO_BLOCK;
        endcase
    end

    always_comb begin
        ghash_data_in = 128'h0;
        ghash_y_in    = 128'h0;
        unique case (state)
            C_GHASH_AAD_START: begin
                ghash_data_in = aad_block;
                ghash_y_in    = 128'h0;
            end
            C_GHASH_PAYLOAD_START: begin
                ghash_data_in = mode_decrypt ? payload_in[payload_index] :
                                               payload_out[payload_index];
                ghash_y_in    = ghash_y_reg;
            end
            C_GHASH_LEN_START: begin
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= C_IDLE;
            mode_decrypt    <= 1'b0;
            in_count        <= 5'd0;
            out_count       <= 5'd0;
            req_count       <= 3'd0;
            payload_index   <= 2'd0;
            aes_result_mask <= 5'd0;
            aad_block       <= 128'h0;
            tag_in_block    <= 128'h0;
            tag_reg         <= 128'h0;
            h_reg           <= 128'h0;
            tag_mask_reg    <= 128'h0;
            ghash_y_reg     <= 128'h0;
            tag_match       <= 1'b0;
            auth_fail       <= 1'b0;
            for (reset_idx = 0; reset_idx < 3; reset_idx = reset_idx + 1) begin
                payload_in[reset_idx]  <= 128'h0;
                payload_out[reset_idx] <= 128'h0;
            end
        end else begin
            if (aes_resp_valid) begin
                unique case (aes_resp_type)
                    REQ_H: begin
                        h_reg <= aes_resp_block;
                        aes_result_mask[0] <= 1'b1;
                    end
                    REQ_TAG_MASK: begin
                        tag_mask_reg <= aes_resp_block;
                        aes_result_mask[1] <= 1'b1;
                    end
                    REQ_KS0: begin
                        payload_out[0] <= payload_in[0] ^ aes_resp_block;
                        aes_result_mask[2] <= 1'b1;
                    end
                    REQ_KS1: begin
                        payload_out[1] <= payload_in[1] ^ aes_resp_block;
                        aes_result_mask[3] <= 1'b1;
                    end
                    REQ_KS2: begin
                        payload_out[2] <= payload_in[2] ^ aes_resp_block;
                        aes_result_mask[4] <= 1'b1;
                    end
                    default: begin
                    end
                endcase
            end

            unique case (state)
                C_IDLE: begin
                    if (start) begin
                        mode_decrypt    <= start_decrypt;
                        in_count        <= 5'd0;
                        out_count       <= 5'd0;
                        req_count       <= 3'd0;
                        payload_index   <= 2'd0;
                        aes_result_mask <= 5'd0;
                        aad_block       <= 128'h0;
                        tag_in_block    <= 128'h0;
                        tag_reg         <= 128'h0;
                        h_reg           <= 128'h0;
                        tag_mask_reg    <= 128'h0;
                        ghash_y_reg     <= 128'h0;
                        tag_match       <= 1'b0;
                        auth_fail       <= 1'b0;
                        for (reset_idx = 0; reset_idx < 3; reset_idx = reset_idx + 1) begin
                            payload_in[reset_idx]  <= 128'h0;
                            payload_out[reset_idx] <= 128'h0;
                        end
                        state <= C_INPUT;
                    end
                end

                C_INPUT: begin
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
                            in_count  <= 5'd0;
                            req_count <= REQ_H;
                            state     <= C_AES_REQ;
                        end else begin
                            in_count <= in_count + 5'd1;
                        end
                    end
                end

                C_AES_REQ: begin
                    if (aes_req_valid && aes_req_ready) begin
                        if (req_count == REQ_KS2) begin
                            req_count <= REQ_H;
                            state     <= C_WAIT_AES;
                        end else begin
                            req_count <= req_count + 3'd1;
                        end
                    end
                end

                C_WAIT_AES: begin
                    if (aes_result_mask == 5'b11111) begin
                        payload_index <= 2'd0;
                        state         <= C_GHASH_AAD_START;
                    end
                end

                C_GHASH_AAD_START: begin
                    state <= C_GHASH_AAD_WAIT;
                end

                C_GHASH_AAD_WAIT: begin
                    if (ghash_done) begin
                        ghash_y_reg   <= ghash_y_out;
                        payload_index <= 2'd0;
                        state         <= C_GHASH_PAYLOAD_START;
                    end
                end

                C_GHASH_PAYLOAD_START: begin
                    state <= C_GHASH_PAYLOAD_WAIT;
                end

                C_GHASH_PAYLOAD_WAIT: begin
                    if (ghash_done) begin
                        ghash_y_reg <= ghash_y_out;
                        if (payload_index == 2'd2) begin
                            state <= C_GHASH_LEN_START;
                        end else begin
                            payload_index <= payload_index + 2'd1;
                            state         <= C_GHASH_PAYLOAD_START;
                        end
                    end
                end

                C_GHASH_LEN_START: begin
                    state <= C_GHASH_LEN_WAIT;
                end

                C_GHASH_LEN_WAIT: begin
                    if (ghash_done) begin
                        tag_reg <= final_tag;
                        if (mode_decrypt) begin
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
                        state     <= C_OUTPUT;
                    end
                end

                C_OUTPUT: begin
                    if (out_valid && out_ready) begin
                        if (out_count == 5'd19) begin
                            out_count <= 5'd0;
                            state     <= C_IDLE;
                        end else begin
                            out_count <= out_count + 5'd1;
                        end
                    end
                end

                default: begin
                    state <= C_IDLE;
                end
            endcase
        end
    end
endmodule
