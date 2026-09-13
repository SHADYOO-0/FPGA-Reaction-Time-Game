`timescale 1ns/1ps

module tb_FPGA_reaction_timer_game;

    // 50MHz clk, 50,000 cycles =1ms

    reg clk;
    reg rst_n;
    reg start_pulse;
    reg react_pulse;
    reg delay_done;

    wire delay_arm;
    wire led_go;
    wire [13:0] captured_ms;
    wire show_result;

    FPGA_reaction_timer_game dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_pulse(start_pulse),
        .react_pulse(react_pulse),
        .delay_done(delay_done),
        .delay_arm(delay_arm),
        .led_go(led_go),
        .captured_ms(captured_ms),
        .show_result(show_result)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    task start_game;
        begin
            @(negedge clk);
            start_pulse=1;
            @(negedge clk);
            start_pulse=0;
        end
    endtask

    task finish_random_delay;
        begin
            @(negedge clk);
            delay_done = 1;
            @(negedge clk);
            delay_done = 0;
        end
    endtask

    task react;
        begin
            @(negedge clk);
            react_pulse = 1;
            @(negedge clk);
            react_pulse = 0;
        end
    endtask

    task wait_ms;
        input integer ms;
        integer i;
        begin
            for (i=0; i<ms*50000; i=i+1)
                @(posedge clk);
        end
    endtask

    integer passed;
    integer failed;

    task check;
        input integer expected;
        input integer test_number;
        begin
            if (captured_ms==expected) begin
                $display("test %0d passed: captured_ms=%0d",test_number,captured_ms);
                passed=passed+1;
            end
            else begin
                $display("test %0d failed: expected %0d, got %0d",
                         test_number,expected,captured_ms);
                failed=failed+1;
            end
        end
    endtask

    initial begin

        // Waveform recording
        $dumpfile("waveform.vcd");
        $dumpvars(0,tb_FPGA_reaction_timer_game);

        start_pulse=0;
        react_pulse=0;
        delay_done=0;
        passed=0;
        failed=0;

        rst_n=0;
        repeat (5) @(posedge clk);
        rst_n=1;
        repeat (2) @(posedge clk);

        start_game();

        @(posedge clk);
        if (delay_arm ==1) begin
            $display("Test 1 passed");
            passed=passed+1;
        end
        else begin
            $display("Test 1 failed");
            failed=failed+1;
        end

        finish_random_delay();

        @(posedge clk);
        if (led_go==1) begin
            $display("Test 2 passed");
            passed=passed+1;
        end
        else begin
            $display("Test 2 failed");
            failed=failed+1;
        end

        react();
        @(posedge clk);
        check(0,3);

        rst_n=0;
        repeat (2) @(posedge clk);
        rst_n=1;
        @(posedge clk);

        if (captured_ms==0 && led_go==0 && show_result==0) begin
            $display("Test 4 passed");
            passed=passed+1;
        end
        else begin
            $display("Test 4 failed");
            failed=failed+1;
        end

        start_game();
        finish_random_delay();

        repeat (50005) @(posedge clk);
        react();

        @(posedge clk);
        check(1,5);

        rst_n=0;
        repeat (2) @(posedge clk);
        rst_n=1;
        @(posedge clk);

        start_game();
        finish_random_delay();

        repeat (500005) @(posedge clk);
        react();

        @(posedge clk);
        check(10, 6);

        if (show_result==1) begin
            $display("Test 7 passed:show_result=1");
            passed=passed+1;
        end
        else begin
            $display("Test 7 failed");
            failed=failed+1;
        end

        $display("");
        $display("Simulation completed");
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        $finish;
    end

endmodule
