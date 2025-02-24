abstract type AbstractAlgorithm end


mutable struct Algorithm{T} <: AbstractAlgorithm
    parameters::T
    status::State
    information::Information
    options::Options
end

function Algorithm(
    parameters;
    initial_state::State = State(nothing, []),
    information::Information = Information(),
    options::Options = Options(),
)

    Algorithm(parameters, initial_state, information, options)

end

function Base.show(io::IO, alg::Algorithm)
    Base.show(io, alg.parameters)
end

termination_status_message(alg::Algorithm) = termination_status_message(alg.status)
should_stop(algorithm::AbstractAlgorithm) = algorithm.status.stop
function get_result(algorithm::AbstractAlgorithm)
    if isnothing(algorithm.status.best_sol)
        error("First optimize a function: `optimize!(f, bounds, method)`")
    end
    
    algorithm.status
end

mutable struct Problem{T} <: AbstractProblem
    f::Function
    bounds::Array{T,2}
    f_calls::Int
    parallel_evaluation::Bool
end

function Problem(f::Function, bounds::Array; parallel_evaluation=false)

    if size(bounds,1) > 2 && size(bounds,2) == 2
        bounds = Array(bounds')
    end

    Problem(f, bounds, 0, parallel_evaluation)
end

function evaluate(x, problem::Problem)
    problem.f_calls += 1
    return problem.f(x)
end


