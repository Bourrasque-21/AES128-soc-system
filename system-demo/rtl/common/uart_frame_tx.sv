module uart_frame_tx #(
    parameter int PACKET_BYTES = 80,
    parameter logic [15:0] SOF = 16'hA55A
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         load,
    input  logic [(PACKET_BYTES*8)-1:0]  packet_bits,
    input  logic                         uart_tx_ready,
    output logic [7:0]                   uart_tx_data,
    output logic                         uart_tx_valid,
    output logic                         busy,
    output logic                         done_pulse
);
    localparam int PACKET_BITS = PACKET_BYTES * 8;
    localparam int FRAME_BYTES = PACKET_BYTES + 2;
    localparam int COUNT_WIDTH = $clog2(FRAME_BYTES + 1);

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_SEND,
        TX_WAIT_ACCEPT,
        TX_WAIT_LAST
    } state_t;

    state_t state;
    logic [COUNT_WIDTH-1:0] byte_idx;
    logic [PACKET_BITS-1:0] packet_latched;

    function automatic logic [7:0] frame_byte(
        input logic [PACKET_BITS-1:0] packet,
        input logic [COUNT_WIDTH-1:0] idx
    );
        if (idx == 0) begin
            frame_byte = SOF[15:8];
        end else if (idx == 1) begin
            frame_byte = SOF[7:0];
        end else begin
            frame_byte = packet[PACKET_BITS-1-((idx-2)*8) -: 8];
        end
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= TX_IDLE;
            byte_idx       <= '0;
            packet_latched <= '0;
            uart_tx_data   <= 8'h00;
            uart_tx_valid  <= 1'b0;
            busy           <= 1'b0;
            done_pulse     <= 1'b0;
        end else begin
            uart_tx_valid <= 1'b0;
            done_pulse    <= 1'b0;

            unique case (state)
                TX_IDLE: begin
                    busy <= 1'b0;
                    if (load) begin
                        packet_latched <= packet_bits;
                        byte_idx       <= '0;
                        busy           <= 1'b1;
                        state          <= TX_SEND;
                    end
                end

                TX_SEND: begin
                    busy <= 1'b1;
                    if (uart_tx_ready) begin
                        uart_tx_data  <= frame_byte(packet_latched, byte_idx);
                        uart_tx_valid <= 1'b1;
                        state         <= TX_WAIT_ACCEPT;
                    end
                end

                TX_WAIT_ACCEPT: begin
                    busy          <= 1'b1;
                    uart_tx_valid <= 1'b1;
                    if (!uart_tx_ready) begin
                        uart_tx_valid <= 1'b0;
                        if (byte_idx == FRAME_BYTES - 1) begin
                            state <= TX_WAIT_LAST;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= TX_SEND;
                        end
                    end
                end

                TX_WAIT_LAST: begin
                    busy <= 1'b1;
                    if (uart_tx_ready) begin
                        busy       <= 1'b0;
                        done_pulse <= 1'b1;
                        state      <= TX_IDLE;
                    end
                end

                default: begin
                    state <= TX_IDLE;
                end
            endcase
        end
    end
endmodule
