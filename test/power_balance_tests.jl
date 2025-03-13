using Test
include("../src/main.jl")

@testset "Power Balance and Objective Tests" begin
    par = default_parameters()
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    T = par.T

    # Test Power Balance Constraint: total generation plus battery discharge equals net demand plus battery charge
    for t in 1:T
        lhs = value(conventional_gen[t]) + value(wind_gen[t]) + value(solar_gen[t]) + value(discharge[t])
        rhs = value(net_demand[t]) + value(charge[t])
        @test isapprox(lhs, rhs; atol=1e-3)
    end

    # Test that the objective value (total cost) is nonnegative
    obj_val = objective_value(model)
    @test obj_val >= 0.0
end
