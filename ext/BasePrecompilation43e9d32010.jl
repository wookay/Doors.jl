# from julia/base/precompilation.jl
# julia commit 43e9d32010 v1.14.0-DEV.1962
module BasePrecompilation43e9d32010

using Base.Precompilation: PkgId, Config, ExplicitEnv, CoreLogging, StaleCacheKey, UUID, _collect_reachable!,
                           PkgConfig, scan_pkg!, collect_all_deps, full_name, printpkgstyle

function precompile_pkgs_maybe_cachefile_lock(f, io::IO, print_lock::ReentrantLock, fancyprint::Bool, pkg_config, pkgspidlocked, hascolor, parallel_limiter::Base.Semaphore, fullname)
    if !(isdefined(Base, :mkpidlock_hook) && isdefined(Base, :trymkpidlock_hook) && Base.isdefined(Base, :parse_pidfile_hook))
        return f()
    end
    pkg, config = pkg_config
    flags, cacheflags = config
    stale_age = Base.compilecache_pidlock_stale_age
    pidfile = Base.compilecache_pidfile_path(pkg, flags=cacheflags)
    cachefile = @invokelatest Base.trymkpidlock_hook(f, pidfile; stale_age)
    if cachefile === false
        pid, hostname, age = @invokelatest Base.parse_pidfile_hook(pidfile)
        pkgspidlocked[pkg_config] = if isempty(hostname) || hostname == gethostname()
            if pid == getpid()
                "an async task in this process (pidfile: $pidfile)"
            else
                "another process (pid: $pid, pidfile: $pidfile)"
            end
        else
            "another machine (hostname: $hostname, pid: $pid, pidfile: $pidfile)"
        end
        !fancyprint && @lock print_lock begin
            println(io, "    ", fullname, _color_string(" Being precompiled by $(pkgspidlocked[pkg_config])", Base.info_color(), hascolor))
        end
        Base.release(parallel_limiter) # release so other work can be done while waiting
        try
            # wait until the lock is available
            cachefile = @invokelatest Base.mkpidlock_hook(() -> begin
                    delete!(pkgspidlocked, pkg_config)
                    Base.acquire(f, parallel_limiter)
                end,
                pidfile; stale_age)
        finally
            Base.acquire(parallel_limiter) # re-acquire so the outer release is balanced
        end
    end
    return cachefile
end # function precompile_pkgs_maybe_cachefile_lock

function _precompilepkgs_monitor_std(pkg_config, pipe, single_requested_pkg::Bool,
    ext_to_parent, hascolor::Bool, std_outputs, taskwaiting, pkg_liveprinted, print_lock,
    io::IOContext, fancyprint::Bool, ansi_cleartoendofline::String)
    local pkg, config = pkg_config
    try
        local liveprinting = false
        local thistaskwaiting = false
        while !eof(pipe)
            local str = readline(pipe, keep=true)
            if single_requested_pkg && (liveprinting || !isempty(str))
                @lock print_lock begin
                    if !liveprinting
                        liveprinting = true
                        pkg_liveprinted[] = pkg
                    end
                    print(io, ansi_cleartoendofline, str)
                end
            end
            write(get!(IOBuffer, std_outputs, pkg_config), str)
            if thistaskwaiting
                if occursin("Waiting for background task / IO / timer", str)
                    thistaskwaiting = true
                    !liveprinting && !fancyprint && @lock print_lock begin
                        println(io, full_name(ext_to_parent, pkg), _color_string(str, Base.warn_color(), hascolor))
                    end
                    push!(taskwaiting, pkg_config)
                end
            else
                # XXX: don't just re-enable IO for random packages without printing the context for them first
                !liveprinting && !fancyprint && @lock print_lock begin
                    print(io, ansi_cleartoendofline, str)
                end
            end
        end
    catch err
        err isa InterruptException || rethrow()
    end
end # function _precompilepkgs_monitor_std

_timing_string(t) = string(lpad(round(t * 1e3, digits = 1), 9), " ms")

function _color_string(cstr::String, col::Union{Int64, Symbol}, hascolor)
    if hascolor
        enable_ansi  = get(Base.text_colors, col, Base.text_colors[:default])
        disable_ansi = get(Base.disable_text_style, col, Base.text_colors[:default])
        return string(enable_ansi, cstr, disable_ansi)
    else
        return cstr
    end
end # function _color_string

function _visit_indirect_deps!(direct_deps::Dict{PkgId, Vector{PkgId}}, visited::Set{PkgId},
                               node::PkgId, all_deps::Set{PkgId})
    if node in visited
        return
    end
    push!(visited, node)
    for dep in get(Set{PkgId}, direct_deps, node)
        if !(dep in all_deps)
            push!(all_deps, dep)
            _visit_indirect_deps!(direct_deps, visited, dep, all_deps)
        end
    end
    return
end # function _visit_indirect_deps!

