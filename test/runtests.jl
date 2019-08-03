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
        ["%d", :value]        # argument symbols
    )
end

@testset "ensure the base-case of @ccall works, including library name" begin
    call = @macroexpand @ccall libstring.func(
        str::Cstring,
        num1::Cint,
        num2::Cint
    )::Cstring

    @test call == :(
        ccall((:func, libstring), Cstring,
            (Cstring, Cint, Cint), str, num1, num2)
    )
end

@testset "ensure @ccall handles varargs correctly" begin
    call = @macroexpand @ccall printf(
        "%d, %d, %d\n"::Cstring ; 1::Cint, 2::Cint, 3::Cint
    )::Cint
    @test call == :(
        ccall(:printf, Cint, (Cstring, Cint...), "%d, %d, %d\n", 1, 2, 3)
    )
end

@testset "ensure parsecall throws errors appropriately" begin
    # missing return type
    @test_throws CcallError parsecall(:( foo(4.0::Cdouble )))
    # not a function call
    @test_throws CcallError parsecall(:( foo::Type ))
    # mismatched types on varargs
    @test_throws CcallError parsecall(:( foo(x::Cint; y::Cstring, z::Cint)::Cvoid ))
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
