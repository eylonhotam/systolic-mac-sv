# systolic-mac-sv

A weight-stationary systolic multiply-accumulate (MAC) array in SystemVerilog, the same dataflow used in matrix-multiply accelerators such as Google's TPU. It is built bottom-up (PE → column → array), with a self-checking testbench at each level before moving up.

**Status:** `pe` and `col` and `array`are verified. See [Roadmap](#roadmap).

---

## What it computes

For an S×S tile, the array computes

```
C = A · B        A: M×S (INT8)   B: S×S (INT8)   C: M×S (INT32)
```

`B` (weights) is loaded once and held stationary in the PEs. Rows of `A` (activations) stream in, and each column produces one dot product per row, `C[m][j] = Σ_k A[m][k] · B[k][j]`.

## Architecture

```
            w_in[0]     w_in[1]     w_in[2]
              │           │           │
 A[m][0] ──▶ PE00 ──a──▶ PE01 ──a──▶ PE02 ──▶
              │ psum      │           │
 A[m][1] ──▶ PE10 ──a──▶ PE11 ──a──▶ PE12 ──▶      (1-cycle skew per row)
              │           │           │
 A[m][2] ──▶ PE20 ──a──▶ PE21 ──a──▶ PE22 ──▶      (2-cycle skew)
              │           │           │
            C[m][0]     C[m][1]     C[m][2]
```

Three signals move through the grid, each nearest-neighbour only:

| Signal | Direction | Behaviour |
|---|---|---|
| Weights | top → bottom, within a column | Shift in during a load phase (`w_shift_en = 1` for S cycles), then hold for the whole compute phase. No weight memory traffic during compute. |
| Activations | left → right, across columns | Registered once per PE (`a_out <= a_in`), so each column sees an activation one cycle after the column to its left. |
| Partial sums | top → bottom, within a column | Each PE computes `psum_out <= psum_in + a_in · w_reg`. The top of each column is tied to 0; the bottom is the finished dot product. |

**Weight load order.** The first value shifted in travels furthest. To place `B[i][j]` in row *i* of column *j*, feed `B[S-1][j]` first and `B[0][j]` last.

**Input skew.** Row *i* of the activation stream must enter *i* cycles after row 0, so that `A[m][i]` reaches PE(i, j) on the same cycle as the partial sum from PE(i−1, j). Outputs come out skewed the same way across columns. `array.sv` does not skew internally yet: the driver (currently the testbench) must apply the input skew, and on-chip skew/de-skew buffers are on the roadmap.

### Numeric format

- INT8 activations and weights (signed, two's complement)
- INT32 accumulator (`P_W = 32`)
- With INT8 operands each product fits in 16 bits, so a column of depth S ≤ 16 needs at most 16 + log₂(16) = 20 bits. The 32-bit accumulator cannot overflow in v1, and plain two's-complement wraparound is used intentionally (no saturation on the accumulator).

## Files

| File | Description |
|---|---|
| `pe.sv` | Processing element: weight register with shift enable, signed multiply, registered accumulate and activation pass-through. Synchronous active-low reset. |
| `pe_tb.sv` | Directed, self-checking PE testbench. Prints `PASS_PE` on success. |
| `col.sv` | Column of S PEs chained through internal `w_chain` / `psum_chain` nets via a `generate` loop. Exposes one activation in/out per row. |
| `col_tb.sv` | Directed, self-checking column testbench (S = 3). Prints `PASS_COL` on success. |
| `array.sv` | S×S grid of columns chained by an `act_bus [S+1][S]` (slot 0 = array input, slot S = right edge, unused). Takes one weight feed per column (`w_in[S]`), one activation per row (`a_in[S]`), and produces one result per column (`c_out[S]`). Elaborates; testbench in progress. |

### Parameters

| Name | Default | Meaning |
|---|---|---|
| `S` | 4 | Array dimension (PEs per column, columns per array) |
| `A_W` | 8 | Activation width |
| `W_W` | 8 | Weight width |
| `P_W` | 32 | Partial-sum / accumulator width |

## Verification

Each testbench is directed and self-checking: it counts mismatches and prints a single pass/fail line at the end.

**`pe_tb`** covers:
- reset values on all outputs
- weight load, and weight hold while `w_shift_en = 0`
- the shift cycle still computing with the *old* weight (product uses `w_reg`, not `w_in`)
- signed corners: −128·−128, −128·127, 127·127, −1·1 (catches zero-extension), 0·−128
- accumulation with negative `psum_in`, and two's-complement wrap at `32'h7FFF_FFFF`
- reset asserted mid-operation, with a nonzero precondition check so the test can actually fail, and a post-reset compute proving `w_reg` was cleared

**`col_tb`** covers:
- weight load order (checked against each PE's internal `w_reg`)
- a single hand-checkable row, and back-to-back rows in flight at the same time
- signed accumulation down the chain: maximum magnitude (3·(−128·−128) = 49152), all-negative products, and an intermediate sum that cancels to 0 mid-chain
- reset mid-operation, including clearing of stored weights

### Running the tests (ModelSim / Questa)

```sh
vlib work
vlog -sv pe.sv pe_tb.sv
vsim -c pe_tb -do "run -all; quit"     # expect PASS_PE

vlog -sv pe.sv col.sv col_tb.sv
vsim -c col_tb -do "run -all; quit"    # expect PASS_COL
```

## Roadmap

**v1 (in progress)**
- [x] PE + testbench
- [x] Column + testbench
- [x] Array top-level (elaborates)
- [x] Array testbench with a non-symmetric weight matrix (catches transposed-index bugs)
- [ ] Input skew / output de-skew buffers
- [ ] Valid/ready handshake
- [ ] Requantization INT32 → INT8 (scale, round, saturate to [−128, 127])
- [ ] NumPy golden model driving a self-checking random testbench
- [ ] Synthesis run (area / Fmax)

**Planned extensions** (in order)
1. Tiling for K > S
2. Size sweep: 4×4, 8×8, 16×16
3. AXI-Stream data + AXI-Lite control interfaces
4. Software baseline for comparison

## License

MIT, see [LICENSE](LICENSE).
