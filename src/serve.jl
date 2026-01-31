# module Doors

using Jive # trigger JiveExt

function serve(port::Union{typeof(any), Integer} = PORT; into::Module = Module())
    app = create_app(; into, port)
    !isinteractive() && wait(app.close_notify)
end

# module Doors
