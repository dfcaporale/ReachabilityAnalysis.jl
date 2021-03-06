# types
export Flowpipe,
       ShiftedFlowpipe,
       MappedFlowpipe,
       HybridFlowpipe,
       MixedHybridFlowpipe

# methods
export flowpipe,
       project,
       shift

# convenience constructors
export Projection,
       Shift

# ================================
# Abstract types
# ================================

"""
    AbstractFlowpipe

Abstract type representing a flowpipe.

### Notes

A flowpipe is the set union of an array of reach-sets.
"""
abstract type AbstractFlowpipe end

"""
    basetype(T::Type{<:AbstractFlowpipe})

Return the base type of the given flowpipe type (i.e., without type parameters).

### Input

- `T` -- flowpipe type, used for dispatch

### Output

The base type of `T`.
"""
basetype(T::Type{<:AbstractFlowpipe}) = Base.typename(T).wrapper

# LazySets interface: a flowpipe behaves like the union of the reach-sets (UnionSetArray)
LazySets.ρ(d::AbstractVector, fp::AbstractFlowpipe) = ρ(d, UnionSetArray(array(R)))
LazySets.σ(d::AbstractVector, fp::AbstractFlowpipe) = σ(d, UnionSetArray(array(R)))
function LazySets.dim(fp::AbstractFlowpipe)
    @assert !iszero(fp) "the dimension is not defined because this flowpipe is empty"
    return dim(first(fp)) # it is assumed that the sets do not change dimension (!)
end

# iteration interface
@inline Base.iterate(fp::AbstractFlowpipe) = iterate(array(fp))
@inline Base.iterate(fp::AbstractFlowpipe, state) = iterate(array(fp), state)
@inline Base.length(fp::AbstractFlowpipe) = length(array(fp))
@inline Base.first(fp::AbstractFlowpipe) = getindex(fp, 1)
@inline Base.last(fp::AbstractFlowpipe) = getindex(fp, lastindex(fp))
@inline Base.firstindex(fp::AbstractFlowpipe) = 1
@inline Base.lastindex(fp::AbstractFlowpipe) = length(array(fp))
@inline Base.eachindex(fp::AbstractFlowpipe) = eachindex(array(fp))

# support abstract reach set interface
set(fp::AbstractFlowpipe) = throw(ArgumentError("to retrieve the array of sets represented by this flowpipe, " *
    "use the `array(...)` function, or use the function `set(...)` at a specific index, i.e. " *
    "`set(F[ind])`, or simply `set(F, ind)`, to get the reach-set with index `ind` of the flowpipe `F`"))
set(fp::AbstractFlowpipe, ind::Integer) = set(getindex(array(fp), ind))

# time domain interface
@inline tstart(fp::AbstractFlowpipe) = tstart(first(fp))
@inline tend(fp::AbstractFlowpipe) = tend(last(fp))
@inline tspan(fp::AbstractFlowpipe) = TimeInterval(tstart(fp), tend(fp))

# support indexing with ranges or with vectors of integers
# TODO add bounds checks?
Base.getindex(fp::AbstractFlowpipe, i::Int) = getindex(array(fp), i)
Base.getindex(fp::AbstractFlowpipe, i::Number) = getindex(array(fp), convert(Int, i))
Base.getindex(fp::AbstractFlowpipe, I::AbstractVector) = getindex(array(fp), I)

# get the set of the flowpipe with the given index
#function Base.getindex(fp::AbstractFlowpipe, t::Number)
    # annotate as a boundscheck
#    1 <= i <= length(fp) || throw(BoundsError(fp, i))
#    return getindex(fp, i)

#=
function Projection(fp::Flowpipe, vars::NTuple{D, T}) where {D, T<:Integer}

end
=#

#=
# inplace projection
function project!(fp::AbstractFlowpipe, vars::NTuple{D, T}) where {D, T<:Integer}
    Xk = array(fp)
    for X in Xk
        _project!(set(X), vars)
    end
    return fp
end
=#

# ================================
# Flowpipes
# ================================

"""
    Flowpipe{N, RT<:AbstractReachSet{N}} <: AbstractFlowpipe

Type that wraps a flowpipe.

### Fields

- `Xk`  -- set
- `ext` -- extension dictionary; field used by extensions

### Notes

The dimension of the flowpipe corresponds to the dimension of the underlying
reach-sets; in this type, it is is assumed that the dimension is the same for
the different reach-sets.
"""
struct Flowpipe{N, RT<:AbstractReachSet{N}} <: AbstractFlowpipe
    Xk::Vector{RT}
    ext::Dict{Symbol, Any}
