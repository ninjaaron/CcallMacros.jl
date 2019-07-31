module CcallMacros
export @ccall, @cdef, @disable_sigint, @check_syserr

struct NoType end

getcfunc(f) = QuoteNode(f)
getcfunc(f::Expr) = :(($(f.args[2]), $(f.args[1])))

"""
Determine if there are varargs and return a vector of all arguments
based on the call signature.

returns a tupel of `(hasvarargs, arguments)`
"""
function getargs(call)
    hasvarargs::Bool = false
    firstarg = call.args[2]
    if firstarg isa Expr && firstarg.head === :parameters
        length(firstarg.args) > 1 || (kw = firstarg.args[1].args)[1] !== :varargs &&
            error("@ccall only takes one keyword argument: varargs")
        hasvarargs = true
        vararg_type = kw[2]
        return vararg_type, hasvarargs, call.args[3:end]
    else
        return Nothing, hasvarargs, call.args[2:end]
    end
end

"""
       mkarg(arg)

`mkarg` takes an argument and returns a tuple of symbol and type. The
argument must have a type annotation or an error will be thrown.
"""
function mkarg(arg)
    if arg.head != :(::)
        error("args in @ccall need type annotations")
    end
    return (arg=arg.args[1], type=arg.args[2])
end

"""
    mkargs(args, has_varargs)

takes an iterable of arguments from a function call and returns an
array of named tuples of (arg=symbol, type=type). If `has_varargs` is
set to `true`, the value of `type` will be set to `NoType`, to be
filtered out later.
"""
function mkargs(args, has_varargs)
    in_vararg::Bool = false
    return map(args) do arg
        in_vararg && return (arg=arg, type=NoType)
        if has_varargs && !isa(arg, Expr)
            in_vararg = true
            return (arg=arg, type=NoType)
        end
        return mkarg(arg)
    end
end

"""
    parsecall(expression)

`parsecall` is an implementation detail of `@ccall

it takes and expression like `:(printf("%d"::Cstring, value::Cuint)::Cvoid)`
returns: a tuple of `(function_name, return_type, arg_types, args)`

The above input outputs this:

    (:printf, :Cvoid, :((Cstring, Cuint)), ["%d", :value])

Note that the args are in an array, not a quote block and have to be
appended to the ccall in a separate step.
"""
function parsecall(expr)
    # setup and check for errors
    expr.head != :(::) &&
        error("@ccall needs a function signature with a return type")
    rettype = expr.args[2]

    call = expr.args[1]
    call.head != :call &&
        error("@ccall has to be a function call")

    # get the function symbols
    func = getcfunc(call.args[1])
    vararg_type, hasvarargs, allargs = getargs(call)

    # separate annotations from names
    pairs = mkargs(allargs, hasvarargs)
    args = [a.arg for a in pairs]
    types = Any[a.type for a in pairs if a.type !== NoType]
    hasvarargs && push!(types, :($vararg_type...))
    argtypes = :(())
    argtypes.args = types
    return func, rettype, argtypes, args
end

"""
    @ccall(call expression)

convert a julia-style function definition to a ccall:

    @ccall printf("%d"::Cstring, 10::Cint)::Cint

same as:

    ccall(:printf, Cint, (Cstring, Cint), "%d", 10)

All arguments must have type annotations and the return type must also
be annotated.

varargs are supported with the following convention:

    @ccall printf("%d, %d, %d"::Cstring, 1, 2, 3; varargs=Cint)::Cint

Note that, as with the current ccall API, all varargs must be of the
same type.

Using functions from other libraries is supported like this

    const glib = "libglib-2.0"
    @ccall glib.g_uri_escape_string(
        uri::Cstring, ":/"::Cstring, true::Cint
    )::Cstring

The string literal could also be used directly before the symbol of
the function name, if desired `"libglib-2.0".g_uri_escape_string(...`
"""
macro ccall(expr)
    func, rettype, argtypes, args = parsecall(expr)
    output = :(ccall($func, $rettype, $argtypes))
    append!(output.args, args)
    esc(output)
end
"""
define a _very_ thin wrapper function on a ccall. Mostly for wrapping
libraries quickly as a foundation for a higher-level interface.

    @cdef mkfifo(path::Cstring, mode::Cuint)::Cint

becomes:

   mkfifo(path, mode) = ccall(:mkfifo, Cint, (Cstring, Cuint), path, mode)
"""
macro cdef(expr)
    func, rettype, argtypes, args = parsecall(expr)
    call = :(ccall($func, $rettype, $argtypes))
    append!(call.args, args)
    name = func isa QuoteNode ? func.value : func.args[1].value
    definition = :($name())
    append!(definition.args, args)
    esc(:($definition = $call))
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

const comment = r"#=.*?=# "

"""
throw a system error if the expression returns a non-zero exit status.
"""
macro check_syserr(expr, message=nothing)
    if message == nothing
        message = replace(string(expr), comment => "")
    end
    out = quote
        err = $expr
        systemerror($str, err != 0)
        err
    end
    esc(out)
end

end # module
