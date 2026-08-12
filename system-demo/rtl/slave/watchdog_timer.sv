module watchdog_timer #(
    parameter int TIMEOUT_CYCLES = 300_000_000
) (
    input  logic clk,
    input  logic rst,
    input  logic valid_packet_pulse,
    output logic timeout
);
    localparam int COUNT_W = $clog2(TIMEOUT_CYCLES + 1);
    localparam logic [COUNT_W-1:0] TIMEOUT_LIMIT = TIMEOUT_CYCLES;

    logic [COUNT_W-1:0] count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            count   <= '0;
            timeout <= 1'b1;
        end else if (valid_packet_pulse) begin
            count   <= '0;
            timeout <= 1'b0;
        end else if (count < TIMEOUT_LIMIT) begin
            count <= count + 1'b1;
            if (count == TIMEOUT_LIMIT - 1'b1) begin
                timeout <= 1'b1;
            end
        end else begin
            timeout <= 1'b1;
        end
    end
endmodule
