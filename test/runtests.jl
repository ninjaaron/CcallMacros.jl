using CcallMacros: @ccall, @cdef, @disable_sigint, @check_syserr, parsecall
using Test

const STRING = "hello"
const BUFFER = Ptr{UInt8}(Libc.malloc((length(STRING) + 1) * sizeof(Cchar)))
const CALLEXPR = :(
    libc.printf("%d"::Cstring, value::Cuint)::CVoid
)

# test parsecall
@test parsecall(CALLEXPR) == (
    :(:printf, libc),     # function
    :CVoid,               # return type
    :((Cstring, Cuint)),  # argument types
    ["%d", :value]        # argument symbols
)

# test ccall
@ccall strcpy(BUFFER::Cstring, STRING::Cstring)::Cstring
@test unsafe_string(BUFFER) == STRING

# let's write C in Julia. Uppercasing the hard way.
let buffer = BUFFER
    while (byte = unsafe_load(buffer)) != 0x00
        bigger = @ccall toupper(byte::Cint)::Cint
        unsafe_store!(buffer, bigger) 
        buffer += 1
    end
end

@test unsafe_string(BUFFER) == uppercase(STRING)
Libc.free(BUFFER)
