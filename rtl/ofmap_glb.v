`timescale 1ns / 1ps

module ofmap_glb
#(
    parameter DWIDTH = 0,
    parameter DEPTH  = 0,
    parameter PE_ARRAY_WIDTH = 0,
    parameter MAX_OFMAP_TILE_SIZE = 0,
    parameter MAX_OFMAP_SIZE = 0
)
(
    input wire clk, rst, wr_en, rd_en,
    input wire [$clog2(DEPTH+1)-1:0] elements_size, 
    input wire [$clog2(MAX_OFMAP_SIZE+1)-1:0] ofmap_size,
    input wire [$clog2(MAX_OFMAP_TILE_SIZE+1)-1:0] iteration_ofmap_size,
    input wire update_iteration_ofmap_size,
    input wire [DWIDTH-1:0] data_in,
    output reg [DWIDTH-1:0] data_out,
    output reg full
);

    localparam AWIDTH = $clog2(DEPTH);

    reg [DWIDTH-1:0] mem [0:DEPTH-1];
    reg [AWIDTH-1:0] wptr;
    reg [AWIDTH-1:0] rptr;
    
    reg [AWIDTH-1:0] rows_counter;
    reg [AWIDTH-1:0] base_pointer;

    wire [AWIDTH-1:0] offset = ofmap_size - iteration_ofmap_size + 1;

    always @(posedge clk, posedge rst)
    begin
        if (rst)
        begin
            rptr <= 0;
            wptr <= 0;
            rows_counter <= 0;
            base_pointer <= 0;
            full <= 0;
            data_out <= 0;
        end
        else
        begin
            if (rd_en)
            begin
                data_out <= mem[rptr];
                rptr <= (rptr == elements_size-1) ? 0 : rptr + 1;
            end
            if (wr_en)
            begin
                mem[wptr] <= data_in;
                full <= (wptr == elements_size-1) ? 1 : 0;
                if (rows_counter == iteration_ofmap_size - 1) 
                begin
                    wptr <= wptr + offset;
                    rows_counter <= 0;
                end
                else
                begin
                    wptr <=  wptr + 1;
                    rows_counter <= rows_counter + 1;
                end
            end
            if (update_iteration_ofmap_size)
            begin
                base_pointer <= base_pointer + PE_ARRAY_WIDTH;
                wptr <= base_pointer;
                rows_counter <= 0;
            end
        end
    end

endmodule