end

# getter functions
@inline array(fp::Flowpipe) = fp.Xk
@inline flowpipe(fp::Flowpipe) = fp

# constructor from empty extension dictionary
function Flowpipe(Xk::Vector{RT}) where {N, RT<:AbstractReachSet{N}}
    return Flowpipe(Xk, Dict{Symbol, Any}())
end

Base.IndexStyle(::Type{<:Flowpipe}) = IndexLinear()
setrep(fp::Flowpipe{N, RT}) where {N, RT} = setrep(RT)
setrep(::Type{Flowpipe{N, RT}}) where {N, RT} = setrep(RT)

# evaluate a flowpipe at a given time point: gives a reach set
# here it would be useful to layout the times contiguously in a vector
# (see again array of struct vs struct of array)
function (fp::AbstractFlowpipe)(t::Number)
    Xk = array(fp)
    @inbounds for (i, X) in enumerate(Xk)
        if t ∈ tspan(X) # exit on the first occurrence
            if i < length(Xk) && t ∈ tspan(Xk[i+1])
                return view(Xk, i:i+1)
            else
                return fp[i]
            end
        end
    end
    throw(ArgumentError("time $t does not belong to the time span, " *
                        "$(tspan(fp)), of the given flowpipe"))
end

# evaluate a flowpipe at a given time interval: gives possibly more than one reach set
# i.e. first and last sets and those in between them
function (fp::Flowpipe)(dt::TimeInterval)
    # here we assume that indices are one-based, ie. form 1 .. n
    firstidx = 0
    lastidx = 0
    α = inf(dt)
    β = sup(dt)
    Xk = array(fp)
    for (i, X) in enumerate(Xk)
        if α ∈ tspan(X)
            firstidx = i
        end
        if β ∈ tspan(X)
            lastidx = i
        end
    end
    if firstidx == 0 || lastidx == 0
        throw(ArgumentError("the time interval $dt is not contained in the time span, " *
                            "$(tspan(fp)), of the given flowpipe"))
    end
    return view(Xk, firstidx:lastidx)
end

function project(fp::Flowpipe, vars::NTuple{D, T}) where {D, T<:Integer}
    Xk = array(fp)
    # TODO: use projection of the reachsets
    if 0 ∈ vars # projection includes "time"
        # we shift the vars indices by one as we take the Cartesian prod with the time spans
        aux = vars .+ 1
        return map(X -> _project(convert(Interval, tspan(X)) × set(X), aux), Xk)
    else
        return map(X -> _project(set(X), vars), Xk)
    end
end

function Base.similar(fp::Flowpipe{N, RT}) where {N, RT<:AbstractReachSet{N}}
   return Flowpipe(Vector{RT}())
end

"""
    shift(fp::Flowpipe{N, ReachSet{N, ST}}, t0::Number) where {N, ST}

Return the time-shifted flowpipe by the given number.

### Input

- `fp` -- flowpipe
- `t0` -- time shift

### Output

A new flowpipe such that the time-span of each constituent reach-set has been
shifted by `t0`.

### Notes

See also `Shift` for the lazy counterpart.
"""
function shift(fp::Flowpipe{N, ReachSet{N, ST}}, t0::Number) where {N, ST}
    return Flowpipe([shift(X, t0) for X in array(fp)], fp.ext)
end

# =======================================
# Flowpipe composition with a time-shift
# =======================================

"""
    ShiftedFlowpipe{FT<:AbstractFlowpipe, NT<:Number} <: AbstractFlowpipe

Type that lazily represents a flowpipe that has been shifted in time.

### Fields

- `F`  -- original flowpipe
- `t0` -- time shift

### Notes

This type can wrap any concrete subtype of `AbstractFlowpipe`, and the extra
field `t0` is such that the time spans of each reach-set in `F` are shifted
by the amount `t0` (which should be a subtype of `Number`).

A convenience constructor alias `Shift` is given.
"""
struct ShiftedFlowpipe{FT<:AbstractFlowpipe, NT<:Number} <: AbstractFlowpipe
    F::FT
    t0::NT
end

# getter functions
@inline array(fp::ShiftedFlowpipe) = array(fp.F)
@inline flowpipe(fp::ShiftedFlowpipe) = fp.F
@inline time_shift(fp::ShiftedFlowpipe) = fp.t0

