# An unsafe in-place version of OLS for bootstrap
function _fit!(m::OLS{TF}) where TF
    Y = m.resid
    X = m.X
    coef = m.coef
    mul!(coef, X', Y)
    mul!(m.crossXcache, X', X)
    ldiv!(cholesky!(m.crossXcache), coef)
    if m.intercept === nothing
        copyto!(m.coefB, coef')
    else
        copyto!(m.coefB, view(coef, 2:size(coef,1), :)')
        copyto!(m.intercept, view(coef, 1, :))
    end
    mul!(Y, X, coef, -1.0, 1.0)
    mul!(m.residvcov, Y', Y)
    rdiv!(m.residvcov, m.dofr)
    residchol = m.residchol
    residcholL = m.residcholL
    if residchol !== nothing
        Cfactors = getfield(residchol, :factors)
        Cuplo = getfield(residchol, :uplo)
        copyto!(Cfactors, m.residvcov)
        # residchol could involve changes in immutable objects but it is not used
        residchol = cholesky!(Cfactors)
        N = size(m.residvcov, 1)
        @inbounds for j in 1:N
            for i in 1:j-1
                residcholL[i,j] = zero(TF)
            end
            for i in j:N
                residcholL[i,j] = Cuplo === 'U' ? Cfactors[j,i] : Cfactors[i,j]
            end
        end
    end
    return nothing
end

# An unsafe version for bootstrap
function _fitvar!(data::Matrix, m::OLS, nlag, nocons)
    i0 = nocons ? 0 : 1
    Y = residuals(m)
    X = modelmatrix(m)
    N = size(Y, 2)
    # esample is not used here
    for j in 1:N
        col = view(data, :, j)
        Tfull = length(col)
        copyto!(view(Y, :, j), view(col, nlag+1:Tfull))
        for l in 1:nlag
            copyto!(view(X, :, i0+(l-1)*N+j), view(col, nlag+1-l:Tfull-l))
        end
    end
    _fit!(m)
end

randomindex(r::VectorAutoregression) = sample(1:size(residuals(r),1))

function wilddraw!(out, r::VectorAutoregression)
    randn!(view(out, :, 1))
    K = size(out, 2)
    if K > 1
        for j in 2:K
            copyto!(view(out,:,j), view(out,:,1))
        end
    end
    out .*= residuals(r)
    return out
end

function iidresiddraw!(out, r::VectorAutoregression)
    T = size(out,1)
    for i in 1:T
        idraw = sample(1:T)
        copyto!(view(out, i, :), view(residuals(r), idraw, :))
    end
    return out
end

function _bootstrap!(ks, stats, r::VectorAutoregression, var, initialindex, drawresid,
        ::Val{estimatevar}, allbootdata) where estimatevar
    keepbootdata = allbootdata isa Vector
    T, N = size(residuals(r))
    nlag = arorder(r)
    NP = N * nlag
    X0 = modelmatrix(r)
    bootdata = Matrix{Float64}(undef, T+nlag, N)
    if estimatevar
        m = deepcopy(r.est)
        rk = VectorAutoregression(m, r.names, r.lookup, !hasintercept(r))
    else
        rk = nothing
    end
    X1s = _reshape(view(X0, :, hasintercept(r) ? (2:NP+1) : 1:NP), T, N, nlag)
    Y0s = view(X1s, :, :, nlag:-1:1)
    for k in ks
        i0 = initialindex(r)
        Y0 = view(Y0s, i0, :, :)
        drawresid(view(bootdata, nlag+1:nlag+T, :), r)
        copyto!(view(bootdata, 1:nlag, :), Y0')
        for t in nlag+1:nlag+T
            var(view(bootdata, t, :), _reshape(view(bootdata, t-1:-1:t-nlag, :)', N*nlag))
        end
        keepbootdata && (allbootdata[k] = copy(bootdata))
        estimatevar && _fitvar!(bootdata, m, nlag, !hasintercept(r))
        for stat in stats
            nt = (out=selectdim(stat[1], ndims(stat[1]), k), data=bootdata, r=rk)
            stat[2](nt)
        end
    end
end

function bootstrap!(stats, r::VectorAutoregression;
        initialindex::Union{Function,Integer}=randomindex,
        drawresid::Function=wilddraw!,
        correctbias=false, estimatevar::Bool=true,
        ntasks::Integer=Threads.nthreads(), keepbootdata::Bool=false)
    stats isa Pair && (stats = (stats,))
    out1 = stats[1][1]
    nsample = size(out1, ndims(out1))
    nstat = length(stats)
    if nstat > 1
        for k in 1:nstat
            outk = stats[k][1]
            size(outk, ndims(outk)) == nsample || throw(ArgumentError(
                "all arrays for statistics must have the same length in the last dimesion"))
        end
    end
    if initialindex isa Integer
        initindex = r -> initialindex
    else
        initindex = initialindex
    end
    if correctbias != false
        if coefcorrected(r) === nothing
            if correctbias == true
                r, δ = biascorrect(r)
            else
                r, δ = biascorrect(r; correctbias...)
            end
        end
        # biascorrect is not applied if VAR is not stable
        if δ === nothing
            var = VARProcess(r)
        elseif hasintercept(r)
            # Slightly faster simulate! with copied var
            var = VARProcess(coefcorrected(r)', view(coef(r),1,:), copy=true)
        else
            var = VARProcess(coefcorrected(r)', copy=true)
        end
    else
        var = VARProcess(r)
    end
    allbootdata = keepbootdata ? Vector{Matrix}(undef, nsample) : nothing
    ntasks = min(ntasks, nsample)
    if ntasks > 1
        npertask = nsample ÷ ntasks
        # Assign sample IDs across tasks
        ks = Vector{UnitRange{Int64}}(undef, ntasks)
        k0 = npertask + nsample%ntasks
        ks[1] = 1:k0
        for i in 2:ntasks
            ks[i] = k0+1:k0+npertask
            k0 += npertask
        end
        @sync for itask in 1:ntasks
            Threads.@spawn begin
                _bootstrap!(ks[itask], stats, r, var, initindex, drawresid, Val(estimatevar),
                    allbootdata)
            end
        end
    else
        _bootstrap!(1:nsample, stats, r, var, initindex, drawresid, Val(estimatevar), allbootdata)
    end
    return keepbootdata ? allbootdata : nothing
end

