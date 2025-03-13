using BenchmarkTools
# Make sure your model code is available.
include("../src/main.jl")  # Adjust the path if necessary

# Define a function that builds and solves the model, then returns the objective value.
function run_model()
    par = default_parameters()
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    return objective_value(model)
end

# Benchmark the run_model function using @btime
r = @benchmark run_model()
println(r)
