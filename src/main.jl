using JuMP, GLPK, Plots, CSV, DataFrames

# Helper functions to compute capacity factors

# Computes the wind capacity factor given the wind speed and turbine parameters.
function compute_wind_avail(wind_speed, cut_in, rated, cut_out)
    if wind_speed < cut_in || wind_speed >= cut_out
        return 0.0
    elseif wind_speed < rated
        return (wind_speed - cut_in) / (rated - cut_in)
    else
        return 1.0
    end
end

# Computes the solar capacity factor based on irradiance (W/m^2) and a degradation factor.
# Assuming that 1000 W/m^2 is the nominal irradiance that yields full capacity.
function compute_solar_avail(irradiance, degradation)
    return min((irradiance / 1000.0) * degradation, 1.0)
end

# Define a structure to hold model parameters, including the new wind/solar parameters.
struct ModelParameters
    T::Int                   # Number of time periods (hours)
    L::Int                   # DSM delay time (hours)
    Cup::Float64             # Capacity for DSM upward shifts (MW)
    Cdo::Float64             # Capacity for DSM downward shifts (MW)
    demand::Vector{Float64}  # Baseline demand profile (MW)
    ev_demand::Vector{Float64} # EV demand profile (MW)
    generation_cost::Vector{Float64}  # Conventional generation cost per hour
    ConvCap::Float64         # Capacity of conventional generation (MW)
    WindCap::Float64         # Installed wind capacity (MW)
    wind_avail::Vector{Float64}  # Hourly wind availability factors (computed)
    SolarCap::Float64        # Installed solar capacity (MW)
    solar_avail::Vector{Float64} # Hourly solar availability factors (computed)
    E_max::Float64           # Maximum battery energy capacity (MWh)
    charge_cap::Float64      # Maximum charging power (MW)
    discharge_cap::Float64   # Maximum discharging power (MW)
    eta_charge::Float64      # Battery charging efficiency
    eta_discharge::Float64   # Battery discharging efficiency
    startup_cost::Float64    # Cost to start up the conventional generator
    shutdown_cost::Float64   # Cost to shut down the conventional generator
    startup_ramp::Float64    # Fraction of full capacity allowed immediately after startup
    # Detailed wind turbine parameters:
    wind_speeds::Vector{Float64}  # Hourly wind speeds (m/s)
    wind_cut_in::Float64          # Cut-in speed (m/s)
    wind_rated::Float64           # Rated speed (m/s)
    wind_cut_out::Float64         # Cut-out speed (m/s)
    # Detailed solar parameters:
    solar_irradiance::Vector{Float64} # Hourly solar irradiance (W/m^2)
    solar_degradation::Float64        # Solar panel degradation factor (0-1)
end

