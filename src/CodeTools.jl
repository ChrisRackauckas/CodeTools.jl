module CodeTools

using MacroTools, Lazy, LNR

typealias AString AbstractString

include("utils.jl")
include("eval.jl")
include("module.jl")
include("summaries.jl")
include("completions.jl")
include("doc.jl")

end # module
