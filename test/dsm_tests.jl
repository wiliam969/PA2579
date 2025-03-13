using Test
include("../src/main.jl")  # Adjust the path as needed

@testset "DSM Tests" begin
    par = default_parameters()
    model, DSMup, DSMdo, conventional_gen, u, startup, shutdown, wind_gen, solar_gen, charge, discharge, SOC, net_demand = build_model(par)
    optimize!(model)
    T = par.T
    L = par.L

    # Test DSM Linking Constraint: each upward shift equals the sum of its corresponding downward shifts
    for t in 1:T
        linking_sum = sum(value(DSMdo[t, tt]) for tt in max(1, t-L):min(T, t+L))
        @test isapprox(value(DSMup[t]), linking_sum; atol=1e-3)
    end

    # Test DSM Capacity Limits: upward shifts and the sum of downward shifts do not exceed their capacities
    for t in 1:T
        @test value(DSMup[t]) <= par.Cup + 1e-3
    end
    for tt in 1:T
        dsm_down = sum(value(DSMdo[t, tt]) for t in max(1, tt-L):min(T, tt+L))
        @test dsm_down <= par.Cdo + 1e-3
        @test (value(DSMup[tt]) + dsm_down) <= max(par.Cup, par.Cdo) + 1e-3
    end
end
