module uart_frame_rx #(
    parameter int PACKET_BYTES = 80,
    parameter logic [15:0] SOF = 16'hA55A,
    parameter int FRAME_TIMEOUT_CYCLES = 1_000_000
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic [7:0]                   rx_data,
    input  logic                         rx_valid,
    input  logic                         framing_error,
    output logic [(PACKET_BYTES*8)-1:0]  packet_bits,
    output logic                         packet_valid,
    output logic                         sof_detected,
    output logic                         frame_timeout,
    output logic                         receiving
);
    localparam int PACKET_BITS = PACKET_BYTES * 8;
    localparam int COUNT_WIDTH = (PACKET_BYTES <= 1) ? 1 : $clog2(PACKET_BYTES);
    localparam int TIMEOUT_WIDTH = (FRAME_TIMEOUT_CYCLES <= 1) ? 1 : $clog2(FRAME_TIMEOUT_CYCLES);

    typedef enum logic [1:0] {
        WAIT_SOF0,
        WAIT_SOF1,
        READ_PACKET,
        EMIT_PACKET
    } state_t;

    state_t state;
    logic [COUNT_WIDTH-1:0] byte_idx;
    logic [TIMEOUT_WIDTH-1:0] timeout_count;

    assign receiving = (state == READ_PACKET);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= WAIT_SOF0;
            byte_idx       <= '0;
            timeout_count  <= '0;
            packet_bits    <= '0;
            packet_valid   <= 1'b0;
            sof_detected   <= 1'b0;
            frame_timeout  <= 1'b0;
        end else begin
            packet_valid  <= 1'b0;
            sof_detected  <= 1'b0;
            frame_timeout <= 1'b0;

            if (framing_error) begin
                state         <= WAIT_SOF0;
                byte_idx      <= '0;
                timeout_count <= '0;
                packet_bits   <= '0;
            end else begin
                unique case (state)
                WAIT_SOF0: begin
                    timeout_count <= '0;
                    if (rx_valid) begin
                        if (rx_data == SOF[15:8]) begin
                            state <= WAIT_SOF1;
                        end
                    end
                end

                WAIT_SOF1: begin
                    timeout_count <= '0;
                    if (rx_valid) begin
                        if (rx_data == SOF[7:0]) begin
                            state        <= READ_PACKET;
                            byte_idx     <= '0;
                            timeout_count <= '0;
                            packet_bits  <= '0;
                            sof_detected <= 1'b1;
                        end else if (rx_data == SOF[15:8]) begin
                            state <= WAIT_SOF1;
                        end else begin
                            state <= WAIT_SOF0;
                        end
                    end
                end

                READ_PACKET: begin
                    if (rx_valid) begin
                        timeout_count <= '0;
                        packet_bits[PACKET_BITS-1-(byte_idx*8) -: 8] <= rx_data;
                        if (byte_idx == PACKET_BYTES - 1) begin
                            state    <= EMIT_PACKET;
                            byte_idx <= '0;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end else if (timeout_count == FRAME_TIMEOUT_CYCLES - 1) begin
                        state         <= WAIT_SOF0;
                        byte_idx      <= '0;
                        timeout_count <= '0;
                        packet_bits   <= '0;
                        frame_timeout <= 1'b1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                EMIT_PACKET: begin
                    timeout_count <= '0;
                    packet_valid  <= 1'b1;
                    state         <= WAIT_SOF0;
                end

                default: begin
                    state         <= WAIT_SOF0;
                    timeout_count <= '0;
                end
                endcase
            end
        end
    end
endmodule
