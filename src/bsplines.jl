"""
    BSpline(t, x, w, B, S)

Basis structure for the B-splines generated by the knot set `t`. `x`
and `w` are the associated quadrature roots and weights, respectively,
the columns of `B` correspond to the B-splines resolved on the
quadrature roots, and `S` is the (banded) B-spline overlap matrix.
"""
struct BSpline{T,R<:Real,
               KnotSet<:AbstractKnotSet{<:Any,<:Any,<:Any,R},
               XV<:AbstractVector{T},
               WV<:AbstractVector{R},
               BM<:AbstractMatrix{T},
               SM<:AbstractMatrix{T}} <: Basis{T}
    t::KnotSet
    x::XV
    w::WV
    B::BM
    S::SM
end

const RestrictedBSpline{T} = RestrictedQuasiArray{T,2,<:BSpline{T}}
const AdjointRestrictedBSpline{T} = AdjointRestrictedQuasiArray{T,2,<:BSpline{T}}

const BSplineOrRestricted{T} = BasisOrRestricted{<:BSpline{T}}
const AdjointBSplineOrRestricted{T} = AdjointBasisOrRestricted{<:BSpline{T}}

function basis_functions(t::AbstractKnotSet{k}, x::AbstractVector{T}, m=0) where {k,T}
    nf = numfunctions(t)
    B = spzeros(T, length(x), nf)

    nei = nonempty_intervals(t)
    # This is the amount of quadrature points per interval (assuming
    # the same amount per interval, which is currently the case), this
    # could conceivably be passed as an argument, instead.
    N = findlast(e -> e < t[nei[1]+1], x)

    ix = 1
    for i ∈ nei
        # These are the functions which are non-zero on the interval
        # t[i]..t[i+1].
        for j ∈ max(1,i-k+1):min(i,nf)
            eⱼ = UnitVector{T}(nf, j)
            for l ∈ ix:ix+N-1
                B[l,j] = deBoor(t, eⱼ, x[l], i, m)
            end
        end
        ix += N
    end

    B
end

basis_functions(B::BSpline, args...) = basis_functions(B.t, B.x, args...)
basis_functions(B::RestrictedBSpline, args...) =
    basis_functions(parent(B), args...)[:,indices(B,2)]

function overlap_matrix!(S::Union{BandedMatrix,Tridiagonal}, χ, ξ, w)
    m = min(size(S,1),size(χ,2))
    n = min(size(S,2),size(ξ,2))
    # It is assumed that the bandwidth is correct for the overlap
    # ⟨χ|ξ⟩.
    p = max(bandwidths(S)...)
    W = Diagonal(w)
    for i ∈ 1:m
        for j ∈ max(i-p,1):min(i+p,n)
            S[i,j] = χ[:,i]' * W * ξ[:,j]
        end
    end
    # χ == ξ && isreal(χ) && isreal(W) && isreal(ξ) ?
    #     Symmetric(S) : S
    S
end

function assert_compatible_bases(A::BSplineOrRestricted, B::BSplineOrRestricted)
    A = parent(A)
    B = parent(B)
    A.t.t == B.t.t &&
        A.x == B.x &&
        A.w == B.w ||
        throw(ArgumentError("Can only multiply B-spline bases with identical knot sets, resolved on the same Gauß–Legendre points"))
end

function overlap_matrix!(S::Union{BandedMatrix,Tridiagonal},
                         Ac::AdjointBSplineOrRestricted,
                         B::BSplineOrRestricted,
                         op=I)
    A = parent(Ac)
    assert_compatible_bases(A,B)
    χ = view(parent(A).B, :, indices(A,2))
    ξ = view(parent(B).B, :, indices(B,2))
    overlap_matrix!(S, χ, op*ξ, weights(parent(B)))
end

function BSpline(t::AbstractKnotSet{k}, x::AbstractVector{T}, w::AbstractVector) where {k,T}
    B = basis_functions(t, x)

    nf = numfunctions(t)
    S = BandedMatrix(Zeros{T}(nf, nf), (k-1,k-1))

    BSpline(t, x, w, B, overlap_matrix!(S, B, B, w))
end

"""
    BSpline(t[, N])

Create the B-spline basis corresponding to the knot set `t`. `N` is
the amount of Gauß–Legendre quadrature points per interval.
"""
BSpline(t::AbstractKnotSet, N) = BSpline(t, lgwt(t, N)...)

