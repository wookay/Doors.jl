# module Doors

function runexpr(expr_str::String, port::Integer = PORT)
    fix2 = Base.Fix2(request_runexpr, expr_str)
    returns = conn_and_req(fix2, port)
    expr = Meta.parse(returns.value)
    Base.eval(expr)
end

function runexpr(expr::Expr, port::Integer = PORT)
    runexpr(string(expr), port)
end

# module Doors
