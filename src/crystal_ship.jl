# module Doors

using Sockets: Sockets, TCPSocket
using IOCapture: IOCapture

mutable struct App
    into::Module
    close_notify::Condition
    runloop_task::Union{Nothing,Task}
    is_running::Bool
    server_port::Union{Nothing,Integer}
    function App(; into::Module,
                   close_notify::Condition = Condition(),
                   runloop_task::Union{Nothing,Task} = nothing,
                   is_running::Bool = false,
                   server_port::Union{Nothing,Integer} = nothing)
        new(into, close_notify, runloop_task, is_running, server_port)
    end
end

const token_runexpr = "Doors::token_runexpr"
const token_runfile = "Doors::token_runfile"
const token_end     = "Doors::token_end"
const PORT::UInt16  = 3001

function serverRun(f::Function, sock::TCPSocket, dir, args::Vector{String})
    @debug :serverRun f sock dir args

    empty!(ARGS)
    push!(ARGS, args...)

    original_stdout = stdout
    c = IOCapture.capture(; rethrow=Union{}, color = true) do
        cd(f, dir)
    end
    print(sock, c.output)
    if c.error
        write_error(sock, c.value, c.backtrace)
    end
    println(sock, token_end)
end

function serverReplyError(sock::TCPSocket, ex)
    @debug :serverReplyError sock ex

    bt = backtrace()
    write_error(sock, ex, bt)
    println(sock, token_end)
end

function write_error(io::IO, ex, bt::Vector{Union{Ptr{Nothing}, Base.InterpreterIP}})
    io_context = IOContext(io, :color => true)
    printstyled(io_context, "ERROR: ", color = :red)
    showerror(io_context, ex, bt; backtrace=true)
    println(io)
end

function async_process(sock::TCPSocket, into::Module)
    try
        mode::String = readline(sock)
        if mode == token_runexpr
            dir = readline(sock)
            expr_str::String = readuntil(sock, token_end)
            expr = Meta.parse(expr_str)
            serverRun(sock, dir, String[]) do
                Base.eval(into, expr)
            end
        elseif mode == token_runfile
            dir = readline(sock)
            filepath = readline(sock)
            args = Base.eval(Meta.parse(readline(sock)))
            rest::String = readuntil(sock, token_end)
            Base.PROGRAM_FILE = basename(filepath)
            serverRun(sock, dir, args) do
                Base.include(into, filepath)
            end
        else
            ex = ArgumentError(mode)
            serverReplyError(sock, ex)
        end
    catch ex
        serverReplyError(sock, ex)
    end
end

function showerror_with_backtrace(io::IO, ex)
    bt = backtrace()[1:min(end, 10)]
    showerror(io, ex, bt; backtrace=true)
    println(io)
end


### App
function create_app(; into::Module = Module(), port::Union{typeof(any), Integer} = PORT)::App
    app = App(; into)
    runloop_task = @async runloop(app, port)
    app.runloop_task = runloop_task
    app
end

function runloop(app::App, port::Union{typeof(any), Integer})
    if port === any
        (server_port, tcp_server) = Sockets.listenany(Sockets.localhost, PORT)
    else
        server_port = port
        tcp_server = Sockets.listen(Sockets.localhost, port)
    end
    app.is_running = true
    app.server_port = server_port
    @debug :runloop tcp_server Int(server_port)
    tasks = Task[]
    while isopen(tcp_server) && app.is_running
        sock::TCPSocket = Sockets.accept(tcp_server)
        task = @async begin
            async_process(sock, app.into)
        end
        push!(tasks, task)
    end
    if nicely
        for task in tasks
            try
                wait(task)
            catch ex
                showerror_with_backtrace(stderr, ex)
            end
        end
    end
    close(tcp_server)
    notify(app.close_notify)
end

function shutdown(app::App)
    app.is_running = false
    @async Base.throwto(app.runloop_task, ErrorException("stop"))
end

### client
function conn_and_req(f::Function, port::Integer)
    sock = Sockets.connect(port)
    f(sock)

    while true
        line = readline(sock)
        if endswith(line, token_end)
            length_token_end = length(token_end)
            if length(line) > length_token_end
                crumb = line[1:end-length_token_end]
                print(stdout, crumb)
            end
            break
        else
            println(stdout, line)
        end
    end
end

function request_runfile(sock::TCPSocket, dir, filepath, args::Vector{String})
    println(sock, token_runfile)
    println(sock, dir)
    println(sock, filepath)
    println(sock, repr(args))
    println(sock, token_end)
end

# using JuliaSyntaxHighlighting: highlight
highlight(expr_str::String) = expr_str

function request_runexpr(sock::TCPSocket, dir, expr_str::String)
    printstyled(stdout, "julia> ", color = :light_green)
    println(stdout, highlight(expr_str))

    println(sock, token_runexpr)
    println(sock, dir)
    println(sock, expr_str)
    println(sock, token_end)
end

# module Doors
