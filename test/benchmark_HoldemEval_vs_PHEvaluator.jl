"""
Benchmarks HoldemEval.evaluate7 (pure-Julia table lookups) against
PHEvaluatorWrapper.evaluate_7cards (ccall into the C++ libpheval) on identical
7-card hands, so the numbers reflect a real apples-to-apples comparison
rather than different workloads.

## Usage

    julia benchmark_HoldemEval_vs_PHEvaluator.jl

    PHEVALUATOR_LIB=/path/to/libpheval.so julia benchmark_HoldemEval_vs_PHEvaluator.jl

Uses BenchmarkTools if available (installs it into the active project on
first run if missing) for statistically solid per-call timings, plus a
manual bulk-throughput loop (hands/sec) that mimics how you'd actually
use either evaluator inside a Monte-Carlo equity simulator.

Tune the bulk sample size with:

    HOLDEMEVAL_BENCH_N=20000000 julia benchmark_HoldemEval_vs_PHEvaluator.jl
"""

import Pkg
try
    using BenchmarkTools
catch
    @info "Installing BenchmarkTools..."
    Pkg.add("BenchmarkTools")
    using BenchmarkTools
end

using Random
using Printf

include("PHEvaluatorWrapper.jl")
include("../src/HoldemEval.jl")
using .PHEvaluatorWrapper
using .HoldemEval

# ---------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------

function _library_available()
    try
        r = PHEvaluatorWrapper.evaluate_5cards(0, 1, 2, 3, 4)
        return r isa Integer && 1 <= r <= 7462
    catch
        return false
    end
end

LIB_OK = _library_available()
if !LIB_OK
    error("libpheval not found/loadable. Set ENV[\"PHEVALUATOR_LIB\"] or call " *
          "PHEvaluatorWrapper.set_library!(path) before running this benchmark.")
end

println("Building HoldemEval tables...")
const TABLES = @time HoldemEvalTables()

# Fixed pool of random hands, materialized up front so hand generation
# never shows up inside the timed region for either evaluator.
function random_hands(n::Int; seed=42)
    rng = MersenneTwister(seed)
    hands = Vector{NTuple{7,Int}}(undef, n)
    for i in 1:n
        cards = randperm(rng, 52)[1:7] .- 1   # 0:51 ids, matches both libs
        hands[i] = NTuple{7,Int}(cards)
    end
    return hands
end

# ---------------------------------------------------------------------
# Bulk-throughput helpers (function-barriered so the JIT sees concrete
# types and neither loop pays interpreter/global-variable overhead)
# ---------------------------------------------------------------------

function run_julia_bulk(tables, hands::Vector{NTuple{7,Int}})
    acc = 0
    @inbounds for h in hands
        acc += HoldemEval.evaluate7(tables, h[1], h[2], h[3], h[4], h[5], h[6], h[7])
    end
    return acc
end

function run_cpp_bulk(hands::Vector{NTuple{7,Int}})
    acc = 0
    @inbounds for h in hands
        acc += PHEvaluatorWrapper.evaluate_7cards(h[1], h[2], h[3], h[4], h[5], h[6], h[7])
    end
    return acc
end

function bulk_bench(label, f, args...; reps=5)
    # Warmup / compile
    f(args...)
    best = Inf
    for _ in 1:reps
        t = @elapsed r = f(args...)
        best = min(best, t)
    end
    return best
end

# ---------------------------------------------------------------------
# 1. Single-call microbenchmark (BenchmarkTools)
# ---------------------------------------------------------------------

println()
println("="^70)
println("1. Single-call latency (BenchmarkTools, one fixed hand)")
println("="^70)

const C1, C2, C3, C4, C5, C6, C7 = 0, 5, 10, 15, 20, 25, 30  # arbitrary fixed hand

julia_single = @benchmark HoldemEval.evaluate7($TABLES, $C1, $C2, $C3, $C4, $C5, $C6, $C7)
cpp_single   = @benchmark PHEvaluatorWrapper.evaluate_7cards($C1, $C2, $C3, $C4, $C5, $C6, $C7)

println("\nHoldemEval.evaluate7 (Julia):")
display(julia_single)
println("\n\nPHEvaluator.evaluate_7cards (C++ via ccall):")
display(cpp_single)
println()

# ---------------------------------------------------------------------
# 2. Bulk throughput over a large pool of random hands
# ---------------------------------------------------------------------

n = parse(Int, get(ENV, "HOLDEMEVAL_BENCH_N", "10000"))
println()
println("="^70)
println("2. Bulk throughput ($n random hands, best-of-5)")
println("="^70)
println("Generating $n random hands...")
hands = @time random_hands(n)

println("\nWarming up + timing HoldemEval (Julia)...")
t_julia = bulk_bench("julia", run_julia_bulk, TABLES, hands)

println("Warming up + timing PHEvaluatorWrapper (C++)...")
t_cpp = bulk_bench("cpp", run_cpp_bulk, hands)

julia_rate = n / t_julia
cpp_rate   = n / t_cpp

println()
@printf("HoldemEval (Julia):        %8.3f s   (%10.2f hands/sec, %6.2f ns/hand)\n",
        t_julia, julia_rate, 1e9 / julia_rate)
@printf("PHEvaluatorWrapper (C++ ccall):   %8.3f s   (%10.2f hands/sec, %6.2f ns/hand)\n",
        t_cpp, cpp_rate, 1e9 / cpp_rate)
println()
if julia_rate > cpp_rate
    @printf("=> HoldemEval (Julia) is %.2fx faster than the C++ library over this ccall boundary.\n",
            julia_rate / cpp_rate)
else
    @printf("=> PHEvaluatorWrapper (C++) is %.2fx faster than the pure-Julia evaluator.\n",
            cpp_rate / julia_rate)
end

# ---------------------------------------------------------------------
# 3. Memory allocation check (should be zero for both, per-call)
# ---------------------------------------------------------------------

println()
println("="^70)
println("3. Allocations per call (should be 0 for both — table lookups only)")
println("="^70)
julia_allocs = @allocated HoldemEval.evaluate7(TABLES, C1, C2, C3, C4, C5, C6, C7)
cpp_allocs   = @allocated PHEvaluatorWrapper.evaluate_7cards(C1, C2, C3, C4, C5, C6, C7)
println("HoldemEval.evaluate7:      $julia_allocs bytes")
println("PHEvaluatorWrapper.evaluate_7cards: $cpp_allocs bytes")
