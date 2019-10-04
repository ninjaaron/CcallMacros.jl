using Test
using CcallMacros: @ccall, ccall_macro_parse, ccall_macro_lower

@testset "test basic ccall_macro_parse functionality" begin
    callexpr = :(
        libc.printf("%s = %d\n"::Cstring ; name::Cstring, value::Cint)::Cvoid
    )
    @test ccall_macro_parse(callexpr) == (
        :((:printf, libc)),               # function
        :Cvoid,                           # returntype
        Any[:Cstring, :Cstring, :Cint],   # argument types
        Any["%s = %d\n", :name, :value],  # argument symbols
        1                                 # number of required arguments (for varargs)
    )
end

@testset "ensure the base-case of @ccall works, including library name and pointer interpolation" begin
    call = ccall_macro_lower(:ccall, ccall_macro_parse( :( libstring.func(
        str::Cstring,
        num1::Cint,
        num2::Cint
    )::Cstring))...)
    @test call == Base.remove_linenums!(
        quote
        arg1root = Base.cconvert($(Expr(:escape, :Cstring)), $(Expr(:escape, :str)))
        arg1 = Base.unsafe_convert($(Expr(:escape, :Cstring)), arg1root)
        arg2root = Base.cconvert($(Expr(:escape, :Cint)), $(Expr(:escape, :num1)))
        arg2 = Base.unsafe_convert($(Expr(:escape, :Cint)), arg2root)
        arg3root = Base.cconvert($(Expr(:escape, :Cint)), $(Expr(:escape, :num2)))
        arg3 = Base.unsafe_convert($(Expr(:escape, :Cint)), arg3root)
        $(Expr(:foreigncall,
               :($(Expr(:escape, :((:func, libstring))))),
               :($(Expr(:escape, :Cstring))),
               :($(Expr(:escape, :(($(Expr(:core, :svec)))(Cstring, Cint, Cint))))),
               0,
               :(:ccall),
               :arg1, :arg2, :arg3, :arg1root, :arg2root, :arg3root))
        end)

    # pointer interpolation
    call = ccall_macro_lower(:ccall, ccall_macro_parse(:( $(Expr(:$, :fptr))("bar"::Cstring)::Cvoid ))...)
    @test Base.remove_linenums!(call) == Base.remove_linenums!(
    quote
        func = $(Expr(:escape, :fptr))
        begin
            if !(func isa Ptr{Cvoid})
                name = :fptr
                throw(ArgumentError("interpolated function `$(name)` was not a Ptr{Cvoid}, but $(typeof(func))"))
            end
        end
        arg1root = Base.cconvert($(Expr(:escape, :Cstring)), $(Expr(:escape, "bar")))
        arg1 = Base.unsafe_convert($(Expr(:escape, :Cstring)), arg1root)
        $(Expr(:foreigncall, :func, :($(Expr(:escape, :Cvoid))), :($(Expr(:escape, :(($(Expr(:core, :svec)))(Cstring))))), 0, :(:ccall), :arg1, :arg1root))
    end)

end

@testset "check error paths" begin
    # missing return type
    @test_throws ArgumentError("@ccall needs a function signature with a return type") ccall_macro_parse(:( foo(4.0::Cdouble )))
    # not a function call
    @test_throws ArgumentError("@ccall has to take a function call") ccall_macro_parse(:( foo::Type ))
    # missing type annotations on arguments
    @test_throws ArgumentError("args in @ccall need type annotations. 'x' doesn't have one.") ccall_macro_parse(:( foo(x)::Cint ))
    # missing type annotations on varargs arguments
    @test_throws ArgumentError("args in @ccall need type annotations. 'y' doesn't have one.") ccall_macro_parse(:( foo(x::Cint ; y)::Cint ))
    # no reqired args on varargs call
    @test_throws ArgumentError("C ABI prohibits vararg without one required argument") ccall_macro_parse(:( foo(; x::Cint)::Cint ))
    # not a function pointer
    @test_throws ArgumentError("interpolated function `PROGRAM_FILE` was not a Ptr{Cvoid}, but String") @ccall $PROGRAM_FILE("foo"::Cstring)::Cvoid
end


# call some c functions
@testset "run @ccall with C standard library functions" begin
    @test @ccall(sqrt(4.0::Cdouble)::Cdouble) == 2.0

    str = "hello"
    buf = Ptr{UInt8}(Libc.malloc((length(str) + 1) * sizeof(Cchar)))
    @ccall strcpy(buf::Cstring, str::Cstring)::Cstring
    @test unsafe_string(buf) == str
    Libc.free(buf)

    # test pointer interpolation
    str_identity = @cfunction(identity, Cstring, (Cstring,))
    foo = @ccall $str_identity("foo"::Cstring)::Cstring
    @test unsafe_string(foo) == "foo"
    # test interpolation of an expresison that returns a pointer.
    foo = @ccall $(@cfunction(identity, Cstring, (Cstring,)))("foo"::Cstring)::Cstring
    @test unsafe_string(foo) == "foo"

    # test of a vararg foreigncall using @ccall
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
