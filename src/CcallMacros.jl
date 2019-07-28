module CcallMacros
export @ccall, @cdef, @disable_sigint, @check_syserr

struct NoType end

getfunc(f) = QuoteNode(f)
getfunc(f::Expr) = :(($(f.args[2]), $(f.args[1])))

"""
`parsecall` is an implementation detail of `@ccall` and `@cdef`

takes and expression like `:(printf("%d"::Cstring, value::Cuint)::Cvoid)`
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
    func = getfunc(call.args[1])

    hasvarargs = false
    firstarg = call.args[2]
    if firstarg isa Expr && firstarg.head === :parameters
        length(firstarg.args) > 1 || (kw = firstarg.args[1].args)[1] !== :varargs &&
            error("@ccall only takes one keyword argument: varargs")
        hasvarargs = true
        vararg_type = kw[2]
        allargs = call.args[3:end]
    else
        allargs = call.args[2:end]
    end

    # separate annotations from names
    in_vararg::Bool = false
    function mkarg(arg)
        in_vararg && return (arg=arg, type=NoType)
        if hasvarargs && !isa(arg, Expr)
            in_vararg = true
            return mkarg(arg)
        end

        if arg.head != :(::)
            error("args in @ccall must be annotated")
        end
        type = if in_vararg
            :($(arg.args[2])...)
        else
            arg.args[2]
        end
        return (arg=arg.args[1], type=type)
    end

    pairs = mkarg.(allargs)
    args = [a.arg for a in pairs]
    types = Any[a.type for a in pairs if a.type !== NoType]
    hasvarargs && push!(types, :($vararg_type...))
    argtypes = :(())
    argtypes.args = types
    return func, rettype, argtypes, args
end

"""
convert a julia-style function definition to a ccall:

    @ccall printf("%d"::Cstring, 10::Cint)::Cvoid

same as:

    ccall(:printf, Cvoid, (Cstring, Cint), "%d", 10)
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
