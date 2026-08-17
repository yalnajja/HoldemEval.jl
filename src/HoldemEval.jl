module HoldemEval

export HoldemEvalTables,evaluate7, evaluate7_oneIndexed_reversed

using Combinatorics


"""
    HoldemEvalTables

Pre-allocated lookup tables required for fast 7-card hand evaluations.

# Fields
- `flush_table`: Bitmask-indexed lookup for flush hands (8,192 entries, ~16 KB).
- `noflush7_table`: Combination-indexed lookup for non-flush hands (50,388 entries, ~100.8 KB).
- `dp_table`: 7 x 13 dynamic programming matrix mapping 7 sorted card ranks to a dense combination index.
"""

struct HoldemEvalTables
    flush_table::Vector{UInt16}     # 8,192 entries (~16 KB)
    noflush7_table::Vector{UInt16}  # 50,388 entries (~100.8 KB)
    dp_table::Matrix{Int32}         # 7 × 13 combination DP table
end

"""
    HoldemEvalTables()

Construct lookup tables dynamically in memory upon initialization.
"""

function HoldemEvalTables()
    dp_table = generate_dp_table()
    rank_map = build_rank_map()
    flush_table = generate_flush_table(rank_map)
    noflush7_table = generate_noflush7_table(dp_table, rank_map)

    return HoldemEvalTables(flush_table, noflush7_table, dp_table)
end

"""
    HoldemEvalTables(flush_path::String, noflush_path::String)

Load precomputed binary tables from disk if available; otherwise, generate
them and persist them to the specified binary file paths.
"""

function HoldemEvalTables(flush_path::String, noflush_path::String)
    dp_table = generate_dp_table()

    if isfile(flush_path) && isfile(noflush_path)
        flush_table = reinterpret(UInt16, read(flush_path)) |> collect
        noflush7_table = reinterpret(UInt16, read(noflush_path)) |> collect
    else
        rank_map = build_rank_map()
        flush_table = generate_flush_table(rank_map)
        noflush7_table = generate_noflush7_table(dp_table, rank_map)

        write(flush_path, flush_table)
        write(noflush_path, noflush7_table)
    end

    return HoldemEvalTables(flush_table, noflush7_table, dp_table)
end

"""
    save_tables(eval::HoldemEvalTables, flush_path="flush7.bin", noflush_path="noflush7.bin")

Persist internal lookup tables to disk in raw binary format for instant reloading.
"""
function save_tables(eval::HoldemEvalTables, flush_path::String="flush7.bin", noflush_path::String="noflush7.bin")
    write(flush_path, eval.flush_table)
    write(noflush_path, eval.noflush7_table)
end


# -------------------------------------------------------------------
# Evaluators
# -------------------------------------------------------------------


"""
    evaluate7(eval, c1, c2, c3, c4, c5, c6, c7)

Evaluate a 7-card hand represented by seven 0-indexed integers (`0:51`).

Cards are encoded as: `rank = card >> 2` (0=2, 12=Ace), `suit = card & 3` (0..3).
Returns a 1-indexed canonical rank score where **1 is the absolute best hand** 
(Royal Flush) and **7,462 is the worst hand** (7-high).
"""
@inline function evaluate7(
    eval::HoldemEvalTables,
    c1::Integer, c2::Integer, c3::Integer, c4::Integer, c5::Integer, c6::Integer, c7::Integer
)
    suit_counts = UInt32(
        (1 << ((c1 & 3) * 4)) + (1 << ((c2 & 3) * 4)) +
        (1 << ((c3 & 3) * 4)) + (1 << ((c4 & 3) * 4)) +
        (1 << ((c5 & 3) * 4)) + (1 << ((c6 & 3) * 4)) +
        (1 << ((c7 & 3) * 4))
    )

    flush_suit = find_flush_suit(suit_counts)

    if flush_suit >= 0
        mask = 0
        # No branches. The boolean simply becomes a 0 or 1 multiplier.
        mask |= ((c1 & 3) == flush_suit) << (c1 >> 2)
        mask |= ((c2 & 3) == flush_suit) << (c2 >> 2)
        mask |= ((c3 & 3) == flush_suit) << (c3 >> 2)
        mask |= ((c4 & 3) == flush_suit) << (c4 >> 2)
        mask |= ((c5 & 3) == flush_suit) << (c5 >> 2)
        mask |= ((c6 & 3) == flush_suit) << (c6 >> 2)
        mask |= ((c7 & 3) == flush_suit) << (c7 >> 2)

        @inbounds return eval.flush_table[mask+1]
    end

    r1, r2, r3, r4, r5, r6, r7 = sort7(
        c1 >> 2, c2 >> 2, c3 >> 2, c4 >> 2, c5 >> 2, c6 >> 2, c7 >> 2
    )

    @inbounds hash_idx = eval.dp_table[1, r1+1] +
                         eval.dp_table[2, r2+1] +
                         eval.dp_table[3, r3+1] +
                         eval.dp_table[4, r4+1] +
                         eval.dp_table[5, r5+1] +
                         eval.dp_table[6, r6+1] +
                         eval.dp_table[7, r7+1]

    @inbounds return eval.noflush7_table[hash_idx+1]
