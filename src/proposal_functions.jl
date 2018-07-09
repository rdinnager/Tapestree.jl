#=

Proposal functions for joint
Biogeographic competition model

Ignacio Quintero Mächler

t(-_-t)

May 16 2017

=#





#=
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
`Y` IID proposal functions
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
=#





"""
    upnode!(λ1     ::Float64,
            λ0     ::Float64,
            triad  ::Array{Int64,1},
            Y      ::Array{Int64,3},
            stemevs::Array{Array{Float64,1},1},
            bridx_a::Array{Array{UnitRange{Int64},1},1},
            brδt   ::Vector{Vector{Float64}},
            brl    ::Vector{Float64},
            brs    ::Array{Int64,3},
            narea  ::Int64,
            nedge  ::Int64)

Update node and incident branches using discrete 
Data Augmentation for all areas using a non-competitive 
mutual-independence Markov model.
"""
function upnode!(λ1     ::Float64,
                 λ0     ::Float64,
                 triad  ::Array{Int64,1},
                 Y      ::Array{Int64,3},
                 stemevs::Array{Array{Float64,1},1},
                 bridx_a::Array{Array{UnitRange{Int64},1},1},
                 brδt   ::Vector{Vector{Float64}},
                 brl    ::Vector{Float64},
                 brs    ::Array{Int64,3},
                 narea  ::Int64,
                 nedge  ::Int64)

  @inbounds begin
   
    # define branch triad
    pr, d1, d2 = triad

    # sample
    samplenode!(λ1, λ0, pr, d1, d2, brs, brl, narea)

    # save extinct
    while sum(brs[pr,2,:]) < 1
      samplenode!(λ1, λ0, pr, d1, d2, brs, brl, narea)
    end

    # set new node in Y
    for k in Base.OneTo(narea)
      Y[bridx_a[k][pr][end]] = 
      Y[bridx_a[k][d1][1]]   = 
      Y[bridx_a[k][d2][1]]   = brs[pr,2,k]
    end

    # sample a consistent history
    createhists!(λ1, λ0, Y, pr, d1, d2, brs, brδt, bridx_a, narea, nedge,
                 stemevs, brl[nedge])

    ntries::Int64 = 1
    while ifextY(Y, stemevs, triad, brs[nedge,1,:], brl[nedge],
                 narea, bridx_a, nedge)
      createhists!(λ1, λ0, Y, pr, d1, d2, brs, brδt, bridx_a, narea, nedge,
                   stemevs, brl[nedge])
      ntries += 1
      if ntries == 1_000
        return false::Bool
      end
    end
  end

  return true::Bool
end





"""
    samplenode!(λ::Array{Float64,1}, pr::Int64, d1::Int64, d2::Int64, brs::Array{Int64,3}, brl::Array{Float64,1}, narea::Int64)

Sample one internal node according to 
mutual-independence model transition probabilities.
"""
function samplenode!(λ1   ::Float64, 
                     λ0   ::Float64,
                     pr   ::Int64,
                     d1   ::Int64,
                     d2   ::Int64,
                     brs  ::Array{Int64,3},
                     brl  ::Array{Float64,1},
                     narea::Int64)
  @inbounds begin

    for k = Base.OneTo(narea)

      # transition probabilities for the trio
      ppr_1, ppr_2 = 
        Ptrfast_start(λ1, λ0, brl[pr], brs[pr,1,k])
      pd1_1, pd1_2 = 
        Ptrfast_end(  λ1, λ0, brl[d1], brs[d1,2,k])
      pd2_1, pd2_2 = 
        Ptrfast_end(  λ1, λ0, brl[d2], brs[d2,2,k])

      # normalize probability
      tp = normlize(*(ppr_1, pd1_1, pd2_1),
                    *(ppr_2, pd1_2, pd2_2))::Float64

      # sample the node's character
      brs[pr,2,k] = brs[d1,1,k] = brs[d2,1,k] = coinsamp(tp)::Int64
    end
  end

  return nothing
end





