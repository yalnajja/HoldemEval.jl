
const FAST = lowercase(get(ENV, "HoldemEval_FAST_TESTS", "false")) == "true"
const N_RANDOM_HANDS = FAST ? 150 : 2000

# 0-indexed card from (rank, suit): rank 0=2 .. 12=A, suit 0..3
card(rank, suit) = rank * 4 + suit

# ---------------------------------------------------------------------
# Brute-force reference, independent of the DP/table fast path. Trusts
# only eval_5card_score + build_rank_map (the functions that *define*
# correctness) and checks all C(7,5)=21 five-card subsets directly.
# ---------------------------------------------------------------------
function ref_best_rank(rank_map::Dict, cards::NTuple{7,Int})
    best = typemax(UInt16)
    for combo in combinations(collect(cards), 5)
        ranks = Tuple(sort([c >> 2 for c in combo]))
        suits = [c & 3 for c in combo]
        is_flush = length(Set(suits)) == 1
        score = HoldemEval.eval_5card_score(NTuple{5,Int}(ranks), is_flush)
        best = min(best, rank_map[score])
    end
    return best
end

@testset "HoldemEval.jl test suite" begin

    @testset "generate_dp_table" begin
        dp = HoldemEval.generate_dp_table()
        @test size(dp) == (7, 13)
        @test eltype(dp) == Int32
        for i in 1:7, r in 0:12
            @test dp[i, r+1] == binomial(r + i - 1, i)
        end
        @test dp[1, 1] == 0 # binomial(0,1)
        @test dp[1, 13] == 12 # binomial(12,1)
        @test dp[7, 1] == 0 # binomial(6,7) = 0, since 6 < 7
    end

    @testset "find_flush_suit" begin
        @test HoldemEval.find_flush_suit(UInt32(0x0005)) == 0 # suit0 count 5
        @test HoldemEval.find_flush_suit(UInt32(0x0007)) == 0 # suit0 count 7
        @test HoldemEval.find_flush_suit(UInt32(0x0050)) == 1 # suit1 count 5
        @test HoldemEval.find_flush_suit(UInt32(0x0500)) == 2 # suit2 count 5
        @test HoldemEval.find_flush_suit(UInt32(0x5000)) == 3 # suit3 count 5
        @test HoldemEval.find_flush_suit(UInt32(0x0004)) == -1 # suit0 count 4: no flush
        @test HoldemEval.find_flush_suit(UInt32(0x1114)) == -1 # 4/1/1/1 split (7 cards): no flush
        @test HoldemEval.find_flush_suit(UInt32(0x0115)) == 0 # 5/1/1/0 split (7 cards): flush suit 0
    end

    @testset "sort7 sorting network" begin
        for perm in permutations(0:6) # exhaustive: all 5040 perms
            @test HoldemEval.sort7(perm...) == Tuple(sort(collect(perm)))
        end
        rng = MersenneTwister(2024)
        for _ in 1:5000 # randomized, with repeated ranks
            vals = rand(rng, 0:12, 7)
            @test HoldemEval.sort7(vals...) == Tuple(sort(vals))
        end
    end

    @testset "eval_5card_score — hand categorization" begin
        @test HoldemEval.eval_5card_score((8, 9, 10, 11, 12), true) == (9, 12) # royal flush
        @test HoldemEval.eval_5card_score((0, 1, 2, 3, 12), true) == (9, 3) # steel wheel (5-high SF)
        @test HoldemEval.eval_5card_score((0, 0, 0, 0, 5), false) == (8, 0, 5) # quads
        @test HoldemEval.eval_5card_score((0, 0, 0, 5, 5), false) == (7, 0, 5) # full house
        @test HoldemEval.eval_5card_score((0, 1, 2, 3, 5), true) == (6, 5, 3, 2, 1, 0) # flush (non-straight)
        @test HoldemEval.eval_5card_score((0, 1, 2, 3, 4), false) == (5, 4) # straight
        @test HoldemEval.eval_5card_score((0, 1, 2, 3, 12), false) == (5, 3) # wheel straight
        @test HoldemEval.eval_5card_score((0, 0, 0, 5, 8), false) == (4, 0, 8, 5) # trips
        @test HoldemEval.eval_5card_score((0, 0, 5, 5, 8), false) == (3, 5, 0, 8) # two pair
        @test HoldemEval.eval_5card_score((0, 0, 5, 8, 11), false) == (2, 0, 11, 8, 5) # one pair
        @test HoldemEval.eval_5card_score((0, 1, 2, 3, 5), false) == (1, 5, 3, 2, 1, 0) # high card (worst possible)

        cats = [
            HoldemEval.HoldemEval.eval_5card_score((8, 9, 10, 11, 12), true),
            HoldemEval.eval_5card_score((0, 0, 0, 0, 5), false),
            HoldemEval.eval_5card_score((0, 0, 0, 5, 5), false),
            HoldemEval.eval_5card_score((0, 1, 2, 3, 5), true),
            HoldemEval.eval_5card_score((0, 1, 2, 3, 4), false),
            HoldemEval.eval_5card_score((0, 0, 0, 5, 8), false),
            HoldemEval.eval_5card_score((0, 0, 5, 5, 8), false),
            HoldemEval.eval_5card_score((0, 0, 5, 8, 11), false),
            HoldemEval.eval_5card_score((0, 1, 2, 3, 5), false),
        ]
        @test issorted(cats, rev=true)
    end

    @testset "build_rank_map — combinatorics sanity" begin
        rank_map = HoldemEval.build_rank_map()
        @test length(rank_map) == 7462
        @test rank_map[(9, 12)] == 1 # royal flush: the single best hand
        @test rank_map[(1, 5, 3, 2, 1, 0)] == 7462 # 7-5-4-3-2: the single worst hand

        # Distinct rank-pattern counts per category. These come from the
        # textbook 5-card hand counts (40/624/3744/5108/10200/54912/
        # 123552/1098240/1302540, summing to C(52,5)=2,598,960) divided
        # by their suit-arrangement multipliers.
        counts = Dict{Int,Int}()
        for score in keys(rank_map)
            counts[score[1]] = get(counts, score[1], 0) + 1
        end
        @test counts[9] == 10 # straight flush (incl. royal)
        @test counts[8] == 156 # four of a kind
        @test counts[7] == 156 # full house
        @test counts[6] == 1277 # flush
        @test counts[5] == 10 # straight
        @test counts[4] == 858 # three of a kind
        @test counts[3] == 858 # two pair
        @test counts[2] == 2860 # one pair
        @test counts[1] == 1277 # high card
        @test sum(values(counts)) == 7462
    end

    # Build once, reuse everywhere below (the expensive part).
    holdemEvalTables = HoldemEvalTables()

    @testset "HoldemEval() — struct shape" begin
        @test holdemEvalTables.flush_table isa Vector{UInt16}
        @test length(holdemEvalTables.flush_table) == 8192
        @test holdemEvalTables.noflush7_table isa Vector{UInt16}
        @test length(holdemEvalTables.noflush7_table) == 50388
        @test holdemEvalTables.dp_table isa Matrix{Int32}
        @test size(holdemEvalTables.dp_table) == (7, 13)
    end

    @testset "generate_flush_table / generate_noflush7_table — direct spot checks" begin
        rank_map = HoldemEval.build_rank_map()

        royal_mask = sum(1 << r for r in 8:12)
        @test holdemEvalTables.flush_table[royal_mask+1] == rank_map[(9, 12)]

        worst_flush_mask = sum(1 << r for r in [0, 1, 2, 3, 5])
        @test holdemEvalTables.flush_table[worst_flush_mask+1] == rank_map[(6, 5, 3, 2, 1, 0)]

        # Quad 7s (rank 5) with kickers ranks 0,1,2 -> best kicker is rank 2
        dp = HoldemEval.generate_dp_table()
        r1, r2, r3, r4, r5, r6, r7 = 0, 1, 2, 5, 5, 5, 5
        idx = dp[1, r1+1] + dp[2, r2+1] + dp[3, r3+1] + dp[4, r4+1] +
              dp[5, r5+1] + dp[6, r6+1] + dp[7, r7+1]
        @test holdemEvalTables.noflush7_table[idx+1] == rank_map[(8, 5, 2)]
    end

    @testset "evaluate7 — known hand types (relative ordering)" begin
        royal = (card(8, 0), card(9, 0), card(10, 0), card(11, 0), card(12, 0), card(0, 1), card(1, 2))
        royal2 = (card(8, 1), card(9, 1), card(10, 1), card(11, 1), card(12, 1), card(0, 2), card(1, 3))
        quads = (card(12, 0), card(12, 1), card(12, 2), card(12, 3), card(0, 0), card(1, 0), card(2, 0))
        boat = (card(12, 0), card(12, 1), card(12, 2), card(11, 0), card(11, 1), card(0, 0), card(1, 0))
        flush_hand = (card(0, 0), card(1, 0), card(2, 0), card(3, 0), card(5, 0), card(7, 1), card(9, 2))
        straight = (card(3, 0), card(4, 1), card(5, 2), card(6, 3), card(7, 0), card(9, 1), card(0, 2))
        trips = (card(5, 0), card(5, 1), card(5, 2), card(0, 0), card(1, 1), card(2, 2), card(3, 3))
        two_pair = (card(5, 0), card(5, 1), card(8, 0), card(8, 1), card(0, 2), card(1, 3), card(2, 0))
        one_pair = (card(5, 0), card(5, 1), card(0, 2), card(1, 3), card(2, 0), card(3, 1), card(9, 2))
        high_card = (card(12, 0), card(10, 1), card(8, 2), card(6, 3), card(4, 0), card(0, 1), card(1, 2))

        r_royal, r_royal2 = evaluate7(holdemEvalTables, royal), evaluate7(holdemEvalTables, royal2)
        r_quads, r_boat = evaluate7(holdemEvalTables, quads), evaluate7(holdemEvalTables, boat)
        r_flush, r_straight = evaluate7(holdemEvalTables, flush_hand), evaluate7(holdemEvalTables, straight)
        r_trips, r_two_pair = evaluate7(holdemEvalTables, trips), evaluate7(holdemEvalTables, two_pair)
        r_one_pair, r_high_card = evaluate7(holdemEvalTables, one_pair), evaluate7(holdemEvalTables, high_card)

        @test r_royal == 1
        @test r_royal == r_royal2 # two royal flushes (different suits) tie
        @test r_royal < r_quads < r_boat < r_flush < r_straight
        r_trips < r_two_pair < r_one_pair < r_high_card
        @test all(1 .<= (r_royal, r_quads, r_boat, r_flush, r_straight,
                      r_trips, r_two_pair, r_one_pair, r_high_card) .<= 7462)
    end

    @testset "evaluate7 — invariances" begin
        cards = (card(0, 0), card(1, 1), card(2, 2), card(3, 3), card(5, 0), card(6, 1), card(7, 2))
        base = evaluate7(holdemEvalTables, cards)

        rng = MersenneTwister(7)
        for _ in 1:20 # order of the 7 cards must not matter
            perm = Tuple(shuffle(rng, collect(cards)))
            @test evaluate7(holdemEvalTables, perm) == base
        end

        for shift in 1:3 # relabeling suits consistently must not matter
            relabel(c) = (c >> 2) * 4 + mod((c & 3) + shift, 4)
            @test evaluate7(holdemEvalTables, Tuple(map(relabel, cards))) == base
        end

        @test evaluate7(holdemEvalTables, cards) == evaluate7(holdemEvalTables, cards...) # tuple vs vararg form
    end

    @testset "HoldemEval — 1-indexed, higher-is-better wrapper" begin
        royal_0idx = (card(8, 0), card(9, 0), card(10, 0), card(11, 0), card(12, 0), card(0, 1), card(1, 2))
        royal_1idx = Tuple(c + 1 for c in royal_0idx)

        @test HoldemEval.evaluate7_oneIndexed_reversed(holdemEvalTables, royal_1idx) == 7463 - HoldemEval.evaluate7(holdemEvalTables, royal_0idx)
        @test HoldemEval.evaluate7_oneIndexed_reversed(holdemEvalTables, royal_1idx) == 7462
        @test HoldemEval.evaluate7_oneIndexed_reversed(holdemEvalTables, collect(royal_1idx)) == HoldemEval.evaluate7_oneIndexed_reversed(holdemEvalTables, royal_1idx) # Vector vs Tuple
    end

    @testset "evaluate7 vs brute-force reference (property-based)" begin
        rank_map = HoldemEval.build_rank_map()
        rng = MersenneTwister(20260814)
        deck = collect(0:51)
        for _ in 1:N_RANDOM_HANDS
            hand = Tuple(shuffle(rng, deck)[1:7])
            @test HoldemEval.evaluate7(holdemEvalTables, hand) == ref_best_rank(rank_map, hand)
        end
    end

    @testset "save_tables / load round-trip" begin
        mktempdir() do dir
            fpath, npath = joinpath(dir, "flush7.bin"), joinpath(dir, "noflush7.bin")
            HoldemEval.save_tables(holdemEvalTables, fpath, npath)

            @test filesize(fpath) == length(holdemEvalTables.flush_table) * 2
            @test filesize(npath) == length(holdemEvalTables.noflush7_table) * 2

            holdemEvalTables2 = HoldemEvalTables(fpath, npath)
            @test holdemEvalTables2.flush_table == holdemEvalTables.flush_table
            @test holdemEvalTables2.noflush7_table == holdemEvalTables.noflush7_table
            @test holdemEvalTables2.dp_table == holdemEvalTables.dp_table

            royal = (card(8, 0), card(9, 0), card(10, 0), card(11, 0), card(12, 0), card(0, 1), card(1, 2))
            @test evaluate7(holdemEvalTables2, royal) == evaluate7(holdemEvalTables, royal)
        end
    end

    if !FAST
        @testset "HoldemEval(path, path) — generates tables when files are missing" begin
            mktempdir() do dir
                fpath, npath = joinpath(dir, "flush7.bin"), joinpath(dir, "noflush7.bin")
                @test !isfile(fpath) && !isfile(npath)

                PH3 = HoldemEvalTables(fpath, npath)
                @test isfile(fpath) && isfile(npath)

                royal = (card(8, 0), card(9, 0), card(10, 0), card(11, 0), card(12, 0), card(0, 1), card(1, 2))
                @test evaluate7(PH3, royal) == 1
                @test PH3.flush_table == holdemEvalTables.flush_table
                @test PH3.noflush7_table == holdemEvalTables.noflush7_table
            end
        end
    end


end