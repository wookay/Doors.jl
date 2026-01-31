module JiveExt

if VERSION >= v"1.11"
using Jive
using Doors
using IOCapture

HIDE_STACKFRAME_IN_MODULES = Set([Jive, Doors, IOCapture, Base.Filesystem, Base.CoreLogging])

# from Jive.jl/src/errorshow.jl
import Jive: showable_stackframe
function showable_stackframe(frame::Base.StackTraces.StackFrame)::Bool
    if Base.parentmodule(frame) in HIDE_STACKFRAME_IN_MODULES
        return false
    elseif frame.func === Symbol("macro expansion")
        target_macro_expansions::Set{String} = Set([
            "Jive/src/runtests.jl",
          # "Jive/src/compat.jl",
            "Test/src/Test.jl",
        ])
        frame_file = String(frame.file)
        for suffix in target_macro_expansions
            endswith(frame_file, suffix) && return false
        end
    elseif frame.func === :include && frame.file === Symbol("./Base.jl")
        return false
    end
    return true
end # function showable_stackframe

end # if VERSION >= v"1.11"

end # module JiveExt
