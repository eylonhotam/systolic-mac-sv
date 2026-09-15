module pe_tb;

  localparam A_W = 8;
  localparam W_W = 8;
  localparam P_W = 32;

  logic                  clk = 0;
  logic                  rst_n;
  logic                  w_shift_en;
  logic signed [W_W-1:0] w_in,    w_out;
  logic signed [A_W-1:0] a_in,    a_out;
  logic signed [P_W-1:0] psum_in, psum_out;

  integer errors = 0;

  pe #(.A_W(A_W), .W_W(W_W), .P_W(P_W)) dut (
    .clk(clk), .rst_n(rst_n), .w_shift_en(w_shift_en),
    .w_in(w_in),       .w_out(w_out),
    .a_in(a_in),       .a_out(a_out),
    .psum_in(psum_in), .psum_out(psum_out)
  );

  always #5 clk = ~clk;

  initial begin
    rst_n = 0; w_shift_en = 0;
    w_in = 0; a_in = 0; psum_in = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;

    // ---- reset values ----
    if (a_out !== 0 || w_out !== 0 || psum_out !== 0) begin
      $display("ERROR: outputs not 0 after reset");
      errors = errors + 1;
    end

    // ---- weight load / hold ----
    w_shift_en = 1;
    w_in = 5;  
    @(negedge clk);
    if (w_out !== 5) begin 
      $display("ERROR: load failed, w_out=%0d", w_out);
      errors = errors + 1;
    end
    w_shift_en = 0;
    w_in = 2;
    @(negedge clk);
    if (w_out !== 5) begin 
      $display("ERROR: weights updated when shouldn't have");
      errors = errors + 1;
    end
    w_in = -1;
    @(negedge clk);
    if (w_out !== 5) begin 
      $display("ERROR: weights updated when shouldn't have");
      errors = errors + 1;
    end
    
    // ---- shift uses old weight ----
    w_shift_en = 1;
    w_in = 3;
    @(negedge clk);
    w_in = 5; w_shift_en = 1; a_in = 2; psum_in = 0;
    @(negedge clk);
    if (psum_out !== 6) begin
      $display("ERROR: shift cycle psum_out=%0d, expected 6 (old weight)",
               psum_out);
      errors = errors + 1;
    end
    
    // ---- signed corners ----
    psum_in = 0;

    // -128 * -128 = 16384
    w_shift_en = 1; w_in = -128;
    @(negedge clk);
    w_shift_en = 0; a_in = -128;
    @(negedge clk);
    if (psum_out !== 16384) begin
      $display("ERROR: -128*-128 psum_out=%0d, expected 16384", psum_out);
      errors = errors + 1;
    end

    // -128 * 127 = -16256
    w_shift_en = 1; w_in = 127;
    @(negedge clk);
    w_shift_en = 0; a_in = -128;
    @(negedge clk);
    if (psum_out !== -16256) begin
      $display("ERROR: -128*127 psum_out=%0d, expected -16256", psum_out);
      errors = errors + 1;
    end

    // 127 * 127 = 16129
    w_shift_en = 1; w_in = 127;
    @(negedge clk);
    w_shift_en = 0; a_in = 127;
    @(negedge clk);
    if (psum_out !== 16129) begin
      $display("ERROR: 127*127 psum_out=%0d, expected 16129", psum_out);
      errors = errors + 1;
    end

    // -1 * 1 = -1   (catches zero-extension bugs)
    w_shift_en = 1; w_in = 1;
    @(negedge clk);
    w_shift_en = 0; a_in = -1;
    @(negedge clk);
    if (psum_out !== -1) begin
      $display("ERROR: -1*1 psum_out=%0d, expected -1", psum_out);
      errors = errors + 1;
    end

    // 0 * -128 = 0
    w_shift_en = 1; w_in = -128;
    @(negedge clk);
    w_shift_en = 0; a_in = 0;
    @(negedge clk);
    if (psum_out !== 0) begin
      $display("ERROR: 0*-128 psum_out=%0d, expected 0", psum_out);
      errors = errors + 1;
    end

    // ---- accumulation ----
    w_shift_en = 1;
    w_in = 10;
    psum_in = -100;
    a_in = 3;
    @(negedge clk);
    w_shift_en = 0;
    @(negedge clk);
    if (psum_out !== -70) begin
      $display("ERROR: flawed accumulation, psum_out=%0d", psum_out);
      errors = errors + 1;
    end
    psum_in = 100;
    a_in = -3;
    @(negedge clk);
    if (psum_out !== 70) begin
      $display("ERROR: flawed accumulation, psum_out=%0d", psum_out);
      errors = errors + 1;
    end
    psum_in = 32'h7FFF_FFFF;
    a_in = 1;
    @(negedge clk);
    if (psum_out !== 32'h8000_0009) begin
      $display("ERROR: flawed accumulation, psum_out=%0d", psum_out);
      errors = errors + 1;
    end
    
    // ---- reset mid-operation ----
    w_shift_en = 1;
    a_in = 3; w_in = 7; psum_in = 0;
    @(negedge clk);
    w_shift_en = 0;
    @(negedge clk);

    // precondition: outputs must be nonzero, or the reset check proves nothing
    if (a_out === 0 || w_out === 0 || psum_out === 0) begin
      $display("ERROR: precondition failed a_out=%0d w_out=%0d psum_out=%0d",
               a_out, w_out, psum_out);
      errors = errors + 1;
    end

    // assert reset for one cycle
    rst_n = 0;
    @(negedge clk);
    if (a_out !== 0 || w_out !== 0 || psum_out !== 0) begin
      $display("ERROR: reset failed a_out=%0d w_out=%0d psum_out=%0d",
               a_out, w_out, psum_out);
      errors = errors + 1;
    end

    // release reset, compute with a_in still nonzero
    rst_n = 1;
    w_shift_en = 0; a_in = 3; psum_in = 50;
    @(negedge clk);
    if (psum_out !== 50) begin
      $display("ERROR: w_reg not cleared, psum_out=%0d, expected 50", psum_out);
      errors = errors + 1;
    end
 
    // ---- final result printout ----
    if (errors == 0) $display("PASS");
    else             $display("FAIL: %0d errors", errors);
    $finish;
  end

endmodule
