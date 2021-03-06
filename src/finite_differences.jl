abstract type AbstractFiniteDifferences{T,I<:Integer} <: Basis{T} end
const RestrictedFiniteDifferences{T,B<:AbstractFiniteDifferences{T}} =
    RestrictedQuasiArray{T,2,B}
const FiniteDifferencesOrRestricted = BasisOrRestricted{<:AbstractFiniteDifferences}

eltype(::AbstractFiniteDifferences{T}) where T = T

axes(B::AbstractFiniteDifferences{T}) where T = (Inclusion(leftendpoint(B)..rightendpoint(B)), Base.OneTo(length(locs(B))))
size(B::AbstractFiniteDifferences) = (ℵ₁, length(locs(B)))

distribution(B::AbstractFiniteDifferences) = distribution(locs(B))

"""
    local_step(B, i)

The step size around grid point `i`. For uniform grids, this is
equivalent to [`step`](@ref).
"""
local_step(B::AbstractFiniteDifferences, _) = step(B)
weight(B::AbstractFiniteDifferences{T}, _) where T = one(T)
weights(B::AbstractFiniteDifferences{T}) where T = ones(T,size(B,2))

inverse_weight(B::AbstractFiniteDifferences{T}, _) where T = one(T)
inverse_weights(B::AbstractFiniteDifferences{T}) where T = ones(T,size(B,2))

==(A::AbstractFiniteDifferences,B::AbstractFiniteDifferences) = locs(A) == locs(B)

assert_compatible_bases(A::FiniteDifferencesOrRestricted, B::FiniteDifferencesOrRestricted) =
    locs(A) == locs(B) ||
        throw(ArgumentError("Can only multiply finite-differences sharing the same nodes"))

function loc(B::AbstractFiniteDifferences, i)
    N = size(B,2)
    if i < 1
        loc(B,1) - local_step(B,1)
    elseif i > N
        loc(B,N) + local_step(B,N)
    else
        locs(B)[i]
    end
end

tent(x, a, b, c) =
    1 - clamp((b-x)/(b-a), 0, 1) - clamp((b-x)/(b-c), 0, 1)

getindex(B::AbstractFiniteDifferences, x::Real, i::Integer) =
    weight(B,i)*tent(x, loc(B, i-1), loc(B, i), loc(B, i+1))

step(B::RestrictedFiniteDifferences) = step(parent(B))
local_step(B::RestrictedFiniteDifferences, i) = local_step(parent(B), j+first(indices(B,2))-1)

function getindex(B::AbstractFiniteDifferences{T}, x::AbstractVector, sel::AbstractVector) where T
    l = locs(B)
    χ = spzeros(T, length(x), length(sel))
    o = sel[1] - 1

    n = length(l)
    j = sel[1]
    b = l[j]
    a = j > 1 ? l[j-1] : 2b - l[j+1]
    for j in sel
        c = j < n ? l[j+1] : 2b - l[j-1]
        x₀ = b
        J = j - o
        δx = local_step(B, j)
        w = weight(B, j)
        for i ∈ findall(in(a..c), x)
            χ[i,J] = w*tent(x[i], a, b, c)
        end
        a,b = b,c
    end
    χ
end

getindex(B::FiniteDifferencesOrRestricted, x::AbstractVector, ::Colon) =
    getindex(parent(B), x, indices(B,2))

getindex(B::RestrictedFiniteDifferences, x::AbstractVector, sel::AbstractVector) =
    getindex(parent(B), x, indices(B,2)[sel])

vandermonde(::Uniform, B::AbstractFiniteDifferences{T}) where T =
    BandedMatrices._BandedMatrix(Ones{T}(1,size(B,2)), axes(B,2), 0, 0)

vandermonde(::NonUniform, B::AbstractFiniteDifferences) =
    BandedMatrix(0 => weights(B))

vandermonde(B::AbstractFiniteDifferences) = vandermonde(distribution(B), B)

metric_shape(B::FiniteDifferencesOrRestricted) = Diagonal

# * Types

const FDArray{T,N,B<:FiniteDifferencesOrRestricted} = FuncArray{T,N,B}
const FDVector{T,B<:FiniteDifferencesOrRestricted} = FuncVector{T,B}
const FDMatrix{T,B<:FiniteDifferencesOrRestricted} = FuncMatrix{T,B}
const FDVecOrMat{T,B<:FiniteDifferencesOrRestricted} = FuncVecOrMat{T,B}

