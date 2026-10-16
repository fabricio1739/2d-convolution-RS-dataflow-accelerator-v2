`timescale 1ns / 1ps

module id_controller
#(
    parameter IDS_CAPACITY = 0
)
(
    input wire update_id,
    input wire [$clog2(IDS_CAPACITY+1)-1:0] row_size,
    input wire clk,
    input wire rst,
    output reg [$clog2(IDS_CAPACITY+1)-1:0] row_id
);

    always @(posedge clk)
    begin
        if (rst)
        begin
            row_id <= 0;
        end
        else if (update_id)
        begin
            row_id <= row_id == row_size - 1 ? 0 : row_id + 1;
        end
    end

endmodule