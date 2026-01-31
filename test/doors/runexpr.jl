using Test
using Doors

Doors.runexpr

function test_runexpr()
    app = Doors.create_app(; port = any, into = Module())
    wait(app.started_notify)

    expr_str = """println(3)"""
    value = runexpr(expr_str, app.server_port)
    @test value === nothing
    println(stdout)

    expr_str = "1+2"
    value = runexpr(expr_str, app.server_port)
    @test value == 3
    println(stdout, value)
    println(stdout)

    expr = quote
    1+2
    end
    value = runexpr(expr, app.server_port)
    @test value == 3
    println(stdout, value)

    Doors.shutdown(app)

    @test !app.is_running
end

# using Base.CoreLogging: with_logger, ConsoleLogger, Debug
# with_logger(test_runexpr, ConsoleLogger(Debug))
test_runexpr()
