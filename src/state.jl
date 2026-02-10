# module Doors

using Preferences

const doors_state_packages::String = "packages"

function doors_state_key(state::String)::String
    string("state.", state)
end

function load(; state::String = doors_state_packages)::Vector{Module}
    dict = Preferences.load_preference(@__MODULE__, doors_state_key(state))
    loaded_modules = Module[]
    if dict === nothing
        return loaded_modules
    else
        for (name, uuid_str) in pairs(dict)
            uuid = Base.UUID(uuid_str)
            modkey = Base.PkgId(uuid, name)
            if haskey(Base.loaded_modules, modkey)
            else
                newm = load_package(modkey)
                push!(loaded_modules, newm)
            end
        end
        return loaded_modules
    end
end

function load_package(modkey::Base.PkgId)
    Base.require(modkey)
end

function save(; state::String = doors_state_packages)::Vector{Module}
    idx_doors = findfirst(isequal(Doors), Base.loaded_modules_order)
    # Doors      JiveExt
    # idx_doors  idx_doors+1
    target_modules = Base.loaded_modules_order[idx_doors + 2 : end]
    save_packages(target_modules, state)
    return target_modules
end

function save_packages(target_modules::Vector{Module}, state::String)
    dict = Dict{String, Any}()
    for from in target_modules
        name = string(nameof(from))
        modkey = Base.PkgId(from)
        dict[name] = string(modkey.uuid)
    end
    Preferences.set_preferences!(@__MODULE__, doors_state_key(state) => dict; force = true)
end

# module Doors
