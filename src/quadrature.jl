# * Linear interpolation

# https://github.com/JuliaLang/julia/pull/18777
lerp(a::T,b::T,t) where T = T(fma(t, b, fma(-t, a, a)))
lerp(a::R,b::R,t::C) where {R<:Real,C<:Complex} = lerp(a,b,real(t)) + im*lerp(a,b,imag(t))
lerp(a::C,b::C,t::R) where {R<:Real,C<:Complex} = lerp(real(a),real(b),t) + im*lerp(imag(a),imag(b),(t))

# * Gaußian quadrature

"""
    change_interval!(xs, ws, x, w[, a=0, b=1, γ=1])

Transform the Gaußian quadrature roots `x` and weights `w` on the
elementary interval `[-1,1]` to the interval `[γ*a,γ*b]` and store the
result in `xs` and `ws`, respectively. `γ` is an optional root of
unity, used to complex-rotate the roots (but not the weights).
"""
function change_interval!(xs::AbstractVector{T}, ws, x, w,
                          a=zero(T), b=one(T), γ=one(T)) where T
    xs .= lerp.(γ*a, γ*b, (x .+ 1)/2)
    ws .= (b-a)*w/2
    xs,ws
end

change_interval(x::AbstractVector{T}, w::AbstractVector{T},
                a=zero(T), b=one(T), γ::U=one(T)) where {T,U} =
    change_interval!(similar(x,U), similar(w), x, w, a, b)

# * Gauß–Legendre quadrature

"""
    num_quadrature_points(k, k′)

The number of quadrature points needed to exactly compute the matrix
elements of an operator of polynomial order `k′` with respect to a
basis of order `k`.
"""
function num_quadrature_points(k, k′)
    N2 = 2*(k-1) + k′
    N2>>1 + N2&1
end

"""
    lgwt(t, N) -> (x,w)

Generate the `N` Gauß–Legendre quadrature roots `x` and associated
weights `w`, with respect to the B-spline basis generated by the knot
set `t`.

# Examples

```jldoctest
julia> CompactBases.lgwt(LinearKnotSet(2, 0, 1, 3), 2)
([0.0704416, 0.262892, 0.403775, 0.596225, 0.737108, 0.929558], [0.166667, 0.166667, 0.166667, 0.166667, 0.166667, 0.166667])

julia> CompactBases.lgwt(ExpKnotSet(2, -4, 2, 7), 2)
([2.11325e-5, 7.88675e-5, 0.000290192, 0.000809808, 0.00290192, 0.00809808, 0.0290192, 0.0809808, 0.290192, 0.809808, 2.90192, 8.09808, 29.0192, 80.9808], [5.0e-5, 5.0e-5, 0.00045, 0.00045, 0.0045, 0.0045, 0.045, 0.045, 0.45, 0.45, 4.5, 4.5, 45.0, 45.0])
```
"""
function lgwt(t::AbstractKnotSet{k,ml,mr,T}, N) where {k,ml,mr,T}
    2N-1 ≥ 2(k-1) || @warn "N = $N quadrature point$(N > 1 ? "s" : "") not enough to calculate overlaps between polynomials of order k = $k"
    x, w = gausslegendre(N)

    nei = nonempty_intervals(t)
    ni = length(nei)
    xo = zeros(T, ni*length(x))
    wo = zeros(T, ni*length(x))

    for (i,j) in enumerate(nei)
        sel = (i-1)*N+1 : i*N
        change_interval!(view(xo, sel), view(wo, sel),
                         x, w,
                         t[j], t[j+1])
    end

    xo,wo
end

# * Gauß–Lobatto

function element_grid(order, a::T, b::T, c::T=zero(T), eiϕ=one(T)) where T
    x,w = gausslobatto(order)
    xs,ws = change_interval(x, w, a-c, b-c, eiϕ)
    c .+ xs, ws
end
