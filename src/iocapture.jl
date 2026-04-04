# module Doors

using Sockets: TCPSocket

# original code from IOCapture.jl/src/IOCapture.jl
# function capture

function iocapture(
    f,
    sock::TCPSocket ;
    color::Bool = false
)
    rethrow_type::Type = Union{}
    io_context::AbstractVector = []

    # Original implementation from Documenter.jl (MIT license)
    # Save the default output streams.
    default_stdout = stdout
    default_stderr = stderr

    # Redirect both the `stdout` and `stderr` streams to a single `Pipe` object.
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    @static if VERSION >= v"1.6.0-DEV.481" # https://github.com/JuliaLang/julia/pull/36688
        pe_stdout = IOContext(pipe.in, :color => get(stdout, :color, false) & color, io_context...)
        pe_stderr = IOContext(pipe.in, :color => get(stderr, :color, false) & color, io_context...)
    else
        pe_stdout = pipe.in
        pe_stderr = pipe.in
    end
    redirect_stdout(pe_stdout)
    redirect_stderr(pe_stderr)

    bufsize = 32
    buffer = Vector{UInt8}(undef, bufsize)
    buffer_redirect_task = @async begin
        while !eof(pipe)
            nbytes = readbytes!(pipe, buffer, bufsize)
            data = view(buffer, 1:nbytes)
            write(sock, data)
        end
    end

    # Run the function `f`, capturing all output that it might have generated.
    # Success signals whether the function `f` did or did not throw an exception.
    result, success, backtrace =
        try
            yield() # avoid hang, see https://github.com/JuliaDocs/Documenter.jl/issues/2121
            f(), true, Vector{Ptr{Cvoid}}()
        catch err
            err isa rethrow_type && Base.rethrow(err)
            # If we're capturing the error, we return the error object as the value.
            err, false, catch_backtrace()
        finally
            # Restore the original output streams.
            redirect_stdout(default_stdout)
            redirect_stderr(default_stderr)
            close(pe_stdout)
            close(pe_stderr)
            wait(buffer_redirect_task)
        end
    return (
        value = result,
        output = "",
        error = !success,
        backtrace = backtrace,
    )
end

# module Doors
