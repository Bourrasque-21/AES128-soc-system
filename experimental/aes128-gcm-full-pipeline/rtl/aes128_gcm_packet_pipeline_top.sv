module aes128_gcm_packet_pipeline_top #(
    parameter logic [127:0] FIXED_KEY = 128'h000102030405060708090a0b0c0d0e0f
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        pkt_start,
    input  logic        pkt_decrypt,
    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] in_data,

    output logic        out_valid,
    input  logic        out_ready,
    output logic [31:0] out_data,
    output logic        out_decrypt,

    output logic        busy,
    output logic        done,
    output logic        tag_match,
    output logic        auth_fail,

    output logic [2:0]  irq_sources,
    output logic        irq_tx_done,
    output logic        irq_rx_done,
    output logic        irq_rx_auth_fail,
    output logic        irq
);
    // AES result latency is 20 cycles after request acceptance. The request
    // type is registered at pipe[0] on the acceptance edge, so pipe[20]
    // aligns with the AES output.
    localparam int AES_PIPE_LATENCY = 21;

    logic         aes_req_valid;
    logic         aes_req_ready;
    logic [2:0]   aes_req_type;
    logic [127:0] aes_req_block;
    logic         aes_resp_valid;
    logic [2:0]   aes_resp_type;
    logic [127:0] aes_resp_block;

    logic         aes_in_valid;
    logic         aes_in_ready;
    logic [127:0] aes_in_block;
    logic         aes_out_valid;
    logic [127:0] aes_out_block;

    logic [2:0] meta_pipe [0:AES_PIPE_LATENCY-1];
    logic [AES_PIPE_LATENCY-1:0] meta_valid_pipe;

    integer meta_idx;

    assign aes_req_ready = aes_in_ready;
    assign aes_in_valid  = aes_req_valid;
    assign aes_in_block  = aes_req_block;

    assign aes_resp_valid = aes_out_valid && meta_valid_pipe[AES_PIPE_LATENCY-1];
    assign aes_resp_type  = meta_pipe[AES_PIPE_LATENCY-1];
    assign aes_resp_block = aes_out_block;

    aes128_gcm_packet_context u_packet_context (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (pkt_start),
        .start_decrypt  (pkt_decrypt),
        .in_valid       (in_valid),
        .in_ready       (in_ready),
        .in_data        (in_data),
        .out_valid      (out_valid),
        .out_ready      (out_ready),
        .out_data       (out_data),
        .out_decrypt    (out_decrypt),
        .busy           (busy),
        .done           (done),
        .tag_match      (tag_match),
        .auth_fail      (auth_fail),
        .aes_req_valid  (aes_req_valid),
        .aes_req_ready  (aes_req_ready),
        .aes_req_type   (aes_req_type),
        .aes_req_block  (aes_req_block),
        .aes_resp_valid (aes_resp_valid),
        .aes_resp_type  (aes_resp_type),
        .aes_resp_block (aes_resp_block)
    );

    aes128_full_pipeline_bram_core u_aes_pipeline (
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
            meta_valid_pipe <= '0;
            for (meta_idx = 0; meta_idx < AES_PIPE_LATENCY; meta_idx = meta_idx + 1) begin
                meta_pipe[meta_idx] <= 3'd0;
            end
        end else begin
            meta_pipe[0]       <= aes_req_type;
            meta_valid_pipe[0] <= aes_req_valid && aes_req_ready;
            for (meta_idx = 1; meta_idx < AES_PIPE_LATENCY; meta_idx = meta_idx + 1) begin
                meta_pipe[meta_idx]       <= meta_pipe[meta_idx - 1];
                meta_valid_pipe[meta_idx] <= meta_valid_pipe[meta_idx - 1];
            end
        end
    end

    assign irq_tx_done      = done && !out_decrypt;
    assign irq_rx_done      = done && out_decrypt;
    assign irq_rx_auth_fail = done && out_decrypt && auth_fail;
    assign irq_sources      = {irq_rx_auth_fail, irq_rx_done, irq_tx_done};
    assign irq              = |irq_sources;
endmodule
