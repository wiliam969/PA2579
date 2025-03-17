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
            new_par.co2_conventional, new_par.co2_wind, new_par.co2_solar,
            new_par.conv_initial_cost, new_par.conv_maintenance_cost, new_par.conv_production_cost,
            new_par.wind_initial_cost, new_par.wind_maintenance_cost, new_par.wind_production_cost,
            new_par.solar_initial_cost, new_par.solar_maintenance_cost, new_par.solar_production_cost
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
            new_par.co2_conventional, new_par.co2_wind, new_par.co2_solar,
            new_par.conv_initial_cost, new_par.conv_maintenance_cost, new_par.conv_production_cost,
            new_par.wind_initial_cost, new_par.wind_maintenance_cost, new_par.wind_production_cost,
            new_par.solar_initial_cost, new_par.solar_maintenance_cost, new_par.solar_production_cost
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
            sim["co2_conventional"], new_par.co2_wind, new_par.co2_solar,
            new_par.conv_initial_cost, new_par.conv_maintenance_cost, new_par.conv_production_cost,
            new_par.wind_initial_cost, new_par.wind_maintenance_cost, new_par.wind_production_cost,
            new_par.solar_initial_cost, new_par.solar_maintenance_cost, new_par.solar_production_cost
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
        return elapsed, NaN, NaN, NaN, NaN, NaN, NaN
    end
    
    obj = objective_value(model)
    T = par.T

    # Compute total CO₂ emissions.
    total_co2_conventional = sum(value(conventional_gen[t]) * par.co2_conventional for t in 1:T)
    total_co2_wind         = sum(value(wind_gen[t]) * par.co2_wind for t in 1:T)
    total_co2_solar        = sum(value(solar_gen[t]) * par.co2_solar for t in 1:T)
    total_co2 = total_co2_conventional + total_co2_wind + total_co2_solar

    # Compute production amounts (MWh) for each technology.
    prod_conv = sum(value(conventional_gen[t]) for t in 1:T)
    prod_wind = sum(value(wind_gen[t]) for t in 1:T)
    prod_solar = sum(value(solar_gen[t]) for t in 1:T)

    # Calculate production costs.
    cost_conv_prod = prod_conv * par.conv_production_cost
    cost_wind_prod = prod_wind * par.wind_production_cost
    cost_solar_prod = prod_solar * par.solar_production_cost

    # Fixed costs: initial and maintenance costs are assumed to be proportional to installed capacity.
    # Here we assume the installed capacity is given by ConvCap, WindCap, and SolarCap.
    cost_conv_fixed = par.ConvCap * (par.conv_initial_cost + par.conv_maintenance_cost * T)
    cost_wind_fixed = par.WindCap * (par.wind_initial_cost + par.wind_maintenance_cost * T)
    cost_solar_fixed = par.SolarCap * (par.solar_initial_cost + par.solar_maintenance_cost * T)

    total_cost_conv = cost_conv_prod + cost_conv_fixed
    total_cost_wind = cost_wind_prod + cost_wind_fixed
    total_cost_solar = cost_solar_prod + cost_solar_fixed
    total_cost = total_cost_conv + total_cost_wind + total_cost_solar

    return elapsed, obj, total_co2, total_cost, total_cost_conv, total_cost_wind, total_cost_solar
end

# Load simulation configurations from JSON.
config_file = "data/simulations.json"  # Adjust this path to where your JSON file is located.
config_data = JSON3.read(open(config_file), Dict{String,Any})
simulations = config_data["simulations"]

results = DataFrame(simulation=Int[], elapsed_time=Float64[], objective_value=Float64[],
                    total_co2=Float64[], total_cost=Float64[],
                    cost_conv=Float64[], cost_wind=Float64[], cost_solar=Float64[])

default_par = default_parameters()

for (i, sim) in enumerate(simulations)
    println(@sprintf("Running simulation %d/%d...", i, length(simulations)))
    sim_par = update_parameters(default_par, sim)
    elapsed, obj, co2, total_cost, cost_conv, cost_wind, cost_solar = benchmark_simulation(sim_par)
    push!(results, (simulation=i, elapsed_time=elapsed, objective_value=obj, total_co2=co2,
                     total_cost=total_cost, cost_conv=cost_conv, cost_wind=cost_wind, cost_solar=cost_solar))
end

println("Benchmark Results:")
println(results)

# Compare simulations by sorting by key metrics.
sorted_by_co2 = sort(results, :total_co2)
sorted_by_cost = sort(results, :total_cost)

println("\nSimulations sorted by lowest total CO₂ emissions:")
println(sorted_by_co2)

println("\nSimulations sorted by lowest total cost:")
println(sorted_by_cost)

using Plots, DataFrames

# Assuming `results` is your DataFrame from the benchmark simulations:
# For example:
# results = DataFrame(simulation = 1:20, elapsed_time = rand(20) .* 0.1)

# Create a histogram of the elapsed times
hist = histogram(results.elapsed_time,
                 bins = 10,
                 xlabel = "Elapsed Time (seconds)",
                 ylabel = "Frequency",
                 title = "Histogram of Benchmark Elapsed Times",
                 legend = false)

# Save the plot if desired (this will overwrite any existing file)
savefig(hist, "build/elapsed_time_histogram.png")

display(hist)
