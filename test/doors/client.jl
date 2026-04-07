using Test
using Doors: Doors
using HTTP: HTTP

Doors.request_runexpr
Doors.conn_and_req

f = Doors.request_runexpr
expr::String = "1 + 2"
port::UInt16 = 0
@test_throws HTTP.Exceptions.ConnectError Doors.conn_and_req(f, expr, port)
