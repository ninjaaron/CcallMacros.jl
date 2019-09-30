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

@testset "ensure the base-case of @ccall works, including library name and pointer interpolation" begin
    call = lower(:ccall, parsecall( :( libstring.func(
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
    call = lower(:ccall, parsecall(:( $(Expr(:$, :fptr))("bar"::Cstring)::Cvoid ))...)
    @test Base.remove_linenums!(call) == Base.remove_linenums!(
    quote
        begin
            func = $(Expr(:escape, :fptr))
            if !(func isa Ptr{Nothing})
                name = :fptr
                throw(ArgumentError("interpolated function `$(name)` was not a Ptr{Nothing}, but $(typeof(func))"))
            end
        end
        arg1root = Base.cconvert($(Expr(:escape, :Cstring)), $(Expr(:escape, "bar")))
        arg1 = Base.unsafe_convert($(Expr(:escape, :Cstring)), arg1root)
        $(Expr(:foreigncall,
               :($(Expr(:escape, :fptr))),
               :($(Expr(:escape, :Cvoid))),
               :($(Expr(:escape, :(($(Expr(:core, :svec)))(Cstring))))),
               0,
               :(:ccall),
               :arg1, :arg1root))
    end)

end

@testset "check error paths" begin
    # missing return type
    @test_throws ArgumentError parsecall(:( foo(4.0::Cdouble )))
    # not a function call
    @test_throws ArgumentError parsecall(:( foo::Type ))
    # missing type annotations on arguments
    @test_throws ArgumentError parsecall(:( foo(x)::Cint ))
    # not a function pointer
    @test_throws ArgumentError @ccall $PROGRAM_FILE("foo"::Cstring)::Cvoid
end


# call some c functions
@testset "run @ccall with C standard library functions" begin
    @test @ccall(sqrt(4.0::Cdouble)::Cdouble) == 2.0

    str = "hello"
    buf = Ptr{UInt8}(Libc.malloc((length(str) + 1) * sizeof(Cchar)))
    @ccall strcpy(buf::Cstring, str::Cstring)::Cstring
    @test unsafe_string(buf) == str
    Libc.free(buf)

    str_identity = @cfunction(identity, Cstring, (Cstring,))
    foo = @ccall $str_identity("foo"::Cstring)::Cstring
    @test unsafe_string(foo) == "foo"

    # test of foreigncall with varargs, rewritten with @ccall
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
