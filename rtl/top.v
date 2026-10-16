`timescale 1ns / 1ps

`include "fifo.v"
`include "filter_spad.v"
`include "id_controller.v"
`include "ifmap_glb.v"
`include "ifmap_spad.v"
`include "ofmap_glb.v"
`include "pe_array.v"
`include "pe.v"

module top #(
    parameter WIDTH  = 5,
    parameter HEIGHT = 5,

    parameter INPUT_BITWIDTH  = 8,
    parameter PSUM_BITWIDTH   = 20,

    parameter MAX_IFMAP_SIZE  = 28,
    parameter MAX_FILTER_SIZE = 5,
    parameter MAX_OFMAP_SIZE  = 28,
    parameter MAX_STRIDE      = 1
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire pooling,

    input wire wr_to_ifmap_glb,
    input wire wr_to_filter_glb,
    input wire rd_from_ofmap_glb,

    input wire [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_row_size,
    input wire [$clog2(MAX_FILTER_SIZE+1)-1:0] filter_row_size,
    input wire [$clog2(MAX_OFMAP_SIZE+1)-1:0]  ofmap_row_size,
    input wire [$clog2(MAX_IFMAP_SIZE**2+1)-1:0]  ifmap_square_size,
    input wire [$clog2(MAX_FILTER_SIZE**2+1)-1:0] filter_square_size,
    input wire [$clog2(MAX_OFMAP_SIZE**2+1)-1:0]  ofmap_square_size,
    input wire [$clog2(MAX_STRIDE+1)-1:0] stride,

    input wire [INPUT_BITWIDTH-1:0] input_ifmap,
    input wire [INPUT_BITWIDTH-1:0] input_filter,

    output wire [PSUM_BITWIDTH-1:0] output_ofmap,
    output reg done
);

    localparam MAX_IFMAP_TILE_SIZE = HEIGHT*WIDTH;
    localparam MAX_OFMAP_TILE_SIZE = WIDTH;

    localparam IDLE = 2'd0;
    localparam CONF = 2'd1;
    localparam RUN  = 2'd2;
    localparam DONE = 2'd3;

    reg [1:0] state;
    reg running;

    reg [$clog2(MAX_OFMAP_SIZE+1)-1:0] remaining_ofmap_cols;
    reg [$clog2(WIDTH+1)-1:0] iteration_ofmap_size;
    reg [$clog2(WIDTH+1)-1:0] psum_count;
    reg [$clog2(MAX_OFMAP_SIZE+1)-1:0] col_count;

    /* ----------------- wires ----------------- */

    wire [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_row_id;
    wire [$clog2(MAX_FILTER_SIZE+1)-1:0] filter_row_id;

    wire [PSUM_BITWIDTH-1:0] ofmap_to_glb;
    wire wr_ofmap_glb;

    wire run_iteration = (state == RUN);
    wire pes_ack_ifmap;

    wire rd_ifmap_glb = pes_ack_ifmap & run_iteration;

    wire [INPUT_BITWIDTH-1:0] ifmap;

    wire [$clog2(MAX_IFMAP_SIZE+1)-1:0] iteration_ifmap_size =
        filter_row_size + stride * (iteration_ofmap_size-1);

    wire rst_ifmap_id_controller = rst || (run_iteration && !running);
    wire rst_pe_array = rst || state == CONF;
    wire update_ifmap_id = rd_ifmap_glb && running;

    /* ------------------------------------------------------------ */
    /* FIXED FSM                                                    */
    /* ------------------------------------------------------------ */

    wire last_psum = (psum_count == iteration_ofmap_size - 1);
    wire last_col  = (col_count  == ofmap_row_size - 1);
    wire update_iteration_ifmap_size = state == CONF;
    wire update_iteration_ofmap_size = state == CONF;

    always @(posedge clk) begin
        if (rst) begin
            state                <= IDLE;
            remaining_ofmap_cols <= 0;
            iteration_ofmap_size <= 0;
            psum_count           <= 0;
            col_count            <= 0;
            done                 <= 0;
            running              <= 0;
        end else begin
            case (state)
            IDLE: begin
                done    <= 0;
                running <= 0;

                if (start) begin
                    remaining_ofmap_cols <= ofmap_row_size;
                    state <= CONF;
                end
            end

            CONF: begin
                running <= 0;

                iteration_ofmap_size <=
                    (remaining_ofmap_cols > WIDTH) ? WIDTH : remaining_ofmap_cols;

                remaining_ofmap_cols <=
                    (remaining_ofmap_cols > WIDTH) ?
                    (remaining_ofmap_cols - WIDTH) : 0;

                psum_count <= 0;
                col_count  <= 0;

                state <= RUN;
            end

            RUN: begin
                if (wr_ofmap_glb) begin
                    if (last_psum) begin
                        psum_count <= 0;
                        col_count  <= col_count + 1;
                        if (last_col) begin
                            state <= (remaining_ofmap_cols == 0) ? DONE : CONF;
                        end
                    end else begin
                        psum_count <= psum_count + 1;
                    end
                end
                running <= (wr_ofmap_glb && last_psum && last_col) ? 0 : 1;
            end

            DONE: begin
                running <= 0;
                done    <= 1'b1;
            end

            default: begin
                state                <= state;
                remaining_ofmap_cols <= remaining_ofmap_cols;
                iteration_ofmap_size <= iteration_ofmap_size;
                psum_count           <= psum_count;
                col_count            <= col_count;
                done                 <= done;
                running              <= running;
            end
            endcase
        end
    end

    /* ---------------- IFMAP GLB ---------------- */

    ifmap_glb #(
        .DWIDTH(INPUT_BITWIDTH),
        .DEPTH(MAX_IFMAP_SIZE**2),
        .PE_ARRAY_WIDTH(WIDTH),
        .MAX_IFMAP_SIZE(MAX_IFMAP_SIZE),
        .MAX_STRIDE(MAX_STRIDE)
    ) ifmap_glb_inst (
        .clk(clk),
        .rst(rst),
        .stride(stride),
        .elements_size(ifmap_square_size),
        .wr_en(wr_to_ifmap_glb),
        .rd_en(rd_ifmap_glb),
        .data_in(input_ifmap),
        .data_out(ifmap),
        .full(),
        .ifmap_size(ifmap_row_size),
        .iteration_ifmap_size(iteration_ifmap_size),
        .update_iteration_ifmap_size(update_iteration_ifmap_size)
    );

    /* ---------------- OFMAP GLB ---------------- */

    ofmap_glb #(
        .DWIDTH(PSUM_BITWIDTH),
        .DEPTH(MAX_OFMAP_SIZE**2),
        .PE_ARRAY_WIDTH(WIDTH),
        .MAX_OFMAP_TILE_SIZE(WIDTH),
        .MAX_OFMAP_SIZE(MAX_OFMAP_SIZE)
    ) ofmap_glb_inst (
        .clk(clk),
        .rst(rst),
        .elements_size(ofmap_square_size),
        .wr_en(wr_ofmap_glb),
        .rd_en(rd_from_ofmap_glb),
        .data_in(ofmap_to_glb),
        .data_out(output_ofmap),
        .full(),
        .ofmap_size(ofmap_row_size),
        .iteration_ofmap_size(iteration_ofmap_size),
        .update_iteration_ofmap_size(update_iteration_ofmap_size)
    );

    /* ---------------- PE ARRAY ---------------- */

    pe_array #(
        .HEIGHT(HEIGHT),
        .WIDTH(WIDTH),
        .INPUT_BITWIDTH(INPUT_BITWIDTH),
        .PSUM_BITWIDTH(PSUM_BITWIDTH),
        .MAX_IFMAP_SIZE(MAX_IFMAP_SIZE),
        .MAX_FILTER_SIZE(MAX_FILTER_SIZE),
        .MAX_OFMAP_SIZE(WIDTH),
        .MAX_STRIDE(MAX_STRIDE)
    ) pe_array_inst (
        .clk(clk),
        .rst(rst_pe_array),
        .pooling(pooling),
        .en(running),
        .input_ifmap(ifmap),
        .wr_filter(wr_to_filter_glb),
        .input_filter(input_filter),

        .current_ifmap_id(ifmap_row_id),
        .current_filter_id(filter_row_id),

        .ifmap_size(ifmap_row_size),
        .filter_size(filter_row_size),
        .ofmap_size(iteration_ofmap_size),
        .stride(stride),

        .all_pes_ack(pes_ack_ifmap),
        .wr_ofmap_glb(wr_ofmap_glb),
        .psum_out(ofmap_to_glb)
    );

    /* ---------------- ID CONTROLLERS ---------------- */

    id_controller #(
        .IDS_CAPACITY(MAX_IFMAP_SIZE)
    ) ifmap_id_ctrl (
        .clk(clk),
        .rst(rst_ifmap_id_controller),
        .row_size(iteration_ifmap_size),
        .update_id(update_ifmap_id),
        .row_id(ifmap_row_id)
    );

    id_controller #(
        .IDS_CAPACITY(MAX_FILTER_SIZE)
    ) filter_id_ctrl (
        .clk(clk),
        .rst(rst),
        .row_size(filter_row_size),
        .update_id(wr_to_filter_glb),
        .row_id(filter_row_id)
    );

endmodule