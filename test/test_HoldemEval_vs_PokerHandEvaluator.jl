#!/usr/bin/env julia
#
# Benchmark: HoldemEval  vs  PokerHandEvaluator.jl
# https://github.com/charleskawczynski/PokerHandEvaluator.jl
#
# USAGE
# -----
#   1) Put your HoldemEval module in a file called "../src/HoldemEval.jl" (or edit the `include(...)` path below).
#   2) Install deps (one-time):
#         julia --project -e 'using Pkg; Pkg.add(["PlayingCards","PokerHandEvaluator","BenchmarkTools","Combinatorics"])'
#   3) Run:
#         julia -O3 benchmark_HoldemEval.jl
#
# NOTE: run with `-O3` (and ideally `--check-bounds=no`) for a realistic
# apples-to-apples comparison, since HoldemEval's evaluate7 is meant to be used
# in a tight, bounds-check-free loop.

# using BenchmarkTools
# using Random
using Printf
import PlayingCards
using PokerHandEvaluator

# ---------------------------------------------------------------------
# Card conversion: PlayingCards.jl <-> HoldemEval's 0-indexed card encoding
# HoldemEval convention: card = (rank << 2) | suit
#   rank: 0 = Two, 1 = Three, ... , 12 = Ace   (i.e. high_value(card) - 2)
#   suit: any consistent 0..3 labeling works, since HoldemEval only needs
#         "same suit => same code" within a single evaluation call.
# ---------------------------------------------------------------------
@inline function pc_to_HoldemEval0(card)
    r = PlayingCards.high_value(card) - 2
    c = string(card)[end]
    s = c == '♣' ? 0 : c == '♠' ? 1 : c == '♡' ? 2 : 3
    return r * 4 + s
end
 
@testset "PokerHandEvaluator.jl Cross-Check" begin
    evaluator = HoldemEvalTables()
    rng = MersenneTwister(42)
    deck = collect(PlayingCards.ordered_deck())
    n_trials = 20_000

    mismatches = 0
    for _ in 1:n_trials
        Random.shuffle!(rng, deck)
        handA = Tuple(deck[1:7])
        handB = Tuple(deck[8:14])

        fheA = FullHandEval(handA)
        fheB = FullHandEval(handB)
        ref_a = hand_rank(fheA)
        ref_b = hand_rank(fheB)

        idxA = ntuple(i -> pc_to_HoldemEval0(handA[i]), 7)
        idxB = ntuple(i -> pc_to_HoldemEval0(handB[i]), 7)
        mine_a = Int(HoldemEval.evaluate7(evaluator, idxA))
        mine_b = Int(HoldemEval.evaluate7(evaluator, idxB))

        ref_result  = sign(ref_a  - ref_b)   # -1 A wins, 0 tie, +1 B wins
        mine_result = sign(mine_a - mine_b)

        if ref_result != mine_result
            mismatches += 1
        end
    end

    @test mismatches == 0
end
 
# ---------------------------------------------------------------------
#  Speed benchmark
# ---------------------------------------------------------------------
function make_hands(n::Int; seed::Int=1)
    rng = MersenneTwister(seed)
    deck = collect(PlayingCards.ordered_deck())   
    HoldemEval_hands = Vector{NTuple{7,Int}}(undef, n)
    pc_hands     = Vector{NTuple{7,eltype(deck)}}(undef, n)
    for i in 1:n
        Random.shuffle!(rng, deck)
        h = Tuple(deck[1:7])
        pc_hands[i]     = h
        HoldemEval_hands[i] = ntuple(j -> pc_to_HoldemEval0(h[j]), 7)
    end
    return HoldemEval_hands, pc_hands
end
 
sum_HoldemEval(evaluator, hands) = begin
    s = 0
    @inbounds for h in hands
        s += HoldemEval.evaluate7(evaluator, h)
    end
    s
end
 
sum_full(hands) = begin
    s = 0
    @inbounds for h in hands
        s += hand_rank(FullHandEval(h))
    end
    s
end
 
sum_compact(hands) = begin
    s = 0
    @inbounds for h in hands
        s += hand_rank(CompactHandEval(h))
    end
    s
end
 
function run_benchmarks(evaluator; n_hands::Int=10_000)
    HoldemEval_hands, pc_hands = make_hands(n_hands)
 
    println("\n=== 7-card evaluation: $(n_hands) unique random hands per sample ===\n")
 
    println("-- HoldemEval.evaluate7 --")
    b_mine = @benchmark sum_HoldemEval($evaluator, $HoldemEval_hands)
    display(b_mine); println()
 
    println("\n-- PokerHandEvaluator.CompactHandEval (closest apples-to-apples) --")
    b_compact = @benchmark sum_compact($pc_hands)
    display(b_compact); println()
 
    println("\n-- PokerHandEvaluator.FullHandEval (also computes best_cards/all_cards) --")
    b_full = @benchmark sum_full($pc_hands)
    display(b_full); println()
 
    t_mine    = minimum(b_mine.times) / n_hands
    t_compact = minimum(b_compact.times) / n_hands
    t_full    = minimum(b_full.times) / n_hands
 
    println("\n=== Summary (ns / hand, min timing) ===")
    @printf("%-30s %10.1f ns\n", "HoldemEval", t_mine)
    @printf("%-30s %10.1f ns   (%.2fx HoldemEval)\n", "PokerHandEvaluator (Compact)", t_compact, t_compact / t_mine)
    @printf("%-30s %10.1f ns   (%.2fx HoldemEval)\n", "PokerHandEvaluator (Full)",    t_full,    t_full    / t_mine)
end
 
function main()
    println("Building HoldemEval tables...")
    evaluator = HoldemEvalTables()   # or HoldemEval("flush7.bin", "noflush7.bin") to cache to disk
 
    correctness_check(evaluator; n_trials=200_000, max_debug=5)
    run_benchmarks(evaluator; n_hands=10_000)
end
 
# main()
