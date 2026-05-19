import aes_pkg::*;

module aes128_core (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] plaintext,
    input  logic [127:0] key,
    output logic [127:0] ciphertext,
    output logic         busy,
    output logic         done
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_KEY_EXPAND,
        S_INIT,
        S_ROUND,
        S_FINAL,
        S_DONE
    } aes_state_t;

    aes_state_t state;

    logic [127:0]  key_reg;
    logic [127:0]  block_reg;
    logic [127:0]  state_reg;
    logic [3:0]    round_ctr;
    logic [3:0]    expand_round;
    logic [1407:0] round_keys;
    logic [127:0]  current_round_key;
    logic [127:0]  round_out;
    logic          final_round;
    logic [31:0]   exp_w0;
    logic [31:0]   exp_w1;
    logic [31:0]   exp_w2;
    logic [31:0]   exp_w3;
    logic [31:0]   exp_temp;
    logic [31:0]   exp_next_w0;
    logic [31:0]   exp_next_w1;
    logic [31:0]   exp_next_w2;
    logic [31:0]   exp_next_w3;

    aes_round u_round (
        .state_in    (state_reg),
        .round_key   (current_round_key),
        .final_round (final_round),
        .state_out   (round_out)
    );

    function automatic logic [127:0] round_key_at(
        input logic [1407:0] keys,
        input logic [3:0]    round
    );
        unique case (round)
            4'd0:  round_key_at = keys[1407:1280];
            4'd1:  round_key_at = keys[1279:1152];
            4'd2:  round_key_at = keys[1151:1024];
            4'd3:  round_key_at = keys[1023:896];
            4'd4:  round_key_at = keys[895:768];
            4'd5:  round_key_at = keys[767:640];
            4'd6:  round_key_at = keys[639:512];
            4'd7:  round_key_at = keys[511:384];
            4'd8:  round_key_at = keys[383:256];
            4'd9:  round_key_at = keys[255:128];
            4'd10: round_key_at = keys[127:0];
            default: round_key_at = 128'h0;
        endcase
    endfunction

    function automatic logic [31:0] rot_word(input logic [31:0] word_in);
        rot_word = {word_in[23:0], word_in[31:24]};
    endfunction

    function automatic logic [31:0] sub_word(input logic [31:0] word_in);
        sub_word = {
            aes_sbox_byte(word_in[31:24]),
            aes_sbox_byte(word_in[23:16]),
            aes_sbox_byte(word_in[15:8]),
            aes_sbox_byte(word_in[7:0])
        };
    endfunction

    function automatic logic [7:0] rcon(input logic [3:0] round);
        unique case (round)
            4'd1:  rcon = 8'h01;
            4'd2:  rcon = 8'h02;
            4'd3:  rcon = 8'h04;
            4'd4:  rcon = 8'h08;
            4'd5:  rcon = 8'h10;
            4'd6:  rcon = 8'h20;
            4'd7:  rcon = 8'h40;
            4'd8:  rcon = 8'h80;
            4'd9:  rcon = 8'h1b;
            4'd10: rcon = 8'h36;
            default: rcon = 8'h00;
        endcase
    endfunction

    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign done = (state == S_DONE);
    assign final_round = (state == S_FINAL);
    assign current_round_key = final_round ? round_key_at(round_keys, 4'd10) : round_key_at(round_keys, round_ctr);

    always_comb begin
        exp_temp    = sub_word(rot_word(exp_w3)) ^ {rcon(expand_round), 24'h000000};
        exp_next_w0 = exp_w0 ^ exp_temp;
        exp_next_w1 = exp_w1 ^ exp_next_w0;
        exp_next_w2 = exp_w2 ^ exp_next_w1;
        exp_next_w3 = exp_w3 ^ exp_next_w2;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            key_reg    <= 128'h0;
            block_reg  <= 128'h0;
            state_reg  <= 128'h0;
            round_ctr  <= 4'h0;
            expand_round <= 4'h0;
            round_keys <= 1408'h0;
            ciphertext <= 128'h0;
            exp_w0 <= 32'h0;
            exp_w1 <= 32'h0;
            exp_w2 <= 32'h0;
            exp_w3 <= 32'h0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        key_reg   <= key;
                        block_reg <= plaintext;
                        round_ctr <= 4'h0;
                        expand_round <= 4'd1;
                        round_keys[1407:1280] <= key;
                        exp_w0 <= key[127:96];
                        exp_w1 <= key[95:64];
                        exp_w2 <= key[63:32];
                        exp_w3 <= key[31:0];
                        state <= S_KEY_EXPAND;
                    end
                end

                S_KEY_EXPAND: begin
                    round_keys[1407 - (expand_round * 128) -: 128] <= {
                        exp_next_w0,
                        exp_next_w1,
                        exp_next_w2,
                        exp_next_w3
                    };
                    exp_w0 <= exp_next_w0;
                    exp_w1 <= exp_next_w1;
                    exp_w2 <= exp_next_w2;
                    exp_w3 <= exp_next_w3;

                    if (expand_round == 4'd10) begin
                        state <= S_INIT;
                    end else begin
                        expand_round <= expand_round + 4'd1;
                    end
                end

                S_INIT: begin
                    state_reg <= block_reg ^ round_key_at(round_keys, 4'd0);
                    round_ctr <= 4'd1;
                    state     <= S_ROUND;
                end

                S_ROUND: begin
                    state_reg <= round_out;
                    if (round_ctr == 4'd9) begin
                        round_ctr <= 4'd10;
                        state     <= S_FINAL;
                    end else begin
                        round_ctr <= round_ctr + 4'd1;
                    end
                end

                S_FINAL: begin
                    state_reg  <= round_out;
                    ciphertext <= round_out;
                    state      <= S_DONE;
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
