module col #(
    parameter int S      = 4,   // PEs in the column
    parameter int W_A    = 8,   // activation width
    parameter int W_W    = 8,   // weight width
    parameter int W_PSUM = 32   // accumulator width
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // weight load path: enters at the top, shifts down
  	// B array (weights) need to enter last first (B[S-1][0]) so that B[0][0] occupies PE(0,0)
    input  logic                      w_shift_en,
    input  logic signed [W_W-1:0]     w_in,

    // activations: one per row, flow left-to-right through this column
    input  logic signed [W_A-1:0]     a_in  [S],
    output logic signed [W_A-1:0]     a_out [S],

    // partial sum: exits at the bottom
    output logic signed [W_PSUM-1:0]  psum_out
);

    // ---- internal chains ----
    // S+1 entries so each PE has a distinct "above" and "below" net.
  	// chain[i] enters into i'th PE, chain[i+1] exits it
    logic signed [W_PSUM-1:0] psum_chain [S+1];
    logic signed [W_W-1:0]    w_chain    [S+1];

  	// start the chain with partial sum 0 and weight w_in
  	assign psum_chain[0] = '0;
  	assign w_chain[0] = w_in;

    // ---- the PEs ----
    generate
        for (genvar i = 0; i < S; i++) begin : g_pe
            pe #(
              	.A_W    (W_A),
                .W_W    (W_W),
              	.P_W 	(W_PSUM)
            ) u_pe (
                .clk        (clk),
                .rst_n      (rst_n),
                .w_shift_en (w_shift_en),
              	.w_in 		(w_chain[i]),
              	.w_out 		(w_chain[i+1]),
              	.a_in 		(a_in[i]),
              	.a_out		(a_out[i]),
              	.psum_in 	(psum_chain[i]),
              	.psum_out 	(psum_chain[i+1])
            );
        end
    endgenerate

  	assign psum_out = psum_chain[S];

endmodule
