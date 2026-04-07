# module Doors

using HTTP: HTTP
using Sockets: Sockets
using JSON: JSON

function serverRun(::typeof(Base.eval), into::Module, stream::HTTP.Stream, expr::String)
    parsed_expr = Meta.parse(expr)
    @noinline f() = Base.eval(into, parsed_expr)

    HTTP.setstatus(stream, 200)
    HTTP.startwrite(stream)

    output_buf = IOBuffer()
    c = iocapture(f, output_buf; color = true)
    dict = Dict()
    if c.error
        err_buf = IOBuffer()
        write_error(err_buf, c.value, [])
        dict["error"] = String(take!(err_buf))
    end
    dict["output"] = String(take!(output_buf))
    dict["result"] = c.value
    body = JSON.json(dict)
    write(stream, body)
end

function serverRun(::typeof(Base.include), into::Module, stream::HTTP.Stream, filepath::String, args::Vector{String})
    check_revise(into)

    @noinline f() = Base.include(into, filepath)
    empty!(ARGS)
    push!(ARGS, args...)

    HTTP.setstatus(stream, 200)
    HTTP.startwrite(stream)

    c = iocapture(f, stream; color = true)
    if c.error
        write_error(stream, c.value, c.backtrace)
    end
end

function write_error(io::IO, ex, bt::Vector)
    io_context = IOContext(io, :color => true)
    printstyled(io_context, "ERROR: ", color = :red)
    showerror(io_context, ex, bt; backtrace=!isempty(bt))
end

function serverReplyError(stream::HTTP.Stream, ex)
    @debug :serverReplyError stream ex

    HTTP.setstatus(stream, 404)
    HTTP.setheader(stream, "Content-Type" => "text/plain")
    HTTP.startwrite(stream)

    write_error(stream, ex, [])
end

function handle_stream(stream::HTTP.Stream, into::Module)
    try
        req::HTTP.Request = stream.message
        if req.target == "/runexpr"
            body = read(stream)
            dict = JSON.parse(body)
            expr::String = dict["expr"]
            serverRun(Base.eval, into, stream, expr)
        elseif req.target == "/runfile"
            body = read(stream)
            dict = JSON.parse(body)
            dir::String = dict["dir"]
            filepath::String = dict["filepath"]
            args::Vector{String} = dict["args"]
            Base.PROGRAM_FILE = basename(filepath)
            @noinline function do_serverRun()
                serverRun(Base.include, into, stream, filepath, args)
            end
            cd(do_serverRun, dir)
        else
            ex = ArgumentError(req.target)
            serverReplyError(stream, ex)
        end
    catch ex
        if ex isa ShutdownException
        elseif ex isa SystemError
        else
            @info :handle_stream ex
            serverReplyError(stream, ex)
        end
    end
end

function runloop(app::App, port::Union{typeof(any), Integer})
    host = Sockets.localhost
    (hostport, listenany) = port === any ? (PORT, true) : (port, false)
    listener = HTTP.Servers.Listener(host, hostport; listenany)
    app.is_running = true
    app.server_port = parse(UInt16, listener.hostport)
    notify(app.started_notify)
    stream::Bool = true
    on_shutdown() = notify(app.closed_notify)
    verbose::Int = -1
    fix2 = Base.Fix2(handle_stream, app.into)
    task = @async begin
        HTTP.Servers.listen(fix2, listener; stream, on_shutdown, verbose)
        @info :failed
    end
    return task
end

### client
function request_runfile(uri::String,
                         tup::Tuple{String, String, Vector{String}},
                         response_stream::IO)
    (dir::String, filepath::String, args::Vector{String}) = tup
    dict = Dict(
        "dir" => dir,
        "filepath" => filepath,
        "args" => args,
    )
    body = Vector{UInt8}(JSON.json(dict))
    verbose::Bool = false
    HTTP.request("POST", uri; body, verbose, response_stream)
end

function request_runexpr(uri::String,
                         expr::String)
    printstyled(stdout, "julia> ", color = :light_green)
    println(stdout, highlight(expr))
    dict = Dict(
        "expr" => expr,
    )
    body = Vector{UInt8}(JSON.json(dict))
    verbose::Bool = false
    HTTP.request("POST", uri; body, verbose)
end

function conn_and_req(f::typeof(request_runfile),
                      tup::Tuple{String, String, Vector{String}},
                      port::Integer,
                      response_stream::IO)
    host = Sockets.localhost
    uri = "http://$host:$port/runfile"
    f(uri, tup, response_stream)
end

function conn_and_req(f::typeof(request_runexpr),
                      expr::String,
                      port::Integer)
    host = Sockets.localhost
    uri = "http://$host:$port/runexpr"
    f(uri, expr)
end

# module Doors
