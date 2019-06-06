#=
Simulation for ESSE

Ignacio Quintero Mächler

t(-_-t)

January 12 2017
=#





"""
    simulate_sse(λ       ::Array{Float64,1},
                 μ       ::Array{Float64,1},
                 l       ::Array{Float64,1},
                 g       ::Array{Float64,1},
                 q       ::Array{Float64,1},
                 β       ::Array{Float64,1},
                 x       ::Array{Float64,1},
                 y       ::Array{Float64,N};
                 cov_mod ::String  = "speciation",
                 δt      ::Float64 = 1e-4,
                 nspp_min::Int64   = 1,
                 nspp_max::Int64   = 200_000,
                 retry_ext::Bool   = true)

Simulate tree according to EGeoHiSSE.
"""
function simulate_sse(λ       ::Array{Float64,1},
                      μ       ::Array{Float64,1},
                      l       ::Array{Float64,1},
                      g       ::Array{Float64,1},
                      q       ::Array{Float64,1},
                      β       ::Array{Float64,1},
                      x       ::Array{Float64,1},
                      y       ::Array{Float64,N};
                      cov_mod ::String  = "speciation",
                      δt      ::Float64 = 1e-4,
                      nspp_min::Int64   = 1,
                      nspp_max::Int64   = 200_000,
                      retry_ext::Bool   = true) where N

  # make simulation
  ed, el, st, simt, n, af!, r, S, k, h = 
    simulate_edges(λ, μ, l, g, q, β, x, y, δt, cov_mod, nspp_max)

  println("Tree with $n species successfully simulated")

  if retry_ext 
    in(0.0, el) && println("a lineage speciated at time 0.0...")
    while ed == 0 || n < nspp_min || n > nspp_max || in(0.0, el)
      ed, el, st, simt, n, af!, r, S, k, h = 
        simulate_edges(λ, μ, l, g, q, β, x, y, δt, cov_mod, nspp_max)
      println("Tree with $n species successfully simulated")
    end
  else 
    if ed == 0
      return 0, 0, 0
    end
  end

  # organize in postorder
  ed     = numberedges(ed, n)
  ed, el = postorderedges(ed, el, n)

  # organize states
  tip_val = Dict(i => st[i] for i = 1:n)

  tip_val = states_to_values(tip_val, S, k)

  return tip_val, ed, el
end





