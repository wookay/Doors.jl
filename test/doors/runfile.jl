using Test
using Doors

Doors.runfile
Doors.runargs

function test_runfile()
    app = Doors.create_app(; port = any, into = Module())
    
    yield()
    sleep(0.00000001)
    
    dir = normpath(@__DIR__, "../")
    filepath = "runtests.jl"
    args = ["dummy"]
    
    Doors.runfile(dir, filepath, args, app.server_port)
    
    Doors.shutdown(app)

    @test !app.is_running
end

using Base.CoreLogging: with_logger, ConsoleLogger, Debug
with_logger(test_runfile, ConsoleLogger(Debug))