# alias
const Shift = ShiftedFlowpipe

# time domain interface
@inline tstart(fp::ShiftedFlowpipe) = tstart(first(fp)) + time_shift(fp)
@inline tend(fp::ShiftedFlowpipe) = tend(last(fp)) + time_shift(fp)
@inline tspan(fp::ShiftedFlowpipe) = TimeInterval(tstart(fp), tend(fp))

# =====================================
# Flowpipe composition with a lazy map
# =====================================

"""
    MappedFlowpipe{FT<:AbstractFlowpipe, ST} <: AbstractFlowpipe

### Fields

- `F`    -- flowpipe
- `func` -- function representing the map
"""
struct MappedFlowpipe{FT<:AbstractFlowpipe, ST} <: AbstractFlowpipe
    F::FT
    func::ST
end

"""
    Projection(fp::AbstractFlowpipe, vars::NTuple{D, T}) where {D, T<:Integer}

Return the lazy projection of a flowpipe.

### Input

### Output

### Notes

The projection is lazy, and consists of mapping each set
`X` in the flowpipe to `MX`, where `M` is the projection matrix associated with
the given variables `vars`.
"""
function LazySets.Projection(fp::AbstractFlowpipe, vars::NTuple{D, T}) where {D, T<:Integer}
    # TODO: assert that vars belong to the variables of the flowpipe
    M = projection_matrix(collect(vars), dim(F), Float64)
    func = @map(x -> M*x)
    return MappedFlowpipe(fp, func)
end

# ================================
# Hybrid flowpipe
# ================================

"""
    HybridFlowpipe{N, D, FT<:AbstractFlowpipe, VOA<:VectorOfArray{N, D, Vector{FT}}} <: AbstractFlowpipe

Type that wraps a vector of flowpipes of possibly differen types.

### Fields

- `Fk`  -- vector of flowpipes
- `ext` -- (optional, default: empty) dictionary for extensions

### Notes
"""
struct HybridFlowpipe{N, D, FT<:AbstractFlowpipe} <: AbstractFlowpipe
    Fk::VectorOfArray{N, D, Vector{FT}}
    ext::Dict{Symbol, Any}
end

array(fp::HybridFlowpipe) = fp.Xk

#=
#dim(fp::Flowpipe{ST, RT}) where {ST, RT<:AbstractReachSet{ST}} = dim(first(fp.Xk))
# Base.getindex
=#

#=
# define the projection lazily?
# project(fp::Flowpipe, args; kwargs) -> lazy flowpipe with time
function project(fp::Flowpipe, args...; kwargs...)

    for X in fp.Xk # sets(fp.Xk)
        project(X, args...; kwargs...)
    end
end
=#

#=
"""
    project(Rsets, options)

Projects a sequence of sets according to the settings defined in the options.

### Input

- `Rsets`   -- solution of a reachability problem
- `options` -- options structure

### Notes

A projection matrix can be given in the options structure, or passed as a
dictionary entry.
"""
function project(Rsets::Vector{<:AbstractReachSet}, options::AbstractOptions)
    return project_reach(Rsets, options[:plot_vars], options)
end

TODO:

-> project a flowpipe

# helper function to take the cartesian product with the time variable
#fp::Flowpipe{FT, ST} where {FT, ST}


function add_time()
    flowpipe_with_time = Vector{ReachSet{CartesianProduct{Float64, IT64, ST}}}()
    add_time!()
end

function add_time!(F::Flowpipe{ST}) where {ST}
    @inbounds for X in fp
        Δt = X.Δt
        push!(fp, ReachSet(Δt × set(X), Δt))
    end
    return flowpipe_with_time
end
=#

# ============================================
# Hybrid flowpipe of possibly different types
# ============================================

"""
    MixedHybridFlowpipe{N, D, FT<:AbstractFlowpipe, VOA<:VectorOfArray{N, D, Vector{FT}}} <: AbstractFlowpipe

Type that wraps a vector of flowpipes of possibly different types.

### Fields

- `Fk`  -- vector of flowpipes
- `ext` -- (optional, default: empty) dictionary for extensions

### Notes
"""
struct MixedHybridFlowpipe{T, S<:Tuple} <: AbstractFlowpipe # TODO: ask <:AbstractFlowpipe for each element in the tuple..?
    Fk::ArrayPartition{T, S}
    ext::Dict{Symbol, Any}
end
