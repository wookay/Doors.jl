# module Doors

# Doors
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:into,), Tuple{Module}}, Type{Doors.App}})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:into,), Tuple{Module}}, typeof(Doors.serve), Int64})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:port, :into), Tuple{typeof(Base.any), Module}}, typeof(Doors.create_app)})
precompile(Tuple{typeof(Base.getproperty), Doors.App, Symbol})
precompile(Tuple{typeof(Doors.runfile), String, String, Array{String, 1}, UInt16})
precompile(Tuple{typeof(Doors.runargs), UInt16})
precompile(Tuple{typeof(Doors.runexpr), String, UInt16})
precompile(Tuple{typeof(Doors.runexpr), Expr, UInt16})
precompile(Tuple{typeof(Doors.shutdown), Doors.App})

# Base
precompile(Tuple{typeof(Base.getindex), Base.Threads.Atomic{Int32}})
precompile(Tuple{typeof(Base.:(>=)), Int32, Int32})
precompile(Tuple{typeof(Base.CoreLogging.shouldlog), Base.CoreLogging.ConsoleLogger, Base.CoreLogging.LogLevel, Module, Symbol, Symbol})
precompile(Tuple{Type{Base.IOContext{IO_t} where IO_t<:IO}, Base.GenericIOBuffer{Memory{UInt8}}, Base.TTY})
precompile(Tuple{typeof(Base.getproperty), Base.GenericCondition{Base.ReentrantLock}, Symbol})
precompile(Tuple{typeof(Base.lock), Base.GenericCondition{Base.Threads.SpinLock}})
precompile(Tuple{typeof(Base.notify), Base.GenericCondition{Base.Threads.SpinLock}})
precompile(Tuple{typeof(Base.unlock), Base.GenericCondition{Base.Threads.SpinLock}})
precompile(Tuple{typeof(Base.push!), Array{String, 1}})
precompile(Tuple{typeof(Base.write), Base.TTY, Array{UInt8, 1}})
precompile(Tuple{typeof(Base.lock), Base.TTY})
precompile(Tuple{typeof(Base.unlock), Base.TTY})
precompile(Tuple{typeof(Base.ocachefile_from_cachefile), String})
precompile(Tuple{typeof(Base.close), Base.IOContext{Base.PipeEndpoint}})
precompile(Tuple{typeof(Base._atexit), Int32}) # recompile

# module Doors
