# check_for_updates_using_sugar_cubes.jl
#
# ~/.julia/dev/Doors main✔   ln -s  JULIA_SOURCE_PATH  sources

using Test
using SugarCubes: code_block_with, has_diff
# https://github.com/wookay/SugarCubes.jl

function check_the_code_block_diff(src_path::String,
                                   src_signature::Expr,
                                   dest_path::String,
                                   dest_signature::Expr ;
                                   skip_lines = (src = Int[], dest = Int[]))
    printstyled(stdout, "check_the_code_block_diff", color = :blue)
    print(stdout, " ", basename(src_path), " ")
    src_filepath = normpath(@__DIR__, "..", src_path)
    dest_filepath = normpath(@__DIR__, "..", dest_path)
    @test isfile(src_filepath)
    @test isfile(dest_filepath)
    src_block = code_block_with(; filepath = src_filepath, signature = src_signature)
    (depth, kind, sig) = src_block.signature.layers[end]
    printstyled(stdout, sig.args[1], color = :cyan)
    dest_block = code_block_with(; filepath = dest_filepath, signature = dest_signature)
    @test has_diff(src_block, dest_block; skip_lines) === false
    println(stdout)
end

check_the_code_block_diff(
    "sources/base/precompilation.jl",
    :(module Precompilation function monitor_background_precompile(io::IO = stderr, detachable::Bool = true, wait_for_pkg::Union{Nothing, PkgId} = nothing) end end),
    "ext/JuliaBasePrecompilationExt.jl",
    :(module JuliaBasePrecompilationExt if VERSION >= v"1.14.0-DEV.1963" function monitor_background_precompile(io::Base.PipeEndpoint = stderr, detachable::Bool = true, wait_for_pkg::Union{Nothing, PkgId} = nothing; key_controls::Bool = current_task() === Base.roottask) end end end) ;
    skip_lines = (src = vcat(41), dest = vcat(1:3, 44))
)
