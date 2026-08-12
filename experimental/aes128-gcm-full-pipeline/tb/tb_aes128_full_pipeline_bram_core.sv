module tb_aes128_full_pipeline_bram_core;
    logic clk;
    logic rst_n;
    logic in_valid;
    logic in_ready;
    logic [127:0] in_block;
    logic [127:0] key;
    logic out_valid;
    logic [127:0] out_block;

    localparam logic [127:0] KEY = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] PLAIN0 = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] CIPHER0 = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;

    logic [127:0] expected [0:2];
    integer out_idx;

    aes128_full_pipeline_bram_core u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .in_block  (in_block),
        .key       (key),
        .out_valid (out_valid),
        .out_block (out_block)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic send_block(input logic [127:0] block);
        begin
            @(negedge clk);
            in_valid = 1'b1;
            in_block = block;
            if (!in_ready) begin
                $fatal(1, "AES pipeline should be ready every cycle");
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        in_valid = 1'b0;
        in_block = 128'h0;
        key = KEY;
        expected[0] = CIPHER0;
        expected[1] = CIPHER0;
        expected[2] = CIPHER0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        send_block(PLAIN0);
        send_block(PLAIN0);
        send_block(PLAIN0);
        @(negedge clk);
        in_valid = 1'b0;
        in_block = 128'h0;

        repeat (80) @(posedge clk);

        if (out_idx != 3) begin
            $fatal(1, "Expected 3 AES outputs, got %0d", out_idx);
        end

        $display("PASS: AES-128 BRAM S-box full pipeline core KAT passed");
        $finish;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_idx <= 0;
        end else if (out_valid) begin
            if (out_idx >= 3) begin
                $fatal(1, "Unexpected extra AES output %032h", out_block);
            end

            if (out_block !== expected[out_idx]) begin
                $fatal(1, "AES output[%0d] mismatch: got %032h expected %032h",
                       out_idx, out_block, expected[out_idx]);
            end

            out_idx <= out_idx + 1;
        end
    end
endmodule
