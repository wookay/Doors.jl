# module Doors

function serve(port::Union{typeof(any), Integer} = PORT)
    app = create_app(port)
    !isinteractive() && wait(app.close_notify)
end

# module Doors
