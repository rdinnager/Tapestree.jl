#=

Functions to estimate area and lineage trait averages 
and lineage specific differences

Ignacio Quintero Mächler

t(-_-t)

May 15 2017

=#





"""
    area_lineage_means!(AA::Array{Float64,2}, LA::Array{Float64,2}, X::Array{Float64,2}, Y::Array{Int64,3}, wcol::Array{Array{Int64,1},1}, m::Int64)

Estimate area means according to presence
absence of species and linage means according
to area averages.
"""
function area_lineage_means!(AA  ::Array{Float64,2}, 
                             LA   ::Array{Float64,2},
                             AO   ::Array{Int64,2},
                             X    ::Array{Float64,2}, 
                             Y    ::Array{Int64,3}, 
                             wcol ::Array{Array{Int64,1},1},
                             m    ::Int64,
                             narea::Int64)

  @inbounds begin

    for k in Base.OneTo(m)

      # area averages
      for j in Base.OneTo(narea)
        AA[k,j] = 0.0::Float64
        sumY    = 0.0::Float64
        AO[k,j] = 0::Int64
        for i in wcol[k]::Array{Int64,1}
          if Y[k,i,j] == 1
            AA[k,j] += X[k,i]::Float64
            sumY    += 1.0::Float64
            AO[k,j]  = 1::Int64
          end
        end
        AA[k,j] /= (sumY == 0.0 ? 1.0 : sumY)::Float64
      end

      # lineage average
      for i = wcol[k]::Array{Int64,1}
        LA[k,i] = 0.0::Float64
        sden    = 0.0::Float64
        for j = Base.OneTo(narea) 
          if Y[k,i,j] == 1
            LA[k,i] += AA[k,j]::Float64
            sden    += 1.0::Float64
          end
        end
        
        LA[k,i] /= sden::Float64
      end
    end

  end

  nothing
end





"""
    linarea_diff!(LD::Array{Float64,3}, X::Array{Float64,2}, AA::Array{Float64,2}, narea::Int64, ntip::Int64, m::Int64)

Create multi-dimensional array with 
lineage and area averages differences in X.
"""
function linarea_diff!(LD   ::Array{Float64,3},
                       X    ::Array{Float64,2},
                       AA   ::Array{Float64,2},
                       AO   ::Array{Int64,2},
                       narea::Int64,
                       ntip ::Int64,
                       m    ::Int64)
  @inbounds begin

    for j = Base.OneTo(narea), n = Base.OneTo(ntip), i = Base.OneTo(m)
      setindex!(LD, 
                (AO[i,j] == 0 ? 0.0 : abs(X[i,n] - AA[i,j]))::Float64, 
                i, n, j)
    end
  end

  nothing
end





"""
    linarea_branch_avg!(avg_Δx ::Array{Float64,1}, LD::Array{Float64,3}, bridx_a::Array{Array{Array{Int64,1},1},1}, narea::Int64, nedge::Int64)

Estimate the branch average of lineage differences in each specific area.
"""
function linarea_branch_avg!(avg_Δx ::Array{Float64,2},
                             LD     ::Array{Float64,3},
                             bridx_a::Array{Array{UnitRange{Int64},1},1},
                             narea  ::Int64,
                             nedge  ::Int64)
  @inbounds begin

    for j = Base.OneTo(narea), i = Base.OneTo(nedge - 1)
      setindex!(avg_Δx, mean(LD[bridx_a[j][i]]), i, j)
    end

  end

  nothing
end




aak = 



aak, lak, ldk    = Xupd_linavg(43,wcol[43], X, Y, narea)
aak2, lak2, ldk2 = Xupd_linavg2(43,wcol[43], X, Y, narea)


@benchmark Xupd_linavg( 10,wcol[10], X, Y, narea)
@benchmark Xupd_linavg2(10,wcol[10], X, Y, narea)


"""
    Xupd_linavg(k::Int64, wck::Array{Int64,1}, X::Array{Float64,2}, Y::Array{Int64,3}, narea::Int64)

Re-estimate lineage specific means 
for a branch update.
"""
function Xupd_linavg(k    ::Int64, 
                     wck  ::Array{Int64,1},
                     X    ::Array{Float64,2},
                     Y    ::Array{Int64,3},
                     narea::Int64)
  @inbounds begin

    const nsp = endof(wck)::Int64
    const aa  = zeros(Float64, narea)
    const ao  = zeros(Int64,   narea)
    const la  = zeros(Float64, nsp)
    const ld  = Array{Float64}(nsp, narea)

    for j = Base.OneTo(narea)
      sumY  = 0.0::Float64
      for i = wck
        if Y[k,i,j] == 1
          aa[j] += X[k,i]::Float64
          sumY  += 1.0::Float64
          ao[j]  = 1::Int64
        end
      end
      aa[j] /= (sumY == 0.0 ? 1.0 : sumY)::Float64
    end

    for i = Base.OneTo(nsp)
      sden  = 0.0::Float64
      for j = Base.OneTo(narea)
        if Y[k,wck[i],j] == 1
          la[i] += aa[j]
          sden  += 1.0
        end
      end
      la[i] /= sden::Float64
    end

    for j = Base.OneTo(narea), i = Base.OneTo(nsp)
      setindex!(ld, (ao[j] == 0 ? 0.0 : abs(X[k,wck[i]] - aa[j])), i, j)
    end

  end


  return aa, la, ld
end