end


"""
    evaluate7(eval, cards)

Convenience tuple/vector overload for 0-indexed 7-card evaluation (`0:51`).
"""
@inline function evaluate7(
    eval::HoldemEvalTables,
    cards::Union{NTuple{7, <:Integer},AbstractVector{<:Integer}}
)
    @inbounds return evaluate7(
        eval,
        cards[1], cards[2], cards[3], cards[4], cards[5], cards[6], cards[7]
    )
end

"""
evaluate7_oneIndexed_reversed(eval, cards)

1-indexed (`1:52`) card evaluator returning a **Higher-Is-Better** score.
Scale ranges from `1` (worst 7-high hand) up to `7,462` (Royal Flush).
"""
# 1-indexed (1:52) wrapper with Higher-Is-Better scale
@inline function evaluate7_oneIndexed_reversed(
    eval::HoldemEvalTables,
    cards::Union{NTuple{7, <:Integer},AbstractVector{<:Integer}}
)
    @inbounds return 7463 - evaluate7(
        eval,
        cards[1] - 1, cards[2] - 1, cards[3] - 1, 
        cards[4] - 1, cards[5] - 1, cards[6] - 1, cards[7] - 1
    )
end



"""
find_flush_suit(suit_counts::UInt32) -> Int

Determine if any suit has 5 or more cards from a 4-nibble suit accumulator.

# Returns
- `0, 1, 2, 3`: Suit index corresponding to the flush.
- `-1`: No flush present.

Input:
 Bits 0-3: Count of Suit 0 (Spades)

Bits 4-7: Count of Suit 1 (Hearts)

Bits 8-11: Count of Suit 2 (Diamonds)

Bits 12-15: Count of Suit 3 (Clubs)

Output:
0, 1, 2, or 3: The exact ID of the suit that has a flush (5 or more cards).
-1: No flush exists.

"""

# -------------------------------------------------------------------
# Evaluation Kernel
# -------------------------------------------------------------------

# @inline function find_flush_suit(suit_counts::UInt32)
#     (suit_counts & 0x000F) >= 5 && return 0
#     (suit_counts & 0x00F0) >= 0x0050 && return 1
#     (suit_counts & 0x0F00) >= 0x0500 && return 2
#     (suit_counts & 0xF000) >= 0x5000 && return 3
#     return -1
# end

@inline function find_flush_suit(suit_counts::UInt32)
    # Add 3 to each nibble. If a nibble was >= 5, its 4th bit (8) becomes 1.
    flush_flags = (suit_counts + 0x3333) & 0x8888
    
    # One highly predictable branch: is there a flush at all?
    flush_flags == 0 && return -1
    
    # Use trailing zeros to instantly find which suit triggered it (0, 1, 2, or 3)
    return trailing_zeros(flush_flags) >> 2
end

# @inline swap(a, b) = a > b ? (b, a) : (a, b)
@inline swap(a, b) = minmax(a, b)

"""
    sort7(c1, c2, c3, c4, c5, c6, c7)

Optimal 16-comparator sorting network for sorting 7 elements in ascending order.
"""
@inline function sort7(c1, c2, c3, c4, c5, c6, c7)
    c1, c2 = swap(c1, c2)
    c3, c4 = swap(c3, c4)
    c5, c6 = swap(c5, c6)

    c1, c3 = swap(c1, c3)
    c2, c4 = swap(c2, c4)
    c5, c7 = swap(c5, c7)

    c2, c3 = swap(c2, c3)
    c6, c7 = swap(c6, c7)
    c1, c5 = swap(c1, c5)

    c3, c7 = swap(c3, c7)
    c2, c6 = swap(c2, c6)

    c3, c5 = swap(c3, c5)
    c4, c6 = swap(c4, c6)

    c2, c3 = swap(c2, c3)
    c4, c5 = swap(c4, c5)
    c6, c7 = swap(c6, c7)

    return (c1, c2, c3, c4, c5, c6, c7)
end





"""
    generate_dp_table() -> Matrix{Int32}

Build the combination DP matrix based on binomial coefficients ``\\binom{r + i - 1}{i}``.
Maps 7 sorted ranks into a dense index range `0..50387`.
"""
function generate_dp_table()
    dp = zeros(Int32, 7, 13)
    for i in 1:7, r in 0:12
        dp[i, r + 1] = binomial(r + i - 1, i)
    end
    return dp
end

