# HoldemEval.jl

[![Julia](https://img.shields.io/badge/julia-v1.6+-9558B2.svg)](https://julialang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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
Pkg.add(url="[https://github.com/your-username/HoldemEval.jl](https://github.com/your-username/HoldemEval.jl)")
