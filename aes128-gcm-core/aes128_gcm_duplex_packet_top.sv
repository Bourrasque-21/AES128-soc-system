module aes128_gcm_duplex_packet_top (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [127:0] tx_key,
    input  logic [127:0] rx_key,

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
    aes128_gcm_packet_top u_tx_gcm (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (tx_start),
        .decrypt   (1'b0),
        .key       (tx_key),
        .in_valid  (tx_in_valid),
        .in_ready  (tx_in_ready),
        .in_data   (tx_in_data),
        .out_valid (tx_out_valid),
        .out_ready (tx_out_ready),
        .out_data  (tx_out_data),
        .busy      (tx_busy),
        .done      (tx_done),
        .tag_match (tx_tag_match),
        .auth_fail (tx_auth_fail)
    );

    aes128_gcm_packet_top u_rx_gcm (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (rx_start),
        .decrypt   (1'b1),
        .key       (rx_key),
        .in_valid  (rx_in_valid),
        .in_ready  (rx_in_ready),
        .in_data   (rx_in_data),
        .out_valid (rx_out_valid),
        .out_ready (rx_out_ready),
        .out_data  (rx_out_data),
        .busy      (rx_busy),
        .done      (rx_done),
        .tag_match (rx_tag_match),
        .auth_fail (rx_auth_fail)
    );

    assign irq_tx_done      = tx_done;
    assign irq_rx_done      = rx_done;
    assign irq_rx_auth_fail = rx_done && rx_auth_fail;
    assign irq_sources      = {irq_rx_auth_fail, irq_rx_done, irq_tx_done};
    assign irq              = |irq_sources;
endmodule
