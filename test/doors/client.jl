using Test
using Doors: Doors

Doors.conn_and_req

f(sock) = nothing
@test_throws Base.IOError Doors.conn_and_req(f, 0)
