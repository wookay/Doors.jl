# module Doors

function runfile(dir, filepath, args::Vector{String}, port::Integer)
    conn_and_req(port) do sock
        request_runfile(sock, dir, filepath, args)
    end
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
