# module Doors

function runexpr(expr_str::String, port::Integer = PORT)
    returns = conn_and_req(port) do sock
        request_runexpr(sock, expr_str)
    end
    expr = Meta.parse(returns.value)
    Base.eval(expr)
end

function runexpr(expr::Expr, port::Integer = PORT)
    runexpr(string(expr), port)
end

# module Doors