# Function to define default parameters and compute wind/solar availability factors
function default_parameters()
    T = 24
    L = 3
    Cup = 10.0
    Cdo = 10.0
    # Baseline demand (MW)
    demand = [100, 100, 100, 100, 120, 120, 120, 100, 100, 100, 80, 80, 80, 80, 100, 100, 120, 120, 120, 100, 100, 100, 100, 100]
    # EV demand (MW)
    ev_demand = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30, 30, 0, 0, 0, 0, 0, 0]
    # Generation cost: off-peak cost=10, peak cost=50
    generation_cost = [(t <= 8 || t >= 21) ? 10 : 50 for t in 1:T]
    ConvCap = 150.0

    # --- Wind parameters ---
    WindCap = 50.0
    # Example hourly wind speeds (m/s) for 24 hours
    wind_speeds = [4.0, 4.2, 4.5, 4.7, 5.0, 5.2, 5.5, 6.0, 6.2, 6.5, 6.7, 7.0, 7.2, 7.5, 7.8, 8.0, 8.2, 8.5, 8.7, 9.0, 9.2, 9.5, 9.7, 10.0]
    wind_cut_in = 3.0    # m/s
    wind_rated = 12.0    # m/s
    wind_cut_out = 25.0  # m/s
    wind_avail = [compute_wind_avail(ws, wind_cut_in, wind_rated, wind_cut_out) for ws in wind_speeds]

    # --- Solar parameters ---
    SolarCap = 30.0
    # Example hourly solar irradiance (W/m^2) for 24 hours (typical clear-sky profile)
    solar_irradiance = [0.0, 0.0, 0.0, 0.0, 100.0, 300.0, 500.0, 700.0, 900.0, 1000.0, 900.0, 700.0, 500.0, 300.0, 100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    solar_degradation = 0.9
    solar_avail = [compute_solar_avail(irr, solar_degradation) for irr in solar_irradiance]

    E_max = 100.0
    charge_cap = 20.0
    discharge_cap = 20.0
    eta_charge = 0.95
    eta_discharge = 0.95
    startup_cost = 500.0
    shutdown_cost = 300.0
    startup_ramp = 0.5

    return ModelParameters(T, L, Cup, Cdo, demand, ev_demand, generation_cost,
                           ConvCap, WindCap, wind_avail, SolarCap, solar_avail,
                           E_max, charge_cap, discharge_cap, eta_charge, eta_discharge,
                           startup_cost, shutdown_cost, startup_ramp,
                           wind_speeds, wind_cut_in, wind_rated, wind_cut_out,
                           solar_irradiance, solar_degradation)
end

# The rest of the model-building functions remain largely unchanged.
# (See previous example for build_model and solve_and_visualize functions.)
# They use par.wind_avail and par.solar_avail in the generation constraints.

function build_model(par::ModelParameters)
    model = Model(GLPK.Optimizer)
    T = par.T
    L = par.L

    # --- DSM Variables and Constraints ---
    @variable(model, DSMup[1:T] >= 0)
    @variable(model, DSMdo[1:T, 1:T] >= 0)
    @constraint(model, [t=1:T],
                DSMup[t] == sum(DSMdo[t, tt] for tt in max(1, t-L):min(T, t+L)))
    @constraint(model, [t=1:T], DSMup[t] <= par.Cup)
    @constraint(model, [tt=1:T],
                sum(DSMdo[t, tt] for t in max(1, tt-L):min(T, tt+L)) <= par.Cdo)
    @constraint(model, [tt=1:T],
                DSMup[tt] + sum(DSMdo[t, tt] for t in max(1, tt-L):min(T, tt+L)) <= max(par.Cup, par.Cdo))
    @expression(model, net_demand[t=1:T],
                (par.demand[t] + par.ev_demand[t]) + DSMup[t] - sum(DSMdo[k, t] for k in max(1, t-L):min(T, t+L)))

    # --- Generation Variables and Constraints ---
    @variable(model, conventional_gen[1:T] >= 0)
    @variable(model, u[1:T], Bin)
    @variable(model, startup[1:T], Bin)
    @variable(model, shutdown[1:T], Bin)
    for t in 1:T
        @constraint(model,
            conventional_gen[t] <= par.ConvCap * u[t] - (par.ConvCap - par.startup_ramp * par.ConvCap) * startup[t])
    end
    @constraint(model, startup[1] == u[1])
    for t in 2:T
        @constraint(model, startup[t] >= u[t] - u[t-1])
        @constraint(model, shutdown[t] >= u[t-1] - u[t])
    end

    @variable(model, wind_gen[1:T] >= 0)
    for t in 1:T
        @constraint(model, wind_gen[t] <= par.WindCap * par.wind_avail[t])
    end

    @variable(model, solar_gen[1:T] >= 0)
    for t in 1:T
        @constraint(model, solar_gen[t] <= par.SolarCap * par.solar_avail[t])
    end

    # --- Battery Storage Variables and Constraints ---
    @variable(model, charge[1:T] >= 0)
    @variable(model, discharge[1:T] >= 0)
    @variable(model, SOC[0:T] >= 0)
    @constraint(model, SOC[0] == par.E_max/2)
    for t in 1:T
        @constraint(model, SOC[t] == SOC[t-1] + par.eta_charge * charge[t] - discharge[t] / par.eta_discharge)
        @constraint(model, SOC[t] <= par.E_max)
        @constraint(model, charge[t] <= par.charge_cap)
        @constraint(model, discharge[t] <= par.discharge_cap)
    end

    @constraint(model, [t=1:T],
        conventional_gen[t] + wind_gen[t] + solar_gen[t] + discharge[t] ==
        net_demand[t] + charge[t])

    @objective(model, Min,
        sum(par.generation_cost[t] * conventional_gen[t] for t in 1:T) +
        sum(par.startup_cost * startup[t] + par.shutdown_cost * shutdown[t] for t in 1:T)
    )
    
    return model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand
end

function solve_and_visualize(par::ModelParameters)
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    
    T = par.T
    println("Optimal DSM upward shifts:")
    println(value.(DSMup))
    println("\nOptimal DSM downward shifts:")
    for t in 1:T
        println("Hour ", t, ": ", value.(DSMdo[:, t]))
    end
    println("\nConventional Generation (MW):")
    println(value.(conventional_gen))
    println("\nUnit Commitment (u):")
    println(value.(u))
    println("\nStartup events:")
    println(value.(startup))
    println("\nShutdown events:")
    println(value.(shutdown))
    println("\nWind Generation (MW):")
    println(value.(wind_gen))
    println("\nSolar Generation (MW):")
    println(value.(solar_gen))
    println("\nBattery Charging (MW):")
    println(value.(charge))
    println("\nBattery Discharging (MW):")
    println(value.(discharge))
    println("\nBattery State-of-Charge (MWh):")
    println([value(SOC[t]) for t in 0:T])
    
    hours = 1:T
    DSMdo_sum = [sum(value.(DSMdo[:, t])) for t in 1:T]
    net_demand_array = [(par.demand[t] + par.ev_demand[t]) + value(DSMup[t]) - DSMdo_sum[t] for t in 1:T]
    
    p1 = plot(hours, par.demand, lw=2, marker=:circle, label="Baseline Demand",
              xlabel="Hour", ylabel="Load (MW)", title="Demand Profiles")
    plot!(p1, hours, [par.demand[t] + par.ev_demand[t] for t in 1:T], lw=2, marker=:diamond, label="Total Demand (incl. EV)")
    plot!(p1, hours, net_demand_array, lw=2, marker=:square, label="Net Demand after DSM")
    
    p2 = bar(hours, value.(DSMup), label="Upward Shifts", xlabel="Hour", ylabel="MW",
             title="DSM Shifts", alpha=0.6)
    bar!(p2, hours, DSMdo_sum, label="Downward Shifts", alpha=0.6)
    
    p3 = plot(hours, value.(conventional_gen), lw=2, marker=:circle, label="Conventional Gen",
              xlabel="Hour", ylabel="Generation (MW)", title="Generation & Battery Dispatch")
    plot!(p3, hours, value.(wind_gen), lw=2, marker=:star, label="Wind Gen")
    plot!(p3, hours, value.(solar_gen), lw=2, marker=:diamond, label="Solar Gen")
    plot!(p3, hours, net_demand_array, lw=2, marker=:utriangle, label="Net Demand", ls=:dash)
    plot!(p3, hours, value.(discharge), lw=2, marker=:vline, label="Battery Discharge", ls=:dot)
    plot!(p3, hours, value.(charge), lw=2, marker=:hline, label="Battery Charge", ls=:dashdot)
    
    p4 = plot(0:T, [value(SOC[t]) for t in 0:T], lw=2, marker=:circle,
              xlabel="Hour", ylabel="SOC (MWh)", title="Battery State-of-Charge", label="SOC")
    
    plot(p1, p2, p3, p4, layout=(4,1), legend=:bottomright, size=(1200, 1200))
end

# Main execution
par = default_parameters()
solve_and_visualize(par)