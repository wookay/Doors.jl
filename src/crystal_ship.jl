# module Doors

mutable struct App
    into::Module
    started_notify::Base.Event
    closed_notify::Condition
    runloop_task::Union{Nothing,Task}
    is_running::Bool
    server_port::Union{Nothing,Integer}
    function App(; into::Module,
                   started_notify::Base.Event = Base.Event(),
                   closed_notify::Condition = Condition(),
                   runloop_task::Union{Nothing,Task} = nothing,
                   is_running::Bool = false,
                   server_port::Union{Nothing,Integer} = nothing)
        new(into, started_notify, closed_notify, runloop_task, is_running, server_port)
    end
end

struct ShutdownException <: Exception
    msg::AbstractString
end

const PORT::UInt16  = 3001

if VERSION < v"1.12"
const isdefinedglobal = isdefined
end
function check_revise(into::Module)
    if @invokelatest isdefinedglobal(into, :Revise)
        Revise = @invokelatest getglobal(into, :Revise)
        if isa(Revise, Module) && isdefinedglobal(Revise, :revise)
            revise = getglobal(Revise, :revise)
            if revise isa Function
                @invokelatest revise()
                # @info revise
            end
        end
    end
end

function showerror_with_backtrace(io::IO, ex)
    bt = backtrace()[1:min(end, 10)]
    showerror(io, ex, bt; backtrace=true)
    println(io)
end

### App
function create_app(; port::Union{typeof(any), Integer} = PORT, into::Module)::App
    app = App(; into)
    app.runloop_task = runloop(app, port)
    app
end

function shutdown(app::App)
    app.is_running = false
    @async Base.throwto(app.runloop_task, ShutdownException("shutdown"))
    try wait(app.runloop_task) catch end
end

# using JuliaSyntaxHighlighting: highlight
highlight(expr_str::String) = expr_str

include("http.jl")

# module Doors
