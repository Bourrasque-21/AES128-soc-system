import aes_pkg::*;

module aes_sbox_bram_sync (
    input  logic       clk,
    input  logic [7:0] addr,
    output logic [7:0] data
);
    (* rom_style = "block", ram_style = "block" *)
    logic [7:0] sbox_rom [0:255];

    integer init_idx;

    initial begin
        for (init_idx = 0; init_idx < 256; init_idx = init_idx + 1) begin
            sbox_rom[init_idx] = aes_sbox_byte(init_idx[7:0]);
        end
    end

    always_ff @(posedge clk) begin
        data <= sbox_rom[addr];
    end
endmodule

