using Test
include("../src/main.jl")

@testset "Generation Tests" begin
    par = default_parameters()
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    T = par.T

    # Test Renewable Generation Limits: ensure wind and solar generation are bounded correctly
    for t in 1:T
        @test value(wind_gen[t]) <= par.WindCap * par.wind_avail[t] + 1e-3
        @test value(solar_gen[t]) <= par.SolarCap * par.solar_avail[t] + 1e-3
    end

    # Test Unit Commitment Consistency: if the generator is off, conventional generation should be near zero.
    for t in 1:T
        if value(u[t]) < 0.5  # Off state
            @test value(conventional_gen[t]) ≤ 1e-3
        else
            @test value(conventional_gen[t]) <= par.ConvCap + 1e-3
        end
    end

    # Additional check for startup/shutdown consistency
    @test isapprox(value(startup[1]), value(u[1]); atol=1e-3)
    for t in 2:T
        if value(u[t]) - value(u[t-1]) > 0.5
            @test isapprox(value(startup[t]), 1.0; atol=1e-3)
        end
        if value(u[t-1]) - value(u[t]) > 0.5
            @test isapprox(value(shutdown[t]), 1.0; atol=1e-3)
        end
    end
end
