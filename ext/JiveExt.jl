module JiveExt

using Base.StackTraces: StackFrame
using Jive
using Doors
using IOCapture

import Jive: check_to_hide_the_stackframe
function check_to_hide_the_stackframe(frame::StackFrame)::Bool
    HIDE_STACKFRAME_IN_MODULES = [Jive, Doors, IOCapture, Base.Filesystem, Base.CoreLogging]
    if Base.parentmodule(frame) in HIDE_STACKFRAME_IN_MODULES
        return true
    elseif frame.func === Symbol("macro expansion")
        target_macro_expansions::Set{String} = Set([
            "Test/src/Test.jl",
        ])
        frame_file = String(frame.file)
        for suffix in target_macro_expansions
            endswith(frame_file, suffix) && return true
        end
    elseif frame.func === :include && frame.file === Symbol("./Base.jl")
        return true
    end
    return false
end

end # module JiveExt
