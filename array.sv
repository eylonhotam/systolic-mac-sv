module array #(
    parameter int S   = 4,
    parameter int A_W = 8,   // activation width
    parameter int W_W = 8,   // weight width
    parameter int P_W = 32   // accumulator width
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  w_shift_en,
    input  logic signed [W_W-1:0] w_in [S],
    input  logic signed [A_W-1:0] a_in [S],

    // the sum is no longer partial, represents C = A[i] dot B[j]
    output logic signed [P_W-1:0] c_out [S]
);
    // ---- horizontal activation bus ----
    // S+1 column slots, S rows each.
    // slot 0 = left edge of the array, slot S = right edge (unused).
    logic signed [A_W-1:0] act_bus [S+1][S];

    // ---- drive slot 0 from the array input ----
    generate
        for (genvar i = 0; i < S; i++) begin : g_drive_act
            assign act_bus[0][i] = a_in[i];
        end
    endgenerate

    // ---- the columns ----
    generate
        for (genvar j = 0; j < S; j++) begin : g_col
            col #(
                .S   (S),
                .A_W (A_W),
                .W_W (W_W),
                .P_W (P_W)
            ) u_col (
                .clk        (clk),
                .rst_n      (rst_n),
                .w_shift_en (w_shift_en),
                .w_in       (w_in[j]),
                .a_in       (act_bus[j]),
                .a_out      (act_bus[j+1]),
                .psum_out   (c_out[j])
            );
        end
    endgenerate

    // act_bus[S] is driven by the last column and read by nothing.
    // That's expected; lint may warn about it.

endmodule
