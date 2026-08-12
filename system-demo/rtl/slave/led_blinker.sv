module led_blinker #(
    parameter int BLINK_CYCLES = 10_000_000
) (
    input  logic clk,
    input  logic rst,
    input  logic pulse,
    output logic led_on
);
    localparam int COUNT_W = $clog2(BLINK_CYCLES + 1);
    localparam logic [COUNT_W-1:0] BLINK_RELOAD = BLINK_CYCLES;

    logic [COUNT_W-1:0] count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            count  <= '0;
            led_on <= 1'b0;
        end else begin
            if (pulse) begin
                count  <= BLINK_RELOAD;
                led_on <= 1'b1;
            end else if (count != '0) begin
                count <= count - 1'b1;
                if (count == {{(COUNT_W-1){1'b0}}, 1'b1}) begin
                    led_on <= 1'b0;
                end
            end else begin
                led_on <= 1'b0;
            end
        end
    end
endmodule
