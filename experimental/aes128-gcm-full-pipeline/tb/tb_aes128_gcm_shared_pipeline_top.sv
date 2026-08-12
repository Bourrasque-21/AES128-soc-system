module tb_aes128_gcm_shared_pipeline_top;
    logic clk;
    logic rst_n;

    logic        tx_start;
    logic        tx_in_valid;
    logic        tx_in_ready;
    logic [31:0] tx_in_data;
    logic        tx_out_valid;
    logic        tx_out_ready;
    logic [31:0] tx_out_data;
    logic        tx_busy;
    logic        tx_done;
    logic        tx_tag_match;
    logic        tx_auth_fail;

    logic        rx_start;
    logic        rx_in_valid;
    logic        rx_in_ready;
    logic [31:0] rx_in_data;
    logic        rx_out_valid;
    logic        rx_out_ready;
    logic [31:0] rx_out_data;
    logic        rx_busy;
    logic        rx_done;
    logic        rx_tag_match;
    logic        rx_auth_fail;
    logic [2:0]  irq_sources;
    logic        irq_tx_done;
    logic        irq_rx_done;
    logic        irq_rx_auth_fail;
    logic        irq;

    logic [127:0] tx_aad;
    logic [127:0] tx_block0;
    logic [127:0] tx_block1;
    logic [127:0] tx_block2;
    logic [127:0] tx_tag;

    logic [127:0] rx_aad;
    logic [127:0] rx_block0;
    logic [127:0] rx_block1;
    logic [127:0] rx_block2;
    logic [127:0] rx_tag;

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

    aes128_gcm_shared_pipeline_top #(
        .FIXED_KEY (KEY)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
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
            irq_tx_done_count <= 8'd0;
            irq_rx_done_count <= 8'd0;
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

    task automatic pulse_duplex_start;
        begin
            @(negedge clk);
            tx_start = 1'b1;
            rx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;
            rx_start = 1'b0;
        end
    endtask

    task automatic send_tx_words(input integer word_count);
        integer idx;
        begin
            for (idx = 0; idx < word_count; idx = idx + 1) begin
                @(negedge clk);
                tx_in_data = packet_word(AAD, PLAIN_0, PLAIN_1, PLAIN_2, 128'h0, idx);
                tx_in_valid = 1'b1;
                while (!tx_in_ready) @(negedge clk);
            end
            @(negedge clk);
            tx_in_valid = 1'b0;
            tx_in_data = 32'h0;
        end
    endtask

    task automatic send_rx_words(input logic [127:0] input_tag);
        integer idx;
        begin
            for (idx = 0; idx < 20; idx = idx + 1) begin
                @(negedge clk);
                rx_in_data = packet_word(AAD, CIPHER_0, CIPHER_1, CIPHER_2, input_tag, idx);
                rx_in_valid = 1'b1;
                while (!rx_in_ready) @(negedge clk);
            end
            @(negedge clk);
            rx_in_valid = 1'b0;
            rx_in_data = 32'h0;
        end
    endtask

    task automatic store_tx_word(input integer idx, input logic [31:0] word);
        unique case (idx)
            0:  tx_aad[127:96]    = word;
            1:  tx_aad[95:64]     = word;
            2:  tx_aad[63:32]     = word;
            3:  tx_aad[31:0]      = word;
            4:  tx_block0[127:96] = word;
            5:  tx_block0[95:64]  = word;
            6:  tx_block0[63:32]  = word;
            7:  tx_block0[31:0]   = word;
            8:  tx_block1[127:96] = word;
            9:  tx_block1[95:64]  = word;
            10: tx_block1[63:32]  = word;
            11: tx_block1[31:0]   = word;
            12: tx_block2[127:96] = word;
            13: tx_block2[95:64]  = word;
            14: tx_block2[63:32]  = word;
            15: tx_block2[31:0]   = word;
            16: tx_tag[127:96]    = word;
            17: tx_tag[95:64]     = word;
            18: tx_tag[63:32]     = word;
            19: tx_tag[31:0]      = word;
            default: begin end
        endcase
    endtask

    task automatic store_rx_word(input integer idx, input logic [31:0] word);
        unique case (idx)
            0:  rx_aad[127:96]    = word;
            1:  rx_aad[95:64]     = word;
            2:  rx_aad[63:32]     = word;
            3:  rx_aad[31:0]      = word;
            4:  rx_block0[127:96] = word;
            5:  rx_block0[95:64]  = word;
            6:  rx_block0[63:32]  = word;
            7:  rx_block0[31:0]   = word;
            8:  rx_block1[127:96] = word;
            9:  rx_block1[95:64]  = word;
            10: rx_block1[63:32]  = word;
            11: rx_block1[31:0]   = word;
            12: rx_block2[127:96] = word;
            13: rx_block2[95:64]  = word;
            14: rx_block2[63:32]  = word;
            15: rx_block2[31:0]   = word;
            16: rx_tag[127:96]    = word;
            17: rx_tag[95:64]     = word;
            18: rx_tag[63:32]     = word;
            19: rx_tag[31:0]      = word;
            default: begin end
        endcase
    endtask

    task automatic recv_tx_packet;
        integer idx;
        integer timeout;
        begin
            tx_aad = 128'h0;
            tx_block0 = 128'h0;
            tx_block1 = 128'h0;
            tx_block2 = 128'h0;
            tx_tag = 128'h0;
            idx = 0;
            timeout = 0;
            while (idx < 20 && timeout < 5000) begin
                @(posedge clk);
                if (tx_out_valid && tx_out_ready) begin
                    store_tx_word(idx, tx_out_data);
                    idx = idx + 1;
                end
                timeout = timeout + 1;
            end
            if (idx != 20) $fatal(1, "TX packet timeout, got %0d words", idx);
        end
    endtask

    task automatic recv_rx_packet;
        integer idx;
        integer timeout;
        begin
            rx_aad = 128'h0;
            rx_block0 = 128'h0;
            rx_block1 = 128'h0;
            rx_block2 = 128'h0;
            rx_tag = 128'h0;
            idx = 0;
            timeout = 0;
            while (idx < 20 && timeout < 5000) begin
                @(posedge clk);
                if (rx_out_valid && rx_out_ready) begin
                    store_rx_word(idx, rx_out_data);
                    idx = idx + 1;
                end
                timeout = timeout + 1;
            end
            if (idx != 20) $fatal(1, "RX packet timeout, got %0d words", idx);
        end
    endtask

    task automatic run_transaction(input logic [127:0] rx_input_tag);
        begin
            pulse_duplex_start();
            fork
                send_tx_words(16);
                recv_tx_packet();
                send_rx_words(rx_input_tag);
                recv_rx_packet();
            join
        end
    endtask

    task automatic check_good_outputs;
        begin
            if (tx_aad !== AAD || tx_block0 !== CIPHER_0 || tx_block1 !== CIPHER_1 ||
                tx_block2 !== CIPHER_2 || tx_tag !== TAG) begin
                $fatal(1, "TX mismatch: aad=%032h b0=%032h b1=%032h b2=%032h tag=%032h",
                       tx_aad, tx_block0, tx_block1, tx_block2, tx_tag);
            end

            if (rx_aad !== AAD || rx_block0 !== PLAIN_0 || rx_block1 !== PLAIN_1 ||
                rx_block2 !== PLAIN_2 || rx_tag !== TAG) begin
                $fatal(1, "RX mismatch: aad=%032h b0=%032h b1=%032h b2=%032h tag=%032h",
                       rx_aad, rx_block0, rx_block1, rx_block2, rx_tag);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        tx_start = 1'b0;
        rx_start = 1'b0;
        tx_in_valid = 1'b0;
        rx_in_valid = 1'b0;
        tx_in_data = 32'h0;
        rx_in_data = 32'h0;
        tx_out_ready = 1'b1;
        rx_out_ready = 1'b1;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        run_transaction(TAG);
        repeat (3) @(posedge clk);
        check_good_outputs();
        if (!tx_tag_match || tx_auth_fail) begin
            $fatal(1, "TX status failed");
        end
        if (!rx_tag_match || rx_auth_fail) begin
            $fatal(1, "RX status failed");
        end
        if (irq_tx_done_count !== 8'd1 || irq_rx_done_count !== 8'd1 ||
            irq_rx_auth_fail_count !== 8'd0) begin
            $fatal(1, "IRQ counts failed after good transaction");
        end

        run_transaction(BAD_TAG);
        repeat (3) @(posedge clk);
        if (rx_block0 !== 128'h0 || rx_block1 !== 128'h0 || rx_block2 !== 128'h0) begin
            $fatal(1, "Bad tag RX payload was not cleared");
        end
        if (rx_tag_match || !rx_auth_fail) begin
            $fatal(1, "Bad tag status failed");
        end
        if (irq_tx_done_count !== 8'd2 || irq_rx_done_count !== 8'd2 ||
            irq_rx_auth_fail_count !== 8'd1) begin
            $fatal(1, "IRQ counts failed after bad transaction");
        end

        $display("PASS: AES-128 GCM shared full-pipeline core KAT passed");
        $finish;
    end
endmodule

