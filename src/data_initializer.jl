#=
Data initializer for Competition model

Ignacio Quintero

t(-_-t)

June 14 2017
=#

#=
*******
Requires R and R ape package installed
*******
=#

using RCall
using Optim



function read_data(tree_file::String,
                   data_file::String;
                   delim    ::Char = '\t',
                   eol      ::Char = '\r')

  tree, bts = read_tree(tree_file)

  tip_labels = Dict(i => val for (val,i) = enumerate(tree.tlab))

  data = readdlm(data_file, '\t', '\r')

  data_tlab   = convert(Array{String,1},data[:,1])
  data_values = convert(Array{Float64,1},data[:,2])
  data_areas  = convert(Array{Int64,2},data[:,3:end])

  # create dictionaries
  tip_areas = Dict(tip_labels[val] => data_areas[i,:] 
                   for (i,val) = enumerate(data_tlab))

  tip_values = Dict(tip_labels[val] => data_values[i] 
                    for (i,val) = enumerate(data_tlab))

  return tip_values, tip_areas, tree, bts
end




# a kind of R tree type
immutable rtree
  ed  ::Array{Int64,2}
  el  ::Array{Float64,1}
  tlab::Array{String,1}
  nnod::Int64
end




# function to read a tree using R
# reading tree capabilities 
function read_tree(tree_file::String)

  tree = reval("""
                library(\"ape\")
                tree    <- read.tree('$tree_file') 
                tree    <- reorder(tree)
                """)

  edge     = rcopy(tree[1])
  edge     = convert(Array{Int64},edge)
  Nnode    = rcopy(tree[2])
  Nnode    = convert(Int64,Nnode)
  tiplabel = rcopy(tree[3])
  edlength = rcopy(tree[4])

  tree = rtree(edge, edlength, tiplabel, Nnode)

  brtimes = reval("""
                  brtimes <- branching.times(tree)
                  """)

  brtimes = rcopy(brtimes)

  return tree, brtimes
end





# function to initialize X and Y matrix
# tip_values, x(t), and tip_areas, y(t),
# must be Dictionaries 
function initialize_data(tip_values::Dict{Int64,Float64},
                         tip_areas ::Dict{Int64,Array{Int64,1}},
                         m         ::Int64,
                         tree      ::rtree,
                         bts       ::Array{Float64,1})

  br     = branching_times(tree)
  n      = tree.nnod + 1
  nareas = length(tip_areas[1])

  # make times and δt vector
  bts = unique(br[:,4])
  sort!(bts, rev = true)
  ets = convert(Array{Float64,1},linspace(0,bts[1],m+1))
  append!(ets,bts[2:end])
  ets = unique(ets)

  # epoch times
  sort!(ets, rev = true)

  # δt
  δt = abs.(diff(ets))

  # initialize data augmentation matrices
  X = fill(NaN, length(ets), n)
  B = deepcopy(X)
  Y = fill(23, length(ets), n, nareas)

  # which rows are branching points
  wch = indexin(bts, ets)

  # coupled nodes (cells that are coupled in array)
  coup = zeros(Int64, tree.nnod, 3)

  bord = sortperm(br[:,5])[(1:tree.nnod-1)+n]

  alive = collect(1:n)

  #which column alive
  wca = 1:n

  wts = sort(wch, rev = true) .+ 1

  setindex!(coup, wts .- 1, :,3)

  wrtf = wts[1]:length(ets)
  X[wrtf, wca] = 1.0
  B[wrtf, wca] = repeat(alive, inner = length(wrtf))

  for i=Base.OneTo(tree.nnod-1)
    
    fn  = br[bord[i],2]
    wda = br[find(br[:,1] .== fn),2]
    cda = indexin(wda,alive)
    coup[i,1:2] = cda

    alive[cda] = [fn,0]
    wrtf = wts[i+1]:(wts[i]-1)

    B[wrtf,:] = repeat(alive, inner = length(wrtf))

    wca = find(alive .> 0)
    X[wts[i+1]:length(ets),wca] = 1.0

  end

  coup[tree.nnod,1:2] = find(alive .> 0)
 
  ncoup = zeros(Int64,tree.nnod,2)

  for j=Base.OneTo(tree.nnod), i=1:2
    ncoup[j,i] = vecind(coup[j,3],coup[j,i],length(ets))
  end

  X[1,1]     = 1.0
  B[1,1]     = n + 1
  B[B .== 0] = NaN

  # Brownian bridges initialization for X
  si = initialize_X!(tip_values, X, B, ncoup, δt, tree)

  # declare non-23s for Y
  initialize_Y!(tip_areas, Y, B)

  return X, Y, B, ncoup, δt, tree, si
end