"""
    simulate_edges(λ       ::Array{Float64,1},
                   μ       ::Array{Float64,1},
                   l       ::Array{Float64,1},
                   g       ::Array{Float64,1},
                   q       ::Array{Float64,1},
                   β       ::Array{Float64,1},
                   x       ::Array{Float64,1},
                   y       ::Array{Float64, N},
                   δt      ::Float64,
                   cov_mod ::String,
                   nssp_max::Int64)

Simulate edges tree according to ESSE.
"""
function simulate_edges(λ       ::Array{Float64,1},
                        μ       ::Array{Float64,1},
                        l       ::Array{Float64,1},
                        g       ::Array{Float64,1},
                        q       ::Array{Float64,1},
                        β       ::Array{Float64,1},
                        x       ::Array{Float64,1},
                        y       ::Array{Float64, N},
                        δt      ::Float64,
                        cov_mod ::String,
                        nssp_max::Int64) where N

  h = Int64((sqrt(length(q)*4 + 1) + 1)/2)
  k = div(length(l), h)

  # if multidimensional
  md = N > 1

  # check number of parameters and data
  model = id_mod(cov_mod, k, h, size(y,2), λ, μ, l, g, q, β)

  # total simulation time
  simt = x[end]

  # make approximate time function
  af! = make_af(x, y, Val(size(y,2)))

  # preallocate af! result vector 
  r = Array{Float64,1}(undef, size(y,2))

  # get function estimates at `simt`
  af!(simt, r)

  # create states
  S = create_states(k, h)

  ns = length(S)

  # areas & hidden states
  as = 1:k
  hs = 0:(h-1)

  # vector of initial state probabilities
  isp = Array{Float64,1}(undef, length(S))

  # assign initial state probabilities
  init_states_pr!(isp, l, g, q, μ, β, S, k, h, model, md, as, hs)

  # preallocate vector of individual area probabilities 
  spr = Array{Float64,1}(undef, ns)

  # sample initial state
  si = prop_sample(spr, isp, ns)

  # n = 2 starting lineages (assume no stem branch)
  n = 2

  # edges alive
  ea = [1, 2]


  # edge array
  ed = zeros(Int64, nssp_max*2, 2)
  ed[ea,:] = [1 2;
              1 3]

  # edge lengths
  el = zeros(nssp_max*2)

  # make probability vectors
  λpr, μpr, gpr, qpr, Sλpr, Sμpr, Sgpr, Sqpr = 
   event_probs(λ, μ, l, g, q, β, r, S, k, h, model, md, δt, ns, as, hs)

  # make λ, μ, g & q probability functions
  updλpr! = make_updλpr!(λ, β, λpr, Sλpr, δt, k, model, md)
  updμpr! = make_updμpr!(μ, β, μpr, Sμpr, δt, k, model, md)
  updgpr! = make_updgpr!(g, β, gpr, Sgpr, δt, k, model, md, as, S)
  updqpr! = make_updqpr!(Sqpr)

  # preallocate states probabilities for specific lengths of each event
  svλ = Array{Float64,1}[]
  svμ = Array{Float64,1}[]
  svg = Array{Float64,1}[]
  svq = Array{Float64,1}[]
  for i in Base.OneTo(ns)
    push!(svλ, zeros(length(λpr[i])))
    push!(svμ, zeros(length(μpr[i])))
    push!(svg, zeros(length(gpr[i])))
    push!(svq, zeros(length(qpr[i])))
  end

  # make state change vectors
  gtos, μtos, qtos, λtos = makecorresschg(gpr, μpr, qpr, λpr, S, as, hs, k, ns)

  # model first speciation event for daughter inheritance
  st = λtos[si][prop_sample(svλ[si], λpr[si], length(svλ[si]))]

  # random assignment to daughters
  if rand() < 0.5
    reverse!(st)
  end

  # start simulation
  while true

    # keep track of time
    simt -= δt

    # estimate `z(simt)`
    af!(simt, r)
 
    # one time step
    for i in Base.OneTo(n)

      # update edge length
      el[ea[i]] += δt

      sti = st[i]

      #=
        gain event?
      =#
      if rand() < updgpr!(sti, S[sti], r)
        # sample from the transition probabilities
        @inbounds st[i] = gtos[sti][prop_sample(svg[sti], gpr[sti], length(svg[sti]))]

        # no more events at this time
        continue
      end

      #=
        μ or loss event?
      =#
      if rand() < updμpr!(sti, S[sti], r)

        # if extinction
        if isone(length(S[sti].g))

          # update time in other extant lineages
          el[ea[(i+1):n]] .+= δt

          # node to remove
          nod = ed[ea[i],1]

          # top or bottom edge of node
          top = nod == ed[ea[i]+1, 1] 

          # remove edge (only preserving persisting species)
          ned = findfirst(isequal(0), ed)[1]

          if ned == 3
            printstyled("What would you do if an endangered animal is eating an endangered plant? Sometimes nature is too cruel... \n", 
              color=:light_red)
            printstyled("tree went extinct... rerun simulation \n",
              color=:light_red)
            return 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          end

          @views ed[ea[i]:(ned-1),:] = ed[(ea[i]+1):ned,:]

          # remove edge length
          @views el[ea[i]:(ned-1)] = el[(ea[i]+1):ned]

          # update alive lineages
          deleteat!(ea,i)
          ea[i:end] .-= 1

          # remove node and extra edge
          @views pr = findfirst(isequal(nod), ed[:,1])
          @views da = findfirst(isequal(nod), ed[:,2])

          if isnothing(da)
            da = 0
          end

          if da != 0
            ed[da,2] = ed[pr,2]
            el[da]  += el[pr]
          end

          # remove intervening edge
          @views ed[pr:(ned-2),:] = ed[(pr+1):(ned-1),:]

          # remove edge lengths of intervening node
          @views el[pr:(ned-2)] = el[(pr+1):(ned-1)]

          ## update alive lineages
          # is the remaining node terminal?
          if da == 0 || in(ed[da,2], ed[:,1])
            ea[i:end] .-= 1
          else 
            ea[findfirst(isequal(pr),ea)] = da
            sort!(ea)
            if top
              ea[(i+1):end] .-= 1
            else
              ea[i:end]     .-= 1
            end
          end

          # update living species states
          deleteat!(st,i)

          # update n species
          n = lastindex(ea)

          # break loop
          break

        # if local extinction (state change)
        else
          @inbounds st[i] = μtos[sti][prop_sample(svμ[sti], μpr[sti], length(svμ[sti]))]

          continue
        end

      end

      #=
          q event?
      =#
      if rand() < updqpr!(sti) 
        @inbounds st[i] = qtos[sti][prop_sample(svq[sti], qpr[sti], length(svq[sti]))]

        # no more events at this time
        continue
      end

      #=
          λ event?
      =#
      if rand() < updλpr!(sti, S[sti], r)

        # update time in other extant lineages
        el[ea[(i+1):n]] .+= δt

        ### add new edges
        # start node
        ed[ea[end] + 1,1] = ed[ea[end] + 2,1] = ed[ea[i],2]

        # end nodes
        ed[ea[end] + 1,2] = maximum(ed)+1
        ed[ea[end] + 2,2] = maximum(ed)+1

        # update living edges
        push!(ea, ea[end]+1, ea[end]+2)
        deleteat!(ea, i)

        # update living states according to speciation event
        nst1, nst2 = 
          λtos[sti][prop_sample(svλ[sti], λpr[sti], length(svλ[sti]))]

        # random assignment to daughters
        if rand() < 0.5
          push!(st,nst1,nst2)
        else
          push!(st,nst2,nst1)
        end

        deleteat!(st,i)

        # update number of species alive
        n = lastindex(ea)

        # no more events for any of the remaining lineages
        break
      end

    end

    simt < 0.0 && break

    if n == nssp_max 
      @warn "more than $nssp_max species"
      return 0, 0, 0, 0, n, 0, 0, 0, 0, 0
    end
  end

  # remove 0s
  ed = ed[1:(2n-2),:]
  el = el[1:(2n-2)]

  sort!(ea)

  return ed, el, st, simt, n, af!, r, S, k, h
