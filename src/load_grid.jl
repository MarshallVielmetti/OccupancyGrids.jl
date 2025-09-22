module LoadGrid
"""
    LoadGrid

This module provides functionality for loading and working with occupancy grids.

Grids can be loaded from various sources:
1. A directory containing a 'grid_info.yaml' file with metadata, and the actual grid data files.
2. A GridInfo object that contains the necessary metadata, and the data object (passed seperately).
3. Pass an IncludedGrid enum value to load an included grid object.
"""

export load_grid, GridInfo

using StaticArrays, YAML
using Base.Enums

using ..FileUtil

## IMPORTANT: When adding new included grids, update the enum, 
## export statement, and package level export (yes this is annoying)
export IncludedGrid, WillowGarage, SimpleIndoor, SimpleIndoor1, SimpleIndoor1Large, SimpleIndoor2
@enum IncludedGrid WillowGarage SimpleIndoor SimpleIndoor1 SimpleIndoor1Large SimpleIndoor2

const BASE_PATH = joinpath(@__DIR__, "..", "maps")

const INCLUDED_GRID_INFO = Dict(
    WillowGarage => joinpath(BASE_PATH, "willow_garage"),
    SimpleIndoor => joinpath(BASE_PATH, "simple_indoor"),
    SimpleIndoor1 => joinpath(BASE_PATH, "simple_indoor_1"),
    SimpleIndoor1 => joinpath(BASE_PATH, "simple_indoor_1_large"),
    SimpleIndoor2 => joinpath(BASE_PATH, "simple_indoor_2")
)

"""
    GridInfo

A struct containing metadata about an occupancy grid.

# Fields
- `file_type::String`: The file type of the grid data (e.g., "pgm").
- `grid_file::String`: The name of the file containing the grid data.
- `resolution::Float64`: The resolution of the grid in meters per cell.
- `origin::SVector{3,Float64}`: The 3D origin of the grid in world coordinates.
- `negate::Bool`: Whether to negate the occupancy values.
- `occuped_threshold::Float64`: The threshold for a cell to be considered occupied.
- `free_threshold::Float64`: The threshold for a cell to be considered free.
"""
struct GridInfo
    file_type::String
    grid_file::String

    resolution::Float64
    origin::SVector{3,Float64}
    negate::Bool
    occuped_threshold::Float64
    free_threshold::Float64
end

"""
    load_grid(grid::IncludedGrid)

Load a grid from the included grids defined in `INCLUDED_GRID_INFO`. This is a convenience
function for loading maps that are packaged with this library.
"""
function load_grid(grid::IncludedGrid; kwargs...)
    return load_grid(INCLUDED_GRID_INFO[grid]; kwargs...)
end

"""
    load_grid(directory::AbstractString)

Load a grid from a directory. The directory must contain a `grid_info.yaml` file with
metadata about the grid, and the grid data file itself (e.g., a PGM file).
"""
function load_grid(directory::AbstractString; kwargs...)
    info = load_grid_info(directory)
    data = load_grid_data(directory, info)
    return load_grid(info, data; kwargs...)
end

"""
    load_grid(info::GridInfo, data)

Construct a concrete `OccupancyGrid` from a `GridInfo` object and the grid data.
This method must be implemented by concrete grid types (e.g., `DenseOccupancyGrid`).
"""
function load_grid(info::GridInfo, data)
    throw(MethodError(load_grid, (info, data)))
end

"""
    load_grid_info(directory::AbstractString)::GridInfo

Load grid metadata from a `grid_info.yaml` file in the specified directory.

The YAML file can contain the following fields:
- `file_type`: (Optional) The file type of the grid data (default: "pgm").
- `grid_file`: (Optional) The name of the grid data file (default: "grid.pgm").
- `resolution`: (Optional) The grid resolution in meters per cell (default: 0.1).
- `origin`: (Optional) The 3D grid origin (default: [0.0, 0.0, 0.0]).
- `negate`: (Optional) Whether to negate occupancy values (default: false).
- `occupied_threshold`: (Optional) Occupancy threshold (default: 0.65).
- `free_threshold`: (Optional) Free space threshold (default: 0.35).
"""
function load_grid_info(directory::AbstractString)::GridInfo
    info_path = joinpath(directory, "grid_info.yaml")

    info = YAML.load_file(info_path)

    file_type = get(info, "file_type", "pgm")
    grid_file = get(info, "grid_file", "grid.pgm")

    resolution = get(info, "resolution", 0.1)
    origin = get(info, "origin", [0.0, 0.0, 0.0])
    negate = get(info, "negate", false)

    occupied_threshold = get(info, "occupied_threshold", 0.65)
    free_threshold = get(info, "free_threshold", 0.35)

    return GridInfo(file_type, grid_file, resolution, SVector{3,Float64}(origin), negate, occupied_threshold, free_threshold)
end

"""
    load_grid_data(directory::AbstractString, info::GridInfo)

Load the grid data from the file specified in the `GridInfo` object.
Currently, only PGM files are supported.
"""
function load_grid_data(directory::AbstractString, info::GridInfo)
    data_path = joinpath(directory, info.grid_file)
    if info.file_type == "pgm"
        return load_pgm(data_path)
    end

    throw(ArgumentError("Unsupported file type: $(info.file_type)"))
end


end # module LoadGrid
