module CcallMacros
export @ccall, @cdef, @disable_sigint, @check_syserr

"""
    parsecall(expression)

`parsecall` is an implementation detail of `@ccall

it takes and expression like `:(printf("%d"::Cstring, value::Cuint)::Cvoid)`
returns: a tuple of `(function_name, return_type, arg_types, args)`

The above input outputs this:

    (:printf, :Cvoid, [:Cstring, :Cuint], ["%d", :value])
"""
function parsecall(expr::Expr)
    # setup and check for errors
    if !Meta.isexpr(expr, :(::))
        throw(ArgumentError("@ccall needs a function signature with a return type"))
    end
    rettype = expr.args[2]

    call = expr.args[1]
    if !Meta.isexpr(call, :call)
        throw(ArgumentError("@ccall has to take a function call"))
    end

    # get the function symbols
    func = let f = call.args[1]
        if Meta.isexpr(f, :.)
            :(($(f.args[2]), $(f.args[1])))
        elseif Meta.isexpr(f, :$)
            f.args[1]
        elseif f isa Symbol
            QuoteNode(f)
        else
            throw(ArgumentError("@ccall function name must be a symbol, a `.` node (e.g. `libc.printf`) or an interpolated function pointer (with `\$`)"))
        end
    end

    # detect varargs
    varargs = nothing
    argstart = 2
    callargs = call.args
    if length(callargs) >= 2 && Meta.isexpr(callargs[2], :parameters)
        argstart = 3
        varargs = callargs[2].args
    end

    # collect args and types
    args = []
    types = []

    function pusharg!(arg)
        if !Meta.isexpr(arg, :(::))
            throw(ArgumentError("args in @ccall need type annotations. '$(repr(arg))' doesn't have one."))
        end
        push!(args, arg.args[1])
        push!(types, arg.args[2])
    end

    for i in argstart:length(callargs)
        pusharg!(callargs[i])
    end
    # add any varargs if necessary
    nreq = 0
    if !isnothing(varargs)
        nreq = length(args)
        for a in varargs
            pusharg!(a)
        end
    end

    return func, rettype, types, args, nreq
end

function lower(convention, func, rettype, types, args, nreq)
    lowering = []
    realargs = []
    gcroots = []

    # if interpolation was used, ensure  variable is a function pointer at runtime.
    if func isa Symbol
        check = quote
            func = $(esc(func))
            if !isa(func, Ptr{Nothing})
                name = $(QuoteNode(func))
                throw(ArgumentError("interpolated function `$name` was not a Ptr{Nothing}, but $(typeof(func))"))
            end
        end
        push!(lowering, check)
    end

    for (i, (arg, type)) in enumerate(zip(args, types))
        sym = Symbol(string("arg", i, "root"))
        sym2 = Symbol(string("arg", i, ))
        earg, etype = esc(arg), esc(type)
        push!(lowering, :($sym = Base.cconvert($etype, $earg)))
        push!(lowering, :($sym2 = Base.unsafe_convert($etype, $sym)))
        push!(realargs, sym2)
        push!(gcroots, sym)
    end
    etypes = Expr(:call, Expr(:core, :svec), types...)
    exp = Expr(:foreigncall,
               esc(func),
               esc(rettype),
               esc(etypes),
               nreq,
               QuoteNode(convention),
               realargs..., gcroots...)
    push!(lowering, exp)

    return Expr(:block, lowering...)
end


"""
    @ccall some_c_function(arg::Type [...])::ReturnType

    @ccall calling_convetion some_c_function(arg::Type)::ReturnType

convert a julia-style function definition to a ccall:

    @ccall link(source::Cstring, dest::Cstring)::Cint

same as:

    ccall(:link, Cint, (Cstring, Cstring), source, dest)

All arguments must have type annotations and the return type must also
be annotated.

varargs are supported with the following convention:

    @ccall printf("%s = %d"::Cstring ; "foo"::Cstring, foo::Cint)::Cint

Mind the semicolon.

Using functions from other libraries is supported by prefixing
the function name with the name of the C library, like this:

    const glib = "libglib-2.0"
    @ccall glib.g_uri_escape_string(uri::Cstring, ":/"::Cstring, true::Cint)::Cstring

The string literal could also be used directly before the symbol of
the function name, if desired `"libglib-2.0".g_uri_escape_string(...`
"""
macro ccall(convention, expr)
    return lower(convention, parsecall(expr)...)
end

macro ccall(expr)
    return lower(:ccall, parsecall(expr)...)
end

getsym(arg) = Meta.isexpr(arg, :(::)) ? arg.args[1] : arg
getmacrocall(expr) = begin
    Meta.isexpr(expr, :macrocall) ? Tuple(expr.args) : (nothing, nothing, expr)
end

function cdef(funcname, expr)
    macrocall, lnnode, expr = getmacrocall(expr)
    func, rettype, argtypes, args = parsecall(expr)
    realargs = getsym.(args)
    call = :(ccall($func, $realret, $argtypes))
    append!(call.args, realargs)
    if macrocall != nothing
        call = Expr(:macrocall, macrocall, lnnode, call)
    end
    definition = :($funcname())
    append!(definition.args, args)
    esc(:($definition = $call))
end

"""
define a _very_ thin wrapper function on a ccall. Mostly for wrapping
libraries quickly as a foundation for a higher-level interface.

    @cdef mkfifo(path::Cstring, mode::Cuint)::Cint

becomes:

   mkfifo(path, mode) = ccall(:mkfifo, Cint, (Cstring, Cuint), path, mode)
"""
macro cdef(funcname, expr)
    cdef(funcname, expr)
end

macro cdef(expr)
    _, _, inner = getmacrocall(expr)
    func, _, _, _ = parsecall(inner)
    name = func isa QuoteNode ? func.value : func.args[1].value
    cdef(name, expr)
end

"""
disable SIGINT while expr is being executed. Mostly useful for calling
C functions that call back into Julia in a concurrent context because
memory corruption can occur and crash the whole program.
"""
macro disable_sigint(expr)
    out = quote
        disable_sigint() do
            $expr
        end
    end
    esc(out)
end

"""
throw a system error if the expression returns a non-zero exit status.
"""
macro check_syserr(expr, message=nothing)
    if message == nothing
        message = Base.remove_linenums!(expr) |> string
    end
    return quote
        err = $(esc(expr))
        systemerror($message, err != 0)
    end
end

end # module
