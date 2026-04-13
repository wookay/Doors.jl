module JuliaBasePrecompilationExt

# wait until fix the issue #3
if VERSION >= v"1.14.0-DEV.1963" # julia commit cb2e1ecf24

__precompile__(false)

using Base.Precompilation: PkgId, BG, ansi_enablecursor, printpkgstyle
import Base.Precompilation: monitor_background_precompile

# apply Ian Butterworth's patch
function monitor_background_precompile(io::Base.PipeEndpoint = stderr, detachable::Bool = true, wait_for_pkg::Union{Nothing, PkgId} = nothing;
                                       # disable key controls when not on the main task to avoid
                                       # stealing stdin from the REPL
                                       key_controls::Bool = current_task() === Base.roottask)
    local completed_at::Union{Nothing, Float64}
    local task

    @lock BG begin
        completed_at = BG.completed_at
        task = BG.task
    end

    if task === nothing || istaskdone(task)
        if completed_at !== nothing
            elapsed = time() - completed_at
            time_str = if elapsed < 60
                "$(round(Int, elapsed)) seconds ago"
            elseif elapsed < 3600
                "$(round(Int, elapsed / 60)) minutes ago"
            elseif elapsed < 86400
                "$(round(Int, elapsed / 3600)) hours ago"
            else
                "$(round(Int, elapsed / 86400)) days ago"
            end
            printpkgstyle(io, :Info, "Background precompilation completed $time_str", color = Base.info_color())
            result = @lock BG BG.result
            if result !== nothing && !isempty(result)
                println(io, "  ", result)
            end
        else
            printpkgstyle(io, :Info, "No background precompilation is running or has been run in this session", color = Base.info_color())
        end
        return
    end

    # Enable output from do_precompile
    @lock BG BG.monitoring = true

    exit_requested = Ref(false)
    cancel_requested = Ref(false)
    interrupt_requested = Ref(false)

    # Start a task to listen for keypresses (only if stdin isn't already being
    # consumed in raw mode by another reader, e.g. runtests.jl's stdin_monitor)
    key_task = if key_controls && stdin isa Base.TTY
        Threads.@spawn :samepool try
            trylock(stdin.raw_lock) || return
            @lock BG begin
                BG.detachable = detachable
                BG.confirming = :none
            end
            buffered_input = UInt8[]
            try
                term = Base.Terminals.TTYTerminal(get(ENV, "TERM", "dumb"), stdin, stdout, stderr)
                Base.Terminals.raw!(term, true)
                # Drain any pre-existing input (e.g. pasted or pre-typed text)
                # before entering the key listener. This avoids accidentally
                # triggering menu actions from stale input (see #61520).
                # The drained bytes are replayed into stdin on exit.
                # We must start_reading + yield first so libuv delivers any
                # bytes sitting in the kernel tty buffer into stdin.buffer.
                Base.start_reading(stdin)
                yield()
                while bytesavailable(stdin) > 0
                    push!(buffered_input, read(stdin, UInt8))
                end
                try
                    while true
                        completed = @lock BG (BG.completed_at !== nothing)
                        if completed || exit_requested[] || cancel_requested[] || interrupt_requested[]
                            break
                        end
                        Base.wait_readnb(stdin, 1)
                        completed = @lock BG (BG.completed_at !== nothing)
                        if completed || exit_requested[] || cancel_requested[] || interrupt_requested[]
                            break
                        end
                        bytesavailable(stdin) > 0 || continue
                        c = read(stdin, Char)
                        # If waiting for confirmation, Enter confirms, anything else aborts
                        confirmed_action = @lock BG begin
                            prev = BG.confirming
                            BG.confirming = :none
                            (prev !== :none && c in ('\r', '\n')) ? prev : :none
                        end
                        if confirmed_action == :cancel
                            cancel_requested[] = true
                            println(io)
                            @lock BG BG.cancel_requested = true
                            broadcast_signal(Base.SIGKILL)
                            break
                        elseif confirmed_action == :info
                            broadcast_signal(Sys.isapple() ? Base.SIGINFO : Base.SIGUSR1)
                            continue
                        end
                        if c in ('c', 'C')
                            @lock BG begin
                                BG.confirming = :cancel
                                BG.confirm_deadline = time() + 5.0
                            end
                        elseif detachable && c in ('d', 'D', 'q', 'Q', ']')
                            exit_requested[] = true
                            println(io)  # newline after keypress
                            break
                        elseif c == '\x03'  # Ctrl-C
                            interrupt_requested[] = true
                            println(io)  # newline after keypress
                            @lock BG BG.interrupt_requested = true
                            broadcast_signal(Base.SIGINT)
                            break
                        elseif c in ('i', 'I')
                            @lock BG begin
                                BG.confirming = :info
                                BG.confirm_deadline = time() + 5.0
                            end
                        elseif c in ('v', 'V')
                            @lock BG BG.verbose = !BG.verbose
                        elseif c in ('?', 'h', 'H')
                            @lock io begin
                                println(io, "  Keyboard shortcuts:", ansi_cleartoendofline)
                                println(io, "    c       Cancel precompilation via killing subprocesses (press Enter to confirm)", ansi_cleartoendofline)
                                if detachable
                                    println(io, "    d/q/]   Detach (precompilation continues in background)", ansi_cleartoendofline)
                                end
                                println(io, "    i       Send profiling signal to subprocesses (press Enter to confirm)", ansi_cleartoendofline)
                                fields = Sys.iswindows() ? "elapsed time and PID" : "elapsed time, PID, CPU% and memory"
                                println(io, "    v       Toggle verbose mode (show $(fields) for each worker)", ansi_cleartoendofline)
                                println(io, "    Ctrl-C  Interrupt (sends SIGINT, shows output)", ansi_cleartoendofline)
                                println(io, "    ?/h     Show this help", ansi_cleartoendofline)
                            end
                        end
                    end
                finally
                    Base.Terminals.raw!(term, false)
                end
            catch err
                err isa EOFError && return
                exit_requested[] = true
                rethrow()
            finally
                # Replay any buffered input back into stdin so the REPL
                # (or whatever reads stdin next) sees it as typed text.
                if !isempty(buffered_input)
                    lock(stdin.cond)
                    try
                        write(stdin.buffer, buffered_input)
                        notify(stdin.cond)
                    finally
                        unlock(stdin.cond)
                    end
                end
                Base.reseteof(stdin)
                @lock BG BG.confirming = :none
                unlock(stdin.raw_lock)
            end
        finally
            @lock BG.task_done notify(BG.task_done)
        end
    else
        nothing
    end

    # Wake up key_task by signaling EOF on stdin so wait_readnb returns
    wake_key_task = () -> begin
        if key_task !== nothing && !istaskdone(key_task)
            lock(stdin.cond)
            try
                stdin.status = Base.StatusEOF
                notify(stdin.cond)
            finally
                unlock(stdin.cond)
            end
        end
    end

    # If waiting for a specific package, spawn a watcher that exits when it's done
    pkg_watcher = if wait_for_pkg !== nothing
        Threads.@spawn :samepool begin
            @lock BG.pkg_done begin
                # Wait for the package to appear in pending_pkgids (it may not be
                # registered yet if the request was just injected via work_channel
                # and drain_work_channel! hasn't processed it).
                # Also check completed_pkgids in case the package was added and
                # removed before we started watching.
                while get(BG.pending_pkgids, wait_for_pkg, 0) == 0 && wait_for_pkg ∉ BG.completed_pkgids && BG.completed_at === nothing
                    wait(BG.pkg_done)
                end
                # Now wait for it to finish
                while get(BG.pending_pkgids, wait_for_pkg, 0) > 0
                    wait(BG.pkg_done)
                end
            end
            exit_requested[] = true
            @lock BG.task_done notify(BG.task_done)
        end
    else
        nothing
    end

    return try
        # Wait for task completion or user action
        @lock BG.task_done begin
            while !exit_requested[] && !cancel_requested[] && !interrupt_requested[]
                BG.completed_at !== nothing && break
                wait(BG.task_done)
            end
        end

        # If user requested cancel, stop the background task
        if cancel_requested[]
            @lock BG BG.monitoring = false
            key_task !== nothing && wait(key_task)
            print(io, ansi_enablecursor, ansi_cleartoend)
            printpkgstyle(io, :Info, "Canceling precompilation...$(ansi_cleartoend)", color = Base.info_color())
            wait(task; throw=false)
            return
        end

        # If user requested interrupt, wait for background task to finish cleanly
        if interrupt_requested[]
            key_task !== nothing && wait(key_task)
            # Escalate to SIGKILL if background task doesn't finish promptly
            escalation = Timer(5) do _
                broadcast_signal(Base.SIGKILL)
            end
            wait(task; throw=false)
            close(escalation)
            return
        end

        # If we were waiting for a specific package and it finished, clean up silently
        if exit_requested[] && wait_for_pkg !== nothing
            @lock BG BG.monitoring = false
            if key_task !== nothing
                wake_key_task()
                wait(key_task)
            end
            print(io, ansi_enablecursor, ansi_cleartoend)
            return
        end

        # If user requested exit, clean up and return
        if exit_requested[]
            @lock BG BG.monitoring = false
            key_task !== nothing && wait(key_task)
            print(io, ansi_enablecursor, ansi_cleartoend)
            n_pending = @lock BG length(BG.pending_pkgids)
            progress = n_pending > 0 ? " ($n_pending packages remaining)." : "."
            printpkgstyle(io, :Precompiling, "detached$(progress) Precompilation will continue in the background. Monitor with `precompile --monitor`.$(ansi_cleartoend)", color = Base.info_color())
            return
        end

        # Normal completion - signal key_task to exit and wait
        if key_task !== nothing
            wake_key_task()
            wait(key_task)
        end

        wait(task; throw=false)
    catch e
        # Clean up on error
        @lock BG BG.monitoring = false
        if key_task !== nothing
            exit_requested[] = true
            wake_key_task()
            try; wait(key_task); catch; end
        end
        rethrow()
    end
end # function monitor_background_precompile

end # if VERSION >= v"1.14.0-DEV.1963"

end # module JuliaBasePrecompilationExt
