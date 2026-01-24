using Test
using Doors # runexpr

app = Doors.create_app(; port = any, into = Module())

yield()
sleep(0.00000001)

expr_str = """println(3)"""
runexpr(expr_str, app.server_port)

Doors.shutdown(app)

@test !app.is_running
