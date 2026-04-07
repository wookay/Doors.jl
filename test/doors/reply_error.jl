using Test
using Doors # runexpr

app = Doors.create_app(; port = any, into = Module())
wait(app.started_notify)

expr = """fafo"""
runexpr(expr, app.server_port)

Doors.shutdown(app)

@test !app.is_running
