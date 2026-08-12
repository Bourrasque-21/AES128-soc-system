module fifo #(
    parameter DEPTH   = 4,
    parameter D_WIDTH = 8
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 push,
    input  logic                 pop,
    input  logic [(D_WIDTH-1):0] push_data,
    output logic [(D_WIDTH-1):0] pop_data,
    output logic                 full,
    output logic                 empty
);

    logic [$clog2(DEPTH)-1 : 0] w_wptr, w_rptr;
    logic w_do_we;

    fifo_mem #(
        .DEPTH  (DEPTH),
        .D_WIDTH(D_WIDTH)
    ) U_FIFO_MEM (
        .clk  (clk),
        .we   (w_do_we),
        .waddr(w_wptr),
        .raddr(w_rptr),
        .wdata(push_data),
        .rdata(pop_data)
    );

    fifo_ctrl #(
        .DEPTH(DEPTH)
    ) U_FIFO_CTRL (
        .clk  (clk),
        .rst  (rst),
        .wr_en(push),
        .rd_en(pop),
        .w_ptr(w_wptr),
        .r_ptr(w_rptr),
        .full (full),
        .empty(empty),
        .do_we(w_do_we)
    );

endmodule


module fifo_mem #(
    parameter DEPTH   = 4,
    parameter D_WIDTH = 8
) (
    input  logic                     clk,
    input  logic                     we,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [$clog2(DEPTH)-1:0] raddr,
    input  logic [      D_WIDTH-1:0] wdata,
    output logic [      D_WIDTH-1:0] rdata
);

    logic [(D_WIDTH-1):0] mem[0:(DEPTH-1)];

    always_ff @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
    end

    assign rdata = mem[raddr];

endmodule


module fifo_ctrl #(
    parameter DEPTH = 4
) (
    input logic clk,
    input logic rst,
    input logic wr_en,
    input logic rd_en,

    output logic [$clog2(DEPTH)-1:0] w_ptr,
    output logic [$clog2(DEPTH)-1:0] r_ptr,
    output logic                     full,
    output logic                     empty,
    output logic                     do_we
);

    logic [$clog2(DEPTH):0] w_ptr_reg, w_ptr_next, r_ptr_reg, r_ptr_next;
    logic full_reg, full_next, empty_reg, empty_next, wr_fire, rd_fire;

    assign w_ptr = w_ptr_reg[$clog2(DEPTH)-1:0];
    assign r_ptr = r_ptr_reg[$clog2(DEPTH)-1:0];
    assign full  = full_reg;
    assign empty = empty_reg;

    assign do_we = wr_en && (!full_reg || rd_fire);

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            w_ptr_reg <= 0;
            r_ptr_reg <= 0;
            full_reg  <= 0;
            empty_reg <= 1;
        end else begin
            w_ptr_reg <= w_ptr_next;
            r_ptr_reg <= r_ptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
        end
    end

    always_comb begin
        w_ptr_next = w_ptr_reg;
        r_ptr_next = r_ptr_reg;
        full_next = full_reg;
        empty_next = empty_reg;

        rd_fire = rd_en && !empty_reg;
        wr_fire = wr_en && (!full_reg || rd_fire);

        case ({
            wr_fire, rd_fire
        })
            2'b10: begin
                w_ptr_next = w_ptr_reg + 1'b1;
            end

            2'b01: begin
                r_ptr_next = r_ptr_reg + 1'b1;
            end

            2'b11: begin
                w_ptr_next = w_ptr_reg + 1'b1;
                r_ptr_next = r_ptr_reg + 1'b1;
            end
        endcase

        empty_next = (w_ptr_next == r_ptr_next);
        full_next = (w_ptr_next[$clog2(DEPTH)] != r_ptr_next[$clog2(DEPTH)]) &&
            (w_ptr_next[$clog2(DEPTH)-1:0] == r_ptr_next[$clog2(DEPTH)-1:0]);
    end

endmodule