const AdjointFDArray{T,N,B<:FiniteDifferencesOrRestricted} = AdjointFuncArray{T,N,B}
const AdjointFDVector{T,B<:FiniteDifferencesOrRestricted} = AdjointFuncVector{T,B}
const AdjointFDMatrix{T,B<:FiniteDifferencesOrRestricted} = AdjointFuncMatrix{T,B}
const AdjointFDVecOrMat{T,B<:FiniteDifferencesOrRestricted} = AdjointFuncVecOrMat{T,B}

# This is an operator on the form O = B*M*B⁻¹, where M is a matrix
# acting on the expansion coefficients. When applied to e.g. a
# FDVector, v = B*c, we get O*v = B*M*B⁻¹*B*c = B*M*c. Acting on an
# AdjointFDVector is also trivial: v'O' = (B*c)'*(B*M*B⁻¹)' =
# B'c'M'. It is less clear if it is possible to form Hermitian
# operator that does _not_ need be transposed before application to
# adjoint vectors.
const FDOperator{T,B<:FiniteDifferencesOrRestricted,M<:AbstractMatrix} = MulQuasiArray{T,2,<:Tuple{<:B,<:M,
                                                                                                   <:PInvQuasiMatrix{<:Any,<:Tuple{<:B}}}}

const FDMatrixElement{T,B<:FiniteDifferencesOrRestricted,M<:AbstractMatrix,V<:AbstractVector} =
    MulQuasiArray{T,0,<:Mul{<:Any,
                            <:Tuple{<:Adjoint{<:Any,<:V},<:QuasiAdjoint{<:Any,<:B},
                                    <:B,<:M,<:QuasiAdjoint{<:Any,<:B},
                                    <:B,<:V}}}

const FDInnerProduct{T,U,B<:FiniteDifferencesOrRestricted{U},V1<:AbstractVector{T},V2<:AbstractVector{T}} =
    Mul{<:Any, <:Tuple{<:Adjoint{<:Any,<:V1},<:QuasiAdjoint{<:Any,<:B},<:B,<:V2}}

const LazyFDInnerProduct{FD<:FiniteDifferencesOrRestricted} = Mul{<:Any,<:Tuple{
    <:Mul{<:Any, <:Tuple{
        <:Adjoint{<:Any,<:AbstractVector},
        <:QuasiAdjoint{<:Any,<:FD}}},
    <:Mul{<:Any, <:Tuple{
        <:FD,
        <:AbstractVector}}}}

# * Mass matrix

@simplify function *(Ac::QuasiAdjoint{<:Any,<:FiniteDifferencesOrRestricted}, B::FiniteDifferencesOrRestricted)
    step(B)*combined_restriction(parent(Ac),B)
end

# * Basis inverses

@simplify function *(A⁻¹::PInvQuasiMatrix{<:Any,<:Tuple{<:AbstractFiniteDifferences}}, B::AbstractFiniteDifferences)
    A = parent(A⁻¹)
    A == B || throw(ArgumentError("Cannot multiply basis with inverse of other basis"))
    one(eltype(A))*I
end

@simplify function *(A::AbstractFiniteDifferences, B⁻¹::PInvQuasiMatrix{<:Any,<:Tuple{<:AbstractFiniteDifferences}})
    B = parent(B⁻¹)
    A == B || throw(ArgumentError("Cannot multiply basis with inverse of other basis"))
    one(eltype(A))*I
end

@simplify function *(A⁻¹::PInvQuasiMatrix{<:Any,<:Tuple{<:AbstractFiniteDifferences}}, v::FDArray)
    A = parent(A⁻¹)
    B,c = v.args
    A == B || throw(ArgumentError("Cannot multiply basis with inverse of other basis"))
    c
end

@simplify function *(v::AdjointFDArray, B⁻¹::PInvQuasiMatrix{<:Any,<:Tuple{<:AbstractFiniteDifferences}})
    c,Ac = v.args
    B = parent(B⁻¹)
    parent(Ac) == B || throw(ArgumentError("Cannot multiply basis with inverse of other basis"))
    c
end

