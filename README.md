# HoldemEval.jl

**HoldemEval.jl** is an ultra-fast, zero-allocation 7-card Texas Hold'em hand evaluator written in pure Julia. By combining a bit-parallel flush detector, Milton Green's 16-comparator optimal sorting network, dynamic programming combination indexing, and a tiny memory footprint (~117 KB), `HoldemEval.jl` evaluates over **116 million hands per second** on a single thread.

---

## Key Features

* **Blazing Fast**: Evaluates 7-card hands in **~8.3 – 8.6 ns** per hand (~116M hands/sec).
* **Zero Allocations**: $0$ bytes allocated per evaluation call (`evaluate7` / `evaluate7_oneIndexed_reversed`).
* **Ultra-Compact Lookup Tables**: Total table size is under **117 KB** (~16 KB flush table + ~100.8 KB rank table), fitting entirely inside CPU L1 cache.
* **100% Validated**: Verified across all $\binom{52}{7} = 133,784,560$ unique 7-card poker hands.
* **Pure Julia**: No C/C++ dependencies, custom compilation steps, or `ccall` overhead.

---

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/yalnajja/HoldemEval.jl")

```

---

## Quickstart

```julia
using HoldemEval

# Initialize lookup tables in memory (~117 KB)
eval_tables = HoldemEvalTables()

# Card Encoding (0-indexed integers from 0 to 51):
# rank = card >> 2 (0 = 2, 12 = Ace)
# suit = card & 3  (0 = Spades, 1 = Hearts, 2 = Diamonds, 3 = Clubs)
c1, c2, c3, c4, c5, c6, c7 = 0, 4, 8, 12, 16, 20, 24

# Evaluate: lower score is better (1 = Royal Flush, 7462 = Worst 7-high hand)
score = evaluate7(eval_tables, c1, c2, c3, c4, c5, c6, c7)
println("Canonical Score (1 is best): ", score)

# Pass as tuple or vector
hand = (0, 4, 8, 12, 16, 20, 24)
score = evaluate7(eval_tables, hand)

# 1-indexed (1..52) cards returning a Higher-Is-Better rank (7462 = Royal Flush, 1 = 7-high)
score_reversed = evaluate7_oneIndexed_reversed(eval_tables, hand .+ 1)

```

---

## Benchmarks

### 1. Pure Julia Comparison (`PokerHandEvaluator.jl`)

Evaluating 10,000 unique random hands per sample:

| Library | Time / Hand | Allocations | Allocation Size | Speedup vs `HoldemEval` |
| --- | --- | --- | --- | --- |
| **`HoldemEval.jl`** | **8.3 ns** | **0 allocs** | **0 B** | **1.0x (Baseline)** |
| `PokerHandEvaluator.CompactHandEval` | 376.4 ns | 10,000 allocs | 156.25 KiB | 45.37x slower |
| `PokerHandEvaluator.FullHandEval` | 457.5 ns | 19,675 allocs | 619.92 KiB | 55.15x slower |

---

### 2. C++ Comparison (`PHEvaluator` via `ccall`)

Compared against Henry Lee's optimized C++ `PHEvaluator` library via a Julia `ccall` wrapper:

* **Single-Call Latency (Single Fixed Hand)**:
* `HoldemEval.evaluate7` (Julia): **9.15 ns**
* `PHEvaluator.evaluate_7cards` (C++ `ccall`): **12.77 ns**


* **Bulk Throughput (10,000 Random Hands)**:
* `HoldemEval.jl`: **116,590,882 hands/sec** (8.58 ns/hand)
* `PHEvaluator` (C++ `ccall`): **54,994,308 hands/sec** (18.18 ns/hand)
* **Result**: `HoldemEval.jl` runs **2.12x faster** than calling the optimized C++ library across Julia's native `ccall` boundary due to complete function inlining.



---

## How It Works

1. **Bit-Parallel Flush Detector**:
Accumulates suit frequencies into four 4-bit nibbles inside a single `UInt32`. A branchless bitwise shift (`(suit_counts + 0x3333) & 0x8888`) tests if any suit has $\ge 5$ cards, using `trailing_zeros(flush_flags) >> 2` to extract the flush suit instantly.
2. **Optimal 16-Comparator Sorting Network**:
If no flush is present, card ranks are sorted using Milton Green's optimal 16-comparator sorting network (`sort7`). Implemented with branchless `minmax` operations, this avoids standard sorting allocations, pointer overhead, and branch mispredictions.
3. **Binomial Coefficient DP Hash**:
Maps the 7 sorted ranks into a dense index range `0..50387` using a precomputed $7 \times 13$ dynamic programming combination table ($\binom{r + i - 1}{i}$).
4. **Minimal Memory Footprint**:
* `flush_table`: 8,192 entries (~16 KB)
* `noflush7_table`: 50,388 entries (~100.8 KB)
* `dp_table`: $7 \times 13$ matrix (`Int32`)



---

## Verification & Correctness

* **Exhaustive Evaluation**: Validated across all $\binom{52}{7} = 133,784,560$ possible 7-card hand combinations with **[Henry Lee's PHEvaluator](https://github.com/HenryRLee/PokerHandEvaluator)**.
* **Consistency**: Verified against `PokerHandEvaluator.jl` for complete hand rank equivalence across random paired hands.

---

## Acknowledgments

* **[Henry Lee's PHEvaluator](https://github.com/HenryRLee/PokerHandEvaluator)**: Algorithm design, 50,388 non-flush multiset DP table indexing ($\binom{19}{7}$), and the 8,192 flush bitmask table architecture are directly based on the core mechanics introduced in `PHEvaluator`.
* **Milton Green (1969)**: Creator of the optimal 16-comparator sorting network used in `sort7`.
* **AI Collaboration**: Designed, implemented, and benchmarked with assistance from **Gemini** and **Claude AI**.
