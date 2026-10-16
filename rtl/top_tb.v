`timescale 1ns / 1ps

`include "top.v"

module top_tb;

    /* ==========================================================
       CONVOLUTION PARAMETERS
    ========================================================== */

    parameter STRIDE      = 2;
    parameter FILTER_SIZE = 5;
    parameter IFMAP_SIZE  = 19;

    localparam OFMAP_SIZE =
        ((IFMAP_SIZE - FILTER_SIZE) / STRIDE) + 1;

    /* ==========================================================
       HARDWARE PARAMETERS
    ========================================================== */

    localparam MAX_IFMAP_SIZE = 28;
    localparam MAX_FILTER_SIZE = 5;
    localparam PE_ARRAY_WIDTH  = 5;
    localparam PE_ARRAY_HEIGHT = MAX_FILTER_SIZE;
    localparam MAX_OFMAP_SIZE = 28;
    localparam MAX_STRIDE = 5;
    localparam DWIDTH          = 8;
    localparam OUPUT_DWIDTH    = 20;

    /* ==========================================================
       SIMULATION PARAMETERS
    ========================================================== */

    localparam LOAD_FROM_FILE = 0;
    localparam real CLK_PERIOD = 5;
    integer SEED = 0;

    /* ==========================================================
       DATA ARRAYS
    ========================================================== */

    reg signed [DWIDTH-1:0] filter [0:FILTER_SIZE-1][0:FILTER_SIZE-1];
    reg signed [DWIDTH-1:0] ifmap  [0:IFMAP_SIZE-1][0:IFMAP_SIZE-1];

    // If loaded from files
    reg signed [DWIDTH-1:0] filter_mem [0:FILTER_SIZE*FILTER_SIZE-1];
    reg signed [DWIDTH-1:0] ifmap_mem  [0:IFMAP_SIZE*IFMAP_SIZE-1];

    reg signed [OUPUT_DWIDTH-1:0] expected_ofmap [0:OFMAP_SIZE-1][0:OFMAP_SIZE-1];
    reg signed [OUPUT_DWIDTH-1:0] actual_ofmap   [0:OFMAP_SIZE-1][0:OFMAP_SIZE-1];

    /* ==========================================================
       SIGNALS
    ========================================================== */

    reg clk;
    reg rst;
    reg start;
    reg pooling = 0;

    reg [$clog2(MAX_STRIDE+1)-1:0] stride = STRIDE;
    reg [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_row_size  = IFMAP_SIZE;
    reg [$clog2(MAX_FILTER_SIZE+1)-1:0] filter_row_size = FILTER_SIZE;
    reg [$clog2(MAX_OFMAP_SIZE+1)-1:0]  ofmap_row_size  = OFMAP_SIZE;

    reg [$clog2(MAX_IFMAP_SIZE**2+1)-1:0] ifmap_square_size =
        IFMAP_SIZE * IFMAP_SIZE;
    reg [$clog2(MAX_FILTER_SIZE**2+1)-1:0] filter_square_size =
        FILTER_SIZE * FILTER_SIZE;
    reg [$clog2(MAX_OFMAP_SIZE**2+1)-1:0] ofmap_square_size =
        OFMAP_SIZE * OFMAP_SIZE;

    reg signed [DWIDTH-1:0] input_ifmap;
    reg signed [DWIDTH-1:0] input_filter;

    reg wr_to_ifmap_glb;
    reg wr_to_filter_glb;
    reg rd_from_ofmap_glb;

    integer clk_cnt;
    wire done;
    wire signed [OUPUT_DWIDTH-1:0] output_ofmap;

    /* ==========================================================
       DUT
    ========================================================== */

    top #(
        .WIDTH(PE_ARRAY_WIDTH),
        .HEIGHT(PE_ARRAY_HEIGHT),
        .INPUT_BITWIDTH(DWIDTH),
        .PSUM_BITWIDTH(OUPUT_DWIDTH),
        .MAX_IFMAP_SIZE(MAX_IFMAP_SIZE),
        .MAX_FILTER_SIZE(MAX_FILTER_SIZE),
        .MAX_OFMAP_SIZE(MAX_OFMAP_SIZE),
        .MAX_STRIDE(MAX_STRIDE)
    ) top_inst (
        .clk(clk),
        .rst(rst),
        .pooling(pooling),
        .start(start),
        .stride(stride),
        .ifmap_row_size(ifmap_row_size),
        .filter_row_size(filter_row_size),
        .ofmap_row_size(ofmap_row_size),
        .ifmap_square_size(ifmap_square_size),
        .filter_square_size(filter_square_size),
        .ofmap_square_size(ofmap_square_size),
        .input_ifmap(input_ifmap),
        .input_filter(input_filter),
        .wr_to_ifmap_glb(wr_to_ifmap_glb),
        .wr_to_filter_glb(wr_to_filter_glb),
        .rd_from_ofmap_glb(rd_from_ofmap_glb),
        .output_ofmap(output_ofmap),
        .done(done)
    );

    /* ==========================================================
       DISPLAY TASKS
    ========================================================== */

    task display_ifmap;
        integer i, j;
        begin
            $display("\nIFMAP:");
            for (i = 0; i < IFMAP_SIZE; i = i + 1) begin
                for (j = 0; j < IFMAP_SIZE; j = j + 1)
                    $write("%4d ", ifmap[i][j]);
                $display("");
            end
        end
    endtask

    task display_filter;
        integer i, j;
        begin
            $display("\nFILTER:");
            for (i = 0; i < FILTER_SIZE; i = i + 1) begin
                for (j = 0; j < FILTER_SIZE; j = j + 1)
                    $write("%4d ", filter[i][j]);
                $display("");
            end
        end
    endtask

    task display_expected_ofmap;
        integer i, j;
        begin
            $display("\nEXPECTED OFMAP:");
            for (i = 0; i < OFMAP_SIZE; i = i + 1) begin
                for (j = 0; j < OFMAP_SIZE; j = j + 1)
                    $write("%6d ", expected_ofmap[i][j]);
                $display("");
            end
        end
    endtask

    task display_actual_ofmap;
        integer i, j;
        begin
            $display("\nACTUAL OFMAP:");
            for (i = 0; i < OFMAP_SIZE; i = i + 1) begin
                for (j = 0; j < OFMAP_SIZE; j = j + 1)
                    $write("%6d ", actual_ofmap[i][j]);
                $display("");
            end
        end
    endtask

    task write_ofmap_to_file;
        integer fd;
        integer i, j;
        begin
            fd = $fopen("ofmap.mem", "w");

            for (i = 0; i < OFMAP_SIZE; i = i + 1)
                for (j = 0; j < OFMAP_SIZE; j = j + 1)
                    $fdisplay(fd, "%0h", actual_ofmap[i][j]);

            $fclose(fd);
            $display("💾 ofmap.mem written");
        end
    endtask

    /* ==========================================================
       INIT + GOLDEN MODEL
    ========================================================== */

    task init_filter;
        integer i, j;
        begin
            for (i = 0; i < FILTER_SIZE; i = i + 1)
                for (j = 0; j < FILTER_SIZE; j = j + 1)
                    filter[i][j] = $random % 100;
        end
    endtask

    task init_ifmap;
        integer i, j;
        begin
            for (i = 0; i < IFMAP_SIZE; i = i + 1)
                for (j = 0; j < IFMAP_SIZE; j = j + 1)
                    ifmap[i][j] = $random % 100;
        end
    endtask

    task load_from_files;
    integer i, j;
    begin
        $display("📂 Loading data from files...");

        $readmemh("filter.mem", filter_mem);
        $readmemh("ifmap.mem",  ifmap_mem);

        for (i = 0; i < FILTER_SIZE; i = i + 1)
            for (j = 0; j < FILTER_SIZE; j = j + 1)
                filter[i][j] =
                    filter_mem[i*FILTER_SIZE + j];

        for (i = 0; i < IFMAP_SIZE; i = i + 1)
            for (j = 0; j < IFMAP_SIZE; j = j + 1)
                ifmap[i][j] =
                    ifmap_mem[i*IFMAP_SIZE + j];
    end
    endtask

    task do_convolution;
        integer i, j, ii, jj;
        integer sum;
        begin
            for (i = 0; i < OFMAP_SIZE; i = i + 1)
                for (j = 0; j < OFMAP_SIZE; j = j + 1) begin
                    sum = 0;
                    for (ii = 0; ii < FILTER_SIZE; ii = ii + 1)
                        for (jj = 0; jj < FILTER_SIZE; jj = jj + 1)
                            sum = sum +
                                  filter[ii][jj] *
                                  ifmap[i*STRIDE + ii][j*STRIDE + jj];
                    expected_ofmap[i][j] = sum;
                end
        end
    endtask

    /* ==========================================================
       GLB I/O TASKS
    ========================================================== */

    task write_filter_to_glb;
        integer i, j;
        begin
            wr_to_filter_glb = 1;
            for (i = 0; i < FILTER_SIZE; i = i + 1)
                for (j = 0; j < FILTER_SIZE; j = j + 1) begin
                    input_filter = filter[j][i];
                    @(negedge clk);
                end
            wr_to_filter_glb = 0;
        end
    endtask

    task write_ifmap_to_glb;
        integer i, j;
        begin
            wr_to_ifmap_glb = 1;
            for (i = 0; i < IFMAP_SIZE; i = i + 1)
                for (j = 0; j < IFMAP_SIZE; j = j + 1) begin
                    input_ifmap = ifmap[j][i];
                    @(negedge clk);
                end
            wr_to_ifmap_glb = 0;
        end
    endtask

    task read_ofmap_glb;
        integer i, j;
        begin
            rd_from_ofmap_glb = 1;
            for (i = 0; i < OFMAP_SIZE; i = i + 1)
                for (j = 0; j < OFMAP_SIZE; j = j + 1) begin
                    @(negedge clk);
                    actual_ofmap[j][i] = output_ofmap;
                end
            rd_from_ofmap_glb = 0;
        end
    endtask

    task assert_ofmap;
        integer i, j;
        begin
            for (i = 0; i < OFMAP_SIZE; i = i + 1)
                for (j = 0; j < OFMAP_SIZE; j = j + 1)
                    if (actual_ofmap[i][j] !== expected_ofmap[i][j]) begin
                        $display("Mismatch (%0d,%0d): exp=%0d got=%0d",
                                 i, j, expected_ofmap[i][j], actual_ofmap[i][j]);
                        $finish;
                    end
            $display("\nAll OFMAP values match!");
        end
    endtask

    /* ==========================================================
       CLOCK
    ========================================================== */

    initial begin
        clk = 0;
        clk_cnt = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end


    always @(posedge clk)
        clk_cnt = clk_cnt + 1;
    

    /* ==========================================================
       TEST SEQUENCE
    ========================================================== */

    initial begin

        $dumpfile("top_tb.vcd"); 
        $dumpvars(0);  

        if (LOAD_FROM_FILE) begin
            $display("Testbench running in FILE mode");
            load_from_files;
        end else begin
            $display("Testbench running in RANDOM mode");
            init_filter;
            init_ifmap;
        end

        do_convolution;

        //display_ifmap;
        //display_filter;
        //display_expected_ofmap;

        wr_to_filter_glb = 0;
        wr_to_ifmap_glb  = 0;
        rd_from_ofmap_glb = 0;
        start = 0;

        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;

        write_filter_to_glb;
        $display("Filter written. clk_cnt = ", clk_cnt);
        write_ifmap_to_glb;
        $display("Ifmap written. clk_cnt = ", clk_cnt);

        start = 1;
        wait(done);
        $display("Done. clk_cnt = ", clk_cnt);
        @(negedge clk);

        read_ofmap_glb;
        //display_actual_ofmap;
        assert_ofmap;
        $display("clk_cnt = ", clk_cnt);

        if (LOAD_FROM_FILE) begin
            write_ofmap_to_file;
        end 

        $finish;
    end

endmodule