# create initial trait matrix  
# using Brownian bridges
function initialize_X!(tip_values::Dict{Int64,Float64},
                       X         ::Array{Float64,2},
                       B         ::Array{Float64,2},
                       ncoup     ::Array{Int64,2},
                       δt        ::Array{Float64,1},
                       tree      ::rtree)

  co1 = ncoup[:,1]
  co2 = ncoup[:,2]
  nr, nc = size(X)
  nbrs = 2*nc - 1

  # matrix of delta times
  δtM = zeros(endof(δt)+1,nc)
  for i in Base.OneTo(nc)
    δtM[2:end,i] = δt
  end

  Xnod = ncoup[size(ncoup,1):-1:1,:]

  Xnod = sort(Xnod,1)

  # brownian motion
  bm_ll = make_bm_ll(tip_values, tree)
  op    = optimize(bm_ll, rand(nc), Optim.Options(
                                    g_tol = 1e-6,
                                    iterations = 100_000,
                                    store_trace = false))

  ar = Optim.minimizer(op)[2:end]
  si = Optim.minimizer(op)[1]

  X[Xnod[:,1]] = ar

  for i in Base.OneTo(nc)
    X[nr,i] = tip_values[i]
  end

  X[co2] = X[co1]

  for i=setdiff(1:nbrs,nc+1)
    wbranch = find(B.==i)
    l_i = wbranch[1]-1
    l_f = wbranch[end]
    X[l_i:l_f] = bb(X[l_i], X[l_f], δtM[wbranch], si)
  end

  X[co2] = NaN

  return si
end





# simple function to initialize Y
function initialize_Y!(tip_areas::Dict{Int64,Array{Int64,1}},
                       Y        ::Array{Int64,3},
                       B        ::Array{Float64,2})

  # index non 23 for Y
  const ind = find(.!isnan.(B))
  const lB  = length(ind)

  nr,nc,na = size(Y)
  for i in 1:(na-1)
    append!(ind, (ind[1:lB] + i*nr*nc))
  end

  Y[ind] = 1

  for i in Base.OneTo(nc)
    @views Y[nr,i,:] = tip_areas[i]
  end

end





# Maximum likelihood Brownian Motion
function make_bm_ll(tip_values::Dict{Int64,Float64},
                    tree      ::rtree)

  const wt = tree.ed .<= (tree.nnod + 1)
  tips_ind = find(wt)

  # base with trait values
  ntr  = zeros(size(tree.ed))

  # assign tip values
  for i=eachindex(tip_values)
    ntr[tips_ind[i]] = tip_values[i]
  end

  # internal nodes
  ins  = unique(tree.ed[:,1])
  lins = length(ins)

  # make triads for all internal nodes
  # including the root
  const trios = Array{Int64,1}[]
  ndi  = ins[1]
  daus = find(tree.ed[:,1] .== ndi)
  unshift!(daus, 0)
  push!(trios, daus)

  # for all internal nodes
  for i = 2:lins
    ndi  = ins[i]
    daus = find(tree.ed[:,1] .== ndi)
    unshift!(daus, find(tree.ed[:,2] .== ndi)[1])
    push!(trios, daus)
  end

  function f(p::Array{Float64,1})

    @inbounds begin

      σ² = p[1]

      if σ² <= 0
        return Inf
      end

      for i=eachindex(trios)
        pr, d1, d2 = trios[i]
        if pr == 0
          ntr[d1,1] = ntr[d2,1] = p[i+1]
        else
          ntr[pr,2] = ntr[d1,1] = ntr[d2,1] = p[i+1]
        end
      end
      
      ll = 0.0
      for i in eachindex(tree.el)
        ll -= logdnorm(ntr[i,2], ntr[i,1], tree.el[i]*σ²)
      end
    end  
    
    return ll
  end

  return f
end





# function to estimate absolute
# branching times, with time 0 at the
# present, time going backward
function branching_times(tree::rtree)

  @inbounds begin

    n    = tree.nnod + 1
    el_t = find(tree.ed[:,2] .<= n)

    brs = zeros(endof(tree.el),5)

    setindex!(brs, tree.ed, :, 1:2) 
    setindex!(brs, tree.el, :, 3) 

    for j=eachindex(tree.el)
      if brs[j,1] == (n+1)
        brs[j,4] = 0.0
        brs[j,5] = brs[j,4] + brs[j,3]
      else
        brs[j,4] = @. brs[brs[j,1] == brs[:,2],5][1]
        brs[j,5] = brs[j,4] + brs[j,3]
      end
    end

     # change time forward order
    @views tree_depth = brs[n .== brs[:,2],5][1]

    for j=eachindex(tree.el) 
      brs[j,4] = tree_depth - brs[j,4]
      brs[j,5] = tree_depth - brs[j,5]
    end

    brs[el_t,5] = 0.0

  end

  return brs
end





# Brownian bridge simulation function for
# a vector of times δt 
function bb(xs::Float64, xf::Float64, δt::Array{Float64,1}, σ::Float64)

  t  = unshift!(cumsum(δt),0.0)
  tl = endof(t)
  w  = zeros(tl)

  for i=Base.OneTo(tl-1)
    w[i+1] = randn()*sqrt(δt[i])*σ
  end

  cumsum!(w, w)
  wf = w[tl]
  tf = t[tl]

  return @. xs + w - t/tf * (wf - xf + xs)
end

