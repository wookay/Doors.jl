# module Doors

function runfile(dir::String, filepath::String, args::Vector{String}, port::Integer)
    fix2 = Base.Fix2(request_runfile, (dir, filepath, args))
    conn_and_req(fix2, port)
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
