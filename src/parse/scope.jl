# A pseudo-parser which extracts information from Julia code

using LNR
include("streams.jl")

const identifier_inner = r"[^,⊶⩃↣⩄≗≦⥥∓≨⊘×≥≫⥘⪚⋼⭂⥩⩾⥓∝⤞⇼⥍⭈∽⩁⥎⟑⟉∊∷≳≠⩧⫏⇿⬵≬⩗⥭⦾⥖→∪⫑⪀⩠⥢⤌⋝⊕⪪≈⪏≤⨤⪿⟰≼⫂≹⪣⋴≧∸≐⭋∨⨳⭁∺⋥⟽⊷⟱≡\]⤅⪃⩋⩊⋣⋎⥗⨮⬻⪻≢∙⪕⩓⫺∧⧻⨭⊵≓⥬⥛⋿⭃⫒⫕⩡⬺⧷⥄⊱⨰⊇≊⨬≖>⤕⬴⟿⋘⪇≯⋕⤏⟶⥚⥜⨼∥⪠⥝⬷∘⊴⪈⤔⪍⫄?⊰⪌⋩≟⋜⫀\)⫎⩦⋏⫷⊋⪱⤀⩯⤘⫌⩱≜↓⋗↑≛⋌⪢⫖⋖⩰⊏⊗⪡⋆⟈⤂⥆⧁⊻⤋⤖⩹↦⪳⩸⥅∔⨺⋐≶⟵\}⪙⪧⇺%≭≕⥔⥐⊆⋸⅋⋒≃≝≿⇴⩌⋠⇽≰/⫙⊠⪼⇔\[⟾+≩⊟⨶⥰⪉≎≷⩣⭄&⨲⧣⩭≑⊐⫗⩬⩢⬽⪯⪓⪒≪∈⪘⬿⫸⇹⊅⨥⨩≚⋹⊃⊂⪞⋺⨹⋦∦≮⋧⋛⋾⊁≉￪≔±\{⩒⩑⋫￩⥤⨽⬲⪄⫓⪑∩⧡⩮⪟⪛⋽⪦⇒≁⪝⬳⩝⩳≴⪰⟻≣⦼⩷⇶⋳⪺⪜⩕⥦∛≽⋑⤓⟼⩏≲⊲≸⟺⇷⟹∌⩪⊞⫉⨴⪤⪸⥡⩔⭊⪆⩲⫈⥒⫋⬶⫁⪵∗⫊⩖≙⩐≍⨫⦸⋚⊄⫐⥇⥣⪲↔⪷⨈⧺⭌⨨≄⤟^≵⋭⋊⟷⩅∤⫆⊽\(⬸⤒⪾⩞⥫⥙⋙⨱⬹<⊎⤊⤁⇏≺⋵⥏⩴⋶⪂⥕⪨⋇⊊⫅⊖⪶⋬≻⋍⋓⩍≱⇻⩵↮⋋⪖⨢↠⤎⊈⊮⋪⊓⪔\⨧⩜⥞⫇⪫⬾⋷⤃⧥⫃⨷⥈⤄⩼⋤⥠⬼⤠⩛≂↚⥧|∍⨻⊙⨪∋⪋⋲⤍.\"⊑⩟⇎*:￬⭉⤉⥯⬱⇾⋡÷⥟⥋∉⬰≞≾⫍⨵⩚⩫≅⩿⪎⪴⊒⪽≀⫹⤇⋅⩀⊡⤆∜⤈⨣↛⊩⫔⦷⩺≋\-≇⋨⊜~⫛≌⥉√⋢⊛⤗⋟⧶≏⊔⪗⋞ ⩎⊳∾⥨￫⩘⥌⪹⪩⩻=⨸⪊⨇⧤⇸⊉⥑⥮⭀⧀⊚⊬≒\$⊀⋻⦿⭇⥊≆←⤐≘⋉⊼⥪⧴⪅⩽⪬⪁⋄⤑⨦⩶⇵⪥⊍⫘⩂⪐⟒⪭⪮⤝∻\"\n]"
const identifier = Regex("(?![!0-9])$(identifier_inner.pattern)+")
const identifier_start = Regex("^$(identifier.pattern)")

