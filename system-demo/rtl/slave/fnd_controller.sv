module fnd_controller (
    input  [15:0] fnd_in_data,
    input         dash_mode,
    input         clk,
    input         reset,
    output [ 3:0] fnd_digit,
    output [ 7:0] fnd_data
);
    wire [1:0] w_digit_sel;
    wire [3:0] w_nibble_0, w_nibble_1, w_nibble_2, w_nibble_3;
    wire [3:0] w_mux_4_1_out;
    wire       w_1khz;

    clk_div U_CLK_DIV (
        .clk   (clk),
        .reset (reset),
        .o_1khz(w_1khz)
    );

    counter_4 U_COUNTER_4 (
        .clk      (w_1khz),
        .reset    (reset),
        .digit_sel(w_digit_sel)
    );

    decoder_2_4 U_DECODER_2_4 (
        .btn      (w_digit_sel),
        .fnd_digit(fnd_digit)
    );

    hex_splitter U_HEX_SPL (
        .in_data (fnd_in_data),
        .nibble_0(w_nibble_0),
        .nibble_1(w_nibble_1),
        .nibble_2(w_nibble_2),
        .nibble_3(w_nibble_3)
    );

    mux4_1 U_MUX_4_1 (
        .digit_1   (w_nibble_0),
        .digit_10  (w_nibble_1),
        .digit_100 (w_nibble_2),
        .digit_1000(w_nibble_3),
        .sel       (w_digit_sel),
        .mux_out   (w_mux_4_1_out)
    );

    hex_to_7seg U_HEX_7SEG (
        .hex     (dash_mode ? 4'hF : w_mux_4_1_out),
        .dash    (dash_mode),
        .fnd_data(fnd_data)
    );

endmodule


module clk_div (
    input      clk,
    input      reset,
    output reg o_1khz
);
    reg [16:0] counter_r;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_r <= 1'b0;
            o_1khz    <= 1'b0;
        end else begin
            if (counter_r == 99999) begin
                counter_r <= 0;
                o_1khz    <= 1'b1;
            end else begin
                counter_r <= counter_r + 1;
                o_1khz    <= 1'b0;
            end
        end
    end

endmodule


module counter_4 (
    input        clk,
    input        reset,
    output [1:0] digit_sel
);
    reg [1:0] counter_r;

    assign digit_sel = counter_r;

    always @(posedge clk, posedge reset) begin
        if (reset) counter_r <= 0;
        else counter_r <= counter_r + 1;
    end

endmodule


module decoder_2_4 (
    input      [1:0] btn,
    output reg [3:0] fnd_digit
);

    always @(btn) begin
        case (btn)
            2'b00:   fnd_digit = 4'b1110;
            2'b01:   fnd_digit = 4'b1101;
            2'b10:   fnd_digit = 4'b1011;
            default: fnd_digit = 4'b0111;
        endcase
    end

endmodule


module mux4_1 (
    input      [3:0] digit_1,
    input      [3:0] digit_10,
    input      [3:0] digit_100,
    input      [3:0] digit_1000,
    input      [1:0] sel,
    output reg [3:0] mux_out
);

    always @(*) begin
        case (sel)
            2'b00:   mux_out = digit_1;
            2'b01:   mux_out = digit_10;
            2'b10:   mux_out = digit_100;
            default: mux_out = digit_1000;
        endcase
    end
endmodule


module hex_splitter (
    input  [15:0] in_data,
    output [ 3:0] nibble_0,
    output [ 3:0] nibble_1,
    output [ 3:0] nibble_2,
    output [ 3:0] nibble_3
);

    assign nibble_0 = in_data[3:0];
    assign nibble_1 = in_data[7:4];
    assign nibble_2 = in_data[11:8];
    assign nibble_3 = in_data[15:12];

endmodule


module hex_to_7seg (
    input      [3:0] hex,
    input            dash,
    output reg [7:0] fnd_data
);

    always @(*) begin
        if (dash) begin
            fnd_data = 8'hBF;
        end else begin
            case (hex)
                4'd0: fnd_data = 8'hC0;
                4'd1: fnd_data = 8'hF9;
                4'd2: fnd_data = 8'hA4;
                4'd3: fnd_data = 8'hB0;
                4'd4: fnd_data = 8'h99;
                4'd5: fnd_data = 8'h92;
                4'd6: fnd_data = 8'h82;
                4'd7: fnd_data = 8'hF8;
                4'd8: fnd_data = 8'h80;
                4'd9: fnd_data = 8'h90;
                4'hA: fnd_data = 8'h88;
                4'hB: fnd_data = 8'h83;
                4'hC: fnd_data = 8'hC6;
                4'hD: fnd_data = 8'hA1;
                4'hE: fnd_data = 8'h86;
                4'hF: fnd_data = 8'h8E;
                default: fnd_data = 8'hFF;
            endcase
        end
    end
endmodule