"""
    createhists!(λ::Array{Float64,1}, Y::Array{Int64,3}, pr::Int64, d1::Int64, d2::Int64, brs::Array{Int64,3}, brδt::Array{Array{Float64,1},1}, bridx_a::Array{Array{Array{Int64,1},1},1}, narea::Int64)

Create bit histories for all areas for the branch trio.
"""
function createhists!(λ1     ::Float64,
                      λ0     ::Float64,
                      Y      ::Array{Int64,3},
                      pr     ::Int64,
                      d1     ::Int64,
                      d2     ::Int64,
                      brs    ::Array{Int64,3},
                      brδt   ::Array{Array{Float64,1},1},
                      bridx_a::Array{Array{UnitRange{Int64},1},1},
                      narea  ::Int64,
                      nedge  ::Int64,
                      stemevs::Array{Array{Float64,1},1},
                      stbrl  ::Float64)

  @inbounds begin

    # if stem branch do continuous DA
    if pr == nedge
      mult_rejsam!(stemevs, brs[nedge,1,:], brs[nedge,2,:], λ1, λ0, 
                   stbrl, narea)
      for j = Base.OneTo(narea), idx = (d1,d2)
        bit_rejsam!(Y, bridx_a[j][idx], brs[idx,2,j], 
                    λ1, λ0, brδt[idx])
      end
    else
      for j = Base.OneTo(narea), idx = (pr,d1,d2)
        bit_rejsam!(Y, bridx_a[j][idx], brs[idx,2,j], 
                    λ1, λ0, brδt[idx])
      end
    end
  end

  return nothing
end





"""
  mult_rejsam!(evs   ::Array{Array{Float64,1},1},
               ssii  ::Array{Int64,1}, 
               ssff  ::Array{Int64,1},
               λ1    ::Float64,
               λ0    ::Float64,
               t     ::Float64,
               narea ::Int64)

  Multi-area branch rejection independent model sampling.
"""
function mult_rejsam!(evs  ::Array{Array{Float64,1},1},
                      ssii ::Array{Int64,1}, 
                      ssff ::Array{Int64,1},
                      λ1   ::Float64,
                      λ0   ::Float64,
                      t    ::Float64,
                      narea::Int64)

  for i = Base.OneTo(narea)
    rejsam!(evs[i], ssii[i], ssff[i], λ1, λ0, t)
  end

  return nothing
end





"""
    ifextY(Y      ::Array{Int64,3},
           triad  ::Array{Int64,1},
           narea  ::Int64,
           bridx_a::Array{Array{UnitRange{Int64},1},1})

Return `true` if at some point the species
goes extinct and/or more than one change is 
observed after some **δt**, otherwise returns `false`.
"""
function ifextY(Y      ::Array{Int64,3},
                stemevs::Array{Array{Float64,1},1},
                triad  ::Array{Int64,1},
                sstem  ::Array{Int64,1},
                stbrl  ::Float64,
                narea  ::Int64,
                bridx_a::Array{Array{UnitRange{Int64},1},1},
                nedge  ::Int64)

  @inbounds begin

    if triad[1] == nedge
      ifext_cont(stemevs, sstem, narea, stbrl) && return true::Bool
      for k in triad[2:3]
        ifext_disc(Y, k, narea, bridx_a) && return true::Bool
      end
    else 
      for k in triad
        ifext_disc(Y, k, narea, bridx_a) && return true::Bool
      end
    end
  end

  return false::Bool
end





"""
    ifext(t_hist::Array{Array{Float64,1},1},
          ssii  ::Array{Int64,1}, 
          narea ::Int64,
          t     ::Float64)

Return true if lineage goes extinct.
"""
function ifext_cont(t_hist::Array{Array{Float64,1},1},
                    ssii  ::Array{Int64,1}, 
                    narea ::Int64,
                    t     ::Float64)

  @inbounds begin

    # initial occupancy time
    ioc::Int64    = findfirst(ssii)
    ioct::Float64 = t_hist[ioc][1]

    ntries = 0
    while ioct < t

      if ioc == narea
        ioc = 1
      else 
        ioc += 1
      end

      tc::Float64 = 0.0
      cs::Int64   = ssii[ioc]
      for ts in t_hist[ioc]::Array{Float64,1}
        tc += ts
        if ioct < tc 
          if cs == 1
            ioct            = tc 
            ntries::Int64   = 0
            break
          else
            ntries += 1
            if ntries > narea
              return true::Bool
            end
            break
          end
        end
        cs = 1 - cs
      end

    end
  end

  return false::Bool
end






