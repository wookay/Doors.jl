module JuliaBasePrecompilationExt

# wait until fix the issue #3
if VERSION >= v"1.14.0-DEV.1963" # julia commit cb2e1ecf24

include("BasePrecompilation43e9d32010.jl")
using .BasePrecompilation43e9d32010: _precompilepkgs

__precompile__(false)

import Base.Precompilation: precompilepkgs
using Base.Precompilation: Config, PkgId, can_fancyprint

# from julia/base/precompilation.jl
#=
function precompilepkgs(pkgs::Union{Vector{String}, Vector{PkgId}}=String[];
                        internal_call::Bool=false,
                        strict::Bool = false,
                        warn_loaded::Bool = true,
                        timing::Bool = false,
                        _from_loading::Bool=false,
                        configs::Union{Config,Vector{Config}}=(``=>Base.CacheFlags()),
                        io::IO=stderr,
                        # asking for timing disables fancy mode, as timing is shown in non-fancy mode
                        fancyprint::Bool = can_fancyprint(io) && !timing,
                        manifest::Bool=false,
                        ignore_loaded::Bool=true,
                        detachable::Bool=false)
=#
function precompilepkgs(pkgs::Union{Vector{String}, Vector{PkgId}}=String[];
                        internal_call::Bool=false,
                        strict::Bool = false,
                        warn_loaded::Bool = true,
                        timing::Bool = false,
                        _from_loading::Bool=false,
                        configs::Union{Config,Vector{Config}}=(``=>Base.CacheFlags()),
                        io::IOContext{Base.PipeEndpoint}=stderr, #
                        # asking for timing disables fancy mode, as timing is shown in non-fancy mode
                        fancyprint::Bool = can_fancyprint(io) && !timing,
                        manifest::Bool=false,
                        ignore_loaded::Bool=true,
                        detachable::Bool=false)
    @debug "precompilepkgs called with" pkgs internal_call strict warn_loaded timing _from_loading configs fancyprint manifest ignore_loaded
    # monomorphize this to avoid latency problems
    _precompilepkgs(pkgs, internal_call, strict, warn_loaded, timing, _from_loading,
                    configs isa Vector{Config} ? configs : [configs],
                    IOContext{IO}(io), fancyprint, manifest, ignore_loaded)
end # function precompilepkgs

end # if VERSION >= v"1.14.0-DEV.1963"

end # module JuliaBasePrecompilationExt