"""
    eval_5card_score(ranks5, is_flush) -> Tuple

Evaluate a canonical 5-card poker hand strength tuple `(category, tiebreaker_ranks...)`.
Used internally during table generation to establish relative strength rankings.
"""
function eval_5card_score(ranks5::NTuple{5, Int}, is_flush::Bool)
    r1, r2, r3, r4, r5 = ranks5
    is_straight = (r5 - r1 == 4 && r1 != r2 != r3 != r4 != r5)
    is_wheel    = (ranks5 == (0, 1, 2, 3, 12))
    top_straight = is_wheel ? 3 : r5
    
    if (is_straight || is_wheel) && is_flush
        return (9, top_straight)
    end
    
    counts = Dict{Int, Int}()
    for r in ranks5; counts[r] = get(counts, r, 0) + 1; end
    freq_rank = sort([(cnt, r) for (r, cnt) in counts], rev=true)
    
    if freq_rank[1][1] == 4
        return (8, freq_rank[1][2], freq_rank[2][2])
    elseif freq_rank[1][1] == 3 && freq_rank[2][1] == 2
        return (7, freq_rank[1][2], freq_rank[2][2])
    elseif is_flush
        return (6, r5, r4, r3, r2, r1)
    elseif is_straight || is_wheel
        return (5, top_straight)
    elseif freq_rank[1][1] == 3
        return (4, freq_rank[1][2], freq_rank[2][2], freq_rank[3][2])
    elseif freq_rank[1][1] == 2 && freq_rank[2][1] == 2
        return (3, max(freq_rank[1][2], freq_rank[2][2]), 
                   min(freq_rank[1][2], freq_rank[2][2]), freq_rank[3][2])
    elseif freq_rank[1][1] == 2
        return (2, freq_rank[1][2], freq_rank[2][2], freq_rank[3][2], freq_rank[4][2])
    else
        return (1, r5, r4, r3, r2, r1)
    end
end

"""
    build_rank_map() -> Dict{Tuple, UInt16}

Enumerate all valid 5-card rank combinations, evaluate their score tuples, 
and map every unique equivalence class to a rank integer from 1 (best) to 7,462 (worst).
"""


function build_rank_map()
    scores = Set{Tuple}()
    for r1 in 0:12, r2 in r1:12, r3 in r2:12, r4 in r3:12, r5 in r4:12
        ranks = (r1, r2, r3, r4, r5)
        maximum(count(x -> x == r, ranks) for r in 0:12) > 4 && continue
        push!(scores, eval_5card_score(ranks, false))
        all_distinct = (r1 != r2 && r2 != r3 && r3 != r4 && r4 != r5)
        all_distinct && push!(scores, eval_5card_score(ranks, true))
    end

    sorted_scores = sort(collect(scores), rev=true)
    @assert length(sorted_scores) == 7462 "Attendu 7462 catégories de mains, obtenu $(length(sorted_scores))"
    return Dict{Tuple, UInt16}(score => UInt16(i) for (i, score) in enumerate(sorted_scores))
end

"""
    generate_flush_table(rank_map) -> Vector{UInt16}

Precompute best 5-card flush ranks for all possible 13-bit rank bitmasks (2^13 = 8,192).
"""

function generate_flush_table(rank_map::Dict{Tuple, UInt16})
    flush_table = zeros(UInt16, 8192)
    for mask in 0:8191
        set_bits = [r for r in 0:12 if (mask & (1 << r)) != 0]
        if length(set_bits) >= 5
            best_rank = typemax(UInt16)
            for c in combinations(set_bits, 5)
                score = eval_5card_score(NTuple{5, Int}(c), true)
                best_rank = min(best_rank, rank_map[score])
            end
            flush_table[mask + 1] = best_rank
        end
    end
    return flush_table
end

"""
    generate_noflush7_table(dp, rank_map) -> Vector{UInt16}

Precompute best 5-card hand ranks for all 50,388 valid 7-card non-flush rank multisets.
"""

function generate_noflush7_table(dp::Matrix{Int32}, rank_map::Dict{Tuple, UInt16})
    noflush7_table = zeros(UInt16, 50388)
    for r1 in 0:12, r2 in r1:12, r3 in r2:12, r4 in r3:12, r5 in r4:12, r6 in r5:12, r7 in r6:12
        multiset = (r1, r2, r3, r4, r5, r6, r7)
        maximum(count(x -> x == r, multiset) for r in 0:12) > 4 && continue
        
        best_rank = typemax(UInt16)
        for c in combinations(multiset, 5)
            score = eval_5card_score(NTuple{5, Int}(c), false)
            best_rank = min(best_rank, rank_map[score])
        end
        
        idx = dp[1, r1 + 1] + dp[2, r2 + 1] + dp[3, r3 + 1] + 
              dp[4, r4 + 1] + dp[5, r5 + 1] + dp[6, r6 + 1] + dp[7, r7 + 1]
              
        noflush7_table[idx + 1] = best_rank
    end
    return noflush7_table
end


end
