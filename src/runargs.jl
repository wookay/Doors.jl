# module Doors

function runfile(dir::String, filepath::String, args::Vector{String}, port::Integer)
    response_stream = stdout
    conn_and_req(request_runfile, (dir, filepath, args), port, response_stream)
end

function runargs(port::Integer = PORT)
    dir = pwd()
    if isempty(ARGS)
        throw(ArgumentError("missing filename"))
    else
        filepath = first(ARGS)
        args = ARGS[2:end]
        runfile(dir, filepath, args, port)
    end
end

# module Doors
