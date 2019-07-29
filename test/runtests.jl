using CcallMacros: @ccall, @cdef, @disable_sigint, @check_syserr, parsecall
using Test

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
call = @macroexpand @ccall libstring.func(
    str::Cstring,
    num1::Cint,
    num2::Cint
)::Cstring

@test call == :(
    ccall((:func, libstring), Cstring,
          (Cstring, Cint, Cint), str, num1, num2)
)

# test ccall with varargs
call = @macroexpand @ccall printf(
    "%d, %d, %d\n"::Cstring, 1, 2, 3; varargs=Cint
)::Cint
@test call == :(
    ccall(:printf, Cint, (Cstring, Cint...), "%d, %d, %d\n", 1, 2, 3)
)


# call some c functions
@test @ccall(sqrt(4.0::Cdouble)::Cdouble) == 2.0

const STRING = "hello"
const BUFFER = Ptr{UInt8}(Libc.malloc((length(STRING) + 1) * sizeof(Cchar)))
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