end






"""
    id_mod(cov_mod::String, 
           k      ::Int64, 
           h      ::Int64, 
           nzt    ::Int64,
           λ      ::Array{Float64,1}, 
           μ      ::Array{Float64,1}, 
           l      ::Array{Float64,1},
           g      ::Array{Float64,1},
           q      ::Array{Float64,1},
           β      ::Array{Float64,1})

Check if number of parameters and `z(t)` functions 
is consistent with specified model.
"""
function id_mod(cov_mod::String, 
                k      ::Int64, 
                h      ::Int64, 
                nzt    ::Int64,
                λ      ::Array{Float64,1}, 
                μ      ::Array{Float64,1}, 
                l      ::Array{Float64,1},
                g      ::Array{Float64,1},
                q      ::Array{Float64,1},
                β      ::Array{Float64,1})

  all_ok = true

  # check consistent length of parameter vectors proposed
   if (lastindex(λ) != (k+1)*h   || 
       lastindex(μ) != k*h       ||
       lastindex(l) != k*h       ||
       lastindex(g) != k*(k-1)*h ||
       lastindex(q) != h*(h-1))
     printstyled("$k areas with $h hidden states should have the following parameter lengths:
       λ = $((k+1)*h) parameters
       μ = $(k*h) parameters
       l = $(k*h) parameters
       g = $(k*(k-1)*h) parameter matrix
       q = $(h*(h-1)) parameters")
    error("Parameter vector lengths not consistent with the number of states")
  end

  # if speciation, extinction or transition model
  if occursin(r"^[s|S][A-za-z]*", cov_mod)

    if lastindex(β) == (nzt == 1 ? k*h : nzt*h)
      printstyled("Number of parameters are consistent with specified model \n", 
        color=:green)
    else
      all_ok = false
      printstyled("speciation covariate model with $k areas should have a β vector length of $(nzt == 1 ? k*h : nzt*h) \n")
    end

    modelstring = "speciation" 
    model = 1

  elseif occursin(r"^[e|E][A-za-z]*", cov_mod)

    if lastindex(β) == (nzt == 1 ? k*h : nzt*h)
      printstyled("Number of parameters are consistent with specified model \n", 
        color=:green)    
    else
      all_ok = false
      printstyled("extinction covariate model with $k areas should have a β vector length of $(nzt == 1 ? k*h : nzt*h) \n")
    end

    modelstring = "extinction" 
    model = 2

  elseif occursin(r"^[t|T|r|R|q|Q][A-za-z]*", cov_mod)

    if lastindex(β) == (nzt == 1 ? k*(k-1)*h : h*nzt)
      printstyled("Number of parameters are consistent with specified model \n", 
        color=:green)    
    else
      all_ok = false
      printstyled("transition covariate model with $k areas should have a β vector length of $(nzt == 1 ? k*(k-1)*h : h*nzt) \n")
    end
    modelstring = "transition" 
    model = 3
  else
    model = 0
    warning("cov_mod does not match any ESSE model, running MuSSE \n")
  end

  if all_ok 
    printstyled("Simulating $modelstring covariate SSE model with $k states, $h hidden states and $nzt covariates \n", 
      color=:green)
  else
    error("Parameter and z(t) function number not consistent with specified model")
  end

  return model
end






"""
    init_states_pr!(isp  ::Array{Float64,1},
                    l    ::Array{Float64,1},
                    g    ::Array{Float64,1},
                    q    ::Array{Float64,1},
                    μ    ::Array{Float64,1},
                    β    ::Array{Float64,1},
                    S    ::Array{Sgh,1},
                    k    ::Int64,
                    h    ::Int64,
                    model::Int64,
                    md   ::Bool)

 Estimate starting transition probabilities for initial states
"""
function init_states_pr!(isp  ::Array{Float64,1},
                         l    ::Array{Float64,1},
                         g    ::Array{Float64,1},
                         q    ::Array{Float64,1},
                         μ    ::Array{Float64,1},
                         β    ::Array{Float64,1},
                         S    ::Array{Sgh,1},
                         k    ::Int64,
                         h    ::Int64,
                         model::Int64,
                         md   ::Bool,
                         as   ::UnitRange{Int64},
                         hs   ::UnitRange{Int64})

  if model == 1

    for si in Base.OneTo(length(S))

      s = S[si]

      # loss rates
      lr = 0.0
      for i = setdiff(as, s.g)
        lr += l[s.h*k+i]
      end

      # gain rates
      gr = 0.0
      if length(s.g) > 1
        for ta = s.g, fa = setdiff(s.g, ta)
          gr += g[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)]
        end
      end

      # hidden states
      hr = 0.0
      for fa = setdiff(hs, s.h)
          hr += q[fa*(h-1) + (s.h > fa ? s.h : s.h+1)]
      end

      # add all and hidden rates
      isp[si] = lr + gr + hr
    end

  # if extinction model
  elseif model == 2 && isequal(l, μ)

    for si in Base.OneTo(length(S))

      s = S[si]

      # loss rates
      lr = 0.0
      for i = setdiff(as, s.g)
        lr += expf(l[s.h*k+i], β[s.h*k+i], md ? r[i] : r[1])
      end

      # gain rates
      gr = 0.0
      if length(s.g) > 1
        for ta = s.g, fa = setdiff(s.g, ta)
          gr += g[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)]
        end
      end

      # hidden states
      hr = 0.0
      for fa = setdiff(hs, s.h)
          hr += q[fa*(h-1) + (s.h > fa ? s.h : s.h+1)]
      end

      # add all and hidden rates
      isp[si] = lr + gr + hr
    end

  # if transition model
  elseif model == 3

    for si in Base.OneTo(length(S))

      s = S[si]

      # loss rates
      lr = 0.0
      for i = setdiff(as, s.g)
        lr += l[s.h*k+i]
      end

      # gain rates
      gr = 0.0
      if length(s.g) > 1
        for ta = s.g, fa = setdiff(s.g, ta)
          gr += expf(q[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)], 
                     β[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)], 
                     md ? r[(fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)] : r[1])
        end
      end

      # hidden states
      hr = 0.0
      for fa = setdiff(hs, s.h)
          hr += q[fa*(h-1) + (s.h > fa ? s.h : s.h+1)]
      end

      # add all and hidden rates
      isp[si] = lr + gr + hr
    end

  end

  return nothing
