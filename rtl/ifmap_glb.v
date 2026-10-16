`timescale 1ns / 1ps

module ifmap_glb
#(
    parameter DWIDTH = 0,
    parameter DEPTH  = 0,
    parameter PE_ARRAY_WIDTH = 0,
    parameter MAX_IFMAP_SIZE = 0,
    parameter MAX_STRIDE = 0
)
(
    input wire clk, rst, wr_en, rd_en,
    input wire [$clog2(MAX_STRIDE+1)-1:0] stride, 
    input wire [$clog2(DEPTH+1)-1:0] elements_size, 
    input wire [$clog2(MAX_IFMAP_SIZE+1)-1:0] ifmap_size,
    input wire [$clog2(MAX_IFMAP_SIZE+1)-1:0] iteration_ifmap_size,
    input wire update_iteration_ifmap_size,
    input wire [DWIDTH-1:0] data_in,
    output reg [DWIDTH-1:0] data_out,
    output reg full
);

    // always @*
    // $display("at time %d rst = %b, wr_en=%b rd_en=%b data_in=%d data_out=%d, rptr=%d", $time, rst, wr_en, rd_en, data_in, data_out, rptr);

    localparam AWIDTH = $clog2(DEPTH);

    reg [DWIDTH-1:0] mem [0:DEPTH-1];
    reg [AWIDTH-1:0] wptr;
    reg [AWIDTH-1:0] rptr;
    
    reg [AWIDTH-1:0] rows_counter;
    reg [AWIDTH-1:0] base_pointer;

    reg [7:0] iterations;

    wire [AWIDTH-1:0] offset = ifmap_size - iteration_ifmap_size + 1;

    wire all_iteration_ifmaps_read = (iterations == ifmap_size);

    always @(posedge clk)
    begin
        if (rst)
        begin
            rptr <= 0;
            wptr <= 0;
            rows_counter <= 0;
            base_pointer <= 0;
            full <= 0;
            iterations <= 0;
            data_out <= 0;
        end
        else
        begin
            if (rd_en && !all_iteration_ifmaps_read)
            begin
                data_out <= mem[rptr];
                //$display("at time %d glb[%d] => %d", $time, rptr, mem[rptr]);
                if (rows_counter == iteration_ifmap_size - 1) 
                begin
                    iterations <= iterations + 1;
                    rptr <= rptr + offset;
                    rows_counter <= 0;
                end
                else
                begin
                    rptr <=  rptr + 1;
                    rows_counter <= rows_counter + 1;
                end
            end
            //rptr <= (rptr == DEPTH-1) ? 0 : rptr + 1;
            if (wr_en)
            begin
                //$display("at time %d glb[%d] <= %d", $time,  wptr, $signed(data_in));
                mem[wptr] <= data_in;
                wptr <= (wptr == elements_size-1) ? 0 : wptr + 1;
                full <= (wptr == elements_size-1) ? 1 : 0;
            end
            if (update_iteration_ifmap_size)
            begin
                //$display("at time %d update_iteration_ifmap_size", $time);
                base_pointer <= base_pointer + PE_ARRAY_WIDTH*stride;
                rptr <= base_pointer;
                rows_counter <= 0;
                iterations <= 0;
            end
        end
    end

endmodule