# * Various finite differences
# ** Cartesian finite differences
struct FiniteDifferences{T,I} <: AbstractFiniteDifferences{T,I}
    j::UnitRange{I}
    Δx::T
end
FiniteDifferences(j::UnitRange{I}, Δx::T) where {T<:Real,I<:Integer} =
    FiniteDifferences{T,I}(j, Δx)

FiniteDifferences(n::I, Δx::T) where {T<:Real,I<:Integer} =
    FiniteDifferences(1:n, Δx)

locs(B::FiniteDifferences) = B.j*B.Δx
step(B::FiniteDifferences{T}) where {T} = B.Δx

IntervalSets.leftendpoint(B::FiniteDifferences) = (B.j[1]-1)*step(B)
IntervalSets.rightendpoint(B::FiniteDifferences) = (B.j[end]+1)*step(B)

show(io::IO, B::FiniteDifferences{T}) where {T} =
    write(io, "Finite differences basis {$T} on $(axes(B,1).domain) with $(size(B,2)) points spaced by Δx = $(B.Δx)")

# ** Staggered finite differences

local_step(r::AbstractRange, _) = step(r)
function local_step(r::AbstractVector, j)
    if j == 1
        (r[2] - r[1])
    elseif j == length(r)
        r[j] - r[j-1]
    else
        (r[j+1]-r[j-1])/2
    end
end

schafer_corner_fix(ρ, Z) = 1/ρ^2*Z*ρ/8*(1 + Z*ρ)

function log_lin_grid!(r, ρₘᵢₙ, ρₘₐₓ, α, js)
    0 < ρₘᵢₙ < Inf && 0 < ρₘₐₓ < Inf ||
        throw(DomainError((ρₘᵢₙ, ρₘₐₓ), "Log–linear grid steps need to be finite and larger than zero"))
    δρ = ρₘₐₓ-ρₘᵢₙ
    for j = js
        r[j] = r[j-1] + ρₘᵢₙ + (1-exp(-α*r[j-1]))*δρ
    end
end

function log_lin_grid(ρₘᵢₙ, ρₘₐₓ, α, n::Integer)
    r = zeros(n)
    r[1] = ρₘᵢₙ/2
    log_lin_grid!(r, ρₘᵢₙ, ρₘₐₓ, α, 2:n)
    r
end

function log_lin_grid(ρₘᵢₙ, ρₘₐₓ, α, rₘₐₓ)
    # Guess n
    n = ceil(Int, rₘₐₓ/ρₘₐₓ)
    r = zeros(n)
    r[1] = ρₘᵢₙ/2
    log_lin_grid!(r, ρₘᵢₙ, ρₘₐₓ, α, 2:n)
    nprev = n
    while r[end] < rₘₐₓ
        n *= 2
        resize!(r, n)
        log_lin_grid!(r, ρₘᵢₙ, ρₘₐₓ, α, nprev+1:n)
        nprev = n
    end
    j = findlast(<(rₘₐₓ), r)
    r[1:j+1]
end