end





"""
    event_probs(λ    ::Array{Float64,1},
                μ    ::Array{Float64,1},
                l    ::Array{Float64,1},
                g    ::Array{Float64,1},
                q    ::Array{Float64,1},
                β    ::Array{Float64,1},
                S    ::Array{Sgh,1},
                k    ::Int64,
                h    ::Int64,
                model::Int64,
                md   ::Bool)

Create event probabilities for each state given the input parameters.
"""
function event_probs(λ    ::Array{Float64,1},
                     μ    ::Array{Float64,1},
                     l    ::Array{Float64,1},
                     g    ::Array{Float64,1},
                     q    ::Array{Float64,1},
                     β    ::Array{Float64,1},
                     r    ::Array{Float64,1},
                     S    ::Array{Sgh,1},
                     k    ::Int64,
                     h    ::Int64,
                     model::Int64,
                     md   ::Bool, 
                     δt   ::Float64,
                     ns   ::Int64,
                     as   ::UnitRange{Int64},
                     hs   ::UnitRange{Int64})

  @inbounds begin
    ### make fixed vectors of approximate probabilities for each state
    ## λ
    λpr = Array{Float64,1}[]
    for s in S
      push!(λpr, zeros(length(s.g) + div(length(vicsubsets(s.g)),2)))
    end
    # fill it up
    for si in Base.OneTo(ns)
      s = S[si]
      na = 0
      # within-area speciation
      if model == 1
        for a in s.g
          na += 1
          λpr[si][na] = expf(λ[(k+1)*s.h + a], β[k*s.h + a], md ? r[a] : r[1])*δt
        end
      else
        for a in s.g
          na += 1
          λpr[si][na] = λ[(k+1)*s.h + a]*δt
        end
      end
      # between-area speciation
      if na > 1
        λpr[si][na+1:end] .= λ[k+1 + (k+1)*s.h]*δt
      end
    end

    ## μ and loss
    μpr = Array{Float64,1}[]
    for s in S
      push!(μpr, zeros(length(s.g)))
    end
    # fill it up
    for si in Base.OneTo(ns)
      s = S[si]
      if isone(length(s.g))
        if model == 2
          for a in s.g
            μpr[si][1] = expf(μ[k*s.h + a], β[k*s.h + a], md ? r[a] : r[1])*δt
          end
        else
          for a in s.g
            μpr[si][1] = μ[k*s.h + a]*δt
          end
        end
      else
        na = 0
        for a in s.g
          na += 1
          μpr[si][na] = l[k*s.h + a]*δt
        end
      end
    end

    ## gain
    gpr = Array{Float64,1}[]
    for s in S
      push!(gpr, zeros(length(setdiff(as,s.g))))
    end
    # fill it up
    for si in Base.OneTo(ns)
      s = S[si]
      if model == 3
        for (i,ta) = enumerate(setdiff(as,s.g)), fa = s.g
          gpr[si][i] += 
            expf(q[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)], 
                 β[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)], 
                 md ? r[(fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)] : r[1])*δt
        end
      else
        for (i,ta) = enumerate(setdiff(as,s.g)), fa = s.g
          gpr[si][i] += 
            g[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)]*δt
        end
      end
    end

    ## hidden states
    qpr = Array{Float64,1}[]
    for s in S
      push!(qpr, zeros(h-1))
    end
    # fill it up
    for si in Base.OneTo(ns)
      s = S[si]
       for (i, th) = enumerate(setdiff(hs, s.h))
        qpr[si][i] = q[s.h*(h-1) + (s.h > th ? s.h : s.h+1)]*δt
      end
    end

    # make λ, μ and g probability sums
    Sλpr = zeros(ns)
    Sμpr = zeros(ns)
    Sgpr = zeros(ns)
    Sqpr = zeros(ns)
    for i in Base.OneTo(ns)
      Sλpr[i] = sum(λpr[i])
      Sμpr[i] = sum(μpr[i])
      Sgpr[i] = sum(gpr[i])
      Sqpr[i] = sum(qpr[i])
    end
  end

  return λpr, μpr, gpr, qpr, Sλpr, Sμpr, Sgpr, Sqpr
