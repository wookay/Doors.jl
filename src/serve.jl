# module Doors

using Jive # trigger JiveExt
using JuliaBase # trigger JuliaBasePrecompilationExt

function serve(port::Union{typeof(any), Integer} = PORT; into::Module = Module())
    app = create_app(; into, port)
    wait(app.started_notify)
    !isinteractive() && wait(app.closed_notify)
end

# module Doors
