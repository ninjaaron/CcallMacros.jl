using Test
using CcallMacros: @ccall, parsecall, lower

@testset "test basic parsecall functionality" begin
    callexpr = :(
        libc.printf("%s = %d\n"::Cstring ; name::Cstring, value::Cint)::Cvoid
    )
    @test parsecall(callexpr) == (
        :((:printf, libc)),               # function
        :Cvoid,                           # returntype
        Any[:Cstring, :Cstring, :Cint],   # argument types
        Any["%s = %d\n", :name, :value],  # argument symbols
        1                                 # number of required arguments (for varargs)
    )
end

@testset "ensure the base-case of @ccall works, including library name" begin
    call = lower(:ccall, parsecall( :( libstring.func(
        str::Cstring,
        num1::Cint,
        num2::Cint
    )::Cstring))...)
    @test call == Base.remove_linenums!(quote
        var"%1" = Base.cconvert($(Expr(:escape, :Cstring)), $(Expr(:escape, :str)))
        var"%4" = Base.unsafe_convert($(Expr(:escape, :Cstring)), var"%1")
        var"%2" = Base.cconvert($(Expr(:escape, :Cint)), $(Expr(:escape, :num1)))
        var"%5" = Base.unsafe_convert($(Expr(:escape, :Cint)), var"%2")
        var"%3" = Base.cconvert($(Expr(:escape, :Cint)), $(Expr(:escape, :num2)))
        var"%6" = Base.unsafe_convert($(Expr(:escape, :Cint)), var"%3")
        $(Expr(
            :foreigncall,
            :($(Expr(:escape, :((:func, libstring))))),
            :($(Expr(:escape, :Cstring))),
            :($(Expr(:escape, :(Core.svec(Cstring, Cint, Cint))))),
            0,
            :(:ccall),
            Symbol("%4"), Symbol("%5"), Symbol("%6"),
            Symbol("%1"), Symbol("%2"), Symbol("%3")))
    end)

end

@testset "ensure parsecall throws errors appropriately" begin
    # missing return type
    @test_throws ArgumentError parsecall(:( foo(4.0::Cdouble )))
    # not a function call
    @test_throws ArgumentError parsecall(:( foo::Type ))
    # missing type annotations on arguments
    @test_throws ArgumentError parsecall(:( foo(x)::Cint ))
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

    # jamison's test of foreigncall, rewritten with @ccall
    strp = Ref{Ptr{Cchar}}(0)
    fmt = "hi+%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f\n"

    len = @ccall asprintf(
        strp::Ptr{Ptr{Cchar}},
        fmt::Cstring,
        ; # begin varargs
        0x1::UInt8, 0x2::UInt8, 0x3::UInt8, 0x4::UInt8, 0x5::UInt8, 0x6::UInt8, 0x7::UInt8, 0x8::UInt8, 0x9::UInt8, 0xa::UInt8, 0xb::UInt8, 0xc::UInt8, 0xd::UInt8, 0xe::UInt8, 0xf::UInt8,
        1.1::Cfloat, 2.2::Cfloat, 3.3::Cfloat, 4.4::Cfloat, 5.5::Cfloat, 6.6::Cfloat, 7.7::Cfloat, 8.8::Cfloat, 9.9::Cfloat,
    )::Cint
    str = unsafe_string(strp[], len)
    @ccall free(strp[]::Cstring)::Cvoid
    @test str == "hi+1-2-3-4-5-6-7-8-9-10-11-12-13-14-15-1.1-2.2-3.3-4.4-5.5-6.6-7.7-8.8-9.9\n"
end
