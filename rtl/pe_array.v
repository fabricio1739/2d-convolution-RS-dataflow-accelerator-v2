`timescale 1ns / 1ps

module pe_array #(
    parameter WIDTH = 1,
    parameter HEIGHT = 1,
    parameter INPUT_BITWIDTH  = 0,
    parameter PSUM_BITWIDTH   = 0,
    parameter MAX_IFMAP_SIZE  = 0,
    parameter MAX_FILTER_SIZE = 0,
    parameter MAX_OFMAP_SIZE  = 0,
    parameter MAX_STRIDE      = 0 
)(
    input wire clk, rst, en,

    input wire [INPUT_BITWIDTH-1:0] input_ifmap,
    input wire [INPUT_BITWIDTH-1:0] input_filter,
    input wire pooling,

    input wire wr_filter,
    input wire [$clog2(MAX_FILTER_SIZE+1)-1:0] current_filter_id,
    input wire [$clog2(MAX_IFMAP_SIZE+1)-1:0]  current_ifmap_id,
    input wire [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_size,
    input wire [$clog2(MAX_FILTER_SIZE+1)-1:0] filter_size,
    input wire [$clog2(MAX_OFMAP_SIZE+1)-1:0]  ofmap_size,
    input wire [$clog2(MAX_STRIDE+1)-1:0]      stride,

    output wire all_pes_ack,

    output reg  [PSUM_BITWIDTH-1:0] psum_out,
    output reg  wr_ofmap_glb
);

    genvar i, j;

    /* ==========================================================
       Internal signals
    ========================================================== */

    wire en_pe [0:HEIGHT-1][0:WIDTH-1];

    wire [PSUM_BITWIDTH-1:0] input_psum  [0:HEIGHT-1][0:WIDTH-1];
    wire [PSUM_BITWIDTH-1:0] output_psum [0:HEIGHT-1][0:WIDTH-1];

    wire input_psum_available   [0:HEIGHT-1][0:WIDTH-1];
    wire input_ifmap_available  [0:HEIGHT-1][0:WIDTH-1];
    wire input_filter_available [0:HEIGHT-1][0:WIDTH-1];
    wire ack_ifmap    [0:HEIGHT-1][0:WIDTH-1];

    wire output_psum_ack [0:HEIGHT-1][0:WIDTH-1];
    wire input_psum_ack  [0:HEIGHT-1][0:WIDTH-1];
    wire output_valid    [0:HEIGHT-1][0:WIDTH-1];

    /* ==========================================================
       PE Instantiation
    ========================================================== */

    reg single_pe_r;

    always @(posedge clk) begin
        if (rst)
            single_pe_r <= 1'b0;
        else
            single_pe_r <= (filter_size == 1) && (ofmap_size == 1);
    end
    
    generate
        for (i = 0; i < HEIGHT; i = i + 1)
            for (j = 0; j < WIDTH; j = j + 1) begin : PE_GEN
                pe #(
                    .INPUT_BITWIDTH(INPUT_BITWIDTH),
                    .PSUM_BITWIDTH(PSUM_BITWIDTH),
                    .MAX_IFMAP_SIZE(MAX_IFMAP_SIZE),
                    .MAX_FILTER_SIZE(MAX_FILTER_SIZE),
                    .MAX_STRIDE(MAX_STRIDE)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .en(en_pe[i][j]),
                    .pooling(pooling),
                    .single_pe(single_pe_r),

                    .stride(stride),
                    .ifmap_size(ifmap_size),
                    .filter_size(filter_size),

                    .input_ifmap(input_ifmap),
                    .input_filter(input_filter),
                    .input_psum(input_psum[i][j]),

                    .input_ifmap_available(input_ifmap_available[i][j]),
                    .input_filter_available(input_filter_available[i][j] && wr_filter),
                    .input_psum_available(input_psum_available[i][j]),

                    .output_psum_ack(output_psum_ack[i][j]),

                    .ack_ifmap(ack_ifmap[i][j]),
                    .input_psum_ack(input_psum_ack[i][j]),
                    .output_psum(output_psum[i][j]),
                    .output_valid(output_valid[i][j])
                );
            end
    endgenerate

    /* ==========================================================
       Inter-PE connections
    ========================================================== */

    generate
        for (i = 0; i < HEIGHT; i = i + 1)
            for (j = 0; j < WIDTH; j = j + 1) begin : interconnects

                assign en_pe[i][j] =
                    (i < filter_size) && (j < ofmap_size) && en;

                assign input_ifmap_available[i][j] =
                    (current_ifmap_id == (i + j * stride)) && en;

                assign input_filter_available[i][j] =
                    (current_filter_id == i);

                if (i == 0) begin
                    assign input_psum_available[i][j] = 1'b1;
                    assign input_psum[i][j]           = pooling ? {1'b1, {(PSUM_BITWIDTH-1){1'b0}}} : 0;
                end
                else begin
                    assign input_psum_available[i][j] = output_valid[i-1][j];
                    assign input_psum[i][j]           = output_psum[i-1][j];
                end
            end
    endgenerate


    /* ==========================================================
       Readiness
    ========================================================== */
    wire pe_ack_entry [0:HEIGHT-1][0:WIDTH-1];
    wire [HEIGHT*WIDTH-1:0] pe_ack_flat;
 
    generate
        for (i = 0; i < HEIGHT; i = i + 1)
            for (j = 0; j < WIDTH; j = j + 1) begin : ack_gen
                assign pe_ack_entry[i][j] =
                    ack_ifmap[i][j]             |
                    ~input_ifmap_available[i][j]|
                    ~en_pe[i][j];
 
                assign pe_ack_flat[i*WIDTH + j] = pe_ack_entry[i][j];
            end
    endgenerate
 
    assign all_pes_ack = &pe_ack_flat;

    /* ==========================================================
    Column-based output arbitration (1 psum per cycle)
    ========================================================== */

    reg [$clog2(WIDTH)-1:0] current_col;

    always @(posedge clk) begin
        if (rst) begin
            current_col  <= 0;
            wr_ofmap_glb <= 1'b0;
            psum_out     <= 0;
        end
        else if (en) begin
            if (output_valid[HEIGHT-1][current_col]) begin
                psum_out     <= output_psum[HEIGHT-1][current_col];
                wr_ofmap_glb <= 1'b1;
                if (current_col == ofmap_size-1)
                    current_col <= 0;
                else
                    current_col <= current_col + 1;
            end else begin
                wr_ofmap_glb <= 1'b0;
            end
        end
    end

    /* ==========================================================
       Output ACKs
    ========================================================== */

    generate
        for (j = 0; j < WIDTH; j = j + 1) begin : last_row_acks
            assign output_psum_ack[HEIGHT-1][j] =
                (j == current_col) &&
                output_valid[HEIGHT-1][j];
        end
    endgenerate

    generate
        for (i = 0; i < HEIGHT-1; i = i + 1)
            for (j = 0; j < WIDTH; j = j + 1) begin: acks_interconnects
                assign output_psum_ack[i][j] =
                    input_psum_ack[i+1][j];
            end
    endgenerate

endmodule
