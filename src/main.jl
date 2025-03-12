using JuMP
using GLPK
using Plots

# -----------------------------
# Model Setup and Optimization
# -----------------------------
# Example parameters
T = 24  # Number of time periods (hours)
L = 3   # Delay time (hours)
Cup = 10 # Installed capacity for upward shifts (MW)
Cdo = 10 # Installed capacity for downward shifts (MW)

# Example varying demand pattern
demand = [100, 100, 100, 100, 120, 120, 120, 100, 100, 100, 80, 80, 80, 80, 100, 100, 120, 120, 120, 100, 100, 100, 100, 100]

# Generation costs: lower at off-peak, higher at peak
generation_cost = [(t <= 8 || t >= 21) ? 10 : 50 for t in 1:T]

# Initialize the model
model = Model(GLPK.Optimizer)

# DSM variables
# DSMup[t]: upward shift applied at time t (i.e. additional load in period t)
@variable(model, DSMup[1:T] >= 0)
# DSMdo[k, t]: downward shift executed in period t for load shifted from period k
@variable(model, DSMdo[1:T, 1:T] >= 0)

# Linking constraint: Each upward shift from period t must be recovered by a downward shift
# in one of the periods in the window [t-L, t+L]
@constraint(model, [t = 1:T],
    DSMup[t] == sum(DSMdo[t, tt] for tt in max(1, t - L):min(T, t + L))
)

# Capacity constraints for upward shifts
@constraint(model, [t = 1:T], DSMup[t] <= Cup)

# Capacity constraints for downward shifts:
# For each period tt, the sum of downward shifts executed in tt should not exceed Cdo.
@constraint(model, [tt = 1:T],
    sum(DSMdo[t, tt] for t in max(1, tt - L):min(T, tt + L)) <= Cdo
)

# (Optional) Constraint to avoid simultaneous capacity exceedance in a period:
@constraint(model, [tt = 1:T],
    DSMup[tt] + sum(DSMdo[t, tt] for t in max(1, tt - L):min(T, tt + L)) <= max(Cup, Cdo)
)

# Define net load after DSM:
# For each period t, net demand is the original demand plus upward shift at t,
# minus the downward shifts executed in t.
@expression(model, net_demand[t=1:T],
    demand[t] + DSMup[t] - sum(DSMdo[k, t] for k in max(1, t - L):min(T, t + L))
)

# Objective: Minimize total generation cost over all time periods
@objective(model, Min, sum(generation_cost[t] * net_demand[t] for t in 1:T))

# Solve the model
optimize!(model)

# -----------------------------
# Print Results
# -----------------------------
println("Optimal DSM upward shifts:")
println(value.(DSMup))

println("Optimal DSM downward shifts:")
for t in 1:T
    println("Hour ", t, ": ", value.(DSMdo[:, t]))
end

# -----------------------------
# Visualization
# -----------------------------
# Prepare data for visualization
hours = 1:T
# Sum downward shifts executed in each hour
DSMdo_sum = [sum(value.(DSMdo[:, t])) for t in 1:T]
# Compute net demand after DSM
net_demand_array = [demand[t] + value(DSMup[t]) - DSMdo_sum[t] for t in 1:T]

# Plot original demand and net demand as lines
p1 = plot(hours, demand, lw=2, marker=:circle, label="Original Demand",
          xlabel="Hour", ylabel="Load (MW)", title="Demand & Net Demand")
plot!(p1, hours, net_demand_array, lw=2, marker=:square, label="Net Demand after DSM")

# Plot DSM shifts as bar charts
p2 = bar(hours, value.(DSMup), label="Upward Shifts", xlabel="Hour", ylabel="MW",
         title="DSM Shifts", alpha=0.6)
bar!(p2, hours, DSMdo_sum, label="Downward Shifts", alpha=0.6)

# Combine the two plots vertically
plot(p1, p2, layout = (2,1), legend = :bottomright)