function _precompilepkgs(pkgs::Union{Vector{String}, Vector{PkgId}},
                         internal_call::Bool,
                         strict::Bool,
                         warn_loaded::Bool,
                         timing::Bool,
                         _from_loading::Bool,
                         configs::Vector{Config},
                         io::IOContext{IO},
                         fancyprint′::Bool,
                         manifest::Bool,
                         ignore_loaded::Bool)
    requested_pkgs = copy(pkgs) # for understanding user intent
    pkg_names = pkgs isa Vector{String} ? copy(pkgs) : String[pkg.name for pkg in pkgs]
    if pkgs isa Vector{PkgId}
        requested_pkgids′ = copy(pkgs)
    else
        requested_pkgids′ = PkgId[]
        for name in pkgs
            pkgid = Base.identify_package(name)
            if pkgid === nothing
                if _from_loading
                    return # leave it up to loading to handle this
                else
                    throw(PkgPrecompileError("Unknown package: $name"))
                end
            end
            push!(requested_pkgids′, pkgid)
        end
    end
    requested_pkgids = requested_pkgids′

    time_start = time_ns()

    env = ExplicitEnv()

    # Windows sometimes hits a ReadOnlyMemoryError, so we halve the default number of tasks. Issue #2323
    # TODO: Investigate why this happens in windows and restore the full task limit
    default_num_tasks = Sys.iswindows() ? div(Sys.EFFECTIVE_CPU_THREADS::Int, 2) + 1 : Sys.EFFECTIVE_CPU_THREADS::Int + 1
    default_num_tasks = min(default_num_tasks, 16) # limit for better stability on shared resource systems

    num_tasks = max(1, something(tryparse(Int, get(ENV, "JULIA_NUM_PRECOMPILE_TASKS", string(default_num_tasks))), 1))
    parallel_limiter = Base.Semaphore(num_tasks)

    # suppress precompilation progress messages when precompiling for loading packages, except during interactive sessions
    # or when specified by logging heuristics that explicitly require it
    # since the complicated IO implemented here can have somewhat disastrous consequences when happening in the background (e.g. #59599)
    logio′ = io
    logcalls′ = nothing
    if _from_loading
        if isinteractive()
            logcalls′ = CoreLogging.Info # sync with Base.compilecache
        else
            logio′ = IOContext{IO}(devnull)
            fancyprint′ = false
            logcalls′ = CoreLogging.Debug # sync with Base.compilecache
        end
    end
    fancyprint = fancyprint′
    logio = logio′
    logcalls = logcalls′

    nconfigs = length(configs)
    hascolor = get(logio, :color, false)::Bool
    color_string(cstr::String, col::Union{Int64, Symbol}) = _color_string(cstr, col, hascolor)

    stale_cache = Dict{StaleCacheKey, Bool}()
    cachepath_cache = Dict{PkgId, Vector{String}}()

    # a map from packages/extensions to their direct deps
    direct_deps = Dict{Base.PkgId, Vector{Base.PkgId}}()
    # a map from parent → extension, including all extensions that are loadable
    # in the current environment (i.e. their triggers are present)
    parent_to_exts = Dict{Base.PkgId, Vector{Base.PkgId}}()
    # inverse map of `parent_to_ext` above (ext → parent)
    ext_to_parent = Dict{Base.PkgId, Base.PkgId}()

    function describe_pkg(pkg::PkgId, is_project_dep::Bool, is_serial_dep::Bool, flags::Cmd, cacheflags::Base.CacheFlags)
        name = full_name(ext_to_parent, pkg)
        name = is_project_dep ? name : color_string(name, :light_black)
        if is_serial_dep
            name *= color_string(" (serial)", :light_black)
        end
        if nconfigs > 1 && !isempty(flags)
            config_str = join(flags, " ")
            name *= color_string(" `$config_str`", :light_black)
        end
        if nconfigs > 1
            config_str = join(Base.translate_cache_flags(cacheflags, Base.DefaultCacheFlags), " ")
            name *= color_string(" $config_str", :light_black)
        end
        return name
    end

    # Determine which packages to consider for precompilation by walking
    # transitive dependencies from the appropriate roots.
    # `manifest` controls the scope: workspace_deps (all members) vs project_deps (current project).
    roots = manifest ? env.workspace_deps : env.project_deps
    pkg_uuids = Set{UUID}()
    for (_, uuid) in roots
        _collect_reachable!(pkg_uuids, env.deps, uuid)
    end

    triggers = Dict{Base.PkgId,Vector{Base.PkgId}}()
    for dep in pkg_uuids
        haskey(env.deps, dep) || continue
        pkg = Base.PkgId(dep, env.names[dep])
        Base.in_sysimage(pkg) && continue
        deps = [Base.PkgId(x, env.names[x]) for x in env.deps[dep]]
        direct_deps[pkg] = filter!(!Base.in_sysimage, deps)
        for (ext_name, trigger_uuids) in get(Dict{String, Vector{UUID}}, env.extensions, dep)
            ext_uuid = Base.uuid5(pkg.uuid, ext_name)
            ext = Base.PkgId(ext_uuid, ext_name)
            triggers[ext] = Base.PkgId[pkg] # depends on parent package
            all_triggers_available = true
            for trigger_uuid in trigger_uuids
                trigger_name = Base.PkgId(trigger_uuid, env.names[trigger_uuid])
                if trigger_uuid in pkg_uuids || Base.in_sysimage(trigger_name)
                    push!(triggers[ext], trigger_name)
                else
                    all_triggers_available = false
                    break
                end
            end
            all_triggers_available || continue
            ext_to_parent[ext] = pkg
            direct_deps[ext] = filter(!Base.in_sysimage, triggers[ext])

            if !haskey(parent_to_exts, pkg)
                parent_to_exts[pkg] = Base.PkgId[ext]
            else
                push!(parent_to_exts[pkg], ext)
            end
        end
    end

    project_deps = [
        Base.PkgId(uuid, name)
        for (name, uuid) in env.project_deps if !Base.in_sysimage(Base.PkgId(uuid, name))
    ]

    # consider exts of project deps to be project deps so that errors are reported
    append!(project_deps, keys(filter(d->last(d).name in keys(env.project_deps), ext_to_parent)))

    # An extension effectively depends on another extension if it has a strict superset of its triggers
    for ext_a in keys(ext_to_parent)
        for ext_b in keys(ext_to_parent)
            if triggers[ext_a] ⊋ triggers[ext_b]
                push!(triggers[ext_a], ext_b)
                push!(direct_deps[ext_a], ext_b)
            end
        end
    end

    # A package depends on an extension if it (indirectly) depends on all extension triggers
    function expand_indirect_dependencies(direct_deps)
        local indirect_deps = Dict{Base.PkgId, Set{Base.PkgId}}()
        for package in keys(direct_deps)
            # Initialize a set to keep track of all dependencies for 'package'
            all_deps = Set{Base.PkgId}()
            visited = Set{Base.PkgId}()
            _visit_indirect_deps!(direct_deps, visited, package, all_deps)
            # Update direct_deps with the complete set of dependencies for 'package'
            indirect_deps[package] = all_deps
        end
        return indirect_deps
    end

    # This loop must be run after the full direct_deps map has been populated.
    # Iterate to a fixed point because adding an extension edge (e.g. ExtA → TopPkg)
    # may cause another extension (e.g. ExtAB, which depends on ExtA) to become
    # loadable in TopPkg on the next iteration.
    changed = true
    while changed
        changed = false
        indirect_deps = expand_indirect_dependencies(direct_deps)
        for ext in keys(ext_to_parent)
            ext_loadable_in_pkg = Dict{Base.PkgId,Bool}()
            for pkg in keys(direct_deps)
                is_trigger = in(pkg, direct_deps[ext])
                is_extension = in(pkg, keys(ext_to_parent))
                has_triggers = issubset(direct_deps[ext], indirect_deps[pkg])
                ext_loadable_in_pkg[pkg] = !is_extension && has_triggers && !is_trigger
            end
            for (pkg, ext_loadable) in ext_loadable_in_pkg
                if ext_loadable && !any((dep)->ext_loadable_in_pkg[dep], direct_deps[pkg])
                    if ext ∉ direct_deps[pkg]
                        # add an edge if the extension is loadable by pkg, and was not loadable in any
                        # of the pkg's dependencies
                        push!(direct_deps[pkg], ext)
                        changed = true
                    end
                end
            end
        end
    end

    serial_deps = Base.PkgId[] # packages that are being precompiled in serial

    if _from_loading
        # if called from loading precompilation it may be a package from another environment stack
        # where we don't have access to the dep graph, so just add as a single package and do serial
        # precompilation of its deps within the job.
        for pkgid in requested_pkgids # In case loading asks for multiple packages
            pkgid === nothing && continue
            if !haskey(direct_deps, pkgid)
                @debug "precompile: package `$(pkgid)` is outside of the environment, so adding as single package serial job"
                direct_deps[pkgid] = Base.PkgId[] # no deps, do them in serial in the job
                push!(project_deps, pkgid) # add to project_deps so it doesn't show up in gray
                push!(serial_deps, pkgid)
            end
        end
    end

    # return early if no deps
    if isempty(direct_deps)
        if isempty(pkgs)
            return
        else
            error("No direct dependencies outside of the sysimage found matching $(pkgs)")
        end
    end

    # initialize signalling
    started = Dict{PkgConfig,Bool}()
    was_processed = Dict{PkgConfig,Base.Event}()
    was_recompiled = Dict{PkgConfig,Bool}()
    for config in configs
        for pkgid in keys(direct_deps)
            pkg_config = (pkgid, config)
            started[pkg_config] = false
            was_processed[pkg_config] = Base.Event()
            was_recompiled[pkg_config] = false
        end
    end

    # find and guard against circular deps
    cycles = Vector{Base.PkgId}[]
    # For every scanned package, true if pkg found to be in a cycle
    # or depends on packages in a cycle and false otherwise.
    could_be_cycle = Dict{Base.PkgId, Bool}()
    # temporary stack for the SCC-like algorithm below
    stack = Base.PkgId[]

    # set of packages that depend on a cycle (either because they are
    # a part of a cycle themselves or because they transitively depend
    # on a package in some cycle)
    circular_deps = Base.PkgId[]
    for pkg in keys(direct_deps)
        @assert isempty(stack)
        pkg in serial_deps && continue # skip serial deps as we don't have their dependency graph
        if scan_pkg!(stack, could_be_cycle, cycles, pkg, direct_deps)
            push!(circular_deps, pkg)
            for (pkg_config, evt) in was_processed
                # notify all to allow skipping
                pkg_config[1] == pkg && notify(evt)
            end
        end
    end
    if !isempty(circular_deps)
        @warn excluded_circular_deps_explanation(io, ext_to_parent, circular_deps, cycles)
    end

    # Filter to specific requested packages if the caller asked for a subset
    if !isempty(pkg_names)
        keep = Set{Base.PkgId}()
        for dep_pkgid in keys(direct_deps)
            if dep_pkgid.name in pkg_names
                push!(keep, dep_pkgid)
                collect_all_deps(direct_deps, dep_pkgid, keep)
            end
        end
        # Also keep packages that were explicitly requested as PkgIds (for extensions)
        if pkgs isa Vector{PkgId}
            for requested_pkgid in requested_pkgids
                if haskey(direct_deps, requested_pkgid)
                    push!(keep, requested_pkgid)
                    collect_all_deps(direct_deps, requested_pkgid, keep)
                end
            end
        end
        for ext in keys(ext_to_parent)
            if issubset(collect_all_deps(direct_deps, ext), keep) # if all extension deps are kept
                push!(keep, ext)
            end
        end
        filter!(d->in(first(d), keep), direct_deps)
    end

    if isempty(direct_deps)
        if _from_loading
            # if called from loading precompilation it may be a package from another environment stack so
            # don't error and allow serial precompilation to try
            # TODO: actually handle packages from other envs in the stack
            return
        else
            return
        end
    end

    target = Ref{Union{Nothing, String}}(nothing)
    if nconfigs == 1
        if !isempty(only(configs)[1])
            target[] = "for configuration $(join(only(configs)[1], " "))"
        end
    else
        target[] = "for $nconfigs compilation configurations..."
    end

    pkg_queue = PkgConfig[]
    failed_deps = Dict{PkgConfig, String}()
    precomperr_deps = PkgConfig[] # packages that may succeed after a restart (i.e. loaded packages with no cache file)

    print_lock = io.io isa Base.LibuvStream ? io.io.lock::ReentrantLock : ReentrantLock()
    first_started = Base.Event()
    printloop_should_exit = Ref{Bool}(!fancyprint) # exit print loop immediately if not fancy printing
    interrupted_or_done = Ref{Bool}(false)

    ansi_moveup(n::Int) = string("\e[", n, "A")
    ansi_movecol1 = "\e[1G"
    ansi_cleartoend = "\e[0J"
    ansi_cleartoendofline = "\e[0K"
    ansi_enablecursor = "\e[?25h"
    ansi_disablecursor = "\e[?25l"
    n_done = Ref(0)
    n_already_precomp = Ref(0)
    n_loaded = Ref(0)
    loaded_pkgs = Base.PkgId[]
    interrupted = Ref(false)
    t_print = Ref{Task}()

    function handle_interrupt(err, in_printloop::Bool)
        if err isa InterruptException
            # record that this interrupted_or_done was from InterruptException
            interrupted[] = true
        end
        interrupted_or_done[] = true
        # notify all Event sources
        for (pkg_config, evt) in was_processed
            notify(evt)
        end
        notify(first_started)
        in_printloop || (isassigned(t_print) && wait(t_print[])) # Wait to let the print loop cease first. This makes the printing incorrect, so we shouldn't wait here, but we do anyways.
        if err isa InterruptException
            @lock print_lock begin
                println(io, " Interrupted: Exiting precompilation...", ansi_cleartoendofline)
            end
            return true
        else
            return false
        end
    end
    std_outputs = Dict{PkgConfig,IOBuffer}()
    taskwaiting = Set{PkgConfig}()
    pkgspidlocked = Dict{PkgConfig,String}()
    pkg_liveprinted = Ref{Union{Nothing, PkgId}}(nothing)

    ## fancy print loop
    t_print[] = @async begin
        try
            wait(first_started)
            (isempty(pkg_queue) || interrupted_or_done[]) && return
            @lock print_lock begin
                if target[] !== nothing
                    printpkgstyle(logio, :Precompiling, target[])
                end
                if fancyprint
                    print(logio, ansi_disablecursor)
                end
            end
            t = Timer(0; interval=1/10)
            anim_chars = ["◐","◓","◑","◒"]
            i = 1
            last_length = 0
            bar = MiniProgressBar(; indent=0, header = "Precompiling packages ", color = :green, percentage=false, always_reprint=true)
            n_total = length(direct_deps) * length(configs)
            bar.max = n_total - n_already_precomp[]
            final_loop = false
            n_print_rows = 0
            while !printloop_should_exit[]
                @lock print_lock begin
                    term_size = displaysize(logio)::Tuple{Int, Int}
                    num_deps_show = max(term_size[1] - 3, 2) # show at least 2 deps
                    pkg_queue_show = if !interrupted_or_done[] && length(pkg_queue) > num_deps_show
                        last(pkg_queue, num_deps_show)
                    else
                        pkg_queue
                    end
                    local i_local = i
                    local final_loop_local = final_loop
                    str_ = sprint() do iostr
                        if i_local > 1
                            print(iostr, ansi_cleartoend)
                        end
                        # max(0,...) guards against a race where the print loop runs after
                        # n_already_precomp is incremented but before n_done is incremented,
                        # which would otherwise produce a negative value and crash repeat().
                        bar.current = max(0, n_done[] - n_already_precomp[])
                        bar.max = max(0, n_total - n_already_precomp[])
                        # when sizing to the terminal width subtract a little to give some tolerance to resizing the
                        # window between print cycles
                        termwidth = (displaysize(io)::Tuple{Int,Int})[2] - 4
                        if !final_loop_local
                            s = sprint(io -> show_progress(io, bar; termwidth, carriagereturn=false); context=logio)
                            print(iostr, Base._truncate_at_width_or_chars(true, s, termwidth), "\n")
                        end
                        for pkg_config in pkg_queue_show
                            dep, config = pkg_config
                            loaded = warn_loaded && haskey(Base.loaded_modules, dep)
                            local flags, cacheflags = config
                            name = describe_pkg(dep, dep in project_deps, dep in serial_deps, flags, cacheflags)
                            line = if pkg_config in precomperr_deps
                                string(color_string("  ? ", Base.warn_color()), name)
                            elseif haskey(failed_deps, pkg_config)
                                string(color_string("  ✗ ", Base.error_color()), name)
                            elseif was_recompiled[pkg_config]
                                !loaded && interrupted_or_done[] && continue
                                loaded || @async begin # keep successful deps visible for short period
                                    sleep(1);
                                    filter!(!isequal(pkg_config), pkg_queue)
                                end
                                string(color_string("  ✓ ", loaded ? Base.warn_color() : :green), name)
                            elseif started[pkg_config]
                                # Offset each spinner animation using the first character in the package name as the seed.
                                # If not offset, on larger terminal fonts it looks odd that they all sync-up
                                anim_char = anim_chars[(i_local + Int(dep.name[1])) % length(anim_chars) + 1]
                                anim_char_colored = dep in project_deps ? anim_char : color_string(anim_char, :light_black)
                                waiting = if haskey(pkgspidlocked, pkg_config)
                                    who_has_lock = pkgspidlocked[pkg_config]
                                    color_string(" Being precompiled by $(who_has_lock)", Base.info_color())
                                elseif pkg_config in taskwaiting
                                    color_string(" Waiting for background task / IO / timer. Interrupt to inspect", Base.warn_color())
                                else
                                    ""
                                end
                                string("  ", anim_char_colored, " ", name, waiting)
                            else
                                string("    ", name)
                            end
                            println(iostr, Base._truncate_at_width_or_chars(true, line, termwidth))
                        end
                    end
                    last_length = length(pkg_queue_show)
                    n_print_rows = count("\n", str_)
                    print(logio, str_)
                    printloop_should_exit[] = interrupted_or_done[] && final_loop
                    final_loop = interrupted_or_done[] # ensures one more loop to tidy last task after finish
                    i += 1
                    printloop_should_exit[] || print(logio, ansi_moveup(n_print_rows), ansi_movecol1)
                end
                wait(t)
            end
        catch err
            @info :err0 err
            # For debugging:
            # println("Task failed $err")
            # Base.display_error(ErrorException(""), Base.catch_backtrace())
            handle_interrupt(err, true) || rethrow()
        finally
            fancyprint && print(logio, ansi_enablecursor)
        end
    end

    tasks = Task[]
    if !_from_loading
        @lock Base.require_lock begin
            Base.LOADING_CACHE[] = Base.LoadingCache()
        end
    end
    @debug "precompile: starting precompilation loop" direct_deps project_deps
    ## precompilation loop

    for (pkg, deps) in direct_deps
        cachepaths = Base.find_all_in_cache_path(pkg)
        freshpaths = String[]
        cachepath_cache[pkg] = freshpaths
        sourcespec = Base.locate_package_load_spec(pkg)
        single_requested_pkg = length(requested_pkgs) == 1 &&
            (pkg in requested_pkgids || pkg.name in pkg_names)
        for config in configs
            pkg_config = (pkg, config)
            if sourcespec === nothing
                failed_deps[pkg_config] = "Error: Missing source file for $(pkg)"
                notify(was_processed[pkg_config])
                continue
            end
            # Heuristic for when precompilation is disabled, which must not over-estimate however for any dependent
            # since it will also block precompilation of all dependents
            if _from_loading && single_requested_pkg && occursin(r"\b__precompile__\(\s*false\s*\)", read(sourcespec.path, String))
                @lock print_lock begin
                    Base.@logmsg logcalls "Disabled precompiling $(repr("text/plain", pkg)) since the text `__precompile__(false)` was found in file."
                end
                notify(was_processed[pkg_config])
                continue
            end
            local flags, cacheflags = config
            task = @async begin
                try
                    loaded = warn_loaded && haskey(Base.loaded_modules, pkg)
                    for dep in deps # wait for deps to finish
                        wait(was_processed[(dep,config)])
                        if interrupted_or_done[]
                            return
                        end
                    end
                    circular = pkg in circular_deps
                    freshpath = Base.compilecache_freshest_path(pkg; ignore_loaded, stale_cache, cachepath_cache, cachepaths, sourcespec, flags=cacheflags)
                    is_stale = freshpath === nothing
                    if !is_stale
                        push!(freshpaths, freshpath)
                    end
                    if !circular && is_stale
                        Base.acquire(parallel_limiter)
                        is_serial_dep = pkg in serial_deps
                        is_project_dep = pkg in project_deps

                        # std monitoring
                        std_pipe = Base.link_pipe!(Pipe(); reader_supports_async=true, writer_supports_async=true)
                        t_monitor = @async _precompilepkgs_monitor_std(pkg_config, std_pipe,
                            single_requested_pkg, ext_to_parent, hascolor, std_outputs, taskwaiting,
                            pkg_liveprinted, print_lock, io, fancyprint, ansi_cleartoendofline)

                        local name
                        try
                            name = describe_pkg(pkg, is_project_dep, is_serial_dep, flags, cacheflags)
                            @lock print_lock begin
                                if !fancyprint && isempty(pkg_queue)
                                    printpkgstyle(logio, :Precompiling, something(target[], "packages..."))
                                end
                            end
                            push!(pkg_queue, pkg_config)
                            started[pkg_config] = true
                            fancyprint && notify(first_started)
                            if interrupted_or_done[]
                                return
                            end
                            # for extensions, any extension that can trigger it needs to be accounted for here (even stdlibs, which are excluded from direct_deps)
                            loadable_exts = haskey(ext_to_parent, pkg) ? filter((dep)->haskey(ext_to_parent, dep), triggers[pkg]) : nothing

                            flags_ =if !isempty(deps)
                                # if deps is empty, either it doesn't have any (so compiled-modules is
                                # irrelevant) or we couldn't compute them (so we actually should attempt
                                # serial compile, as the dependencies are not in the parallel list)
                                `$flags --compiled-modules=strict`
                            else
                                flags
                            end

                            if _from_loading && pkg in requested_pkgids
                                # loading already took the cachefile_lock and printed logmsg for its explicit requests
                                t = @elapsed ret = begin
                                    Base.compilecache(pkg, sourcespec, std_pipe, std_pipe, !ignore_loaded;
                                                      flags=flags_, cacheflags, loadable_exts)
                                end
                            else
                                # allows processes to wait if another process is precompiling a given package to
                                # a functionally identical package cache (except for preferences, which may differ)
                                fullname = full_name(ext_to_parent, pkg)
                                t = @elapsed ret = precompile_pkgs_maybe_cachefile_lock(io, print_lock, fancyprint, pkg_config, pkgspidlocked, hascolor, parallel_limiter, fullname) do
                                    # refresh and double-check the search now that we have global lock
                                    if interrupted_or_done[]
                                        return ErrorException("canceled")
                                    end
                                    local cachepaths = Base.find_all_in_cache_path(pkg)
                                    local freshpath = Base.compilecache_freshest_path(pkg; ignore_loaded, stale_cache, cachepath_cache, cachepaths, sourcespec, flags=cacheflags)
                                    local is_stale = freshpath === nothing
                                    if !is_stale
                                        push!(freshpaths, freshpath)
                                        return nothing # returning nothing indicates another process did the recompile
                                    end
                                    logcalls === CoreLogging.Debug && @lock print_lock begin
                                        @debug "Precompiling $(repr("text/plain", pkg))"
                                    end
                                    Base.compilecache(pkg, sourcespec, std_pipe, std_pipe, !ignore_loaded;
                                                      flags=flags_, cacheflags, loadable_exts)
                                end
                            end
                            if ret isa Exception
                                push!(precomperr_deps, pkg_config)
                                !fancyprint && @lock print_lock begin
                                    println(logio, _timing_string(t), color_string("  ? ", Base.warn_color()), name)
                                end
                            else
                                !fancyprint && @lock print_lock begin
                                    println(logio, _timing_string(t), color_string("  ✓ ", loaded ? Base.warn_color() : :green), name)
                                end
                                if ret !== nothing
                                    was_recompiled[pkg_config] = true
                                    cachefile, _ = ret::Tuple{String, Union{Nothing, String}}
                                    push!(freshpaths, cachefile)
                                    build_id, _ = Base.parse_cache_buildid(cachefile)
                                    stale_cache_key = (pkg, build_id, sourcespec, cachefile, ignore_loaded, cacheflags)::StaleCacheKey
                                    stale_cache[stale_cache_key] = false
                                    if loaded && Base.module_build_id(Base.loaded_modules[pkg]) != build_id
                                        n_loaded[] += 1
                                        @lock print_lock push!(loaded_pkgs, pkg)
                                    end
                                elseif loaded
                                    # another process compiled this package; conservatively warn
                                    n_loaded[] += 1
                                    @lock print_lock push!(loaded_pkgs, pkg)
                                end
                            end
                        catch err
                            @info :err1 err
                            close(std_pipe.in) # close pipe to end the std output monitor
                            wait(t_monitor)
                            if err isa ErrorException || (err isa ArgumentError && startswith(err.msg, "Invalid header in cache file"))
                                failed_deps[pkg_config] = sprint(showerror, err)
                                !fancyprint && @lock print_lock begin
                                    println(logio, " "^12, color_string("  ✗ ", Base.error_color()), name)
                                end
                            else
                                rethrow()
                            end
                        finally
                            isopen(std_pipe.in) && close(std_pipe.in) # close pipe to end the std output monitor
                            wait(t_monitor)
                            Base.release(parallel_limiter)
                        end
                    else
                        if !is_stale
                            n_already_precomp[] += 1
                            if loaded
                                fresh_build_id, _ = Base.parse_cache_buildid(freshpath)
                                if Base.module_build_id(Base.loaded_modules[pkg]) != fresh_build_id
                                    n_loaded[] += 1
                                    @lock print_lock push!(loaded_pkgs, pkg)
                                end
                            end
                        end
                    end
                    n_done[] += 1
                    notify(was_processed[pkg_config])
                catch err_outer
                    @info :err_outer2 err_outer
                    # For debugging:
                    println("Task failed $err_outer")
                    Base.display_error(ErrorException(""), Base.catch_backtrace())# logging doesn't show here
                    handle_interrupt(err_outer, false)
                    rethrow()
                end
            end
            push!(tasks, task)
        end
    end
    try
        waitall(tasks; failfast=false, throw=false)
        interrupted_or_done[] = true
    catch err
        @info :err3 err
        # For debugging:
        println("Task failed $err")
        Base.display_error(ErrorException(""), Base.catch_backtrace())# logging doesn't show here
        handle_interrupt(err, false) || rethrow()
    finally
        try
            waitall(tasks; failfast=false, throw=false)
        finally
            @lock Base.require_lock begin
                Base.LOADING_CACHE[] = nothing
            end
        end
    end
    notify(first_started) # in cases of no-op or !fancyprint
    fancyprint && isassigned(t_print) && wait(t_print[])
    quick_exit = any(t -> !istaskdone(t) || istaskfailed(t), tasks) || interrupted[] # all should have finished (to avoid memory corruption)
    seconds_elapsed = round(Int, (time_ns() - time_start) / 1e9)
    ndeps = count(values(was_recompiled))
    # Determine if any of failures were a requested package
    requested_errs = false
    for ((dep, config), err) in failed_deps
        if dep in requested_pkgids
            requested_errs = true
            break
        end
    end
    # if every requested package succeeded, filter away output from failed packages
    # since it didn't contribute to the overall success and can be regenerated if that package is later required
    if !strict && !requested_errs
        for (pkg_config, err) in failed_deps
            delete!(std_outputs, pkg_config)
        end
        empty!(failed_deps)
    end
    if ndeps > 0 || !isempty(failed_deps)
        if !quick_exit
            logstr = sprint(context=logio) do iostr
                if fancyprint # replace the progress bar
                    what = isempty(requested_pkgids) ? "packages finished." : "$(join((full_name(ext_to_parent, p) for p in requested_pkgids), ", ", " and ")) finished."
                    printpkgstyle(iostr, :Precompiling, what)
                end
                plural = length(configs) > 1 ? "dependency configurations" : ndeps == 1 ? "dependency" : "dependencies"
                print(iostr, "  $(ndeps) $(plural) successfully precompiled in $(seconds_elapsed) seconds")
                if n_already_precomp[] > 0 || !isempty(circular_deps)
                    n_already_precomp[] > 0 && (print(iostr, ". $(n_already_precomp[]) already precompiled"))
                    !isempty(circular_deps) && (print(iostr, ". $(length(circular_deps)) skipped due to circular dependency"))
                    print(iostr, ".")
                end
                if n_loaded[] > 0
                    local plural1 = length(configs) > 1 ? "dependency configurations" : n_loaded[] == 1 ? "dependency" : "dependencies"
                    local plural2 = n_loaded[] == 1 ? "a different version is" : "different versions are"
                    local plural3 = n_loaded[] == 1 ? "" : "s"
                    local loaded_names = join(sort!([full_name(ext_to_parent, p) for p in loaded_pkgs]), ", ", " and ")
                    # compute how many precompiled packages transitively depend on the loaded packages
                    local n_affected = 0
                    local loaded_set = Set{Base.PkgId}(loaded_pkgs)
                    let reverse_deps = Dict{Base.PkgId, Vector{Base.PkgId}}()
                        for (p, deps) in direct_deps
                            for d in deps
                                push!(get!(Vector{Base.PkgId}, reverse_deps, d), p)
                            end
                        end
                        affected = Set{Base.PkgId}()
                        frontier = Base.PkgId[p for p in loaded_set]
                        while !isempty(frontier)
                            p = pop!(frontier)
                            for rdep in get(reverse_deps, p, Base.PkgId[])
                                if rdep ∉ affected && rdep ∉ loaded_set
                                    push!(affected, rdep)
                                    push!(frontier, rdep)
                                end
                            end
                        end
                        n_affected = length(affected)
                    end
                    print(iostr, "\n  ",
                        color_string(string(n_loaded[]), Base.warn_color()),
                        " $(plural1) precompiled but ",
                        color_string("$(plural2) currently loaded", Base.warn_color()),
                        " (", loaded_names, ")",
                        ". Restart julia to access the new version$(plural3)."
                    )
                    if n_affected > 0
                        local affected_plural = length(configs) > 1 ? "dependency configurations" : n_affected == 1 ? "dependent" : "dependents"
                        print(iostr,
                            " Otherwise, $(n_affected) $(affected_plural) of ",
                            n_loaded[] == 1 ? "this package" : "these packages",
                            " may trigger further precompilation to work with the unexpected version$(plural3)."
                        )
                    end
                end
                if !isempty(precomperr_deps)
                    pluralpc = length(configs) > 1 ? "dependency configurations" : precomperr_deps == 1 ? "dependency" : "dependencies"
                    print(iostr, "\n  ",
                        color_string(string(length(precomperr_deps)), Base.warn_color()),
                        " $(pluralpc) failed but may be precompilable after restarting julia"
                    )
                end
            end
            @lock print_lock begin
                println(logio, logstr)
            end
        end
    end
    if !isempty(std_outputs)
        str = sprint(context=io) do iostr
            # show any stderr output, even if Pkg.precompile has been interrupted (quick_exit=true), given user may be
            # interrupting a hanging precompile job with stderr output.
            let std_outputs = Tuple{PkgConfig,SubString{String}}[(pkg_config, strip(String(take!(io)))) for (pkg_config,io) in std_outputs]
                filter!(!isempty∘last, std_outputs)
                if !isempty(std_outputs)
                    local plural1 = length(std_outputs) == 1 ? "y" : "ies"
                    local plural2 = length(std_outputs) == 1 ? "" : "s"
                    print(iostr, "\n  ", color_string("$(length(std_outputs))", Base.warn_color()), " dependenc$(plural1) had output during precompilation:")
                    for (pkg_config, err) in std_outputs
                        pkg, config = pkg_config
                        err = if pkg == pkg_liveprinted[]
                            "[Output was shown above]"
                        else
                            join(split(err, "\n"), color_string("\n│  ", Base.warn_color()))
                        end
                        name = full_name(ext_to_parent, pkg)
                        print(iostr, color_string("\n┌ ", Base.warn_color()), name, color_string("\n│  ", Base.warn_color()), err, color_string("\n└  ", Base.warn_color()))
                    end
                end
            end
        end
        isempty(str) || @lock print_lock begin
            println(io, str)
        end
    end
    # Done cleanup and sub-process output, now ensure caller aborts too with the right error
    if interrupted[]
        throw(InterruptException())
    end
    # Fail noisily now with failed_deps if any.
    # Include all messages from compilecache since any might be relevant in the failure.
    if !isempty(failed_deps)
        err_str = IOBuffer()
        for ((dep, config), err) in failed_deps
            write(err_str, "\n")
            print(err_str, "\n", full_name(ext_to_parent, dep), " ")
            join(err_str, config[1], " ")
            print(err_str, "\n", err)
        end
        n_errs = length(failed_deps)
        pluraled = n_errs == 1 ? "" : "s"
        err_msg = "The following $n_errs package$(pluraled) failed to precompile:$(String(take!(err_str)))\n"
        if internal_call
            # Pkg does not implement correct error handling, so this sometimes handles them instead
            print(io, err_msg)
        else
            throw(PkgPrecompileError(err_msg))
        end
    end
    return collect(String, Iterators.flatten((v for (pkgid, v) in cachepath_cache if pkgid in requested_pkgids)))
end # function _precompilepkgs

end # module BasePrecompilation43e9d32010
