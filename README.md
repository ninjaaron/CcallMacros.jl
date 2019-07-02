# Macros related to `ccall`

## @ccall macro

`@ccall` allows you to use more natural Julia syntax for calling C,
leaving the semantics of `ccall` unaltered.

```julia
julia> fmt = "Hello Julia %.1f!\n"
julia> version = 1.1
julia> @ccall printf(fmt::Cstring, version::Cdouble)::Cint
Hello Julia 1.1!
17
```

What's it do?

```julia
julia> println(@macroexpand @ccall printf(fmt::Cstring, version::Cdouble)::Cint)
ccall(:printf, Cint, (Cstring, Cdouble), fmt, version)
```

Nothing revolutionary, just some syntactic sugar to improve
readability.

To work with libraries besides `libc`, you should declare the name of the
library elsewhere in the source as a constant:

```julia
julia > const glib = "libglib-2.0"

julia> uri = "http://example.com/have a nice day"

julia> unsafe_string(@ccall glib.g_uri_escape_string(
           uri::Cstring, ":/"::Cstring, true::Cint
       )::Cstring)

"http://example.com/have%20a%20nice%20day"
```

This is simply translated into:

```julia
julia> println(@macroexpand @ccall glib.g_uri_escape_string(
           uri::Cstring, ":/"::Cstring, true::Cint
       )::Cstring)
ccall((:g_uri_escape_string, glib), Cstring, (Cstring, Cstring, Cint), uri, ":/", true)
```

It is technically also possible to write `@ccall
"libglib-2.0".g_uri_escape_string( ... )`, but that's just nasty.

## @cdef macro

There has been some talk that `@ccall` should be in the `Base` module.
(this repository is mostly just for polishing it up.) `@cdef` has not
been discussed in the community at all. It was just something I wanted
and it happens to share a lot of code with `@ccall`, so it's in this
repo, but I'm not necessarily saying it should be in `Base`. It has
the same syntax as ccall, but it makes a _very_ minimal wrapper
function over the called code, so it can be used again later without
type annotations. It's still a work-in progress, but at the moment, it
works like this:

```julia
julia> @cdef puts(str::Cstring)::Cint
puts (generic function with 1 method)

julia> puts("foo")
foo
4
```

and again with the generated code:

```julia
julia> println(@macroexpand @cdef puts(str::Cstring)::Cint)
puts(str) = ccall(:puts, Cint, (Cstring,), str)
```

In the case of a third-party library, only the function name becomes
the wrapper name.

```julia
julia> println(@macroexpand @cdef glib.foo(bar::Baz)::Cvoid)
foo(bar) = ccall((:foo, glib), Cvoid, (Baz,), bar)
```

This is to reduce the amount of repetitive typing when wrapping a
library. It is probably helpful to define additional dispatches with
additional wrapping in most cases.

## @disable_sigint macro

Disables SIGINT while expr is being executed. Mostly useful for calling
C functions that call back into Julia in a concurrent context because
memory corruption can occur and crash the whole program. I'm frankly
not entirely sure how necessary this is as a separate macro, but some
other people thought it was a good idea, and it was easy to implement.

```julia
@disable_sigint ccall( ... )

# same as:
disable_sigint() do
    ccall( ... )
end
```

## @check_syserr

Throws a system error for a non-zero exit.

```julia
julia> touch("foo")
"foo"

julia> @check_syserr @ccall mkfifo("foo"::Cstring, 0o666::Cuint)::Cint
ERROR: SystemError: @ccall mkfifo("foo"::Cstring, 0x01b6::Cuint)::Cint: File exists

julia> println(@macroexpand @check_syserr @ccall mkfifo("foo"::Cstring, 0o666::Cuint)::Cint)
# LineNumberNodes have been removed for your viewing pleasure.
begin
    err = ccall(:mkfifo, Cint, (Cstring, Cuint), "foo", 0x01b6)
    systemerror("@ccall mkfifo(\"foo\"::Cstring, 0x01b6::Cuint)::Cint", err != 0)
    err
end
```

Kinda iffy on this one, too, but I guess can see the appeal.
