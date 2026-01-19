using Test
using Doors: Doors, App

app = App(; into = @__MODULE__)
@test app.into isa Module
@test app.close_notify isa Condition
@test app.runloop_task === nothing
@test !app.is_running
@test app.server_port === nothing

Doors.create_app
Doors.runloop
Doors.shutdown
