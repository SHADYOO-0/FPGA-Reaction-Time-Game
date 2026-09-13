//FPGA reaction timer game 

module debounce_edge(  // Cleans a noisy mechanical push-button and converts a press into a single 1 clock cycle pulse
    input  wire clk,
    input  wire rst_n,
    input  wire btn_in,   
    output reg  pulse     
);
    reg [2:0] sr;
    reg clean, clean_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr <= 3'b111;
            clean <= 0;
            clean_d <= 0;
            pulse <= 0;
        end else begin
            sr <= {sr[1:0], ~btn_in};   
            if (sr == 3'b111) clean <= 1;
            else if (sr == 3'b000) clean <= 0;
            clean_d <= clean;
            pulse <= clean & ~clean_d; 
        end
    end
endmodule

module random_delay( // Generates a pseudo-random waiting time between 0.5s and 3s after the player presses start
    input wire clk,
    input wire rst_n,
    input wire arm,    
    output reg  done    
);
    reg [15:0] lfsr;
    wire fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    reg [27:0] target;
    reg [27:0] cnt;
    reg running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr    <= 16'hACE1;
            target  <= 0;
            cnt     <= 0;
            running <= 0;
            done    <= 0;
        end else begin
            lfsr <= {lfsr[14:0], fb}; 
            done <= 0;

            if (arm) begin
                case (lfsr[2:0])
                    3'd0: target <= 28'd25_000_000;   
                    3'd1: target <= 28'd37_500_000;   
                    3'd2: target <= 28'd50_000_000;   
                    3'd3: target <= 28'd75_000_000;   
                    3'd4: target <= 28'd100_000_000;  
                    3'd5: target <= 28'd112_500_000;  
                    3'd6: target <= 28'd125_000_000;  
                    3'd7: target <= 28'd150_000_000;  
                endcase
                cnt     <= 0;
                running <= 1;
            end else if (running) begin
                if (cnt >= target - 1) begin
                    done    <= 1;
                    running <= 0;
                    cnt     <= 0;
                end else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end
endmodule

module fsm_ms_counter( // Main control unit of the game
    input wire clk,
    input wire rst_n,
    input wire start_pulse,  
    input wire react_pulse, 
    input wire delay_done,   
    output reg delay_arm,    
    output reg led_go,       
    output reg [13:0] captured_ms,  
    output reg show_result   
);
    localparam IDLE = 2'd0;
    localparam WAIT_RANDOM = 2'd1;
    localparam STIMULUS = 2'd2;
    localparam DISPLAY = 2'd3;

    reg [1:0] state;

    reg [15:0] prescaler; 
    reg [13:0] ms_cnt;    

    reg [27:0] disp_cnt;
    localparam DISP_TIME = 28'd250_000_000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            prescaler <= 0;
            ms_cnt <= 0;
            captured_ms <= 0;
            led_go <= 0;
            delay_arm <= 0;
            show_result <= 0;
            disp_cnt <= 0;
        end else begin
            delay_arm <= 0; 

            case (state)

                IDLE: begin
                    led_go <= 0;
                    show_result <= 0;
                    prescaler <= 0;
                    ms_cnt <= 0;
                    disp_cnt <= 0;

                    if (start_pulse) begin
                        state <= WAIT_RANDOM;
                        delay_arm <= 1; 
                    end
                end

                WAIT_RANDOM: begin
                    led_go <= 0;

                    if (delay_done) begin
                        state <= STIMULUS;
                        led_go <= 1;
                        prescaler <= 0;
                        ms_cnt <= 0;
                    end
                end

                STIMULUS: begin
                    led_go <= 1;

                    if (prescaler == 16'd49999) begin
                        prescaler <= 0;
                        ms_cnt <= ms_cnt + 1;
                    end else begin
                        prescaler <= prescaler + 1;
                    end

                    if (react_pulse) begin
                        captured_ms <= ms_cnt; 
                        show_result <= 1;
                        led_go <= 0;
                        state <= DISPLAY;
                        disp_cnt <= 0;
                    end
                end

                DISPLAY: begin
                    led_go <= 0;
                    show_result <= 1;
                    disp_cnt <= disp_cnt + 1;

                    if (disp_cnt >= DISP_TIME) begin
                        show_result <= 0;
                        state <= IDLE;
                    end
                end

            endcase
        end
    end
endmodule

module bin_to_bcd(    // Converts a 14 bit binary number into 4 BCD digits using double dabble algorithm
    input wire [13:0] bin,
    output reg  [3:0]  d3,  
    output reg  [3:0]  d2,  
    output reg  [3:0]  d1,  
    output reg  [3:0]  d0   
);
    integer    i;
    reg [29:0] s; 

    always @(*) begin
        s = 30'd0;
        s[13:0] = bin;

        for (i = 0; i < 14; i = i + 1) begin
            if (s[17:14] >= 5) s[17:14] = s[17:14] + 3;
            if (s[21:18] >= 5) s[21:18] = s[21:18] + 3;
            if (s[25:22] >= 5) s[25:22] = s[25:22] + 3;
            if (s[29:26] >= 5) s[29:26] = s[29:26] + 3;
            s = s << 1;
        end

        d0 = s[17:14]; 
        d1 = s[21:18]; 
        d2 = s[25:22]; 
        d3 = s[29:26]; 
    end
endmodule

module seg7_display(  // Multiplexed 4 digit 7 segment display driver
    input  wire clk,
    input  wire rst_n,
    input  wire [3:0] d3, d2, d1, d0,
    input  wire show,       
    output reg  [6:0] seg,        
    output reg  [3:0] an          
);
    reg [15:0] ref_cnt;
    reg [1:0] sel;
    reg [3:0] cur;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_cnt <= 0;
            sel <= 0;
        end else begin
            if (ref_cnt >= 16'd49999) begin
                ref_cnt <= 0;
                sel <= sel + 1;
            end else begin
                ref_cnt <= ref_cnt + 1;
            end
        end
    end
    always @(*) begin
        an  = 4'b1111; 
        cur = 4'd10;   

        if (show) begin
            case (sel)
                2'd3: begin an = 4'b0111; cur = d3; end 
                2'd2: begin an = 4'b1011; cur = d2; end 
                2'd1: begin an = 4'b1101; cur = d1; end 
                2'd0: begin an = 4'b1110; cur = d0; end 
            endcase
        end
    end
    always @(*) begin
        case (cur)
            4'd0: seg = 7'b1000000; 
            4'd1: seg = 7'b1111001; 
            4'd2: seg = 7'b0100100; 
            4'd3: seg = 7'b0110000; 
            4'd4: seg = 7'b0011001; 
            4'd5: seg = 7'b0010010; 
            4'd6: seg = 7'b0000010; 
            4'd7: seg = 7'b1111000; 
            4'd8: seg = 7'b0000000; 
            4'd9: seg = 7'b0010000; 
            default: seg = 7'b1111111; 
        endcase
    end
endmodule

module ProjetVerilog( // Top level
    input wire clk,       
    input wire rst_n,     
    input wire btn_start, 
    input wire btn_react, 
    output wire led_go,    
    output wire [6:0] seg,       
    output wire [3:0] an         
);
    wire start_p, react_p;
    wire d_arm, d_done;
    wire [13:0] cap_ms;
    wire show;
    wire [3:0]  bcd3, bcd2, bcd1, bcd0;
    wire fsm_led;

    debounce_edge db_start(
        .clk(clk), .rst_n(rst_n),
        .btn_in(btn_start), .pulse(start_p)
    );
    debounce_edge db_react(
        .clk(clk), .rst_n(rst_n),
        .btn_in(btn_react), .pulse(react_p)
    );
    random_delay rd(
        .clk(clk), .rst_n(rst_n),
        .arm(d_arm), .done(d_done)
    );
    fsm_ms_counter fsm(
        .clk(clk),         .rst_n(rst_n),
        .start_pulse(start_p),  .react_pulse(react_p),
        .delay_done(d_done),    .delay_arm(d_arm),
        .led_go(fsm_led),       .captured_ms(cap_ms),
        .show_result(show)
    );

    assign led_go = ~fsm_led;

    bin_to_bcd b2b(
        .bin(cap_ms),
        .d3(bcd3), .d2(bcd2), .d1(bcd1), .d0(bcd0)
    );

    seg7_display disp(
        .clk(clk), .rst_n(rst_n),
        .d3(bcd3), .d2(bcd2), .d1(bcd1), .d0(bcd0),
        .show(show), .seg(seg), .an(an)
    );

endmodule