"""
    StaggeredFiniteDifferences

Staggered finite differences with variationally derived three-points
stencils for the case where there is Dirichlet0 boundary condition at
r = 0. Supports non-uniform grids, c.f.

- Krause, J. L., & Schafer, K. J. (1999). Control of THz Emission from
  Stark Wave Packets. The Journal of Physical Chemistry A, 103(49),
  10118–10125. http://dx.doi.org/10.1021/jp992144

"""
struct StaggeredFiniteDifferences{T,V<:AbstractVector{T},A,B,D} <: AbstractFiniteDifferences{T,Int}
    r::V
    Z::T
    δβ₁::T # Correction used for bare Coulomb potentials, Eq. (22) Schafer2009
    α::A
    β::B
    δ::D

    # Uniform case
    function StaggeredFiniteDifferences(r::V, Z=one(T),
                                        δβ₁=schafer_corner_fix(local_step(r,1), Z)) where {T,V<:AbstractRange{T}}
        issorted(r) ||
            throw(ArgumentError("Node locations must be non-decreasing"))

        N = length(r)
        j = one(T):N
        j² = j .^ 2
        # Eq. (20), Schafer 2000
        α = (j² ./ (j² .- one(T)/4))[1:N-1]
        β = (j² .- j .+ one(T)/2) ./ (j² .- j .+ one(T)/4)

        β[1] += δβ₁ * step(r)^2

        new{T,V,typeof(α),typeof(β),typeof(α)}(r, T(Z), T(δβ₁), α, β, α)
    end

    # Arbitrary case
    function StaggeredFiniteDifferences(r::V, Z=one(T),
                                        δβ₁=schafer_corner_fix(local_step(r,1), Z)) where {T,V<:AbstractVector{T}}
        issorted(r) ||
            throw(ArgumentError("Node locations must be non-decreasing"))

        N = length(r)
        α = zeros(T, N-1)
        β = zeros(T, N)
        γ = zeros(T, N)
        δ = zeros(T, N-1)

        r̃ = vcat(r, 2r[end]-r[end-1])
        a = 2r[1]-r[2]
        b,c,d = r[1],r[2],r[3]

        for j = 1:N
            if j < N
                d = r̃[j+2]
                # Eq. (A13) Krause 1999
                δ[j] = 2/(√((d-b)*(c-a)))*((b+c)/2)^2/(b*c)
                α[j] = δ[j]/(c-b)
            end

            # Eq. (A14) Krause 1999
            fp = ((c+b)/2b)^2
            fm = ((b+a)/2b)^2
            β[j] = 1/(c-a)*(1/(c-b)*fp + 1/(b-a)*fm)

            a,b,c = b,c,d
        end

        β[1] += δβ₁

        new{T,V,typeof(α),typeof(β),typeof(δ)}(r, T(Z), T(δβ₁), α, β, δ)
    end

    # Constructor of uniform grid
    StaggeredFiniteDifferences(n::Integer, ρ, args...) =
        StaggeredFiniteDifferences(ρ*(1:n) .- ρ/2, args...)

    """
    StaggeredFiniteDifferences(rₘₐₓ::T, n::I, args...)

Convenience constructor for [`StaggeredFiniteDifferences`](@ref) covering the
open interval `(0,rₘₐₓ)` with `n` grid points.
"""
    StaggeredFiniteDifferences(rₘₐₓ::T, n::I, args...) where {I<:Integer, T} =
        StaggeredFiniteDifferences(n, rₘₐₓ/(n-one(T)/2), args...)

    # Constructor of log-linear grid
    StaggeredFiniteDifferences(ρₘᵢₙ, ρₘₐₓ, α, n::Integer, args...) =
        StaggeredFiniteDifferences(log_lin_grid(ρₘᵢₙ, ρₘₐₓ, α, n::Integer), args...)

    StaggeredFiniteDifferences(ρₘᵢₙ::T, ρₘₐₓ::T, α::T, rₘₐₓ::T, args...) where {T<:Real} =
        StaggeredFiniteDifferences(log_lin_grid(ρₘᵢₙ, ρₘₐₓ, α, rₘₐₓ), args...)
end

locs(B::StaggeredFiniteDifferences) = B.r
# step is only well-defined for uniform grids
step(B::StaggeredFiniteDifferences{<:Any,<:AbstractRange}) = step(B.r)
# All-the-same, we define step for non-uniform grids to make the mass
# matrix and derivative stencils work properly.
step(B::StaggeredFiniteDifferences{T}) where T = one(T)
local_step(B::StaggeredFiniteDifferences, j) = local_step(B.r, j)

IntervalSets.leftendpoint(B::StaggeredFiniteDifferences{T}) where T = zero(T)
IntervalSets.rightendpoint(B::StaggeredFiniteDifferences{T}) where T = 2B.r[end]-B.r[end-1]

weight(B::StaggeredFiniteDifferences{T,<:AbstractRange}, _) where T = one(T)
weight(B::StaggeredFiniteDifferences, j) = 1/√(local_step(B, j))

weights(B::StaggeredFiniteDifferences{T,<:AbstractRange}) where T = ones(T, size(B,2))
weights(B::StaggeredFiniteDifferences) = weight.(Ref(B), 1:size(B,2))

inverse_weight(B::StaggeredFiniteDifferences{T,<:AbstractRange}, _) where T = one(T)
inverse_weight(B::StaggeredFiniteDifferences, j) = √(local_step(B, j))

inverse_weights(B::StaggeredFiniteDifferences{T,<:AbstractRange}) where T = ones(T, size(B,2))
inverse_weights(B::StaggeredFiniteDifferences) = inverse_weight.(Ref(B), 1:size(B,2))

