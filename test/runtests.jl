using Test
using Random
using Combinatorics
using HoldemEval


include("PHEvaluatorWrapper.jl")
using .PHEvaluatorWrapper

# Main test runner that executes each sub-test module
@testset "HoldemEval.jl Suite" begin
    include("test_core.jl")
    include("test_HoldemEval_vs_PHEvaluator.jl") # need the env variable PHEVALUATOR_LIB=/path/to/libpheval.so
    include("test_HoldemEval_vs_PokerHandEvaluator.jl")
end