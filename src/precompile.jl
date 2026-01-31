# module Doors

precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:into,), Tuple{Module}}, Type{Doors.App}})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:into,), Tuple{Module}}, typeof(Doors.serve), Int64})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:port, :into), Tuple{typeof(Base.any), Module}}, typeof(Doors.create_app)})
precompile(Tuple{typeof(Base.getproperty), Doors.App, Symbol})
precompile(Tuple{typeof(Doors.runfile), String, String, Array{String, 1}, UInt16})
precompile(Tuple{typeof(Doors.runexpr), String, UInt16})
precompile(Tuple{typeof(Doors.runexpr), Expr, UInt16})
precompile(Tuple{typeof(Doors.runargs), Int64})
precompile(Tuple{typeof(Doors.shutdown), Doors.App})

# module Doors