"""
    ifext_disc(Y      ::Array{Int64,3},
               br     ::Int64,
               narea  ::Int64,
               bridx_a::Array{Array{UnitRange{Int64},1},1})

Return `true` if at some point the species
goes extinct and/or more than one change is 
observed after some **δt**, otherwise returns `false`. 
This specific method is for single branch updates.
"""
function ifext_disc(Y      ::Array{Int64,3},
                    br     ::Int64,
                    narea  ::Int64,
                    bridx_a::Array{Array{UnitRange{Int64},1},1})

  @inbounds begin

    for i = Base.OneTo(length(bridx_a[1][br]::UnitRange{Int64})-1)
      s_e::Int64 = 0            # count current areas
      s_c::Int64 = 0            # count area changes

      for j = Base.OneTo(narea)
        s_e += Y[bridx_a[j][br][i]]::Int64
        if Y[bridx_a[j][br][i]]::Int64 != Y[bridx_a[j][br][i+1]]::Int64
          s_c += 1
        end
      end

      if s_e == 0 || s_c > 1
        return true::Bool
      end
    end

  end

  return false::Bool
end





#=
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
Y stem node proposal function (continuous DA)
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
=#

"""
    upstemnode!(λ1   ::Float64, 
                λ0   ::Float64,
                nedge::Int64,
                stemevs::Array{Array{Float64,1},1},
                brs  ::Array{Int64,3},
                brl  ::Array{Float64,1},
                narea::Int64)


"""
function upstemnode!(λ1     ::Float64, 
                     λ0     ::Float64,
                     nedge  ::Int64,
                     stemevs::Array{Array{Float64,1},1},
                     brs    ::Array{Int64,3},
                     stbrl  ::Float64,
                     narea  ::Int64)

  @inbounds begin

    # sample
    samplestem!(λ1, λ0, nedge, brs, stbrl, narea)

    # save extinct
    while sum(brs[nedge,1,:]) < 1
      samplestem!(λ1, λ0, nedge, brs, stbrl, narea)
    end

    # sample a congruent history
    mult_rejsam!(stemevs, brs[nedge,1,:], brs[nedge,2,:], λ1, λ0, 
                 stbrl, narea)

    ntries = 1
    # check if extinct
    while ifext_cont(stemevs, brs[nedge,1,:], narea, stbrl)
      mult_rejsam!(stemevs, brs[nedge,1,:], brs[nedge,2,:], λ1, λ0, 
                   stbrl, narea)
      ntries += 1
      if ntries == 1_000
        return false::Bool
      end
    end
  end

  return true::Bool
end





"""
    samplestem!(λ1   ::Float64, 
                λ0   ::Float64,
                nedge::Int64,
                brs  ::Array{Int64,3},
                brl  ::Array{Float64,1},
                narea::Int64)


"""
function samplestem!(λ1   ::Float64, 
                     λ0   ::Float64,
                     nedge::Int64,
                     brs  ::Array{Int64,3},
                     stbrl::Float64,
                     narea::Int64)

 @inbounds begin

    for j = Base.OneTo(narea)

      # estimate transition probabilities
      p1, p2 = Ptrfast_end(λ1, λ0, stbrl, brs[nedge,2,j])

      # sample the node's character
      brs[nedge,1,j] = coinsamp(normlize(p1,p2))::Int64
    end
  end

  return nothing
end





#=
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
Y branch proposal functions
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
=#





"""
upbranchY!(λ1     ::Float64,
           λ0     ::Float64,
           ω1     ::Float64,
           ω0     ::Float64,
           avg_Δx ::Array{Float64,2},
           br     ::Int64,
           Y      ::Array{Int64,3},
           stemevc::Array{Array{Float64,1},1},
           wareas ::Array{Int64,1},
           bridx_a::Array{Array{UnitRange{Int64},1},1},
           brδt   ::Vector{Vector{Float64}},
           brl    ::Vector{Float64},
           brs    ::Array{Int64,3},
           narea  ::Int64,
           nedge  ::Int64)

Update one branch using discrete Data Augmentation 
for all areas with independent 
proposals taking into account `Δx` and `ω1` & `ω0`.
"""
function upbranchY!(λ1     ::Float64,
                    λ0     ::Float64,
                    br     ::Int64,
                    Y      ::Array{Int64,3},
                    stemevs::Array{Array{Float64,1},1},
                    bridx_a::Array{Array{UnitRange{Int64},1},1},
                    brδt   ::Vector{Vector{Float64}},
                    stbrl  ::Float64,
                    brs    ::Array{Int64,3},
                    narea  ::Int64,
                    nedge  ::Int64)

  ntries::Int64 = 1

  # if stem branch
  if br == nedge
    mult_rejsam!(stemevs, brs[nedge,1,:], brs[nedge,2,:], λ1, λ0, 
                 stbrl, narea)

    # check if extinct
    while ifext_cont(stemevs, brs[nedge,1,:], narea, stbrl)
      mult_rejsam!(stemevs, brs[nedge,1,:], brs[nedge,2,:], λ1, λ0, 
                 stbrl, narea)
      ntries += 1
      if ntries == 1_000
        return false::Bool
      end
    end

  else 
    # sample a consistent history
    createhists!(λ1, λ0, Y, br, brs, brδt, bridx_a, narea)

    # check if extinct
    while ifext_disc(Y, br, narea, bridx_a)
      createhists!(λ1, λ0, Y, br, brs, brδt, bridx_a, narea)
      ntries += 1
      if ntries == 1_000
        return false::Bool
      end
    end
  end

  return true::Bool
