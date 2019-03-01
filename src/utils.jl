#=

General utilities for ESSE

Ignacio Quintero Mächler

t(-_-t)

October 30 2017

=#



"""
  subsets(x::Array{String,1})

Create all subsets from each string (letters) in x.
"""
function subsets(x::Array{String,1})
  ss = [""]
  for elem in x, j in eachindex(ss)
      push!(ss, ss[j]*elem)
  end

  return ss
end





"""
    build_par_names(k::Int64, h::Int64, mod::NTuple{3,Bool})

Build dictionary for parameter names and indexes for EGeoHiSSE for
`k` areas and `h` hidden states.
"""
function build_par_names(k::Int64, h::Int64, model::NTuple{3,Bool})

  # generate individual area names
  ia = String[]
  for i = 0:(k-1)
    push!(ia, string('A' + i))
  end

  # generate area state space
  sa = subsets(ia)

  # remove empty areas
  popfirst!(sa)

  # total state space length
  na = lastindex(sa)

  # add hidden states
  S = Array{String,1}(undef, na*h)
  for j = 0:(h-1), i = Base.OneTo(na)
    S[na*j + i] = sa[i]*"_$j"
  end

  ## build parameters name 
  par_nams = String[]

  # add λ names
  for s = S
    push!(par_nams, "lambda_$s")
  end

  # which endemics
  wend = findall(x -> lastindex(x) == 3, S)
  # add μ names for endemics
  for i = Base.OneTo(k*h)
    push!(par_nams, "mu_$(S[wend[i]])")
  end

  # add q between areas
  # transitions can only through a widespread transition

  #=
  CHECK FOR DISTINC COLONIZATION RATES BETWEEN AREAS (separate 
  rates or sum of rates of dispersal)
  =#

  for i = 0:(h-1), a = sa, b = sa
    if a == b 
      continue
    elseif occursin(a, b) || occursin(b, a)
      push!(par_nams, "q_$(a)_$(b)_$i")
    end
  end

  # add q between hidden states
  for j = 0:(h-1), i = 0:(h-1)
    if j == i 
      continue
    end
    push!(par_nams, "q_$(j)$(i)")
  end

  ## add betas
  # if model is Q
  if model[3]
    for i = 0:(h-1), a = sa, b = sa
      if a == b 
        continue
      elseif occursin(a, b) || occursin(b, a)
        push!(par_nams, "beta_$(a)_$(b)_$i")
      end
    end
  # if model is speciation or extinction
  else
    for we = wend
      push!(par_nams, "beta_$(S[we])")
    end
  end

  pardic = Dict(par_nams[i] => i for i = Base.OneTo(lastindex(par_nams)))

  return pardic
end




"""
    build_par_names(k::Int64, T::Bool)

Build dictionary for parameter names and indexes for ESSE.
"""
function build_par_names(k::Int64, T::Bool)

  par_nams = String[]
  # build parameters name 
  for i in 0:(k-1)
    push!(par_nams, "lambda$i")
  end

  # add μ names
  for i in 0:(k-1)
    push!(par_nams, "mu$i")
  end

  # add q names
  for j in 0:(k-1), i in 0:(k-1)
    if i == j 
      continue
    end
    push!(par_nams, "q$j$i")
  end

  # add betas
  if T
    for i in 0:(k-1)
      push!(par_nams, "beta$i")
    end
  else
    # add betas
    for j in 0:(k-1), i in 0:(k-1)
      if i == j 
        continue
      end
      push!(par_nams, "beta$j$i")
    end
  end

  pardic = Dict(par_nams[i] => i for i in Base.OneTo(length(par_nams)))

  return pardic
end





"""
    build_par_names(k::Int64)

Build dictionary for parameter names and indexes for MUSSE.
"""
function build_par_names(k::Int64)

  par_nams = String[]
  # build parameters name 
  for i in 0:(k-1)
    push!(par_nams, "lambda$i")
  end

  # add μ names
  for i in 0:(k-1)
    push!(par_nams, "mu$i")
  end

  # add q names
  for j in 0:(k-1), i in 0:(k-1)
    if i == j 
      continue
    end
    push!(par_nams, "q$j$i")
  end

  pardic = Dict(par_nams[i] => i for i in Base.OneTo(length(par_nams)))

  return pardic
end





"""
    set_constraints(constraints::NTuple{endof(constraints),String},
                         pardic::Dict{String,Int64})

Make a Dictionary linking parameter that are to be the same.
"""
function set_constraints(constraints,
                         pardic     ::Dict{String,Int64})

  @inbounds begin
    conpar = Dict{Int64,Int64}()

    for c in constraints
      spl = split(c, '=')
      if length(spl) < 2
        continue
      end
      conpar[pardic[strip(spl[1])]] = pardic[strip(spl[2])]
    end
  end
  return conpar
end






"""
    states_to_values(tipst::Dict{Int64,Int64}, k::Int64)
    
Transform numbered tip_values to array with 1s and 0s
"""
function states_to_values(tipst::Dict{Int64,Int64}, k::Int64)
  tip_val = Dict{Int64,Array{Float64,1}}()
  for (key, val) in tipst
    push!(tip_val, key => zeros(k))
    setindex!(tip_val[key], 1.0, val)
  end

  return tip_val
end