end





"""
    makecorresschg(gpr::Array{Array{Float64,1},1},
                   μpr::Array{Array{Float64,1},1},
                   qpr::Array{Array{Float64,1},1},
                   λpr::Array{Array{Float64,1},1},
                   S  ::Array{Sgh, 1},
                   as::UnitRange{Int64},
                   hs::UnitRange{Int64},
                   ns::Int64)

Make vector of vectors of corresponding states changes 
for **gains** and **looses** and **hidden states**
"""
function makecorresschg(gpr::Array{Array{Float64,1},1},
                        μpr::Array{Array{Float64,1},1},
                        qpr::Array{Array{Float64,1},1},
                        λpr::Array{Array{Float64,1},1},
                        S  ::Array{Sgh, 1},
                        as::UnitRange{Int64},
                        hs::UnitRange{Int64},
                        k ::Int64,
                        ns::Int64)
  # for *gains*
  gtos = Array{Int64,1}[]
  for i in Base.OneTo(ns)
    push!(gtos, zeros(Int64,length(gpr[i])))
  end
  for si in Base.OneTo(ns)
    s = S[si]
    for (i,ta) = enumerate(setdiff(as,s.g))
      gtos[si][i] = findfirst(r -> isSghequal(r,Sgh(union(s.g, ta),s.h)), S)
    end
  end

  # for *losses*
  μtos = Array{Int64,1}[]
  for i in Base.OneTo(ns)
    push!(μtos, zeros(Int64,length(μpr[i])))
  end
  for si in Base.OneTo(ns)
    s = S[si]
    isone(length(s.g)) && continue
    na = 0
    for a in s.g
      na += 1
      μtos[si][na] = findfirst(r -> isSghequal(r,Sgh(setdiff(s.g, a),s.h)), S)
    end
  end

  # for *hidden states*
  qtos = Array{Int64,1}[]
  for i in Base.OneTo(ns)
    push!(qtos, zeros(Int64,length(qpr[i])))
  end
  for si in Base.OneTo(ns)
    s = S[si]
     for (i, th) = enumerate(setdiff(hs, s.h))
      qtos[si][i] = th*(2^k-1) + si - s.h*(2^k-1)
    end
  end

  # for *hidden states*
  qtos = Array{Int64,1}[]
  for i in Base.OneTo(ns)
    push!(qtos, zeros(Int64,length(qpr[i])))
  end
  for si in Base.OneTo(ns)
    s = S[si]
     for (i, th) = enumerate(setdiff(hs, s.h))
      qtos[si][i] = th*(2^k-1) + si - s.h*(2^k-1)
    end
  end

  # for *speciation*
  λtos = Array{Array{Int64,1},1}[]
  for i in Base.OneTo(ns)
    push!(λtos, fill([0,0],length(λpr[i])))
  end
  for si in Base.OneTo(ns)
    s = S[si]
    na = 0
    if isone(length(s.g))
      for a in s.g
        na += 1
        λtos[si][na] = [si,si]
      end
    else
      # within-area speciation
      for a in s.g
        na += 1
        λtos[si][na] = [a + (2^k-1)*s.h,si]
      end
      # between-area speciation
      vs = vicsubsets(s.g)[1:div(end,2)]
      for v in vs
        na += 1
        λtos[si][na] = 
          [findfirst(r -> isSghequal(r,Sgh(v[1],s.h)), S),
           findfirst(r -> isSghequal(r,Sgh(v[2],s.h)), S)]
      end
    end
  end

  return gtos, μtos, qtos, λtos
