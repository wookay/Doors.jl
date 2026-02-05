module JiveExt

using Jive: Jive
using Sockets

if VERSION >= v"1.11"
using Doors
using .Jive: Test

# from Jive.jl/src/errorshow.jl
import Jive: showable_stackframe
function showable_stackframe(frame::Base.StackTraces.StackFrame)::Bool
    TestExt = Base.get_extension(Jive, :TestExt)
    HIDE_STACKFRAME_IN_MODULES = Set([Doors, Jive, TestExt, Test, Base.Filesystem, Base.CoreLogging])
    if Base.parentmodule(frame) in HIDE_STACKFRAME_IN_MODULES
        return false
    else
        frame_file = String(frame.file)
        if frame.inlined && frame.func === Symbol("macro expansion")
            target_macro_expansions::Set{String} = Set([
                "Jive/src/compat.jl",
                "Jive/ext/TestExt.jl",
                "Test/src/Test.jl",
            ])
            for suffix in target_macro_expansions
                endswith(frame_file, suffix) && return false
            end
        elseif frame.inlined && frame.func === :serverRun && endswith(frame_file, "Doors/src/crystal_ship.jl")
            return false
        elseif !frame.inlined && frame.file === Symbol("./boot.jl") && Base.parentmodule(frame) === Core
            return false
        elseif !frame.inlined && frame.file === Symbol("./loading.jl") && (frame.func === :_include || frame.func === :include_string)
            return false
        elseif !frame.inlined && frame.file === Symbol("./Base.jl") && frame.func === :include
            return false
        end
        if VERSION >= v"1.13.0-DEV.1044" # julia commit bb36851288
            if !frame.inlined && Base.parentmodule(frame) === Base.ScopedValues && frame.func === :with &&
                Base.parentmodule(frame.linfo.specTypes.parameters[2]) === Jive
                return false
            end
        end
    end
    return true
end # function showable_stackframe

#=
# from Jive.jl/src/compat.jl
import Jive: jive_print_testset_verbose
function jive_print_testset_verbose(action::Symbol, ts::Test.AbstractTestSet)
    if action === :enter
        # @info ts.description
    end
end
=#

end # if VERSION >= v"1.11"


### precompile

#=  575.8 ms =# precompile(Tuple{typeof(Base.print), Sockets.TCPSocket, Jive.Total})

end # module JiveExt
