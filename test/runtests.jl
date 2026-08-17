using Test
using Random
using Combinatorics
using HoldemEval
using BenchmarkTools

Random.seed!(1234)



# Main test runner that executes each sub-test module
@testset "HoldemEval.jl Suite" begin
    include("test_core.jl")

    cpp_lib_path = get(ENV, "PHEVALUATOR_LIB", "")

    if !isempty(cpp_lib_path) && isfile(cpp_lib_path)
        @testset "C++ PHEvaluator Comparison" begin
            @info "Running C++ PHEvaluator comparison tests..."
            include("test_HoldemEval_vs_PHEvaluator.jl") # need the env variable PHEVALUATOR_LIB=/path/to/libpheval.so
        end
    else
        @info "Skipping C++ comparison tests (PHEVALUATOR_LIB not set or file not found)."
    end
    
    include("test_HoldemEval_vs_PokerHandEvaluator.jl")
end
