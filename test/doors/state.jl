module test_doors_state

using Test
using Doors: Doors

modkey = Base.PkgId(Base.UUID("c599478c-de41-4aed-94ea-b47665d7a42a"), "EmojiSymbols")

@test !Base.root_module_exists(modkey)

Doors.save()

using EmojiSymbols
@test Base.root_module_exists(modkey)

target_modules = Doors.save()
@test last(target_modules) === EmojiSymbols

Base.unreference_module(modkey)

newm = Doors.load_package(modkey)
@test newm === EmojiSymbols
@test Base.root_module_exists(modkey)

Base.unreference_module(modkey)

loaded_modules = Doors.load()
@test last(loaded_modules) === EmojiSymbols

@test Base.root_module_exists(modkey)

Base.unreference_module(modkey)

@test !Base.root_module_exists(modkey)

end # module test_doors_state
