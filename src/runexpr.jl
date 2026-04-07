# module Doors

function runexpr(expr::String, port::Integer = PORT)
    resp = conn_and_req(request_runexpr, expr, port)
    dict = JSON.parse(resp.body)
    if haskey(dict, "error")
        println(stdout, dict["error"])
    end
    if !isempty(dict["output"])
        println(stdout, dict["output"])
    end
    dict["result"]
end

function runexpr(expr::Expr, port::Integer = PORT)
    runexpr(string(expr), port)
end

# module Doors
