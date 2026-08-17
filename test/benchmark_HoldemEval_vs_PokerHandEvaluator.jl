
using BenchmarkTools
using Random
using Printf
using PlayingCards
using PokerHandEvaluator

# include("../src/HoldemEval.jl")
# using .HoldemEval

# ---------------------------------------------------------------------
# Card conversion: PlayingCards.jl <-> HoldemEval's 0-indexed card encoding
# HoldemEval convention: card = (rank << 2) | suit
#   rank: 0 = Two, 1 = Three, ... , 12 = Ace   (i.e. high_value(card) - 2)
#   suit: any consistent 0..3 labeling works, since HoldemEval only needs
#         "same suit => same code" within a single evaluation call.
# ---------------------------------------------------------------------
@inline function pc_to_HoldemEval0(card)
    r = high_value(card) - 2
    c = string(card)[end]
    s = c == '♣' ? 0 : c == '♠' ? 1 : c == '♡' ? 2 : 3
    return r * 4 + s
end


# ---------------------------------------------------------------------
#  Speed benchmark
# ---------------------------------------------------------------------
function make_hands(n::Int; seed::Int=1)
    rng = MersenneTwister(seed)
    deck = collect(ordered_deck())   
    HoldemEval_hands = Vector{NTuple{7,Int}}(undef, n)
    pc_hands     = Vector{NTuple{7,eltype(deck)}}(undef, n)
    for i in 1:n
        shuffle!(rng, deck)
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
 
    run_benchmarks(evaluator; n_hands=10_000)
end

main()