==(A::StaggeredFiniteDifferences,B::StaggeredFiniteDifferences) = locs(A) == locs(B) && A.Z == B.Z && A.δβ₁ == B.δβ₁

show(io::IO, B::StaggeredFiniteDifferences{T}) where T =
    write(io, "Staggered finite differences basis {$T} on $(axes(B,1).domain) with $(size(B,2)) points")

show(io::IO, B::StaggeredFiniteDifferences{T,<:AbstractRange}) where T =
    write(io, "Staggered finite differences basis {$T} on $(axes(B,1).domain) with $(size(B,2)) points spaced by ρ = $(step(B))")

# ** Implicit finite differences
#=
This is an implementation of finite difference scheme described in

- Muller, H. G. (1999). An Efficient Propagation Scheme for the
  Time-Dependent Schrödinger equation in the Velocity Gauge. Laser
  Physics, 9(1), 138–148.

where the first derivative is approximated as

\[\partial f =
\left(1+\frac{h^2}{6}\Delta_2\right)^{-1}
\Delta_1 f
\equiv
M_1^{-1}\tilde{\Delta}_1 f,\]
where
\[M_1 \equiv
\frac{1}{6}
\begin{bmatrix}
4+\lambda' & 1 &\\
1 & 4 & 1\\
& 1 & 4 & \ddots\\
&&\ddots&\ddots\\
\end{bmatrix},\]
and
\[\tilde{\Delta}_1 \equiv
\frac{1}{2h}
\begin{bmatrix}
\lambda & 1 &\\
-1 &  & 1\\
& -1 &  & \ddots\\
&&\ddots&\ddots\\
\end{bmatrix},\]

