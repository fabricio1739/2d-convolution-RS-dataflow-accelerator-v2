
module pe #(
    parameter INPUT_BITWIDTH  = 8,
    parameter PSUM_BITWIDTH   = 32,
    parameter MAX_IFMAP_SIZE  = 32,
    parameter MAX_FILTER_SIZE = 32,
    parameter MAX_STRIDE      = 8
)(
    input wire clk, rst, en,

    input wire [$clog2(MAX_STRIDE+1)-1:0]      stride,
    input wire [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_size,
    input wire [$clog2(MAX_FILTER_SIZE+1)-1:0] filter_size,
    input wire single_pe,

    input wire pooling,
    input wire input_ifmap_available,
    input wire input_filter_available,
    input wire input_psum_available,
    input wire output_psum_ack,

    input wire signed [INPUT_BITWIDTH-1:0] input_ifmap,
    input wire signed [INPUT_BITWIDTH-1:0] input_filter,
    input wire signed [PSUM_BITWIDTH-1:0]  input_psum,

    output wire ack_ifmap,
    output wire output_valid,
    output wire input_psum_ack,
    output wire [PSUM_BITWIDTH-1:0] output_psum
);

    /* ==========================================================
       INTERNAL SIGNALS
    ========================================================== */
    reg ack_ifmap_fifo_reg;
    reg output_psum_acked;

    wire [$clog2(MAX_FILTER_SIZE+1)-1:0] window_size = filter_size;

    reg [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_window_cnt;
    reg [$clog2(MAX_IFMAP_SIZE+1)-1:0]  ifmap_cnt;
    reg [$clog2(MAX_FILTER_SIZE+1)-1:0] mac_cnt;
    reg [$clog2(MAX_STRIDE+1)-1:0]      window_update_cnt;

    wire ifmap_fifo_empty, ifmap_fifo_full;
    wire [INPUT_BITWIDTH-1:0] ifmap_fifo_out;
    wire signed [INPUT_BITWIDTH-1:0] ifmap_spad_out;
    wire signed [INPUT_BITWIDTH-1:0] filter_spad_out;

    reg signed [PSUM_BITWIDTH-1:0] accumulator;

    /* ---------- OUTPUT PSUM FIFO ---------- */
    wire psum_fifo_empty;
    wire psum_fifo_full;
    wire psum_fifo_wr;
    wire psum_fifo_rd;
    wire [PSUM_BITWIDTH-1:0] psum_fifo_out;

    reg wr_ifmap_spad;
    wire wr_filter_spad;
    wire wr_ifmap_fifo;
    wire rd_ifmap_spad;
    wire rd_filter_spad;
    wire rd_ifmap_fifo;

    wire inputs_loaded;
    wire window_done;
    wire ifmap_window_loaded;
    wire window_updated;

    wire rst_mac;
    wire enable_mac;
    wire accumulate_input_psum;

    wire rst_input_counters;
    wire rst_window_counter;

    /* ==========================================================
       FSM
    ========================================================== */

    localparam LOAD_INPUTS   = 3'd0;
    localparam RD_SPAD       = 3'd1;
    localparam MAC           = 3'd2;
    localparam WAIT_PSUM     = 3'd3;
    localparam UPDATE_WINDOW = 3'd5;

    reg [2:0] state, next_state;

    always @(posedge clk) begin
        if (rst)
            state <= LOAD_INPUTS;
        else if (en)
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            LOAD_INPUTS:
                next_state = inputs_loaded ? RD_SPAD : LOAD_INPUTS;

            RD_SPAD:
                next_state = MAC;

            MAC:
                next_state = window_done ? WAIT_PSUM : MAC;

            WAIT_PSUM:
                next_state = input_psum_available ? UPDATE_WINDOW : WAIT_PSUM;

            UPDATE_WINDOW:
                if (window_updated)
                    next_state = output_psum_acked || output_psum_ack ? RD_SPAD : UPDATE_WINDOW;
                else
                    next_state = UPDATE_WINDOW;

            default:
                next_state = LOAD_INPUTS;
        endcase
    end

    /* ==========================================================
       CONTROL
    ========================================================== */

    wire ifmap_loaded;
    assign wr_ifmap_fifo       = input_ifmap_available && !ifmap_fifo_full && !ifmap_loaded;
    assign wr_filter_spad      = input_filter_available;
    assign ack_ifmap    = wr_ifmap_fifo || ack_ifmap_fifo_reg;
    assign rd_ifmap_spad = (state == MAC || state == RD_SPAD) && !window_done;
    assign rd_filter_spad = rd_ifmap_spad && !pooling;
    assign rst_mac    = (state == RD_SPAD);
    assign enable_mac = (state == MAC);

    assign accumulate_input_psum = state == WAIT_PSUM && input_psum_available;

    assign input_psum_ack = en ? accumulate_input_psum : output_psum_ack;

    assign rst_input_counters = state != LOAD_INPUTS;
    assign rst_window_counter = state != UPDATE_WINDOW;

    assign inputs_loaded = (state == LOAD_INPUTS && ifmap_window_cnt == window_size-1 && wr_ifmap_spad);

    assign window_done =
        (mac_cnt == window_size-1 && enable_mac);

    assign ifmap_window_loaded =
        (ifmap_window_cnt == window_size-1 && wr_ifmap_spad);

    assign ifmap_loaded = ifmap_cnt == ifmap_size;
    assign window_updated = (state == UPDATE_WINDOW && window_update_cnt == stride-1 && wr_ifmap_spad);
    assign rd_ifmap_fifo = ((state == LOAD_INPUTS && !ifmap_window_loaded) || (state == UPDATE_WINDOW && !window_updated)) && !ifmap_fifo_empty;

    /* ==========================================================
       IFMAP FIFO → SPAD
    ========================================================== */

    always @(posedge clk) begin
        if (rst)
            wr_ifmap_spad <= 0;
        else
            wr_ifmap_spad <= rd_ifmap_fifo;
    end

    fifo #(
        .DWIDTH(INPUT_BITWIDTH),
        .DEPTH(2)
    ) ifmap_fifo_inst (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_ifmap_fifo),
        .rd_en(rd_ifmap_fifo),
        .data_in(input_ifmap),
        .data_out(ifmap_fifo_out),
        .empty(ifmap_fifo_empty),
        .full(ifmap_fifo_full)
    );

    ifmap_spad #(
        .DWIDTH(INPUT_BITWIDTH),
        .DEPTH(MAX_FILTER_SIZE),
        .MAX_WINDOW_SIZE(MAX_FILTER_SIZE)
    ) ifmap_spad_inst (
        .clk(clk),
        .rst(rst),
        .window_size(window_size),
        .wr_en(wr_ifmap_spad),
        .rd_en(rd_ifmap_spad),
        .data_in(ifmap_fifo_out),
        .data_out(ifmap_spad_out)
    );

    filter_spad #(
        .DWIDTH(INPUT_BITWIDTH),
        .DEPTH(MAX_FILTER_SIZE)
    ) filter_spad_inst (
        .clk(clk),
        .rst(rst),
        .window_size(window_size),
        .wr_en(wr_filter_spad),
        .rd_en(rd_filter_spad),
        .data_in(input_filter),
        .data_out(filter_spad_out)
    );

    /* ==========================================================
       COUNTERS
    ========================================================== */

    always @(posedge clk) begin
        if (rst) begin
            ifmap_window_cnt <= 0;
        end
        else if (rst_input_counters) begin
            ifmap_window_cnt <= 0;
        end
        else if (wr_ifmap_spad) begin
            ifmap_window_cnt <= ifmap_window_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            ifmap_cnt <= 0;
        end
        else if (wr_ifmap_fifo) begin
            ifmap_cnt <= ifmap_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst || rst_window_counter)
            window_update_cnt <= 0;
        else if (wr_ifmap_spad)
            window_update_cnt <= window_update_cnt + 1;
    end

    always @(posedge clk) begin
        if (rst || !input_ifmap_available) begin
            ack_ifmap_fifo_reg <= 0;
        end
        else if (wr_ifmap_fifo) begin
            if (!single_pe)
                ack_ifmap_fifo_reg <= 1;
        end
    end

    always @(posedge clk) begin
        if (rst || state != UPDATE_WINDOW) begin
            output_psum_acked <= 0;
        end
        else if (output_psum_ack) begin
            output_psum_acked <= 1;
        end
    end

    /* ==========================================================
       ARITHIMETIC UNITS
    ========================================================== */

    wire signed [PSUM_BITWIDTH-1:0] mult = ifmap_spad_out * filter_spad_out;
    wire [PSUM_BITWIDTH-1:0] add  = accumulator + (accumulate_input_psum ? input_psum : mult);

    reg signed [PSUM_BITWIDTH-1:0] comp;

    always @(*) begin
        if (accumulate_input_psum) begin
            comp = input_psum > accumulator ? input_psum : accumulator;
        end
        else begin
            comp = ifmap_spad_out > accumulator ? ifmap_spad_out : accumulator;
        end
    end
                
    always @(posedge clk) begin
        if (rst) begin
            accumulator <= pooling ? {1'b1, {(PSUM_BITWIDTH-1){1'b0}}} : 0;
            mac_cnt     <= 0;
        end
        else if (rst_mac) begin
            accumulator <= pooling ? {1'b1, {(PSUM_BITWIDTH-1){1'b0}}} : 0;
            mac_cnt     <= 0;
        end
        else if (enable_mac) begin
            accumulator <= pooling ? comp : add;
            mac_cnt     <= mac_cnt + 1;
        end
        else if (accumulate_input_psum) begin
            accumulator <= pooling ? comp : add;
        end
    end

    assign psum_valid = state == UPDATE_WINDOW && !output_psum_acked;
    assign output_psum  = en ? accumulator : input_psum;
    assign output_valid = en ? psum_valid : input_psum_available;

endmodule
