using Test
using Doors: Doors

Doors.request_runexpr
Doors.conn_and_req

fix2 = Base.Fix2(Doors.request_runexpr, "1+2")
@test_throws Base.IOError Doors.conn_and_req(fix2, 0)
