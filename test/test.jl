using Test
using JuMP, GLPK, MathOptInterface
const MOI = MathOptInterface

# Include your model code if not already loaded:
include("../src/main.jl")

@testset "Additional Energy Model Unit Tests" begin
    # Initialize model parameters and build the model
    par = default_parameters()
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    
    optimize!(model)
    @test termination_status(model) == MOI.OPTIMAL

    T = par.T
    L = par.L

    # 1. Test DSM Linking Constraint: DSMup[t] equals sum of DSMdo[t,tt] in window [t-L, t+L]
    for t in 1:T
        linking_sum = sum(value(DSMdo[t, tt]) for tt in max(1, t-L):min(T, t+L))
        @test isapprox(value(DSMup[t]), linking_sum; atol=1e-3)
    end

    # 2. Test DSM Capacity Constraints:
    for t in 1:T
        @test value(DSMup[t]) <= par.Cup + 1e-3
    end
    for tt in 1:T
        dsm_down = sum(value(DSMdo[t, tt]) for t in max(1, tt-L):min(T, tt+L))
        @test dsm_down <= par.Cdo + 1e-3
        @test (value(DSMup[tt]) + dsm_down) <= max(par.Cup, par.Cdo) + 1e-3
    end

    # 3. Test Battery Evolution and SOC Bounds:
    for t in 1:T
        computed_SOC = value(SOC[t-1]) + par.eta_charge * value(charge[t]) - value(discharge[t]) / par.eta_discharge
        @test isapprox(value(SOC[t]), computed_SOC; atol=1e-3)
        @test value(SOC[t]) <= par.E_max + 1e-3
        @test value(SOC[t]) >= 0.0
    end

    # 4. Test Renewable Generation Limits:
    for t in 1:T
        @test value(wind_gen[t]) <= par.WindCap * par.wind_avail[t] + 1e-3
        @test value(solar_gen[t]) <= par.SolarCap * par.solar_avail[t] + 1e-3
    end

    # 5. Test Unit Commitment Consistency for Conventional Generation:
    for t in 1:T
        if value(u[t]) < 0.5  # Off state
            @test value(conventional_gen[t]) ≤ 1e-3
        else
            @test value(conventional_gen[t]) <= par.ConvCap + 1e-3
        end
    end
    @test isapprox(value(startup[1]), value(u[1]); atol=1e-3)
    for t in 2:T
        if value(u[t]) - value(u[t-1]) > 0.5
            @test isapprox(value(startup[t]), 1.0; atol=1e-3)
        end
        if value(u[t-1]) - value(u[t]) > 0.5
            @test isapprox(value(shutdown[t]), 1.0; atol=1e-3)
        end
    end

    # 6. Test Power Balance Constraint:
    for t in 1:T
        lhs = value(conventional_gen[t]) + value(wind_gen[t]) + value(solar_gen[t]) + value(discharge[t])
        rhs = value(net_demand[t]) + value(charge[t])
        @test isapprox(lhs, rhs; atol=1e-3)
    end

    # 7. Test Objective Value Sanity:
    obj_val = objective_value(model)
    @test obj_val >= 0.0
end
