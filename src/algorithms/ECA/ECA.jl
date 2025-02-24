include("adaptive_parameters.jl")
include("center_of_mass.jl")

mutable struct ECA <: AbstractParameters
    η_max::Float64
    K::Int
    N::Int
    N_init::Int
    p_exploit::Float64
    p_bin::Float64
    p_cr::Array{Float64}
    ε::Float64
    adaptive::Bool
    resize_population::Bool
end

"""
    ECA(;
        η_max = 2.0,
        K = 7,
        N = 0,
        N_init = N,
        p_exploit = 0.95,
        p_bin = 0.02,
        p_cr = Float64[],
        adaptive = false,
        resize_population = false,
        information = Information(),
        options = Options()
    )

Parameters for the metaheuristic ECA: step-size `η_max`,`K` is number of vectors to
generate the center of mass, `N` is the population size.

# Example

```jldoctest
julia> f(x) = sum(x.^2)
f (generic function with 1 method)

julia> optimize(f, [-1 -1 -1; 1 1 1.0], ECA())
+=========== RESULT ==========+
  iteration: 1429
    minimum: 3.3152400000000004e-223
  minimizer: [4.213750597785841e-113, 5.290977430907081e-112, 2.231685329262638e-112]
    f calls: 29989
 total time: 0.1672 s
+============================+

julia> optimize(f, [-1 -1 -1; 1 1 1.0], ECA(N = 10, η_max = 1.0, K = 3))
+=========== RESULT ==========+
  iteration: 3000
    minimum: 0.000571319
  minimizer: [-0.00017150889316537758, -0.007955828028420616, 0.022538733289139145]
    f calls: 30000
 total time: 0.1334 s
+============================+
```

"""
function ECA(;
    η_max::Float64 = 2.0,
    K::Int = 7,
    N::Int = 0,
    N_init::Int = N,
    p_exploit::Float64 = 0.95,
    p_bin::Float64 = 0.02,
    p_cr::Array{Float64} = Float64[],
    ε::Float64 = 0.0,
    adaptive::Bool = false,
    resize_population::Bool = false,
    information = Information(),
    options = Options(),
)


    N_init = N


    parameters = ECA(
        η_max,
        K,
        N,
        N_init,
        p_exploit,
        p_bin,
        p_cr,
        ε,
        adaptive,
        resize_population,
    )
    Algorithm(
        parameters,
        information = information,
        options = options,
    )

end

function eca_solution(status, parameters, options, problem, I, i)
    p = status.f_calls / options.f_calls_limit
    # generate U masses
    U = getU(status.population, parameters.K, I, i, parameters.N)
    # generate center of mass
    c, u_worst, u_best = center(U)
    # stepsize
    η = parameters.η_max * rand()
    # u: worst element in U
    u = U[u_worst] |> get_position
    # current-to-center/bin
    if p < parameters.p_exploit
        # u: worst element in U
        u = U[u_worst] |> get_position
        # current-to-center/bin
        y = get_position(status.population[i]) .+ η .* (c .- u)
    else
        # current-to-best/bin
        y = get_position(status.population[i]) .+ η .*(minimizer(status) .- c)
    end
    # binary crossover
    y, M_current = crossover(U[u_best].x, y, parameters.p_cr)
    evo_boundary_repairer!(y, c, problem.bounds)
    y, M_current
end


function update_state!(
        status,
        parameters::ECA,
        problem::AbstractProblem,
        information::Information,
        options::Options,
        args...;
        kargs...
    )

    I = randperm(parameters.N)
    D = size(problem.bounds, 2)

    parameters.adaptive && (Mcr_fail = zeros(D))

    if options.parallel_evaluation
        X_next = zeros(parameters.N, D)
    end

    # For each elements in Population
    for i in 1:parameters.N
        y, M_current = eca_solution(status, parameters, options,problem,I,i)

        if options.parallel_evaluation
            X_next[i,:] = y
            continue
        end
        
        sol = create_solution(y, problem)

        # replace worst element
        if is_better(sol, status.population[i])
            wi = argworst(status.population)
            status.population[wi] = sol
            if is_better(sol, status.best_sol)
                status.best_sol = sol
            end
        else
            parameters.adaptive && (Mcr_fail += M_current)
        end
    end

    if options.parallel_evaluation
        append!(status.population, create_solutions(X_next, problem))
        environmental_selection!(status.population, parameters)
        status.best_sol = get_best(status.population)
    end

    if parameters.adaptive
        parameters.p_cr =
            adaptCrossover(parameters.p_cr, Mcr_fail / parameters.N)
    end

    resize_population!(status, parameters, options)
end

function resize_population!(status, parameters::ECA, options)
    if !parameters.resize_population
        return
    end

    p = status.f_calls / options.f_calls_limit

    K = parameters.K

    # new size
    parameters.N = 2K .+ round(Int, (1 - p) * (parameters.N_init .- 2K))

    if parameters.N < 2K
        parameters.N = 2K
    end

    status.population = resizePop!(status.population, parameters.N, K)
end



function environmental_selection(population, parameters::ECA)
    @assert length(population) == 2*parameters.N

    new_solutions = population[parameters.N+1:end]
    population = population[1:parameters.N]

    survivals = collect(1:length(population))

    for (i, sol) in enumerate(new_solutions)
        if !is_better(sol, population[i])
            continue
        end
        wi = argworst(population)
        survivals[wi] = parameters.N + i
        population[wi] = sol
    end
    return survivals
end


function environmental_selection!(population, parameters::ECA)
    I = environmental_selection(population, parameters)
    ignored = ones(Bool, length(population))
    ignored[I] .= false
    deleteat!(population, ignored)
end

function initialize!(
        status,
        parameters::ECA,
        problem::AbstractProblem,
        information::Information,
        options::Options,
        args...;
        kargs...
    )
    D = size(problem.bounds, 2)


    if parameters.N <= parameters.K
        parameters.N = parameters.K * D
    end

    if options.f_calls_limit == 0
        options.f_calls_limit = 10000D
        options.debug &&
            @warn( "f_calls_limit increased to $(options.f_calls_limit)")
    end

    if options.iterations == 0
        options.iterations = div(options.f_calls_limit, parameters.N) + 1
    end

    N_init = parameters.N


    if parameters.adaptive
        parameters.p_cr = rand(D)
    else
        parameters.p_cr = parameters.p_bin .* ones(D)
    end


    # initialize!(problem, nothing, parameters, status, information, options)
    st = gen_initial_state(problem,parameters,information,options, status)
    st

end

function final_stage!(
    status,
    parameters::ECA,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
    )
    status.final_time = time()
end


###########################################
## ECA
###########################################
function reproduction(status, parameters::ECA, problem)
    @assert !isempty(status.population)

    N = parameters.N
    D = length(get_position(status.population[1]))

    X = zeros(N,D)

    for i in 1:N
        X[i,:] = ECA_operator(status.population,
                              parameters.K,
                              parameters.η_max;
                              i=i,
                             bounds = problem.bounds)
    end

    X 
end