where \(\lambda=\lambda'=\sqrt{3}-2\) for problems with a singularity
at the boundary \(r=0\) and zero otherwise; and the second derivative
as

\[\partial^2 f =
\left(1+\frac{h^2}{12}\Delta_2\right)^{-1}
\Delta_2 f
\equiv
-2M_2^{-1}\Delta_2 f,\]
where
\[M_2 \equiv
-\frac{1}{6}
\begin{bmatrix}
10-2\delta\beta_1 & 1 &\\
1 & 10 & 1\\
& 1 & 10 & \ddots\\
&&\ddots&\ddots\\
\end{bmatrix},\]
and
\[\Delta_2 \equiv
\frac{1}{h^2}
\begin{bmatrix}
-2(1+\delta\beta_1) & 1 &\\
1 & -2 & 1\\
& 1 & -2 & \ddots\\
&&\ddots&\ddots\\
\end{bmatrix},\]

where, again, \(\delta\beta_1 = -Zh[12-10Zh]^{-1}\) is a correction
introduced for problems singular at the origin.

=#

struct ImplicitFiniteDifferences{T,I} <: AbstractFiniteDifferences{T,I}
    j::UnitRange{I}
    Δx::T
    # Used for radial problems with a singularity at r = 0.
    λ::T
    δβ₁::T
end

function ImplicitFiniteDifferences(j::UnitRange{I}, Δx::T, singular_origin::Bool=false, Z=zero(T)) where {T<:Real,I<:Integer}
    λ,δβ₁ = if singular_origin
        first(j) == 1 ||
            throw(ArgumentError("Singular origin correction only valid when grid starts at Δx (i.e. `j[1] == 1`)"))
        # Eqs. (20,17), Muller (1999)
        (√3 - 2),(-Z*Δx/(12 - 10Z*Δx))
    else
        zero(T),zero(T)
    end
    ImplicitFiniteDifferences{T,I}(j, Δx, λ, δβ₁)
end

ImplicitFiniteDifferences(n::I, Δx::T, args...) where {T<:Real,I<:Integer} =
    ImplicitFiniteDifferences(1:n, Δx, args...)

locs(B::ImplicitFiniteDifferences) = B.j*B.Δx
step(B::ImplicitFiniteDifferences{T}) where {T} = B.Δx

IntervalSets.leftendpoint(B::ImplicitFiniteDifferences) = (B.j[1]-1)*step(B)
IntervalSets.rightendpoint(B::ImplicitFiniteDifferences) = (B.j[end]+1)*step(B)

show(io::IO, B::ImplicitFiniteDifferences{T}) where {T} =
    write(io, "Implicit finite differences basis {$T} on $(axes(B,1).domain) with $(size(B,2)) points spaced by Δx = $(B.Δx)")

mutable struct ImplicitDerivative{T,Tri,Mat,MatFact} <: AbstractMatrix{T}
    Δ::Tri
    M::Mat
    M⁻¹::MatFact
    c::T
end
ImplicitDerivative(Δ::Tri, M::Mat, c::T) where {T,Tri,Mat} =
    ImplicitDerivative(Δ, M, factorize(M), c)

Base.show(io::IO, ∂::ND) where {ND<:ImplicitDerivative} =
    write(io, "$(size(∂,1))×$(size(∂,2)) $(ND)")

Base.show(io::IO, ::MIME"text/plain", ∂::ND) where {ND<:ImplicitDerivative} =
    show(io, ∂)

Base.size(∂::ND, args...) where {ND<:ImplicitDerivative} = size(∂.Δ, args...)
Base.eltype(∂::ND) where {ND<:ImplicitDerivative} = eltype(∂.Δ)
Base.axes(∂::ND, args...) where {ND<:ImplicitDerivative} = axes(∂.Δ, args...)

Base.:(*)(∂::ND,a::T) where {T<:Number,ND<:ImplicitDerivative} =
    ImplicitDerivative(∂.Δ, ∂.M, ∂.M⁻¹, ∂.c*a)

Base.:(*)(a::T,∂::ND) where {T<:Number,ND<:ImplicitDerivative} =
    ∂ * a

Base.:(/)(∂::ND,a::T) where {T<:Number,ND<:ImplicitDerivative} =
    ∂ * inv(a)

function LinearAlgebra.mul!(y::Y, ∂::ND, x::X,
                            α::Number=true, β::Number=false) where {Y<:AbstractVector,
                                                                    ND<:ImplicitDerivative,
                                                                    X<:AbstractVector}
    mul!(y, ∂.Δ, x, α, β)
    ldiv!(∂.M⁻¹, y)
    lmul!(∂.c, y)
    y
end

function Base.copyto!(y::Y, ∂::Mul{<:Any,Tuple{<:ImplicitDerivative, X}}) where {X<:AbstractVector,Y<:AbstractVector}
    C = ∂.C
    mul!(C, ∂.A, ∂.B)
    lmul!(∂.α, C)
    C
end

for op in [:(+), :(-)]
    for Mat in [:Diagonal, :Tridiagonal, :SymTridiagonal, :UniformScaling]
        @eval begin
            function Base.$op(∂::ND, B::$Mat) where {ND<:ImplicitDerivative}
                B̃ = inv(∂.c)*∂.M*B
                ImplicitDerivative($op(∂.Δ, B̃), ∂.M, ∂.M⁻¹, ∂.c)
            end
        end
    end
end

struct ImplicitFactorization{TriFact,Mat}
    Δ⁻¹::TriFact
    M::Mat
end

Base.size(∂⁻¹::NF, args...) where {NF<:ImplicitFactorization} = size(∂⁻¹.M, args...)
Base.eltype(∂⁻¹::NF) where {NF<:ImplicitFactorization} = eltype(∂⁻¹.M)

LinearAlgebra.factorize(∂::ND) where {ND<:ImplicitDerivative} =
    ImplicitFactorization(factorize(∂.c*∂.Δ), ∂.M)

function LinearAlgebra.ldiv!(y, ∂⁻¹::NF, x) where {NF<:ImplicitFactorization}
    mul!(y, ∂⁻¹.M, x)
    ldiv!(∂⁻¹.Δ⁻¹, y)
    y
end

# * Projections

# Vandermonde interpolation for finite differences is equivalent to
# evaluating the function on the grid points, since the basis
# functions are orthogonal (in the sense of a quadrature) and there is
# no overlap between adjacent basis functions.
function Base.:(\ )(B::FiniteDifferencesOrRestricted, f::BroadcastQuasiArray)
    axes(f,1) == axes(B,1) ||
        throw(DimensionMismatch("Function on $(axes(f,1).domain) cannot be interpolated over basis on $(axes(B,1).domain)"))

    x = locs(B)
    getindex.(Ref(f), x) ./ weights(B)
end
