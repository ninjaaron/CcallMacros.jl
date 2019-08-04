module CcallMacros
export @ccall, @cdef, @disable_sigint, @check_syserr

struct NoType end
struct CcallError{T <: AbstractString} <: Exception
    msg::T
end
Base.showerror(io::IO, e::CcallError) = print(io, "CcallError: ", e.msg)

getcfunc(f) = QuoteNode(f)
getcfunc(f::Expr) = :(($(f.args[2]), $(f.args[1])))
hashead(symbol, _) = false
hashead(expr::Expr, head) = expr.head === head

"""
Determine if there are varargs and return a vector of all arguments
based on the call signature.

returns a tuple of `(hasvarargs, arguments)`
"""
function getargs(call)
    firstarg = call.args[2]
    if hashead(firstarg, :parameters)
        return call.args[3:end], firstarg.args
    else
        return call.args[2:end], []
    end
end

"""
       mkarg(arg)

`mkarg` takes an argument and returns a tuple of symbol and type. The
argument must have a type annotation or an error will be thrown.
"""
function mkarg(arg)
    !hashead(arg, :(::)) &&
        throw(CcallError("args in @ccall need type annotations. '$arg' doesn't have one."))
    return (arg=arg.args[1], type=arg.args[2])
end

"""
get the type specified on the varargs. throw if there is more than one type.
"""
function getvarargtype(varargs)
    vararg_types = Set(a.type for a in varargs)
    length(vararg_types) > 1 &&
        throw(CcallError("varargs @ccall with different argument types not yet supported"))
    return pop!(vararg_types)
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
    !hashead(expr, :(::)) &&
        throw(CcallError("@ccall needs a function signature with a return type"))
    rettype = expr.args[2]

    call = expr.args[1]
    !hashead(call, :call) &&
        throw(CcallError("@ccall has to take a function call"))

    # get the function symbols
    func = getcfunc(call.args[1])
    normalargs, varargs = getargs(call)

    # separate annotations from names
    normalargs = mkarg.(normalargs)
    args = Any[a.arg for a in normalargs]
    types = Any[a.type for a in normalargs]
    argtypes = :(())
    argtypes.args = types

    isempty(varargs) && return func, rettype, argtypes, args

    # vararg handling. to be changed if rebased on foreigncall.
    varargs = mkarg.(varargs)
    append!(args, (a.arg for a in varargs))
    vararg_type = getvarargtype(varargs)
    push!(types, :($vararg_type...))
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

    @ccall printf("%d, %d, %d"::Cstring ; 1::Cint, 2::Cint, 3::Cint)::Cint

Mind the semicolon. Note that, as with the current ccall API, all
varargs must be of the same type.

Using functions from other libraries is supported by prefixing
the function name with the name of the C library, like this:

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
    nolinenum(expr)

remove `LineNumberNodes`
"""
nolinenum(s) = s
nolinenum(e::Expr) =
    Expr(e.head, (nolinenum(a) for a in e.args if !isa(a, LineNumberNode))...)

getsym(arg) = hashead(arg, :(::)) ? arg.args[1] : arg
getmacrocall(expr) = begin
    hashead(expr, :macrocall) ? Tuple(expr.args) : (nothing, nothing, expr)
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
        message = nolinenum(expr) |> string
    end
    return quote
        err = $(esc(expr))
        systemerror($message, err != 0)
    end
end

end # module
