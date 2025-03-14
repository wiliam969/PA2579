using JSON3
using BenchmarkTools
using DataFrames, Statistics, Printf
using MathOptInterface
const MOI = MathOptInterface

# Assume default_parameters(), build_model(par), and solve_and_visualize(par) are defined
# and that ModelParameters has been extended to include CO₂ emission factors.
include("../src/main.jl")

# Helper function to update parameters based on simulation overrides from a Dict.
function update_parameters(default::ModelParameters, sim::Dict{String,Any})
    # Create a copy of the default parameters (here we reconstruct, but you could use a copy function)
    new_par = default
    if haskey(sim, "demand_scale")
        new_par = ModelParameters(
            new_par.T, new_par.L, new_par.Cup, new_par.Cdo,
            new_par.demand .* sim["demand_scale"],
            new_par.ev_demand, new_par.generation_cost,
            new_par.ConvCap, new_par.WindCap, new_par.wind_avail,
            new_par.SolarCap, new_par.solar_avail,
            new_par.E_max, new_par.charge_cap, new_par.discharge_cap,
            new_par.eta_charge, new_par.eta_discharge,
            new_par.startup_cost, new_par.shutdown_cost, new_par.startup_ramp,
            new_par.wind_speeds, new_par.wind_cut_in, new_par.wind_rated, new_par.wind_cut_out,
            new_par.solar_irradiance, new_par.solar_degradation,
            new_par.co2_conventional, new_par.co2_wind, new_par.co2_solar
        )
    end
    if haskey(sim, "startup_cost")
        new_par = ModelParameters(
            new_par.T, new_par.L, new_par.Cup, new_par.Cdo,
            new_par.demand, new_par.ev_demand, new_par.generation_cost,
            new_par.ConvCap, new_par.WindCap, new_par.wind_avail,
            new_par.SolarCap, new_par.solar_avail,
            new_par.E_max, new_par.charge_cap, new_par.discharge_cap,
            new_par.eta_charge, new_par.eta_discharge,
            sim["startup_cost"], new_par.shutdown_cost, new_par.startup_ramp,
            new_par.wind_speeds, new_par.wind_cut_in, new_par.wind_rated, new_par.wind_cut_out,
            new_par.solar_irradiance, new_par.solar_degradation,
            new_par.co2_conventional, new_par.co2_wind, new_par.co2_solar
        )
    end
    if haskey(sim, "co2_conventional")
        new_par = ModelParameters(
            new_par.T, new_par.L, new_par.Cup, new_par.Cdo,
            new_par.demand, new_par.ev_demand, new_par.generation_cost,
            new_par.ConvCap, new_par.WindCap, new_par.wind_avail,
            new_par.SolarCap, new_par.solar_avail,
            new_par.E_max, new_par.charge_cap, new_par.discharge_cap,
            new_par.eta_charge, new_par.eta_discharge,
            new_par.startup_cost, new_par.shutdown_cost, new_par.startup_ramp,
            new_par.wind_speeds, new_par.wind_cut_in, new_par.wind_rated, new_par.wind_cut_out,
            new_par.solar_irradiance, new_par.solar_degradation,
            sim["co2_conventional"], new_par.co2_wind, new_par.co2_solar
        )
    end
    return new_par
end

# Benchmark a single simulation.
# This function runs the simulation and returns elapsed time, objective value, and total CO₂ emissions.

function benchmark_simulation(par::ModelParameters)
    # Time the simulation (build and optimize the model)
    elapsed = @belapsed begin
        model, DSMup, DSMdo, conventional_gen, u, startup, shutdown,
            wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
        optimize!(model)
    end

    # Rebuild the model to extract results
    model, DSMup, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    
    # Check if the solution is optimal before extracting the objective value.
    if termination_status(model) != MOI.OPTIMAL
        println("Warning: Simulation did not solve optimally. Termination status: ", termination_status(model))
        return elapsed, NaN, NaN  # Use NaN or missing to indicate failure.
    end
    
    # Get objective value and compute CO₂ emissions.
    obj = objective_value(model)
    T = par.T
    total_co2_conventional = sum(value(conventional_gen[t]) * par.co2_conventional for t in 1:T)
    total_co2_wind         = sum(value(wind_gen[t]) * par.co2_wind for t in 1:T)
    total_co2_solar        = sum(value(solar_gen[t]) * par.co2_solar for t in 1:T)
    total_co2 = total_co2_conventional + total_co2_wind + total_co2_solar
    
    return elapsed, obj, total_co2
end

# Load simulation configurations from JSON.
config_file = "data/simulations.json"  # Adjust this path to where your JSON file is located.
config_data = JSON3.read(open(config_file), Dict{String,Any})
simulations = config_data["simulations"]

# Prepare DataFrame to store benchmark results.
results = DataFrame(simulation=Int[], elapsed_time=Float64[], objective_value=Float64[], total_co2=Float64[])

default_par = default_parameters()

# Run multiple simulations.
num_sims = length(simulations)
for (i, sim) in enumerate(simulations)
    println(@sprintf("Running simulation %d/%d...", i, num_sims))
    sim_par = update_parameters(default_par, sim)
    elapsed, obj, co2 = benchmark_simulation(sim_par)
    push!(results, (simulation=i, elapsed_time=elapsed, objective_value=obj, total_co2=co2))
end

println("Benchmark Results:")
println(results)

# Example comparison: sort simulations by lowest total CO₂ emissions and lowest objective value.
sorted_by_co2 = sort(results, :total_co2)
sorted_by_cost = sort(results, :objective_value)

println("\nSimulations sorted by lowest total CO₂ emissions:")
println(sorted_by_co2)

println("\nSimulations sorted by lowest objective value (cost):")
println(sorted_by_cost)
