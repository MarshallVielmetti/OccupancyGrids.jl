"""
    DenseGrid

This module implements a dense occupancy grid, where the grid is represented by a
dense matrix. This is a straightforward implementation of the `OccupancyGrid`
interface.
"""
module DenseGrid

export DenseOccupancyGrid

using DSP, DataStructures
using ..AbstractGrids
using ..LoadGrid
using RecipesBase

"""
    DenseOccupancyGrid{T<:Real} <: OccupancyGrid

A concrete implementation of an occupancy grid using a dense matrix.

# Fields
- `data::Matrix{T}`: The matrix holding the occupancy values. The type `T` is typically a subtype of `Real` (e.g., `Float64`).
- `sdf::Union{Nothing, Matrix{T}}`: The signed distance field (optional).
- `grid_resolution::Float64`: The resolution of the grid in meters per cell.
- `inv_resolution::Float64`: The inverse of the resolution, pre-calculated for efficiency in coordinate transformations.
- `occupied_threshold::Float64`: The threshold above which a cell is considered occupied.
- `free_threshold::Float64`: The threshold below which a cell is considered free.

# Keyword Arguments
- `inflation::Float64`: The inflation radius in meters. Obstacles will be inflated by this amount. Defaults to `0.0`.
- `negate::Bool`: If `true`, the input `data` is negated (i.e., `1.0 - data`). This is useful when the input data has `1` for free and `0` for occupied. Defaults to `false`.
- `compute_sdf::Bool`: If `true`, the signed distance field (SDF) will be computed during initialization. Defaults to `true`.
"""
struct DenseOccupancyGrid{T<:Real} <: OccupancyGrid
    data::Matrix{T}
    sdf::Union{Nothing,Matrix{T}} # Optional ESDF
    grid_resolution::Float64  # meters per cell
    inv_resolution::Float64   # 1/grid_resolution for efficiency
    occupied_threshold::Float64
    free_threshold::Float64

    function DenseOccupancyGrid{T}(data::Matrix{T}, resolution::Float64, occupied_threshold::Float64, free_threshold::Float64; inflation::Float64=0.0, negate::Bool=false, compute_sdf::Bool=true) where {T<:Real}
        # This is weird -- 0 is free, 1 is occupied. But 1 is white, 0 is black.
        if !negate
            data .= 1.0 .- data
        end

        if inflation != 0.0
            inflate_obstacles!(data, ceil(Int, inflation / resolution))
        end

        sdf = nothing
        if compute_sdf
            sdf = compute_signed_distance_field(data, resolution, free_threshold)
        end

        new{T}(data, sdf, resolution, 1.0 / resolution, occupied_threshold, free_threshold)
    end
end

"""
    inflate_obstacles!(data::Matrix{T}, inflation_cells::Int) where {T<:Real}

Inflates obstacles in the grid by a given number of cells.

This function uses convolution with a kernel of ones to expand the occupied regions.
The result is clamped between 0.0 and 1.0.

# Arguments
- `data::Matrix{T}`: The occupancy grid data, modified in-place.
- `inflation_cells::Int`: The number of cells to inflate obstacles by.
"""
function inflate_obstacles!(data::Matrix{T}, inflation_cells::Int) where {T<:Real}
    kernel = ones(inflation_cells, inflation_cells)
    new_data = conv(data, kernel)
    # Trim new data matrix to the original size, taking from the center

    rows, cols = size(data)
    start_row = ceil(Int, inflation_cells / 2)
    start_col = ceil(Int, inflation_cells / 2)
    end_row = start_row + rows - 1
    end_col = start_col + cols - 1

    data .= clamp.(new_data[start_row:end_row, start_col:end_col], 0.0, 1.0)
end

"""
    DenseOccupancyGrid(data::Matrix{T}, resolution::Float64, occupied_threshold::Float64, free_threshold::Float64; kwargs...) where {T<:Real}

A convenience constructor that delegates to the inner `DenseOccupancyGrid{T}` constructor.
"""
DenseOccupancyGrid(data::Matrix{T}, resolution::Float64, occupied_threshold::Float64, free_threshold::Float64; kwargs...) where {T<:Real} = DenseOccupancyGrid{T}(data, resolution, occupied_threshold, free_threshold; kwargs...)

"""
    DenseOccupancyGrid(data::Matrix{T}, resolution::Float64; kwargs...) where {T<:Real}

A convenience constructor that uses default thresholds for `occupied_threshold` (0.65) and `free_threshold` (0.35).
"""
DenseOccupancyGrid(data::Matrix{T}, resolution::Float64; kwargs...) where {T<:Real} = DenseOccupancyGrid{T}(data, resolution, 0.65, 0.35; kwargs...)