"""
    BSpline(t[; k′=3])
Create the B-spline basis corresponding to the knot set `t`. `k′` is
the highest polynomial order of operators for which it should be
possible to compute the matrix elements exactly (via Gauß–Legendre
quadrature). The default `k′=3` corresponds to operators O(x²).
"""
BSpline(t::AbstractKnotSet; k′=3) = BSpline(t, num_quadrature_points(order(t), k′))

# * Properties

axes(B::BSpline) = (Inclusion(first(B.t)..last(B.t)), Base.OneTo(numfunctions(B.t)))
size(B::BSpline) = (ℵ₁, numfunctions(B.t))
==(A::BSpline,B::BSpline) = A.t == B.t

distribution(B::BSpline) = distribution(B.t)

order(B::BSplineOrRestricted) = order(unrestricted_basis(B).t)

function show(io::IO, B::BSpline{T}) where T
    write(io, "BSpline{$(T)} basis with $(B.t)")
end

locs(B::BSpline) = B.x
weights(B::BSpline) = B.w

IntervalSets.leftendpoint(B::BSpline) = B.x[1]
IntervalSets.rightendpoint(B::BSpline) = B.x[end]

function centers(B::BSplineOrRestricted)
    x = B'*QuasiDiagonal(axes(B,1))*B
    S = B'B

    diag(x) ./ diag(S)
end

# # * Basis functions

"""
    deBoor(t, c, x[, i[, m=0]])

Evaluate the spline given by the knot set `t` and the set of control
points `c` at `x` using de Boor's algorithm. `i` is the index of the
knot interval containing `x`. If `m≠0`, calculate the `m`th derivative
at `x` instead.
"""
function deBoor(t::AbstractKnotSet, c::AbstractVector{T}, x,
                i=find_interval(t, x), m=0) where T
    isnothing(i) && return zero(eltype(t))
    k = order(t)
    nc = length(c)
    k == 1 && return (nc < i || m > 0) ? zero(T) : c[i]

    α = [r > 0 && r ≤ nc ? c[r] : zero(T)
         for r ∈ i-k+1:i]
    nt = length(t)
    nf = numfunctions(t)
    for j = 1:k-1
        for r = i:-1:max(i-k+j,1)
            jjj = r+k-j
            (jjj > nt || jjj < 1) && continue
            r′ = r - i + k
            r ≠ 1 && r′ == 1 && continue

            a = t[r+k-j]
            b = t[r]

            α[r′] = if j ≤ m
                (k-j)*if r == 1
                    -α[r′]
                elseif r == nf + j
                    α[r′-1]
                else
                    α[r′-1] - α[r′]
                end
            else
                if r == 1
                    (b-x)*α[r′]
                elseif r == nf + j
                    (x-a)*α[r′-1]
                else
                    ((x-a)*α[r′-1] + (b-x)*α[r′])
                end
            end
            α[r′] /= (b-a)
        end
    end

    α[end]
end

getindex(B::BSpline{T}, x::Real, j::Integer) where T =
    deBoor(B.t, UnitVector{T}(size(B,2), j),
           x, find_interval(B.t, x))

function basis_function!(χ, B::BSpline{T}, x::AbstractVector, j) where T
    eⱼ = UnitVector{T}(size(B,2), j)
    for (is,k) ∈ within_support(x, B.t, j)
        for i in is
            χ[i] = deBoor(B.t, eⱼ, x[i], k)
        end
    end
end

function getindex(B::BSpline{T}, x::AbstractVector, sel::AbstractVector) where T
    χ = spzeros(T, length(x), length(sel))
    o = sel[1] - 1
    for j in sel
        basis_function!(view(χ, :, j-o), B, x, j)
    end
    χ
end

function getindex(B::BSplineOrRestricted{T}, x::AbstractVector, j::Integer) where T
    χ = spzeros(T, length(x))
    basis_function!(χ, parent(B), x, j+first(indices(B,2))-1)
    χ
end

getindex(B::BSplineOrRestricted, x, ::Colon) =
    getindex(parent(B), x, indices(B,2))

getindex(B::BSplineOrRestricted, x::AbstractVector, sel::AbstractVector) =
    getindex(parent(B), x, indices(B,2)[sel])

# * Types

