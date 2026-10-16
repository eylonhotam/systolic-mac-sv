module array_tb;

  localparam A_W = 8;
  localparam W_W = 8;
  localparam P_W = 32;
  localparam S   = 4;
  localparam M   = 6;   // rows of A streamed through 

  logic                  clk = 0;
  logic                  rst_n;
  logic                  w_shift_en;
  logic signed [W_W-1:0] w_in  [S];
  logic signed [A_W-1:0] a_in  [S];
  logic signed [P_W-1:0] c_out [S];

  // test data: C = A x W
  logic signed [A_W-1:0] A [M][S];
  logic signed [W_W-1:0] W [S][S];
  int                    C_exp [M][S];

  integer errors  = 0;
  integer checked = 0;

  array #(.S(S), .A_W(A_W), .W_W(W_W), .P_W(P_W)) dut (
    .clk(clk), .rst_n(rst_n), .w_shift_en(w_shift_en),
    .w_in(w_in), .a_in(a_in), .c_out(c_out)
  );

  always #5 clk = ~clk;

  initial begin
    // ---- reset ----
    rst_n = 0; w_shift_en = 0;
    for (int i = 0; i < S; i++) begin
      w_in[i] = 0;
      a_in[i] = 0;
    end
    repeat (3) @(negedge clk);
    rst_n = 1;

    // ---- test data ----
    // W: every entry different and not symmetric, so a swapped
    //    index or a transpose gives a wrong answer
    // A: mixed signs
    for (int i = 0; i < S; i++)
      for (int j = 0; j < S; j++)
        W[i][j] = i*S + j - 7;

    for (int m = 0; m < M; m++)
      for (int i = 0; i < S; i++)
        A[m][i] = (m - i) * 3;

    // signed corners in the last row of A:
    //   col 2 of W all -128 -> C[5][2] = S * (-128 * -128)
    //   col 3 of W all  127 -> C[5][3] = S * (-128 *  127)
    for (int i = 0; i < S; i++) begin
      A[M-1][i] = -128;
      W[i][2]   = -128;
      W[i][3]   = 127;
    end

    // ---- expected values: C_exp[m][j] = sum_i A[m][i] * W[i][j] ----
    for (int m = 0; m < M; m++)
      for (int j = 0; j < S; j++) begin
        C_exp[m][j] = 0;
        for (int i = 0; i < S; i++)
          C_exp[m][j] = C_exp[m][j] + int'(A[m][i]) * int'(W[i][j]);
      end

    // ---- weight load ----
    // same rule as col_tb: first value in travels furthest,
    // so feed row S-1 of W first and row 0 last
    w_shift_en = 1;
    for (int k = 0; k < S; k++) begin
      for (int j = 0; j < S; j++)
        w_in[j] = W[S-1-k][j];
      @(negedge clk);
    end
    w_shift_en = 0;
    for (int j = 0; j < S; j++) w_in[j] = 0;

    // ---- stream A through and check C ----
    // drive: row i gets A[m][i] at cycle k = m + i (the skew)
    // check: c_out[j] holds row m = k - S - j at the start of cycle k
    //        (S stages down the column, +j for crossing j columns)
    for (int k = 0; k < M + 2*S - 1; k++) begin

      // check whatever is due this cycle
      for (int j = 0; j < S; j++) begin
        int m = k - S - j;
        if (m >= 0 && m < M) begin
          checked = checked + 1;
          if (c_out[j] !== C_exp[m][j]) begin
            $display("ERROR: C[%0d][%0d] = %0d, expected %0d",
                     m, j, c_out[j], C_exp[m][j]);
            errors = errors + 1;
          end
        end
      end

      // drive this cycle's inputs (0 outside the tile)
      for (int i = 0; i < S; i++) begin
        int m = k - i;
        if (m >= 0 && m < M) a_in[i] = A[m][i];
        else                 a_in[i] = 0;
      end

      @(negedge clk);
    end

    // every C entry must have been checked exactly once
    if (checked !== M*S) begin
      $display("ERROR: checked %0d outputs, expected %0d", checked, M*S);
      errors = errors + 1;
    end

    if (errors == 0) $display("PASS_ARRAY (%0d outputs checked)", checked);
    else             $display("FAIL: %0d errors", errors);
    $finish;
  end

endmodule
