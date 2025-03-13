using Test
include("../src/main.jl")

@testset "Battery Tests" begin
    par = default_parameters()
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    T = par.T

    # Test Battery SOC Evolution: check that SOC evolves correctly and remains within bounds
    for t in 1:T
        computed_SOC = value(SOC[t-1]) + par.eta_charge * value(charge[t]) - value(discharge[t]) / par.eta_discharge
        @test isapprox(value(SOC[t]), computed_SOC; atol=1e-3)
        @test value(SOC[t]) <= par.E_max + 1e-3
        @test value(SOC[t]) >= 0.0
    end
end
