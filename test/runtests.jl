using Test
using CcallMacros: @ccall, parsecall, CcallError

@testset "test basic parsecall functionality" begin
    callexpr = :(
        libc.printf("%d"::Cstring, value::Cuint)::Cvoid
    )
    @test parsecall(callexpr) == (
        :(:printf, libc),     # function
        :Cvoid,               # return type
        :((Cstring, Cuint)),  # argument types
        ["%d", :value],       # argument symbols
        0                     # nreq
    )
end

# @testset "ensure the base-case of @ccall works, including library name" begin
#     call = @macroexpand @ccall libstring.func(
#         str::Cstring,
#         num1::Cint,
#         num2::Cint
#     )::Cstring
#     @test call == (
#     :(let var"%1" = Base.cconvert(Cstring, str), var"%4" = Base.unsafe_convert(Cstring, var"%1"), var"%2" = Base.cconvert(Cint, num1), var"%5" = Base.unsafe_convert(Cint, var"%2"), var"%3" = Base.cconvert(Cint, num2), var"%6" = Base.unsafe_convert(Cint, var"%3")
#       $(Expr(:foreigncall, :((:func, libstring)), :Cstring, :(Core.svec(Cstring, Cint, Cint)), 0, :(:ccall), Symbol("%4"), Symbol("%5"), Symbol("%6"), Symbol("%1"), Symbol("%2"), Symbol("%3")))
#       end)
# end

# @testset "ensure @ccall handles varargs correctly" begin
#     call = @macroexpand @ccall printf("%s = %d\n"::Cstring; "foo"::Cstring, 1::Cint)::Cint
#     @test call == :(let var"%1" = (Base.cconvert)(Cstring, "%s = %d\n"), var"%4" = (Base.unsafe_convert)(Cstring, var"%1"), var"%2" = (Base.cconvert)(Cstring, "foo"), var"%5" = (Base.unsafe_convert)(Cstring, var"%2"), var"%3" = (Base.cconvert)(Cint, 1), var"%6" = (Base.unsafe_convert)(Cint, var"%3")
#         $(Expr(:foreigncall, :(:printf), :Cint, :(Core.svec(Cstring, Cstring, Cint)), 1, :(:ccall), Symbol("%4"), Symbol("%5"), Symbol("%6"), Symbol("%1"), Symbol("%2"), Symbol("%3")))
#     end)
# end

@testset "ensure parsecall throws errors appropriately" begin
    # missing return type
    @test_throws CcallError parsecall(:( foo(4.0::Cdouble )))
    # not a function call
    @test_throws CcallError parsecall(:( foo::Type ))
    # missing type annotations on arguments
    @test_throws CcallError parsecall(:( foo(x)::Cint ))
end



# call some c functions
@testset "run @ccall with C standard library functions" begin
    @test @ccall(sqrt(4.0::Cdouble)::Cdouble) == 2.0

    STRING = "hello"
    BUFFER = Ptr{UInt8}(Libc.malloc((length(STRING) + 1) * sizeof(Cchar)))
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
end
