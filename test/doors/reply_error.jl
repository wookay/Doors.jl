using Doors: create_app
app = create_app(; port = any)

yield()
sleep(0.00000001)
    
using Doors
expr_str = """fafo"""
runexpr(expr_str, app.server_port)

Doors.shutdown(app)

using Test
@test !app.is_running
