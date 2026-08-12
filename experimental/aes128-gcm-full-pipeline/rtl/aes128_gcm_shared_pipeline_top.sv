module aes128_gcm_shared_pipeline_top #(
    parameter logic [127:0] FIXED_KEY = 128'h000102030405060708090a0b0c0d0e0f
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        tx_start,
    input  logic        tx_in_valid,
    output logic        tx_in_ready,
    input  logic [31:0] tx_in_data,
    output logic        tx_out_valid,
    input  logic        tx_out_ready,
    output logic [31:0] tx_out_data,
    output logic        tx_busy,
    output logic        tx_done,
    output logic        tx_tag_match,
    output logic        tx_auth_fail,

    input  logic        rx_start,
    input  logic        rx_in_valid,
    output logic        rx_in_ready,
    input  logic [31:0] rx_in_data,
    output logic        rx_out_valid,
    input  logic        rx_out_ready,
    output logic [31:0] rx_out_data,
    output logic        rx_busy,
    output logic        rx_done,
    output logic        rx_tag_match,
    output logic        rx_auth_fail,

    output logic [2:0]  irq_sources,
    output logic        irq_tx_done,
    output logic        irq_rx_done,
    output logic        irq_rx_auth_fail,
    output logic        irq
);
    // The AES datapath returns a result 20 cycles after request acceptance.
    // Metadata is registered at index 0 on the acceptance edge, so 21 entries
    // are required for meta_pipe[20] to align with the AES output edge.
    localparam int AES_PIPE_LATENCY = 21;
    localparam int META_WIDTH = 4;

    localparam logic META_DIR_TX = 1'b0;
    localparam logic META_DIR_RX = 1'b1;

    logic         tx_req_valid;
    logic         tx_req_ready;
    logic [2:0]   tx_req_type;
    logic [127:0] tx_req_block;
    logic         tx_resp_valid;
    logic [2:0]   tx_resp_type;
    logic [127:0] tx_resp_block;

    logic         rx_req_valid;
    logic         rx_req_ready;
    logic [2:0]   rx_req_type;
    logic [127:0] rx_req_block;
    logic         rx_resp_valid;
    logic [2:0]   rx_resp_type;
    logic [127:0] rx_resp_block;

    logic         aes_in_valid;
    logic         aes_in_ready;
    logic [127:0] aes_in_block;
    logic         aes_out_valid;
    logic [127:0] aes_out_block;

    logic         grant_tx;
    logic         grant_rx;
    logic         last_grant_dir;

    logic [META_WIDTH-1:0] meta_pipe [0:AES_PIPE_LATENCY-1];
    logic [AES_PIPE_LATENCY-1:0] meta_valid_pipe;
    logic [META_WIDTH-1:0] meta_in;
    logic [META_WIDTH-1:0] meta_out;
    logic                  resp_valid;

    integer meta_idx;

    assign grant_tx = tx_req_valid && (!rx_req_valid || (last_grant_dir == META_DIR_RX));
    assign grant_rx = rx_req_valid && (!tx_req_valid || (last_grant_dir == META_DIR_TX));

    assign tx_req_ready = aes_in_ready && grant_tx;
    assign rx_req_ready = aes_in_ready && grant_rx;

    assign aes_in_valid = grant_tx ? tx_req_valid :
                          grant_rx ? rx_req_valid :
                                     1'b0;
    assign aes_in_block = grant_tx ? tx_req_block :
                          grant_rx ? rx_req_block :
                                     128'h0;
    assign meta_in      = grant_tx ? {META_DIR_TX, tx_req_type} :
                          grant_rx ? {META_DIR_RX, rx_req_type} :
                                     {META_WIDTH{1'b0}};

    assign meta_out = meta_pipe[AES_PIPE_LATENCY-1];
    assign resp_valid = aes_out_valid && meta_valid_pipe[AES_PIPE_LATENCY-1];

    assign tx_resp_valid = resp_valid && (meta_out[3] == META_DIR_TX);
    assign tx_resp_type  = meta_out[2:0];
    assign tx_resp_block = aes_out_block;

    assign rx_resp_valid = resp_valid && (meta_out[3] == META_DIR_RX);
    assign rx_resp_type  = meta_out[2:0];
    assign rx_resp_block = aes_out_block;

    aes128_gcm_pipeline_context #(
        .DECRYPT (1'b0)
    ) u_tx_context (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (tx_start),
        .in_valid       (tx_in_valid),
        .in_ready       (tx_in_ready),
        .in_data        (tx_in_data),
        .out_valid      (tx_out_valid),
        .out_ready      (tx_out_ready),
        .out_data       (tx_out_data),
        .busy           (tx_busy),
        .done           (tx_done),
        .tag_match      (tx_tag_match),
        .auth_fail      (tx_auth_fail),
        .aes_req_valid  (tx_req_valid),
        .aes_req_ready  (tx_req_ready),
        .aes_req_type   (tx_req_type),
        .aes_req_block  (tx_req_block),
        .aes_resp_valid (tx_resp_valid),
        .aes_resp_type  (tx_resp_type),
        .aes_resp_block (tx_resp_block)
    );

    aes128_gcm_pipeline_context #(
        .DECRYPT (1'b1)
    ) u_rx_context (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (rx_start),
        .in_valid       (rx_in_valid),
        .in_ready       (rx_in_ready),
        .in_data        (rx_in_data),
        .out_valid      (rx_out_valid),
        .out_ready      (rx_out_ready),
        .out_data       (rx_out_data),
        .busy           (rx_busy),
        .done           (rx_done),
        .tag_match      (rx_tag_match),
        .auth_fail      (rx_auth_fail),
        .aes_req_valid  (rx_req_valid),
        .aes_req_ready  (rx_req_ready),
        .aes_req_type   (rx_req_type),
        .aes_req_block  (rx_req_block),
        .aes_resp_valid (rx_resp_valid),
        .aes_resp_type  (rx_resp_type),
        .aes_resp_block (rx_resp_block)
    );

    aes128_full_pipeline_bram_core u_shared_aes_pipeline (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (aes_in_valid),
        .in_ready  (aes_in_ready),
        .in_block  (aes_in_block),
        .key       (FIXED_KEY),
        .out_valid (aes_out_valid),
        .out_block (aes_out_block)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_grant_dir  <= META_DIR_RX;
            meta_valid_pipe <= '0;
            for (meta_idx = 0; meta_idx < AES_PIPE_LATENCY; meta_idx = meta_idx + 1) begin
                meta_pipe[meta_idx] <= {META_WIDTH{1'b0}};
            end
        end else begin
            if (aes_in_valid && aes_in_ready) begin
                if (grant_tx) begin
                    last_grant_dir <= META_DIR_TX;
                end else if (grant_rx) begin
                    last_grant_dir <= META_DIR_RX;
                end
            end

            meta_pipe[0] <= meta_in;
            meta_valid_pipe[0] <= aes_in_valid && aes_in_ready;
            for (meta_idx = 1; meta_idx < AES_PIPE_LATENCY; meta_idx = meta_idx + 1) begin
                meta_pipe[meta_idx] <= meta_pipe[meta_idx - 1];
                meta_valid_pipe[meta_idx] <= meta_valid_pipe[meta_idx - 1];
            end
        end
    end

    assign irq_tx_done      = tx_done;
    assign irq_rx_done      = rx_done;
    assign irq_rx_auth_fail = rx_done && rx_auth_fail;
    assign irq_sources      = {irq_rx_auth_fail, irq_rx_done, irq_tx_done};
    assign irq              = |irq_sources;
endmodule
