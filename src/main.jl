using JuMP, GLPK, Plots, CSV, DataFrames

# Define a structure to hold model parameters
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
    wind_avail::Vector{Float64}  # Hourly wind availability factors
    SolarCap::Float64        # Installed solar capacity (MW)
    solar_avail::Vector{Float64} # Hourly solar availability factors
    E_max::Float64           # Maximum battery energy capacity (MWh)
    charge_cap::Float64      # Maximum charging power (MW)
    discharge_cap::Float64   # Maximum discharging power (MW)
    eta_charge::Float64      # Battery charging efficiency
    eta_discharge::Float64   # Battery discharging efficiency
end

# Function to define default parameters (you can later load from external files)
function default_parameters()
    T = 24
    L = 3
    Cup = 10.0
    Cdo = 10.0
    # Baseline demand (MW)
    demand = [100, 100, 100, 100, 120, 120, 120, 100, 100, 100, 80, 80, 80, 80, 100, 100, 120, 120, 120, 100, 100, 100, 100, 100]
    # EV demand (MW): for example, EVs charge during two hours (e.g., 17 and 18)
    ev_demand = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30, 30, 0, 0, 0, 0, 0, 0]
    # Generation cost: lower cost (10) during off-peak (hours 1-8, 21-24) and higher (50) during peak (hours 9-20)
    generation_cost = [(t <= 8 || t >= 21) ? 10 : 50 for t in 1:T]
    ConvCap = 150.0
    WindCap = 50.0
    wind_avail = [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.7, 0.65, 0.6, 0.55, 0.5, 0.45, 0.4, 0.35, 0.3, 0.25, 0.2, 0.2, 0.25, 0.3, 0.35]
    SolarCap = 30.0
    solar_avail = [0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.6, 0.8, 0.9, 0.9, 0.8, 0.6, 0.4, 0.2, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    E_max = 100.0
    charge_cap = 20.0
    discharge_cap = 20.0
    eta_charge = 0.95
    eta_discharge = 0.95
    return ModelParameters(T, L, Cup, Cdo, demand, ev_demand, generation_cost,
                           ConvCap, WindCap, wind_avail, SolarCap, solar_avail,
                           E_max, charge_cap, discharge_cap, eta_charge, eta_discharge)
end

# Function to build the optimization model using the given parameters
function build_model(par::ModelParameters)
    model = Model(GLPK.Optimizer)
    T = par.T
    L = par.L

    # --- DSM Variables and Constraints ---
    @variable(model, DSMup[1:T] >= 0)              # Upward DSM shifts in each period
    @variable(model, DSMdo[1:T, 1:T] >= 0)           # Downward DSM shifts: DSMdo[t, tt] recovers load from hour t in period tt

    # Linking: Each upward shift must be recovered within the delay window [t-L, t+L]
    @constraint(model, [t=1:T],
                DSMup[t] == sum(DSMdo[t, tt] for tt in max(1, t-L):min(T, t+L)))
    @constraint(model, [t=1:T], DSMup[t] <= par.Cup)
    @constraint(model, [tt=1:T],
                sum(DSMdo[t, tt] for t in max(1, tt-L):min(T, tt+L)) <= par.Cdo)
    @constraint(model, [tt=1:T],
                DSMup[tt] + sum(DSMdo[t, tt] for t in max(1, tt-L):min(T, tt+L)) <= max(par.Cup, par.Cdo))

    # Net demand after DSM: baseline demand plus EV demand, plus DSM upward shifts minus recovered (downward) shifts
    @expression(model, net_demand[t=1:T],
                (par.demand[t] + par.ev_demand[t]) + DSMup[t] - sum(DSMdo[k, t] for k in max(1, t-L):min(T, t+L)))

    # --- Generation Variables and Constraints ---
    @variable(model, conventional_gen[1:T] >= 0, upper_bound=par.ConvCap)
    @variable(model, wind_gen[1:T] >= 0)
    for t in 1:T
        @constraint(model, wind_gen[t] <= par.WindCap * par.wind_avail[t])
    end
    @variable(model, solar_gen[1:T] >= 0)
    for t in 1:T
        @constraint(model, solar_gen[t] <= par.SolarCap * par.solar_avail[t])
    end

    # --- Battery Storage Variables and Constraints ---
    @variable(model, charge[1:T] >= 0)      # Battery charging power (MW)
    @variable(model, discharge[1:T] >= 0)   # Battery discharging power (MW)
    @variable(model, SOC[0:T] >= 0)         # Battery state-of-charge (MWh), indexed from 0 to T

    @constraint(model, SOC[0] == par.E_max/2)  # Initial SOC set at 50% capacity

    for t in 1:T
        @constraint(model, SOC[t] == SOC[t-1] + par.eta_charge * charge[t] - discharge[t] / par.eta_discharge)
        @constraint(model, SOC[t] <= par.E_max)
        @constraint(model, charge[t] <= par.charge_cap)
        @constraint(model, discharge[t] <= par.discharge_cap)
    end

    # --- Power Balance Constraint ---
    # The sum of all generation plus battery discharging must meet the net demand (which includes EV load and DSM adjustments)
    # Battery charging adds to the net load.
    @constraint(model, [t=1:T],
                conventional_gen[t] + wind_gen[t] + solar_gen[t] + discharge[t] ==
                net_demand[t] + charge[t])

    # --- Objective Function ---
    # Only conventional generation is costed (assuming renewables and battery operations have negligible variable cost)
    @objective(model, Min, sum(par.generation_cost[t] * conventional_gen[t] for t in 1:T))

    return model, DSMup, DSMdo, conventional_gen, wind_gen, solar_gen, charge, discharge, SOC, net_demand
end

# Function to solve the model and visualize the results
function solve_and_visualize(par::ModelParameters)
    model, DSMup, DSMdo, conventional_gen, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
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
    
    # -----------------------------
    # Visualization
    # -----------------------------
    hours = 1:T
    DSMdo_sum = [sum(value.(DSMdo[:, t])) for t in 1:T]
    net_demand_array = [(par.demand[t] + par.ev_demand[t]) + value(DSMup[t]) - DSMdo_sum[t] for t in 1:T]
    
    # Plot 1: Demand Profiles
    p1 = plot(hours, par.demand, lw=2, marker=:circle, label="Baseline Demand",
              xlabel="Hour", ylabel="Load (MW)", title="Demand Profiles")
    plot!(p1, hours, [par.demand[t] + par.ev_demand[t] for t in 1:T], lw=2, marker=:diamond, label="Total Demand (incl. EV)")
    plot!(p1, hours, net_demand_array, lw=2, marker=:square, label="Net Demand after DSM")
    
    # Plot 2: DSM Shifts
    p2 = bar(hours, value.(DSMup), label="Upward Shifts", xlabel="Hour", ylabel="MW",
             title="DSM Shifts", alpha=0.6)
    bar!(p2, hours, DSMdo_sum, label="Downward Shifts", alpha=0.6)
    
    # Plot 3: Generation & Battery Dispatch
    p3 = plot(hours, value.(conventional_gen), lw=2, marker=:circle, label="Conventional Gen",
              xlabel="Hour", ylabel="Generation (MW)", title="Generation & Battery Dispatch")
    plot!(p3, hours, value.(wind_gen), lw=2, marker=:star, label="Wind Gen")
    plot!(p3, hours, value.(solar_gen), lw=2, marker=:diamond, label="Solar Gen")
    plot!(p3, hours, net_demand_array, lw=2, marker=:utriangle, label="Net Demand", ls=:dash)
    plot!(p3, hours, value.(discharge), lw=2, marker=:vline, label="Battery Discharge", ls=:dot)
    plot!(p3, hours, value.(charge), lw=2, marker=:hline, label="Battery Charge", ls=:dashdot)
    
    # Plot 4: Battery SOC over time
    p4 = plot(0:T, [value(SOC[t]) for t in 0:T], lw=2, marker=:circle,
              xlabel="Hour", ylabel="SOC (MWh)", title="Battery State-of-Charge", label="SOC")
    
    # Combine all plots vertically and set an increased overall size
    plot(p1, p2, p3, p4, layout=(4,1), legend=:bottomright, size=(1200, 1200))
end

# Main execution
par = default_parameters()
solve_and_visualize(par)