"""
    is_occupied(grid::DenseOccupancyGrid, x::Real, y::Real) -> Bool

Checks if the specified world coordinates are occupied in the dense grid.

Converts the world coordinates (x, y) into matrix indices and checks the corresponding
cell's value against the free_threshold. Returns true if the cell value is greater
than the free_threshold.

# Throws
- `BoundsError` if the coordinates `(x, y)` are outside the grid's boundaries.
"""
function AbstractGrids.is_occupied(grid::DenseOccupancyGrid, x::Real, y::Real)
    # Convert coordinates to indices (1-based) using pre-computed inverse
    # x corresponds to columns (j), y corresponds to rows (i)
    j = Int(floor(x * grid.inv_resolution)) + 1  # column index from x
    i = Int(floor(y * grid.inv_resolution)) + 1  # row index from y

    # Bounds check with early return for out-of-bounds
    # Check rows (i) against size(..., 1) and columns (j) against size(..., 2)
    if i < 1 || i > size(grid.data, 1) || j < 1 || j > size(grid.data, 2)
        throw(BoundsError(grid, (i, j)))
    end

    return grid.data[i, j] > grid.free_threshold
end

function AbstractGrids.sdf(grid::DenseOccupancyGrid, x::Real, y::Real)
    if isnothing(grid.sdf)
        throw(MethodError(sdf, (grid, x, y), "The signed distance field (SDF) has not been computed for this grid (requires compute_sdf = true)."))
    end

    # Convert coordinates to indices (1-based) using pre-computed inverse
    j = Int(floor(x * grid.inv_resolution)) + 1  # column index from x
    i = Int(floor(y * grid.inv_resolution)) + 1  # row index from y

    # Bounds check with early return for out-of-bounds
    if i < 1 || i > size(grid.sdf, 1) || j < 1 || j > size(grid.sdf, 2)
        throw(BoundsError(grid, (i, j)))
    end

    return grid.sdf[i, j]
end

"""
    Base.size(grid::DenseOccupancyGrid) -> Tuple{Float64, Float64}

Returns the physical dimensions of the grid in world coordinates (meters).

Returns (width, height) corresponding to (x_max, y_max) in world coordinates.
"""
function Base.size(grid::DenseOccupancyGrid)::Tuple{Float64,Float64}
    rows, cols = size(grid.data)
    # Return (width, height) = (x_extent, y_extent) = (cols * resolution, rows * resolution)
    return (cols * grid.grid_resolution, rows * grid.grid_resolution)
end

"""
    load_grid(info::GridInfo, data::Matrix{T}) where {T<:Real} -> DenseOccupancyGrid{T}

A factory method to construct a `DenseOccupancyGrid` from a `GridInfo` object and
a data matrix.

This function is part of the `LoadGrid` interface and allows for the creation of a
`DenseOccupancyGrid` when loading a grid from a file. Uses the thresholds specified
in the GridInfo object.
"""
function LoadGrid.load_grid(info::GridInfo, data::Matrix{T}; kwargs...)::DenseOccupancyGrid{T} where {T<:Real}
    return DenseOccupancyGrid(data, info.resolution, info.occuped_threshold, info.free_threshold; kwargs...)
end

function compute_signed_distance_field(data::Matrix{T}, resolution::Float64, free_threshold::Float64) where {T<:Real}
    rows, cols = size(data)
    sdf = fill(Inf, size(data)) # Initialize SDF with Inf

    q = Queue{Tuple{Int,Int,Float64}}() # (i, j, distance)

    # Initialize the queue with all occupied cells (distance = 0)
    for i in 1:rows
        for j in 1:cols
            if data[i, j] > free_threshold
                sdf[i, j] = 0.0
                enqueue!(q, (i, j, 0.0))
            end
        end
    end

    # Perform a breadth-first search (BFS) to compute the SDF
    while !isempty(q)
        (i, j, current_dist) = dequeue!(q)

        # If current cell already has a shorter distance, skip it
        if current_dist < sdf[i, j]
            continue
        end

        # Check neighboring cells (4-connectivity)
        new_dist = current_dist + resolution
        for (di, dj) in [(-1, 0), (1, 0), (0, -1), (0, 1)]
            ni, nj = i + di, j + dj

            # If neighbor cell is in bounds
            if ni >= 1 && ni <= rows && nj >= 1 && nj <= cols
                # If we found a shorter path to this neighbor
                if new_dist < sdf[ni, nj]
                    sdf[ni, nj] = new_dist
                    enqueue!(q, (ni, nj, new_dist))
                end
            end
        end
    end

    return sdf
end

"""
    plot!(grid::DenseOccupancyGrid; kwargs...)
    plot(grid::DenseOccupancyGrid; kwargs...)

Plots the occupancy grid as a heatmap using Plots.jl.
"""
@recipe function f(grid::DenseOccupancyGrid)

    # Get the occupancy grid data
    grid_data = grid.data
    grid_resolution = grid.grid_resolution

    # Create inverted colormap (0 = white, 1 = black)
    inverted_data = 1.0 .- grid_data

    # Calculate proper coordinate ranges
    n_rows, n_cols = size(grid_data)
    x_range = range(0, n_cols * grid_resolution, length=n_cols)
    y_range = range(0, n_rows * grid_resolution, length=n_rows)

    # Plot as heatmap background with proper coordinates
    @series begin
        seriestype := :heatmap
        colormap --> :grays
        alpha --> 0.8
        aspect_ratio --> :equal
        x_range, y_range, inverted_data
    end
end

end # module DenseGrid
