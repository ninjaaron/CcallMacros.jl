module CcallMacros
export @ccall, @cdef, @disable_sigint, @nonzero_systemerror

"""
`calltoccall` is an implementation detail of @ccall and @cdef

takes and expression like :(printf("%d"::Cstring, value::Cuint)::Cvoid)
returns: a tuple of (function_name, return_type, arg_types, args

The above input outputs this:
(:printf, :Cvoid, :((Cstring, Cuint)), ["%d", :value])

Note that the args are in an array, not a quote block and have to be
appended to the ccall in a separate step.
"""
function calltoccall(expr)
    expr.head != :(::) &&
        error("@ccall needs a function signature with a return type")
    rettype = expr.args[2]

    call = expr.args[1]
    call.head != :call &&
        error("@ccall has to be a function call")

    if (f = call.args[1]) isa Expr
        lib = f.args[1]
        fname = f.args[2]
        func = :(($fname, $lib))
    else
        func = QuoteNode(f)
    end
    argtypes = :(())
    args = []
    for arg in call.args[2:end]
        varargs = false
        if arg.head == :...
            varargs = true
            arg = arg.args[1]
        end

        arg.head != :(::) &&
            error("args in @ccall must be annotated")
        value = arg.args[1]
        type_ = arg.args[2]
        # This currently doesn't work.
        if varargs
            value = :($value...)
            type_ = :($type_...)
        end
        push!(args, value)
        push!(argtypes.args, type_)
    end
    func, rettype, argtypes, args
end

"""
convert a julia-style function definition to a ccall:

`@ccall printf("%d"::Cstring, 10::Cint)::Cvoid`

same as:

`ccall(:printf, Cvoid, (Cstring, Cint), "%d", 10)`
"""
macro ccall(expr)
    func, rettype, argtypes, args = calltoccall(expr)
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
    func, rettype, argtypes, args = calltoccall(expr)
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
macro nonzero_systemerror(expr)
    str = replace(string(expr), comment => "")
    out = quote
        err = $expr
        systemerror($str, err != 0)
        err
    end
    esc(out)
end

end # module