end





"""
    make_updλpr!(λ    ::Array{Float64,1},
                 β    ::Array{Float64,1},
                 λpr  ::Array{Array{Float64,1},1},
                 Sλpr ::Array{Float64,1},
                 δt   ::Float64,
                 k    ::Int64,
                 model::Int64,
                 md   ::Bool)

Make λ instantaneous probability function for each state.
"""
function make_updλpr!(λ    ::Array{Float64,1},
                      β    ::Array{Float64,1},
                      λpr  ::Array{Array{Float64,1},1},
                      Sλpr ::Array{Float64,1},
                      δt   ::Float64,
                      k    ::Int64,
                      model::Int64,
                      md   ::Bool)


  # if dependent on `z(t)` and multidimensional
  function f1(si ::Int64,
              s  ::Sgh,
              r::Array{Float64,1})

    @inbounds begin
      na = 0
      # within-area speciation
      for a in s.g
        na += 1
        λpr[si][na] = expf(λ[(k+1)*s.h + a], β[k*s.h + a], md ? r[a] : r[1])*δt
      end
      # between-area speciation
      if na > 1
        λpr[si][k+1:end] .= λ[k+1 + (k+1)*s.h]*δt
      end

      return Sλpr[si] = sum(λpr[si]) 
    end
  end

  # if dependent on `z(t)` and unidimensional
  function f2(si ::Int64,
              s  ::Sgh,
              r::Array{Float64,1})
    return Sλpr[si]
  end

  if model == 1
    return f1
  else
    return f2
  end
