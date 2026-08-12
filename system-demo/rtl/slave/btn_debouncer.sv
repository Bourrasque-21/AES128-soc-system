module btn_debouncer #(
    parameter int WAIT_TIME = 500_000
)(
    input  logic clk,        
    input  logic rst,        
    input  logic button_in,  
    output logic button_pulse
);

    localparam int COUNTER_WIDTH = $clog2(WAIT_TIME);
    
    logic [COUNTER_WIDTH-1:0] counter;
    logic sync_0;
    logic sync_1; 
    logic debounced_state;  
    logic debounced_state_d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_0 <= 1'b0;
            sync_1 <= 1'b0;
        end else begin
            sync_0 <= button_in;
            sync_1 <= sync_0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter         <= '0;
            debounced_state <= 1'b0;
        end else begin
            if (debounced_state == sync_1) begin
                counter <= '0; 
            end else begin
                counter <= counter + 1'b1;
                if (counter == WAIT_TIME - 1) begin
                    debounced_state <= sync_1; 
                    counter         <= '0;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            debounced_state_d <= 1'b0;
        end else begin
            debounced_state_d <= debounced_state;
        end
    end

    assign button_pulse = debounced_state & ~debounced_state_d;

endmodule