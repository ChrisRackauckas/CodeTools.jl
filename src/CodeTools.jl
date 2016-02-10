module CodeTools

using MacroTools

using LNR, Lazy, Requires, Compat

typealias AString AbstractString

include("parse/parse.jl")
include("eval.jl")
include("module.jl")
include("summaries.jl")
include("completions.jl")
include("doc.jl")

end # module