end





"""
    make_updμpr!(λ    ::Array{Float64,1},
                 β    ::Array{Float64,1},
                 μpr  ::Array{Array{Float64,1},1},
                 Sμpr ::Array{Float64,1},
                 δt   ::Float64,
                 k    ::Int64,
                 model::Int64,
                 md   ::Bool)

Make `μ` instantaneous probability function
"""
function make_updμpr!(μ    ::Array{Float64,1},
                      β    ::Array{Float64,1},
                      μpr  ::Array{Array{Float64,1},1},
                      Sμpr ::Array{Float64,1},
                      δt   ::Float64,
                      k    ::Int64,
                      model::Int64,
                      md   ::Bool)
  function f1(si ::Int64,
              s  ::Sgh,
              r::Array{Float64,1})

    @inbounds begin
      if isone(length(s.g))
        for a in s.g
          μpr[si][1] = expf(μ[k*s.h + a], β[k*s.h + a], md ? r[a] : r[1])*δt
        end
      else
        na = 0
        for a in s.g
          na += 1
          μpr[si][na] = l[k*s.h + a]*δt
        end
      end

      return Sμpr[si] = sum(μpr[si]) 
    end
  end

  # if dependent on `z(t)` and unidimensional
  function f2(si ::Int64,
              s  ::Sgh,
              r::Array{Float64,1})
    return Sμpr[si]
  end

  if model == 2
    return f1
  else
    return f2
  end
end