const blockopeners = Set(["begin", "function", "type", "immutable",
                         "let", "macro", "for", "while",
                         "quote", "if", "else", "elseif",
                         "try", "finally", "catch", "do",
                         "module"])

const blockclosers = Set(["end", "else", "elseif", "catch", "finally"])

const operators = r"(?:\.?[|&^\\%*+\-<>!=\/]=?|\?|~|::|:|\$|<:|\.[<>]|<<=?|>>>?=?|\.[<>=]=|->?|\/\/|\bin\b|\.{3}|\.)"
const operators_end = Regex("^\\s*"*operators.pattern*"\$")

const macros = Regex("@(?:" * identifier.pattern * "\\.?)*")
const macro_start = Regex("^"*macros.pattern)

scope_pass(s::String; kws...) = scope_pass(LineNumberingReader(s); kws...)

# I'm going to be upfront on this one: this is not my prettiest code.
function scope_pass(stream::LineNumberingReader; stop = false, collect = true, target::Union(Cursor, Integer) = cursor(0,0))
  isa(target, Integer) && (target = cursor(target, 1))
  collect && (tokens = Set{UTF8String}())
  scopes = Dict[{:type => :toplevel}]

  tokenstart = cursor(1, 1)
  crossedcursor() = tokenstart <= target <= cursor(stream)

  cur_scope() = scopes[end][:type]
  cur_scope(ts...) = cur_scope() in ts
  leaving_expr() = cur_scope() == :binary && pop!(scopes)
  pushtoken(t) = collect && !crossedcursor() && push!(tokens, t)
  function pushscope(scope)
    if !(stop && cursor(stream) > target)
      push!(scopes, scope)
    end
  end

  while !eof(stream)
    tokenstart = cursor(stream)

    # Comments
    if startswith(stream, "\n")
      cur_scope() in (:comment, :using) && pop!(scopes)

    elseif cur_scope() == :comment
      read(stream, Char)

    elseif startswith(stream, "#=")
      pushscope({:type => :multiline_comment})

    elseif startswith(stream, "#")
      pushscope({:type => :comment})

    elseif cur_scope() == :multiline_comment
      if startswith(stream, "=#")
        pop!(scopes)
      else
        read(stream, Char)
      end

    # Strings
    elseif cur_scope() == :string || cur_scope() == :multiline_string
      if startswith(stream, "\\\"")
      elseif (cur_scope() == :string && startswith(stream, "\"")) ||
             (cur_scope() == :multiline_string && startswith(stream, "\"\"\""))
        pop!(scopes)
      else
        read(stream, Char)
      end

    elseif startswith(stream, "\"\"\"")
      pushscope({:type => :multiline_string})
    elseif startswith(stream, "\"")
      pushscope({:type => :string})

    # Brackets
    elseif startswith(stream, ["(", "[", "{"], eat = false)
      pushscope({:type => :array, :name => read(stream, Char)})

    elseif cur_scope(:array, :call) && startswith(stream, [")", "]", "}"])
      pop!(scopes)

    # Binary Operators
    elseif startswith(stream, operators_end) != ""
      pushscope({:type => :binary})

    elseif startswith(stream, "@", eat = false)
      token = startswith(stream, macro_start)
      token != "" && pushtoken(token)

    # Tokens
    elseif (token = startswith(stream, identifier_start)) != ""
      if token == "end"
        cur_scope() in [:block, :module] && peekbehind(stream, -length(token)) ≠ ':' && pop!(scopes)
        leaving_expr()
      elseif token in ("module", "baremodule")
        skipwhitespace(stream, newlines = false)
        pushscope({:type => :module,
                   :name => startswith(stream, identifier_start)})
      elseif token == "using"
        pushscope({:type => :using})
      else
        keyword = false
        token in blockclosers && (cur_scope() == :block && pop!(scopes); keyword = true)
        token in blockopeners && (pushscope({:type => :block,
                                             :name => token});
                                  keyword = true)
        if !keyword
          pushtoken(token)
          while startswith(stream, ".")
            if (next = startswith(stream, identifier_start)) != ""
              token = "$token.$next"
            end
          end
          startswith(stream, "(") ?
            pushscope({:type => :call, :name => token}) :
            leaving_expr()
        end
      end
    else
      read(stream, Char)
    end
    if stop && cursor(stream) ≥ target
      return scopes
    end
  end
  return collect ? tokens : scopes
end
