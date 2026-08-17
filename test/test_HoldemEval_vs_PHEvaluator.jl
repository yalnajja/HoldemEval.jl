"""
Cross-checks HoldemEval.evaluate7 (pure-Julia table-based evaluator)
against PHEvaluatorWrapper.evaluate_7cards (ccall into Henry Lee's C++
PokerHandEvaluator) to make sure both give the exact same rank for
every possible 7-card hand.

Both modules use the identical card encoding (id = rank*4 + suit,
rank 0:12, suit 0:3) and the identical "1 = best .. 7462 = worst"
rank scale, so a correct implementation should satisfy

    evaluate7(tables, c1,...,c7) == PHEvaluatorWrapper.evaluate_7cards(c1,...,c7)

for every 7-card combination drawn from the 52-card deck.

## Usage

    julia test_HoldemEval_vs_PHEvaluator.jl

By default this runs:
  1. A fast randomized check (100,000 random 7-card hands) — always runs.
  2. The FULL exhaustive check over all C(52,7) = 133,784,560 hands —
     only if you opt in (see below), since it can take a while.

To run the full exhaustive sweep:

    HOLDEMEVAL_EXHAUSTIVE=1 julia test_HoldemEval_vs_PHEvaluator.jl

You can also shrink/grow the random sample:

    HOLDEMEVAL_SAMPLE=1000000 julia test_HoldemEval_vs_PHEvaluator.jl

Point at your compiled libpheval the same way as before:

    PHEVALUATOR_LIB=/path/to/libpheval.so julia test_HoldemEval_vs_PHEvaluator.jl
"""



# # Adjust these include paths/module names to match your project layout.
# include("PHEvaluatorWrapper.jl")
# include("../src/HoldemEval.jl")
# using .PHEvaluatorWrapper
# using .HoldemEval
# already included in runtests.jl

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

const LIB_OK = _library_available()
if !LIB_OK
    @warn "libpheval not found/loadable — cannot cross-check against the C++ library. " *
          "Set ENV[\"PHEVALUATOR_LIB\"] or call PHEvaluatorWrapper.set_library!(path) first."
end

println("Building HoldemEval tables (this generates the 7462-category rank map)...")
const TABLES = @time HoldemEvalTables()

# card ids the C library and HoldemEval both use: 0:51 = rank*4 + suit
const ALL_CARDS = 0:51

# ---------------------------------------------------------------------
# Core comparison helper
# ---------------------------------------------------------------------

"""
    compare_all(card_iter; report_every=5_000_000, max_mismatches=20)

Iterates over an iterable of 7-tuples of card ids, evaluating each hand
with both HoldemEval.evaluate7 and PHEvaluatorWrapper.evaluate_7cards.
Returns (n_checked, mismatches) where mismatches is a Vector of
NamedTuples describing any disagreements (capped at max_mismatches).
"""
function compare_all(card_iter; report_every=5_000_000, max_mismatches=20)
    n = 0
    mismatches = NamedTuple[]
    t0 = time()
    for hand in card_iter
        c1, c2, c3, c4, c5, c6, c7 = hand
        v_julia = HoldemEval.evaluate7(TABLES, c1, c2, c3, c4, c5, c6, c7)
        v_cpp   = PHEvaluatorWrapper.evaluate_7cards(c1, c2, c3, c4, c5, c6, c7)
        if v_julia != v_cpp
            if length(mismatches) < max_mismatches
                push!(mismatches, (cards=hand, julia=Int(v_julia), cpp=Int(v_cpp)))
            end
        end
        n += 1
        if n % report_every == 0
            elapsed = round(time() - t0, digits=1)
            println("  checked $n hands in $(elapsed)s ($(length(mismatches)) mismatches so far)")
        end
    end
    return n, mismatches
end

function _print_mismatches(mismatches)
    for m in mismatches
        c1, c2, c3, c4, c5, c6, c7 = m.cards
        println("    cards=$(m.cards)  julia=$(m.julia) ($(hand_class_name(m.julia)))",
                "  cpp=$(m.cpp) ($(hand_class_name(m.cpp)))")
    end
end

# ---------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------

@testset "HoldemEval vs PHEvaluatorWrapper (C++)" begin

    @testset "randomized sample" begin
        if !LIB_OK
            @test_skip "libpheval not available"
        else
            n_sample = parse(Int, get(ENV, "HOLDEMEVAL_SAMPLE", "100000"))
            println("Randomized check: $n_sample random 7-card hands")

            rng = Random.default_rng()
            hands = (Tuple(sort!(randperm(rng, 52)[1:7] .- 1)) for _ in 1:n_sample)

            n, mismatches = compare_all(hands; report_every=max(n_sample ÷ 4, 1))
            if !isempty(mismatches)
                println("First mismatches:")
                _print_mismatches(mismatches)
            end
            @test isempty(mismatches)
            println("Randomized check done: $n hands compared.")
        end
    end

    @testset "full exhaustive sweep (C(52,7) = 133,784,560 hands)" begin
        if !LIB_OK
            @test_skip "libpheval not available"
        elseif get(ENV, "HOLDEMEVAL_EXHAUSTIVE", "0") != "1"
            @test_skip "set HOLDEMEVAL_EXHAUSTIVE=1 to run the full C(52,7) sweep (slow)"
        else
            println("Exhaustive check: all C(52,7) = 133,784,560 seven-card hands.")
            println("This will take a while — progress prints every 5,000,000 hands.")

            hands = combinations(collect(ALL_CARDS), 7)
            n, mismatches = compare_all(hands)

            if !isempty(mismatches)
                println("First mismatches:")
                _print_mismatches(mismatches)
            end
            @test isempty(mismatches)
            println("Exhaustive check done: $n hands compared, $(length(mismatches)) mismatches.")
        end
    end

end
