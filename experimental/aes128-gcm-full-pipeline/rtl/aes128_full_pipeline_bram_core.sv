import aes_pkg::*;

module aes128_full_pipeline_bram_core (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         in_valid,
    output logic         in_ready,
    input  logic [127:0] in_block,
    input  logic [127:0] key,
    output logic         out_valid,
    output logic [127:0] out_block
);
    localparam int ROUNDS = 10;
    localparam int BYTES_PER_BLOCK = 16;
    localparam int PIPE_LATENCY = 20;

    logic [127:0] round_keys [0:ROUNDS];
    logic [127:0] state_pipe [0:ROUNDS];
    logic [127:0] sbox_out   [0:ROUNDS-1];
    logic [127:0] shiftrows_state [0:ROUNDS-1];
    logic [127:0] mixcolumns_state [0:ROUNDS-2];
    logic [127:0] round_next [0:ROUNDS-1];

    logic [ROUNDS:0] valid_state;
    logic [ROUNDS-1:0] valid_sbox;

    logic [31:0] w [0:43];
    integer key_idx;
    integer reset_idx;

    assign in_ready  = 1'b1;
    assign out_valid = valid_state[ROUNDS];
    assign out_block = state_pipe[ROUNDS];

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

    function automatic logic [31:0] rcon_word(input int round);
        unique case (round)
            1:  rcon_word = 32'h01000000;
            2:  rcon_word = 32'h02000000;
            3:  rcon_word = 32'h04000000;
            4:  rcon_word = 32'h08000000;
            5:  rcon_word = 32'h10000000;
            6:  rcon_word = 32'h20000000;
            7:  rcon_word = 32'h40000000;
            8:  rcon_word = 32'h80000000;
            9:  rcon_word = 32'h1b000000;
            10: rcon_word = 32'h36000000;
            default: rcon_word = 32'h00000000;
        endcase
    endfunction

    always_comb begin
        w[0] = key[127:96];
        w[1] = key[95:64];
        w[2] = key[63:32];
        w[3] = key[31:0];

        for (key_idx = 4; key_idx < 44; key_idx = key_idx + 1) begin
            if ((key_idx % 4) == 0) begin
                w[key_idx] = w[key_idx - 4] ^
                             sub_word(rot_word(w[key_idx - 1])) ^
                             rcon_word(key_idx / 4);
            end else begin
                w[key_idx] = w[key_idx - 4] ^ w[key_idx - 1];
            end
        end

        for (key_idx = 0; key_idx <= ROUNDS; key_idx = key_idx + 1) begin
            round_keys[key_idx] = {
                w[(key_idx * 4) + 0],
                w[(key_idx * 4) + 1],
                w[(key_idx * 4) + 2],
                w[(key_idx * 4) + 3]
            };
        end
    end

    genvar round_idx;
    genvar byte_idx;
    generate
        for (round_idx = 0; round_idx < ROUNDS; round_idx = round_idx + 1) begin : gen_round
            for (byte_idx = 0; byte_idx < BYTES_PER_BLOCK; byte_idx = byte_idx + 1) begin : gen_sbox
                aes_sbox_bram_sync u_sbox (
                    .clk  (clk),
                    .addr (state_pipe[round_idx][127 - (byte_idx * 8) -: 8]),
                    .data (sbox_out[round_idx][127 - (byte_idx * 8) -: 8])
                );
            end

            aes_shiftrows u_shiftrows (
                .state_in  (sbox_out[round_idx]),
                .state_out (shiftrows_state[round_idx])
            );

            if (round_idx < ROUNDS - 1) begin : gen_regular_round
                aes_mixcolumns u_mixcolumns (
                    .state_in  (shiftrows_state[round_idx]),
                    .state_out (mixcolumns_state[round_idx])
                );

                assign round_next[round_idx] = mixcolumns_state[round_idx] ^
                                                round_keys[round_idx + 1];
            end else begin : gen_final_round
                assign round_next[round_idx] = shiftrows_state[round_idx] ^
                                                round_keys[round_idx + 1];
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_state <= '0;
            valid_sbox  <= '0;
            for (reset_idx = 0; reset_idx <= ROUNDS; reset_idx = reset_idx + 1) begin
                state_pipe[reset_idx] <= 128'h0;
            end
        end else begin
            state_pipe[0]  <= in_block ^ round_keys[0];
            valid_state[0] <= in_valid && in_ready;

            for (int stage_idx = 0; stage_idx < ROUNDS; stage_idx = stage_idx + 1) begin
                valid_sbox[stage_idx] <= valid_state[stage_idx];
                state_pipe[stage_idx + 1] <= round_next[stage_idx];
                valid_state[stage_idx + 1] <= valid_sbox[stage_idx];
            end
        end
    end
endmodule

