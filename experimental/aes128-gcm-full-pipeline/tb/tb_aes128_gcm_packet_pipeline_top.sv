module tb_aes128_gcm_packet_pipeline_top;
    localparam logic MODE_ENCRYPT = 1'b0;
    localparam logic MODE_DECRYPT = 1'b1;

    logic clk;
    logic rst_n;

    logic        pkt_start;
    logic        pkt_decrypt;
    logic        in_valid;
    logic        in_ready;
    logic [31:0] in_data;
    logic        out_valid;
    logic        out_ready;
    logic [31:0] out_data;
    logic        out_decrypt;
    logic        busy;
    logic        done;
    logic        tag_match;
    logic        auth_fail;
    logic [2:0]  irq_sources;
    logic        irq_tx_done;
    logic        irq_rx_done;
    logic        irq_rx_auth_fail;
    logic        irq;

    logic [127:0] got_aad;
    logic [127:0] got_block0;
    logic [127:0] got_block1;
    logic [127:0] got_block2;
    logic [127:0] got_tag;
    logic         got_mode;

    logic [7:0] irq_tx_done_count;
    logic [7:0] irq_rx_done_count;
    logic [7:0] irq_rx_auth_fail_count;

    localparam logic [127:0] KEY = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] AAD = 128'h01100030112233445566778800000001;
    localparam logic [127:0] PLAIN_0 = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] PLAIN_1 = 128'h102132435465768798a9babbdcedfe0f;
    localparam logic [127:0] PLAIN_2 = 128'hffeeddccbbaa99887766554433221100;
    localparam logic [127:0] CIPHER_0 = 128'hcf9095b082cbaefdcc6819a97945e918;
    localparam logic [127:0] CIPHER_1 = 128'h2052dadf6dfc914a08aef51ed681338d;
    localparam logic [127:0] CIPHER_2 = 128'hd5ba1e8324813042dc63430665b13367;
    localparam logic [127:0] TAG = 128'h65e306596c7638e920141b6fe84db33e;
    localparam logic [127:0] BAD_TAG = 128'h65e306596c7638e920141b6fe84db33f;

    aes128_gcm_packet_pipeline_top #(
        .FIXED_KEY (KEY)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .pkt_start        (pkt_start),
        .pkt_decrypt      (pkt_decrypt),
        .in_valid         (in_valid),
        .in_ready         (in_ready),
        .in_data          (in_data),
        .out_valid        (out_valid),
        .out_ready        (out_ready),
        .out_data         (out_data),
        .out_decrypt      (out_decrypt),
        .busy             (busy),
        .done             (done),
        .tag_match        (tag_match),
        .auth_fail        (auth_fail),
        .irq_sources      (irq_sources),
        .irq_tx_done      (irq_tx_done),
        .irq_rx_done      (irq_rx_done),
        .irq_rx_auth_fail (irq_rx_auth_fail),
        .irq              (irq)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_tx_done_count      <= 8'd0;
            irq_rx_done_count      <= 8'd0;
            irq_rx_auth_fail_count <= 8'd0;
        end else begin
            if (irq_tx_done) irq_tx_done_count <= irq_tx_done_count + 8'd1;
            if (irq_rx_done) irq_rx_done_count <= irq_rx_done_count + 8'd1;
            if (irq_rx_auth_fail) irq_rx_auth_fail_count <= irq_rx_auth_fail_count + 8'd1;
        end
    end

    function automatic logic [31:0] packet_word(
        input logic [127:0] aad,
        input logic [127:0] block0,
        input logic [127:0] block1,
        input logic [127:0] block2,
        input logic [127:0] tag,
        input integer idx
    );
        unique case (idx)
            0:  packet_word = aad[127:96];
            1:  packet_word = aad[95:64];
            2:  packet_word = aad[63:32];
            3:  packet_word = aad[31:0];
            4:  packet_word = block0[127:96];
            5:  packet_word = block0[95:64];
            6:  packet_word = block0[63:32];
            7:  packet_word = block0[31:0];
            8:  packet_word = block1[127:96];
            9:  packet_word = block1[95:64];
            10: packet_word = block1[63:32];
            11: packet_word = block1[31:0];
            12: packet_word = block2[127:96];
            13: packet_word = block2[95:64];
            14: packet_word = block2[63:32];
            15: packet_word = block2[31:0];
            16: packet_word = tag[127:96];
            17: packet_word = tag[95:64];
            18: packet_word = tag[63:32];
            19: packet_word = tag[31:0];
            default: packet_word = 32'h00000000;
        endcase
    endfunction

    task automatic store_output_word(input integer idx, input logic [31:0] word);
        unique case (idx)
            0:  got_aad[127:96]    = word;
            1:  got_aad[95:64]     = word;
            2:  got_aad[63:32]     = word;
            3:  got_aad[31:0]      = word;
            4:  got_block0[127:96] = word;
            5:  got_block0[95:64]  = word;
            6:  got_block0[63:32]  = word;
            7:  got_block0[31:0]   = word;
            8:  got_block1[127:96] = word;
            9:  got_block1[95:64]  = word;
            10: got_block1[63:32]  = word;
            11: got_block1[31:0]   = word;
            12: got_block2[127:96] = word;
            13: got_block2[95:64]  = word;
            14: got_block2[63:32]  = word;
            15: got_block2[31:0]   = word;
            16: got_tag[127:96]    = word;
            17: got_tag[95:64]     = word;
            18: got_tag[63:32]     = word;
            19: got_tag[31:0]      = word;
            default: begin end
        endcase
    endtask

    task automatic start_packet(input logic mode);
        begin
            @(negedge clk);
            pkt_decrypt = mode;
            pkt_start = 1'b1;
            @(negedge clk);
            pkt_start = 1'b0;
        end
    endtask

    task automatic send_packet(
        input logic mode,
        input logic [127:0] block0,
        input logic [127:0] block1,
        input logic [127:0] block2,
        input logic [127:0] tag
    );
        integer idx;
        integer word_count;
        begin
            word_count = mode ? 20 : 16;
            start_packet(mode);
            for (idx = 0; idx < word_count; idx = idx + 1) begin
                @(negedge clk);
                in_data = packet_word(AAD, block0, block1, block2, tag, idx);
                in_valid = 1'b1;
                while (!in_ready) @(negedge clk);
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_data = 32'h0;
        end
    endtask

    task automatic recv_packet;
        integer idx;
        integer timeout;
        begin
            got_aad = 128'h0;
            got_block0 = 128'h0;
            got_block1 = 128'h0;
            got_block2 = 128'h0;
            got_tag = 128'h0;
            got_mode = 1'b0;
            idx = 0;
            timeout = 0;
            while (idx < 20 && timeout < 5000) begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    if (idx == 0) got_mode = out_decrypt;
                    if (out_decrypt !== got_mode) begin
                        $fatal(1, "Output mode changed inside a packet");
                    end
                    store_output_word(idx, out_data);
                    idx = idx + 1;
                end
                timeout = timeout + 1;
            end
            if (idx != 20) $fatal(1, "Output packet timeout, got %0d words", idx);
        end
    endtask

    task automatic run_packet(
        input logic mode,
        input logic [127:0] block0,
        input logic [127:0] block1,
        input logic [127:0] block2,
        input logic [127:0] tag
    );
        begin
            fork
                send_packet(mode, block0, block1, block2, tag);
                recv_packet();
            join
        end
    endtask

    initial begin
        rst_n = 1'b0;
        pkt_start = 1'b0;
        pkt_decrypt = 1'b0;
        in_valid = 1'b0;
        in_data = 32'h0;
        out_ready = 1'b1;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        run_packet(MODE_ENCRYPT, PLAIN_0, PLAIN_1, PLAIN_2, 128'h0);
        repeat (3) @(posedge clk);
        if (got_mode !== MODE_ENCRYPT || got_aad !== AAD ||
            got_block0 !== CIPHER_0 || got_block1 !== CIPHER_1 ||
            got_block2 !== CIPHER_2 || got_tag !== TAG) begin
            $fatal(1, "Encrypt packet mismatch");
        end
        if (!tag_match || auth_fail) $fatal(1, "Encrypt status mismatch");
        if (irq_tx_done_count !== 8'd1 || irq_rx_done_count !== 8'd0 ||
            irq_rx_auth_fail_count !== 8'd0) begin
            $fatal(1, "IRQ mismatch after encrypt packet");
        end

        run_packet(MODE_DECRYPT, CIPHER_0, CIPHER_1, CIPHER_2, TAG);
        repeat (3) @(posedge clk);
        if (got_mode !== MODE_DECRYPT || got_aad !== AAD ||
            got_block0 !== PLAIN_0 || got_block1 !== PLAIN_1 ||
            got_block2 !== PLAIN_2 || got_tag !== TAG) begin
            $fatal(1, "Decrypt packet mismatch");
        end
        if (!tag_match || auth_fail) $fatal(1, "Decrypt status mismatch");
        if (irq_tx_done_count !== 8'd1 || irq_rx_done_count !== 8'd1 ||
            irq_rx_auth_fail_count !== 8'd0) begin
            $fatal(1, "IRQ mismatch after decrypt packet");
        end

        run_packet(MODE_DECRYPT, CIPHER_0, CIPHER_1, CIPHER_2, BAD_TAG);
        repeat (3) @(posedge clk);
        if (got_mode !== MODE_DECRYPT || got_block0 !== 128'h0 ||
            got_block1 !== 128'h0 || got_block2 !== 128'h0) begin
            $fatal(1, "Bad tag packet did not clear payload");
        end
        if (tag_match || !auth_fail) $fatal(1, "Bad tag status mismatch");
        if (irq_tx_done_count !== 8'd1 || irq_rx_done_count !== 8'd2 ||
            irq_rx_auth_fail_count !== 8'd1) begin
            $fatal(1, "IRQ mismatch after bad tag packet");
        end

        $display("PASS: AES-128 GCM single packet pipeline KAT passed");
        $finish;
    end
endmodule
