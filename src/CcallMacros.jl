module CcallMacros
export @ccall, @cdef, @disable_sigint, @check_syserr


"""
`parsecall` is an implementation detail of @ccall and @cdef

takes and expression like :(printf("%d"::Cstring, value::Cuint)::Cvoid)
returns: a tuple of (function_name, return_type, arg_types, args

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
    getfunc(f) = QuoteNode(f)
    getfunc(f::Expr) = :(($(f.args[2]), $(f.args[1])))
    func = getfunc(call.args[1])

    # separate annotations from names
    mkarg(arg) = arg.head != :(::) ?
        error("args in @ccall must be annotated") :
        (arg=arg.args[1], type_=arg.args[2])

    pairs = mkarg.(call.args[2:end])
    args = [a.arg for a in pairs]
    argtypes = :(())
    argtypes.args = [a.type_ for a in pairs]

    return func, rettype, argtypes, args
end

"""
convert a julia-style function definition to a ccall:

`@ccall printf("%d"::Cstring, 10::Cint)::Cvoid`

same as:

`ccall(:printf, Cvoid, (Cstring, Cint), "%d", 10)`
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
