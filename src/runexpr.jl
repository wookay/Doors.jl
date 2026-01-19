# module Doors

function runexpr(expr_str::String, port::Integer = PORT)
    dir = pwd()
    conn_and_req(port) do sock
        request_runexpr(sock, dir, expr_str)
    end
end

# module Doors
