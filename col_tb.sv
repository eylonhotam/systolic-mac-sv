module col_tb;

  localparam A_W = 8;
  localparam W_W = 8;
  localparam P_W = 32;
  localparam S   = 3;

  logic                  clk = 0;
  logic                  rst_n;
  logic                  w_shift_en;
  logic signed [W_W-1:0] w_in;
  logic signed [A_W-1:0] a_in  [S];
  logic signed [A_W-1:0] a_out [S];
  logic signed [P_W-1:0] psum_out;

  integer errors = 0;

  col #(.S(S), .A_W(A_W), .W_W(W_W), .P_W(P_W)) dut (
    .clk(clk), .rst_n(rst_n), .w_shift_en(w_shift_en),
    .w_in(w_in),
    .a_in(a_in), .a_out(a_out),
    .psum_out(psum_out)
  );

  always #5 clk = ~clk;

  initial begin
    rst_n = 0; w_shift_en = 0; w_in = 0;
    a_in[0] = 0; a_in[1] = 0; a_in[2] = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;

    // ---- reset values ----
    if (psum_out !== 0 || a_out[0] !== 0 || a_out[1] !== 0 || a_out[2] !== 0) begin
      $display("ERROR: outputs not 0 after reset");
      errors = errors + 1;
    end

    // ---- weight load ----
    // want PE(0)=1, PE(1)=2, PE(2)=3
    // first value in travels furthest, so feed 3, then 2, then 1
    w_shift_en = 1;
    w_in = 3;
    @(negedge clk);
    w_in = 2;
    @(negedge clk);
    w_in = 1;
    @(negedge clk);
    w_shift_en = 0;
    
    // ---- check weight load ----
    w_in = 0;
    if (dut.g_pe[0].u_pe.w_reg !== 1 ||
    dut.g_pe[1].u_pe.w_reg !== 2 ||
    dut.g_pe[2].u_pe.w_reg !== 3) begin
      $display("ERROR: weight load, PE regs = %0d %0d %0d",
               dut.g_pe[0].u_pe.w_reg,
               dut.g_pe[1].u_pe.w_reg,
               dut.g_pe[2].u_pe.w_reg);
      errors = errors + 1;
    end

    // ---- single row, hand-checkable ----
    a_in[0] = 4;
    @(negedge clk);
    a_in[0] = 0;
    a_in[1] = 5;
    @(negedge clk);
    a_in[1] = 0;
    a_in[2] = 6;
    @(negedge clk);
    a_in[2] = 0;
    if(psum_out !== 32) begin
      $display("ERROR: faulty arithmetic, psum = %0d not 32", 
               psum_out);
      errors = errors + 1;
    end
    
    // ---- back-to-back rows ----
    // ---- tests the row being able 
    a_in[0] = 4;
    @(negedge clk);
    a_in[0] = 7; a_in[1] = 5;
    @(negedge clk);
    a_in[0] = 0; a_in[1] = 8; a_in[2] = 6;
    @(negedge clk);
    a_in[1] = 0; a_in[2] = 9;
    if (psum_out !== 32) begin
      $display("ERROR: multirow first row, psum = %0d not 32", psum_out);
      errors = errors + 1;
    end
    @(negedge clk);
    a_in[2] = 0;
    if (psum_out !== 50) begin
      $display("ERROR: multirow second row, psum = %0d not 50", psum_out);
      errors = errors + 1;
    end
    
    // ---- signed corners ----
    /* pe_tb already proved single-PE signed multiply; what's new here is sign extension along psum_chain and accumulation across stages.
    */
 
    // max magnitude: all weights -128, all activations -128
    // 3 * (-128 * -128) = 49152
    w_shift_en = 1;
    w_in = -128;
    @(negedge clk);
    w_in = -128;
    @(negedge clk);
    w_in = -128;
    @(negedge clk);
    w_shift_en = 0;
    w_in = 0;
 
    a_in[0] = -128;
    @(negedge clk);
    a_in[0] = 0; a_in[1] = -128;
    @(negedge clk);
    a_in[1] = 0; a_in[2] = -128;
    @(negedge clk);
    a_in[2] = 0;
    if (psum_out !== 49152) begin
      $display("ERROR: max magnitude, psum = %0d not 49152", psum_out);
      errors = errors + 1;
    end
 
    // all products negative: weights {127, -128, 127}, A {-128, 127, -128}
    // -16256 + -16256 + -16256 = -48768
    // feed PE(2) first
    w_shift_en = 1;
    w_in = 127;
    @(negedge clk);
    w_in = -128;
    @(negedge clk);
    w_in = 127;
    @(negedge clk);
    w_shift_en = 0;
    w_in = 0;
 
    a_in[0] = -128;
    @(negedge clk);
    a_in[0] = 0; a_in[1] = 127;
    @(negedge clk);
    a_in[1] = 0; a_in[2] = -128;
    @(negedge clk);
    a_in[2] = 0;
    if (psum_out !== -48768) begin
      $display("ERROR: negative accumulation, psum = %0d not -48768", psum_out);
      errors = errors + 1;
    end
 
    // intermediate cancellation: weights {5, 5, 5}, A {3, -3, 1}
    // psum goes 15, 0, 5 -- a zero mid-chain must not stick
    w_shift_en = 1;
    w_in = 5;
    @(negedge clk);
    w_in = 5;
    @(negedge clk);
    w_in = 5;
    @(negedge clk);
    w_shift_en = 0;
    w_in = 0;
 
    a_in[0] = 3;
    @(negedge clk);
    a_in[0] = 0; a_in[1] = -3;
    @(negedge clk);
    a_in[1] = 0; a_in[2] = 1;
    @(negedge clk);
    a_in[2] = 0;
    if (psum_out !== 5) begin
      $display("ERROR: cancellation, psum = %0d not 5", psum_out);
      errors = errors + 1;
    end
 

    // ---- reset mid-operation ----
    w_shift_en = 1;
    w_in = 7;
    @(negedge clk);
    w_in = 7;
    @(negedge clk);
    w_in = 7;
    @(negedge clk);
    w_shift_en = 0;
    w_in = 0;
    a_in[0] = 6;
    @(negedge clk);
    a_in[0] = 6; a_in[1] = 6;
    @(negedge clk);
    a_in[0] = 6; a_in[1] = 6; a_in[2] = 6;
    @(negedge clk);
 
    // precondition: psum must be nonzero, or the reset check proves nothing
    if (psum_out === 0) begin
      $display("ERROR: reset precondition, psum already 0");
      errors = errors + 1;
    end
 
    // assert reset for one cycle
    rst_n = 0;
    @(negedge clk);
    if (psum_out !== 0 || a_out[0] !== 0 || a_out[1] !== 0 || a_out[2] !== 0) begin
      $display("ERROR: reset mid-op, psum = %0d a_out = %0d %0d %0d",
               psum_out, a_out[0], a_out[1], a_out[2]);
      errors = errors + 1;
    end
 
    // release and drive one row: weights must be cleared, so psum stays 0
    rst_n = 1;
    a_in[0] = 5;
    @(negedge clk);
    a_in[0] = 0; a_in[1] = 5;
    @(negedge clk);
    a_in[1] = 0; a_in[2] = 5;
    @(negedge clk);
    a_in[2] = 0;
    if (psum_out !== 0) begin
      $display("ERROR: w_reg not cleared by reset, psum = %0d not 0", psum_out);
      errors = errors + 1;
    end
    
    
    
    if (errors == 0) $display("PASS_COL");
    else             $display("FAIL: %0d errors", errors);
    $finish;
  end

endmodule
