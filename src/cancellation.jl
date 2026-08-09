# module Doors

# from julia/test/cancellation.jl

if VERSION >= v"1.14.0-DEV.2892" # julia commit cbbb1702f7

const support_cancellation = true

using Base: CancellationTokenSource,
            CancellationToken,
            cancel!
using Sockets: accept

else

const support_cancellation = false

mutable struct CancellationTokenSource
  child_head::Any
  waiters_head::Any
  walk_lock::Any
  state::UInt8
  const nparents::UInt16
  dead_count::UInt32
  reg_count::UInt32
  CancellationTokenSource() = new(nothing, nothing, nothing, 0x00, 0x0000, 0x00000000, 0x00000000)
end

struct CancellationToken
    src::CancellationTokenSource
end

using Sockets: Sockets, TCPServer

function accept(server::TCPServer; cancel::CancellationToken)
    Sockets.accept(server)
end

function cancel!(src::CancellationTokenSource)
end

end # if VERSION

struct Cancellable
   task::Task
   src::CancellationTokenSource
end

function cancellable_async(f)::Cancellable
    src = CancellationTokenSource()
    if support_cancellation
        t = Base.ScopedValues.with(() -> @async(f()), Base.CANCEL_TOKEN => CancellationToken(src))
        return Cancellable(t, src)
    else
        t = @async(f())
        return Cancellable(t, src)
    end
end

# wait a little, so cancellation targets are (most likely) started and parked
spin(n=3) = for _ in 1:n; yield(); end

# module Doors
