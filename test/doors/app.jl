using Test
using Doors: Doors, App

Doors.create_app
Doors.runloop
Doors.shutdown

app = App(; into = @__MODULE__)
@test app.into isa Module
@test app.close_notify isa Condition
@test app.runloop_task === nothing
@test !app.is_running
@test app.server_port === nothing

app1 = Doors.create_app(; port = any, into = @__MODULE__)
app2 = Doors.create_app(; port = any)

@test app1.into != app2.into
@test app1.server_port === app2.server_port === nothing

yield()
sleep(0.00000001)

@test app1.server_port isa UInt16
@test app1.server_port != app2.server_port

Doors.shutdown(app1)
Doors.shutdown(app2)

@test !app1.is_running
@test !app2.is_running
