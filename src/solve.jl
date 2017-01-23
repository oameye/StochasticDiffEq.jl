@inline ODE_DEFAULT_NORM(u) = sqrt(sum(abs2,u) / length(u))
@inline ODE_DEFAULT_PROG_MESSAGE(dt,t,u) = "dt="*string(dt)*"\nt="*string(t)*"\nmax u="*string(maximum(abs.(u)))
@inline ODE_DEFAULT_UNSTABLE_CHECK(dt,t,u) = any(isnan,u)

function solve{uType,tType,isinplace,NoiseClass,F,F2,F3,algType<:AbstractSDEAlgorithm,recompile_flag}(
              prob::AbstractSDEProblem{uType,tType,isinplace,NoiseClass,F,F2,F3},
              alg::algType,timeseries=[],ts=[],ks=[],recompile::Type{Val{recompile_flag}}=Val{true};
              dt = tType(0),save_timeseries::Bool = true,
              timeseries_steps::Int = 1,
              dense = false,
              saveat = tType[],tstops = tType[],d_discontinuities= tType[],
              calck = (!isempty(setdiff(saveat,tstops)) || dense),
              adaptive=isadaptive(alg),γ=9//10,
              abstol=1e-2,reltol=1e-2,
              qmax=qmax_default(alg),qmin=qmin_default(alg),
              qoldinit=1//10^4, fullnormalize=true,
              beta2=beta2_default(alg),
              beta1=beta1_default(alg,beta2),
              δ=1/6,maxiters = 1e9,
              dtmax=tType((prob.tspan[end]-prob.tspan[1])),
              dtmin=tType <: AbstractFloat ? tType(10)*eps(tType) : tType(1//10^(10)),
              internalnorm=ODE_DEFAULT_NORM,
              unstable_check = ODE_DEFAULT_UNSTABLE_CHECK,
              advance_to_tstop = false,stop_at_next_tstop=false,
              discard_length=1e-15,adaptivealg::Symbol=:RSwM3,
              progress_steps=1000,
              progress=false, progress_message = ODE_DEFAULT_PROG_MESSAGE,
              progress_name="SDE",
              userdata=nothing,callback=nothing,
              timeseries_errors = true, dense_errors=false,
              tableau = nothing,kwargs...)

  @unpack u0,noise,tspan = prob

  tdir = tspan[2]-tspan[1]

  if tspan[2]-tspan[1]<0 || length(tspan)>2
    error("tspan must be two numbers and final time must be greater than starting time. Aborting.")
  end

  if !(typeof(alg) <: StochasticDiffEqAdaptiveAlgorithm) && dt == 0 && isempty(tstops)
      error("Fixed timestep methods require a choice of dt or choosing the tstops")
  end

  u = copy(u0)

  f = prob.f
  g = prob.g

  if typeof(alg) <: StochasticDiffEqAdaptiveAlgorithm
    if adaptive
      dt = 1.0*dt
    end
  else
    adaptive = false
  end

  if dtmax == nothing
    dtmax = (tspan[2]-tspan[1])/2
  end
  if dtmin == nothing
    if tType <: AbstractFloat
      dtmin = tType(10)*eps(tType)
    else
      dtmin = tType(1//10^(10))
    end
  end

  if dt == 0.0
    order = alg_order(alg)
    dt = sde_determine_initdt(u0,float(tspan[1]),tdir,dtmax,abstol,reltol,internalnorm,prob,order)
  end

  T = tType(tspan[2])
  t = tType(tspan[1])

  timeseries = Vector{uType}(0)
  push!(timeseries,u0)
  ts = Vector{tType}(0)
  push!(ts,t)

  #PreProcess
  if typeof(alg)== SRA && tableau == nothing
    tableau = constructSRA1()
  elseif tableau == nothing # && (typeof(alg)==:SRI)
    tableau = constructSRIW1()
  end

  uEltype = eltype(u)
  tableauType = typeof(tableau)

  if !(uType <: AbstractArray)
    rands = ChunkedArray(noise.noise_func)
    randType = typeof(u/u) # Strip units and type info
  else
    rand_prototype = similar(map((x)->x/x,u),indices(u))
    rands = ChunkedArray(noise.noise_func,rand_prototype) # Strip units
    randType = typeof(rand_prototype) # Strip units and type info
  end

  uEltypeNoUnits = typeof(recursive_one(u))
  tTypeNoUnits   = typeof(recursive_one(t))


  Ws = Vector{randType}(0)
  if !(uType <: AbstractArray)
    W = 0.0
    Z = 0.0
    push!(Ws,W)
  else
    W = zeros(rand_prototype)
    Z = zeros(rand_prototype)
    push!(Ws,copy(W))
  end
  sqdt = sqrt(dt)
  iter = 0
  maxstacksize = 0
  #EEst = 0
  q11 = tTypeNoUnits(1)

  rateType = typeof(u/t) ## Can be different if united

  #@code_warntype sde_solve(SDEIntegrator{typeof(alg),typeof(u),eltype(u),ndims(u),ndims(u)+1,typeof(dt),typeof(tableau)}(f,g,u,t,dt,T,Int(maxiters),timeseries,Ws,ts,timeseries_steps,save_timeseries,adaptive,adaptivealg,δ,γ,abstol,reltol,qmax,dtmax,dtmin,internalnorm,discard_length,progress,atomloaded,progress_steps,rands,sqdt,W,Z,tableau))

  u,t,W,timeseries,ts,Ws,maxstacksize,maxstacksize2 = sde_solve(
  SDEIntegrator{typeof(alg),uType,uEltype,ndims(u),ndims(u)+1,tType,tTypeNoUnits,tableauType,
                uEltypeNoUnits,randType,rateType,typeof(internalnorm),typeof(progress_message),
                typeof(unstable_check),F,F2}(f,g,u,t,dt,T,alg,Int(maxiters),timeseries,Ws,
                ts,timeseries_steps,save_timeseries,adaptive,adaptivealg,δ,tTypeNoUnits(γ),
                abstol,reltol,tTypeNoUnits(qmax),dtmax,dtmin,internalnorm,discard_length,
                progress,progress_name,progress_steps,progress_message,
                unstable_check,rands,sqdt,W,Z,tableau,
                tTypeNoUnits(beta1),tTypeNoUnits(beta2),tTypeNoUnits(qoldinit),tTypeNoUnits(qmin),q11,tTypeNoUnits(qoldinit)))

  build_solution(prob,alg,ts,timeseries,W=Ws,
                  timeseries_errors = timeseries_errors,
                  maxstacksize = maxstacksize)

end
