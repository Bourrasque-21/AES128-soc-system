module tb_key_update_master_slave;
    localparam int CLK_FREQ       = 100_000_000;
    localparam int UART_BAUD_RATE = 10_000_000;

    localparam logic [7:0]  VERSION          = 8'h01;
    localparam logic [7:0]  MASTER_DEVICE_ID = 8'h10;
    localparam logic [7:0]  SLAVE_TARGET_ID  = 8'h20;
    localparam logic [15:0] MASTER_SOURCE_ID = 16'h0010;
    localparam logic [15:0] SLAVE_SOURCE_ID  = 16'h0020;
    localparam logic [127:0] INITIAL_KEY     = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] SESSION_KEY_1   = 128'h101112131415161718191a1b1c1d1e1f;

    localparam logic [7:0] CMD_HEARTBEAT      = 8'h00;
    localparam logic [7:0] CMD_SW_RESPONSE    = 8'h04;
    localparam logic [7:0] CMD_KEY_UPDATE_ACK = 8'h06;

    logic clk;
    logic rst;

    logic master_uart_tx;
    logic master_uart_rx;
    logic slave_uart_tx;
    logic slave_uart_rx;

    logic send_heartbeat;
    logic send_counter;
    logic send_led_control;
    logic send_read_sw;
    logic send_key_update;
    logic [15:0] counter_value;
    logic [7:0] led_value;
    logic [127:0] new_session_key;
    logic [15:0] new_key_epoch;

    logic master_tx_busy_any;
    logic master_rx_response_valid;
    logic master_key_update_done;
    logic master_key_update_pending;
    logic master_auth_error_latched;
    logic [15:0] master_active_key_epoch;
    logic [7:0] master_last_response_command;
    logic [7:0] master_last_response_status;
    logic [7:0] master_last_switch_value;

    logic [15:0] sw;
    logic btn_send_sw;
    logic [15:0] led;
    logic [3:0] fnd_digit;
    logic [7:0] fnd_data;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    assign slave_uart_rx  = master_uart_tx;
    assign master_uart_rx = slave_uart_tx;

    aes128_demo_master_top #(
        .VERSION            (VERSION),
        .MASTER_DEVICE_ID   (MASTER_DEVICE_ID),
        .SLAVE_TARGET_ID    (SLAVE_TARGET_ID),
        .MASTER_SOURCE_ID   (MASTER_SOURCE_ID),
        .INITIAL_MASTER_KEY (INITIAL_KEY),
        .TX_FIXED_IV        (32'h01010001),
        .CLK_FREQ           (CLK_FREQ),
        .UART_BAUD_RATE     (UART_BAUD_RATE)
    ) dut_master (
        .clk                   (clk),
        .rst                   (rst),
        .uart_rx               (master_uart_rx),
        .uart_tx               (master_uart_tx),
        .send_heartbeat        (send_heartbeat),
        .send_counter          (send_counter),
        .send_led_control      (send_led_control),
        .send_read_sw          (send_read_sw),
        .send_key_update       (send_key_update),
        .counter_value         (counter_value),
        .led_value             (led_value),
        .new_session_key       (new_session_key),
        .new_key_epoch         (new_key_epoch),
        .tx_busy_any           (master_tx_busy_any),
        .rx_response_valid     (master_rx_response_valid),
        .key_update_done       (master_key_update_done),
        .key_update_pending    (master_key_update_pending),
        .auth_error_latched    (master_auth_error_latched),
        .active_key_epoch      (master_active_key_epoch),
        .last_response_command (master_last_response_command),
        .last_response_status  (master_last_response_status),
        .last_switch_value     (master_last_switch_value)
    );

    aes128_demo_slave_top #(
        .VERSION            (VERSION),
        .MASTER_DEVICE_ID   (MASTER_DEVICE_ID),
        .SLAVE_TARGET_ID    (SLAVE_TARGET_ID),
        .SLAVE_SOURCE_ID    (SLAVE_SOURCE_ID),
        .INITIAL_MASTER_KEY (INITIAL_KEY),
        .TX_FIXED_IV        (32'h02010001),
        .CLK_FREQ           (CLK_FREQ),
        .UART_BAUD_RATE     (UART_BAUD_RATE),
        .BLINK_CYCLES       (8),
        .WATCHDOG_CYCLES    (2_000_000)
    ) dut_slave (
        .clk         (clk),
        .rst         (rst),
        .uart_rx     (slave_uart_rx),
        .uart_tx     (slave_uart_tx),
        .sw          (sw),
        .btn_send_sw (btn_send_sw),
        .led         (led),
        .fnd_digit   (fnd_digit),
        .fnd_data    (fnd_data)
    );

    task automatic reset_system;
        begin
            rst              = 1'b1;
            send_heartbeat   = 1'b0;
            send_counter     = 1'b0;
            send_led_control = 1'b0;
            send_read_sw     = 1'b0;
            send_key_update  = 1'b0;
            counter_value    = 16'h0000;
            led_value        = 8'h00;
            new_session_key  = SESSION_KEY_1;
            new_key_epoch    = 16'h0001;
            sw               = 16'h805A;
            btn_send_sw      = 1'b0;
            repeat (30) @(posedge clk);
            rst = 1'b0;
            repeat (30) @(posedge clk);
        end
    endtask

    task automatic wait_master_idle;
        int cycles;
        begin
            cycles = 0;
            while ((master_tx_busy_any !== 1'b0) && (cycles < 500000)) begin
                @(posedge clk);
                cycles++;
            end
            if (master_tx_busy_any !== 1'b0) begin
                $fatal(1, "[FAIL] timed out waiting for master TX idle");
            end
        end
    endtask

    task automatic pulse_counter(input logic [15:0] value);
        begin
            wait_master_idle();
            counter_value = value;
            @(negedge clk);
            send_counter = 1'b1;
            @(negedge clk);
            send_counter = 1'b0;
        end
    endtask

    task automatic pulse_key_update(input logic [127:0] key, input logic [15:0] epoch);
        begin
            wait_master_idle();
            new_session_key = key;
            new_key_epoch   = epoch;
            @(negedge clk);
            send_key_update = 1'b1;
            @(negedge clk);
            send_key_update = 1'b0;
        end
    endtask

    task automatic pulse_read_switch;
        begin
            wait_master_idle();
            @(negedge clk);
            send_read_sw = 1'b1;
            @(negedge clk);
            send_read_sw = 1'b0;
        end
    endtask

    task automatic wait_slave_display(input logic [15:0] expected, input string label);
        int cycles;
        begin
            cycles = 0;
            while ((dut_slave.fnd_plain_value !== expected) && (cycles < 1500000)) begin
                @(posedge clk);
                cycles++;
            end
            if (dut_slave.fnd_plain_value !== expected) begin
                $fatal(1, "[FAIL] %s: expected display 0x%04h, got 0x%04h",
                       label, expected, dut_slave.fnd_plain_value);
            end
            $display("[PASS] %s display = 0x%04h", label, expected);
        end
    endtask

    task automatic wait_master_response(input logic [7:0] expected_cmd, input string label);
        int cycles;
        begin
            cycles = 0;
            while (cycles < 1500000) begin
                @(posedge clk);
                if (master_rx_response_valid && (master_last_response_command == expected_cmd)) begin
                    $display("[PASS] %s response command = 0x%02h", label, expected_cmd);
                    return;
                end
                cycles++;
            end
            $fatal(1, "[FAIL] %s: timed out waiting for response command 0x%02h",
                   label, expected_cmd);
        end
    endtask

    task automatic wait_key_update_done;
        int cycles;
        begin
            cycles = 0;
            while ((master_key_update_done !== 1'b1) && (cycles < 2000000)) begin
                @(posedge clk);
                cycles++;
            end
            if (master_key_update_done !== 1'b1) begin
                $fatal(1, "[FAIL] timed out waiting for key update ACK");
            end
            @(posedge clk);
            if (master_active_key_epoch !== 16'h0001) begin
                $fatal(1, "[FAIL] master key epoch expected 1, got %0d", master_active_key_epoch);
            end
            if (dut_slave.key_epoch !== 16'h0001) begin
                $fatal(1, "[FAIL] slave key epoch expected 1, got %0d", dut_slave.key_epoch);
            end
            $display("[PASS] key update ACK received and both endpoints switched to epoch 1");
        end
    endtask

    initial begin
        reset_system();

        $display("[TEST] initial key counter update");
        pulse_counter(16'h1234);
        wait_slave_display(16'h1234, "initial-key counter");
        wait_master_response(CMD_HEARTBEAT, "initial-key pong");

        $display("[TEST] authenticated session key update");
        pulse_key_update(SESSION_KEY_1, 16'h0001);
        wait_key_update_done();

        $display("[TEST] new key counter update");
        pulse_counter(16'hBEEF);
        wait_slave_display(16'hBEEF, "new-key counter");
        wait_master_response(CMD_HEARTBEAT, "new-key pong");

        $display("[TEST] switch response after key update");
        pulse_read_switch();
        wait_master_response(CMD_SW_RESPONSE, "switch read");
        if (master_last_switch_value !== 8'h5A) begin
            $fatal(1, "[FAIL] expected switch response 0x5A, got 0x%02h",
                   master_last_switch_value);
        end
        $display("[PASS] switch response value = 0x%02h", master_last_switch_value);

        if (master_auth_error_latched || dut_slave.error_latched) begin
            $fatal(1, "[FAIL] unexpected auth/error latch: master=%0b slave=%0b",
                   master_auth_error_latched, dut_slave.error_latched);
        end

        $display("PASS: AES-128 GCM UART master/slave key-update integration test passed");
        $finish;
    end
endmodule
