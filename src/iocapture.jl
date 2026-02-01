# module Doors

# original code from IOCapture.jl/src/IOCapture.jl
# function capture

function iocapture(
    f;
    rethrow::Type=Any,
    color::Bool=false,
    passthrough::Bool=false,
    capture_buffer=IOBuffer(),
    io_context::AbstractVector=[],
)
    if any(x -> !isa(x, Pair{Symbol,<:Any}), io_context)
        throw(ArgumentError("`io_context` must be a `Vector` of `Pair{Symbol,<:Any}`."))
    end

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
    # Also redirect logging stream to the same pipe
    # logger = ConsoleLogger(pe_stderr)

    # old_rng = nothing
    # if VERSION >= v"1.7.0-DEV.1226" # JuliaLang/julia#40546
    #     # In Julia >= 1.7 each task has its own rng seed. This seed
    #     # is obtained by calling rand(...) in the current task which
    #     # modifies the random stream. We therefore copy the current seed
    #     # and reset it after creating the read/write task below.
    #     # See https://github.com/JuliaLang/julia/pull/41184 for more details.
    #     old_rng = copy(Random.default_rng())
    # end

    # Bytes written to the `pipe` are captured in `output` and eventually converted to a
    # `String`. We need to use an asynchronous task to continously tranfer bytes from the
    # pipe to `output` in order to avoid the buffer filling up and stalling write() calls in
    # user code.
    if passthrough
        bufsize = 128
        buffer = Vector{UInt8}(undef, bufsize)
        buffer_redirect_task = @async begin
            while !eof(pipe)
                nbytes = readbytes!(pipe, buffer, bufsize)
                data = view(buffer, 1:nbytes)
                write(capture_buffer, data)
                write(default_stdout, data)
            end
        end
    else
        buffer_redirect_task = @async write(capture_buffer, pipe)
    end

    # if old_rng !== nothing
    #     copy!(Random.default_rng(), old_rng)
    # end

    # Run the function `f`, capturing all output that it might have generated.
    # Success signals whether the function `f` did or did not throw an exception.
    result, success, backtrace = # with_logger(logger) do
        try
            yield() # avoid hang, see https://github.com/JuliaDocs/Documenter.jl/issues/2121
            f(), true, Vector{Ptr{Cvoid}}()
        catch err
            err isa rethrow && Base.rethrow(err)
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
    # end
    (
        value = result,
        output = String(take!(capture_buffer)),
        error = !success,
        backtrace = backtrace,
    )
end

# module Doors
