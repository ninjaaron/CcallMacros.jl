using CcallMacros: @ccall, @cdef, @disable_sigint, @nonzeroerr, parsecall
using Test

const STRING = "hello"
const CALLEXPR = :(printf("%d"::Cstring, value::Cuint)::CVoid)

@test parsecall(CALLEXPR) ==
    (:printf, :Cvoid, :((Cstring, Cuint)), ["%d", :value])

# @ccall strcopy(STRING::Cstring)::