"""
    make_updgpr!(g    ::Array{Float64,1},
                 β    ::Array{Float64,1},
                 gpr  ::Array{Array{Float64,1},1},
                 Sgpr ::Array{Float64,1},
                 δt   ::Float64,
                 k    ::Int64,
                 model::Int64,
                 md   ::Bool,
                 as   ::UnitRange{Int64},
                 S    ::Array{Sgh,1})

Make gain instantaneous probability function
"""
function make_updgpr!(g    ::Array{Float64,1},
                      β    ::Array{Float64,1},
                      gpr  ::Array{Array{Float64,1},1},
                      Sgpr ::Array{Float64,1},
                      δt   ::Float64,
                      k    ::Int64,
                      model::Int64,
                      md   ::Bool,
                      as   ::UnitRange{Int64},
                      S    ::Array{Sgh,1})

  # do setdiff before
  sdf = Array{Int64,1}[]
  for s = S
    push!(sdf, setdiff(as,s.g))
  end

  function f1(si ::Int64,
              s  ::Sgh,
              r::Array{Float64,1})
    @inbounds begin
      gpr[si][i] = 0.0
      for (i,ta) = enumerate(sdf[si]), fa = s.g
        gpr[si][i] += 
          expf(q[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)], 
               β[s.h*k*(k-1) + (fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)], 
               md ? r[(fa-1)*(k-1) + (ta > fa ? ta - 1 : ta)] : r[1])*δt
      end

      return Sgpr[si] = sum(gpr[si]) 
    end
  end

  function f2(si ::Int64,
              s  ::Sgh,
              r::Array{Float64,1})
    return Sgpr[si]
  end

  if model == 3
    return f1
  else
    return f2
  end
end





"""
    make_updqpr!(Sqpr ::Array{Float64,1})

Make hidden states instantaneous probability function
"""
function make_updqpr!(Sqpr ::Array{Float64,1})

  function f(si ::Int64)
    return Sqpr[si]
  end

  return f
end





"""
    postorderedges(ed  ::Array{Int64,2},
                   el  ::Array{Float64,1},
                   nspp::Int64)

Organize edges, edge lengths in postorder traversal fashion.
"""
function postorderedges(ed  ::Array{Int64,2},
                        el  ::Array{Float64,1},
                        nspp::Int64)

  # post-order transversal using 2 stacks
  stack1 = [ed[1]]
  stack2 = Int64[]

  while lastindex(stack1) > 0
    nod = pop!(stack1)
    push!(stack2, nod)

    if nod <= nspp
      continue
    else
      wn = findfirst(isequal(nod), ed[:,1])
      push!(stack1, ed[wn,2],ed[(wn+1),2])
    end
  end

  # rearrange edges accordingly
  indx = deleteat!(indexin(reverse(stack2), ed[:,2]),size(ed,1)+1)

  ed = ed[indx,:]
  el = el[indx]

  # advance nodes with only daughter tips
  tnd = Int64[]
  ndp = Int64[]
  for nd in unique(ed[:,1])
    fed = findall(ed[:,1 ] .== nd)
    if length(filter(x -> x <= nspp, ed[fed,2])) == 2
      push!(tnd, nd)
      push!(ndp, fed[1], fed[2])
    end
  end


  append!(ndp,setdiff(1:(2nspp-2), ndp))

  ed[ndp,:]

  return ed[ndp,:], el[ndp]
end





"""
    numberedges(ed::Array{Int64,2}, nspp::Int64)

Change numbering scheme so that tips are `1:numerofspecies` followed
by node numbering. MRCA is `numerofspecies+1`.
"""
function numberedges(ed::Array{Int64,2}, nspp::Int64)
  nel = 1
  nnd = nspp + 1

  edc         = zeros(Int64,size(ed))
  edc[1:2,1] .= nnd
  nnd        += 1

  for i in axes(ed,1)
    #if internal node
    if in(ed[i,2],ed[:,1])
      e1                = findfirst(isequal(ed[i,2]), ed[:,1])
      edc[e1:(e1+1),1] .= nnd
      edc[i,2]          = nnd
      nnd              += 1 
    else
      edc[i,2] = nel
      nel     += 1
    end
  end

  return edc
end





"""
    expf()

Exponential regression function for rates with base rate `α`, 
coefficient `β` and covariate `x`.
"""
expf(α::Float64, β::Float64, x::Float64) = α * exp(β * x)





"""
    prop_sample(s::Array{Float64,1}, prv::Array{Float64,1}, k::Int64)

Sample one state with the respective (relative) probabilities 
given `prv`.
"""
function prop_sample(s::Array{Float64,1}, prv::Array{Float64,1}, ns::Int64)

  cumsum!(s, prv)
  for i in Base.OneTo(ns)
    s[i] /= s[ns]  
  end

  return searchsortedfirst(s, rand())
end