const SplineArray{T,N,B<:BSplineOrRestricted} = FuncArray{T,N,B}
const SplineVector{T,B<:BSplineOrRestricted} = FuncVector{T,B}
const SplineMatrix{T,B<:BSplineOrRestricted} = FuncMatrix{T,B}
const SplineVecOrMat{T,B<:BSplineOrRestricted} = FuncVecOrMat{T,B}

const AdjointSplineArray{T,N,B<:BSplineOrRestricted} = AdjointFuncArray{T,N,B}
const AdjointSplineVector{T,B<:BSplineOrRestricted} = AdjointFuncVector{T,B}
const AdjointSplineMatrix{T,B<:BSplineOrRestricted} = AdjointFuncMatrix{T,B}
const AdjointSplineVecOrMat{T,B<:BSplineOrRestricted} = AdjointFuncVecOrMat{T,B}

Base.show(io::IO, spline::SplineVector) =
    write(io, "Spline on $(spline.args[1])")

Base.show(io::IO, spline::SplineMatrix) =
    write(io, "$(size(spline, 2))d spline on $(spline.args[1])")

# * Matrix construction

function Matrix(::UndefInitializer, A::BSplineOrRestricted{T}, B::BSplineOrRestricted{T}, ::Type{U}=T) where {T,U}
    m,n = size(A,2), size(B,2)
    k = max(order(A),order(B))
    if k == 2 && m == n
        dl = Vector{U}(undef, m-1)
        d = Vector{U}(undef, m)
        du = Vector{U}(undef, m-1)
        Tridiagonal(dl, d, du)
    else
        ij = first(indices(B,2)) - first(indices(A,2))
        BandedMatrix{U}(undef, (m,n), (k-1+ij,k-1-ij))
    end
end

Matrix(::UndefInitializer, A::BSplineOrRestricted{T}, ::Type{U}=T) where {T,U} =
    Matrix(undef, A, A, U)

function Base.zeros(A::BSplineOrRestricted{T}, B::BSplineOrRestricted{T}=A, ::Type{U}=T) where {T,U}
    M = Matrix(undef, A, B, U)
    M .= zero(U)
    M
end

# * Mass matrix
@materialize function *(Ac::AdjointBSplineOrRestricted,
                        B::BSplineOrRestricted)
    T -> begin
        Matrix(undef, parent(Ac), B, T)
    end
    dest::AbstractMatrix{T} -> begin
        overlap_matrix!(dest, Ac, B)
    end
end

metric(B::BSpline) = B.S

# * Diagonal operators

@materialize function *(Ac::AdjointBSplineOrRestricted,
                        D::QuasiDiagonal,
                        B::BSplineOrRestricted)
    T -> begin
        Matrix(undef, parent(Ac), B, T)
    end
    dest::AbstractMatrix{T} -> begin
        # Evaluate the quasi-diagonal operator D on the quadrature roots
        # of B.
        op = Diagonal(getindex.(Ref(D.diag), locs(parent(B))))
        overlap_matrix!(dest, Ac, B, op)
    end
end

@materialize function *(Ac::AdjointBSplineOrRestricted,
                        D::QuasiDiagonal,
                        E::QuasiDiagonal,
                        B::BSplineOrRestricted)
    T -> begin
        Matrix(undef, parent(Ac), B, T)
    end
    dest::AbstractMatrix{T} -> begin
        # Evaluate the quasi-diagonal operators D & E on the quadrature roots
        # of B.
        op = Diagonal(getindex.(Ref(D.diag), locs(parent(B))) .*
                      getindex.(Ref(E.diag), locs(parent(B))))
        overlap_matrix!(dest, Ac, B, op)
    end
end


# * Function interpolation

function Base.:(\ )(B::BSpline, f::BroadcastQuasiArray)
    axes(f,1) == axes(B,1) ||
        throw(DimensionMismatch("Function on $(axes(f,1).domain) cannot be interpolated over basis on $(axes(B,1).domain)"))
    B.B \ getindex.(Ref(f), B.x)
end

function Base.:(\ )(B::RestrictedBSpline, f::BroadcastQuasiArray)
    axes(f,1) == axes(B,1) ||
        throw(DimensionMismatch("Function on $(axes(f,1).domain) cannot be interpolated over basis on $(axes(B,1).domain)"))
    # We need to evaluate the basis functions of the restricted
    # B-spline basis on /all/ quadrature points.
    x = locs(parent(B))
    V = B[x,:]
    V \ getindex.(Ref(f), x)
end

export BSpline