end





"""
    createhists!(λ1     ::Float64,
                 λ0     ::Float64,
                 ω1     ::Float64,  
                 ω0     ::Float64, 
                 avg_Δx ::Array{Float64,2},
                 Y      ::Array{Int64,3},
                 br     ::Int64,
                 brs    ::Array{Int64,3},
                 brδt   ::Array{Array{Float64,1},1},
                 bridx_a::Array{Array{UnitRange{Int64},1},1},
                 narea  ::Int64)

Create bit histories for all areas for one single branch 
taking into account `Δx` and `ω1` & `ω0` for all areas.
"""
function createhists!(λ1     ::Float64,
                      λ0     ::Float64,
                      Y      ::Array{Int64,3},
                      br     ::Int64,
                      brs    ::Array{Int64,3},
                      brδt   ::Array{Array{Float64,1},1},
                      bridx_a::Array{Array{UnitRange{Int64},1},1},
                      narea  ::Int64)
  @inbounds begin
    for j = Base.OneTo(narea)
      bit_rejsam!(Y, bridx_a[j][br], brs[br,2,j], λ1, λ0, brδt[br])
    end
  end

  return nothing
end




#=
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
X proposal functions
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
=#




"""
    uptrioX!(trio ::Array{Int64,1}, 
             X    ::Array{Float64,2}, 
             bridx::Array{UnitRange{Int64},1},
             brδt ::Array{Array{Float64,1},1}, 
             σ²c  ::Float64)

Update the node and adjoining branhces of `trio` using Brownian bridges.
"""
function uptrioX!(pr   ::Int64, 
                  d1   ::Int64,
                  d2   ::Int64, 
                  X    ::Array{Float64,2}, 
                  bridx::Array{UnitRange{Int64},1},
                  brδt ::Array{Array{Float64,1},1},
                  s2   ::Float64)
  @inbounds begin

    # update node
    X[bridx[pr][end]] = 
    X[bridx[d1][1]]   = 
    X[bridx[d2][1]]   = addupt(X[bridx[trio[3]]][1], rand())

    bbX!(X, bridx[pr], brδt[pr], s2)
    bbX!(X, bridx[d1], brδt[d1], s2)
    bbX!(X, bridx[d2], brδt[d2], s2)

  end

  return nothing
end






"""
    upbranchX!(j    ::Int64, 
               X    ::Array{Float64,2}, 
               bridx::Array{UnitRange{Int64},1},
               brδt ::Array{Array{Float64,1},1}, 
               σ²c  ::Float64)

Update a branch j in X using a Brownian bridge.
"""
function upbranchX!(j    ::Int64, 
                    X    ::Array{Float64,2}, 
                    bridx::Array{UnitRange{Int64},1},
                    brδt ::Array{Array{Float64,1},1},
                    s2   ::Float64)

  @inbounds bbX!(X, bridx[j], brδt[j], s2)

  return nothing
end





"""
    bbX!(x::Array{Float64,1}, t::::Array{Float64,1}, σ::Float64)

Brownian bridge simulation function for updating a branch in X in place.
"""
function bbX!(X  ::Array{Float64,2}, 
              idx::UnitRange,
              t  ::Array{Float64,1},
              s2 ::Float64)

  @inbounds begin

    xf::Float64 = X[idx[end]]

    for i = Base.OneTo(endof(t)-1)
      X[idx[i+1]] = (X[idx[i]] + randn()*sqrt((t[i+1] - t[i])*s2))::Float64
    end

    for i = Base.OneTo(endof(t))
      X[idx[i]] = (X[idx[i]] - t[i]/t[end] * (X[idx[end]] - xf))::Float64
    end
  end

  return nothing
end




