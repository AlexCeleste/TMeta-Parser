
 TMeta and TFold: parsing tools
================================

This is a simple rule-based parsing toolkit for use with BlitzMax. There are three major components:

- the lexer, `TLexer` (in `TMeta.bmx`)
- the parser, `TMetaParser` (also in `TMeta.bmx`)
- the FOLD engine for tree rewriting (in `TFold.bmx`)

All three provide simple, highly declarative interfaces for defining parsers and related frontend tools. The lexer depends on [BaH.Regex](https://github.com/maxmods/bah.mod) (PCRE). The components can be used separately if desired.

**The Lexer**

`TLexer` is a simple regex-based lexical scanner. It consumes a character sequence (loads the whole file first), and matches rules against the head of the sequence to produce an array of `TToken` objects. It has built-in actions for handling file inclusion (with guards), error reporting, and switching between different scan modes. Tokens remember their file of origin and text position (line/col).

Defining a lexer to scan a character string looks like this:

	Local test:String = " 1 +2* f(4, 3 + 1)<< 4 + 5"
	Local toks:TToken[] = GetLexer().ScanString(test)

	Function GetLexer:TLexer()
		Global Store(l:TLexer) = TLexAction.Store, Discard(l:TLexer) = TLexAction.Discard, Mode(l:TLexer) = TLexAction.Mode
	
		Global l:TLexer = TLexer.withRules([..
			R("[0-9]*", Store, "number"),..	'Simple Int
			R("0[xX][0-9a-fA-F]+", Store, "number"),..	'Hex Int (style: 0xABC12)
			R("[0-9]*\.[0-9]+([eE]-?[0-9][0-9]*)?", Store, "number"),..		'Float, simple or scientific
		..
			S("+", Store, "add"),..
			S("-",  Store, "sub"),..
			S("*", Store, "mul"),..
			S("/",  Store, "div"),..
			S("%",  Store, "mod"),..
			S("<<", Store, "shl"),..
			S(">>", Store, "shr"),..
			S("(", Store, "lparen"),..
			S(")", Store, "rparen"),..
			S(",",  Store, "comma"),..
		..
			R("[a-z][a-z0-9_]*", Store, "function"),..
		..
			R("[^[:space:]]", Error)..		'Raise an error over any other printable character
		])
		l.SetCaseSensitivity False
		l.SetGuardMode False
	
		Return l
	
		Function R:TLexRule(r:String, a(l:TLexer), res:String = "", ic:String = "")
			Return TLexRule.Create(r, a, res, "", ic)
		End Function
		Function S:TLexRule(r:String, a(l:TLexer), res:String = "")
			Return TLexRule.CreateSimple(r, a, res)
		End Function
	End Function

Regular expression rules are defined with `TLexRule.Create`, while non-varying tokens like operators that can be matched with a simple string comparison are matched with a simpler engine. It's possible to optimize regular expressions further using "start classes" for even better performance (e.g. the "start class" for numbers is "0123456789").

Since the lexer is aware of files, it handles 99% of the work of taking a program from file to token sequence. Line numbering and file names are maintained automatically even across file boundaries.


**The Parser**

`TMetaParser` (and its parent, `TParser`) is a rule-based parsing engine. Rules are generally defined in a simple BNF-like language in BlitzMax metadata, so the parser generator doesn't need an intermediate build step but rather constructs a parser at runtime. Although the resulting parser is interpreted, performance is still good enough for production use. (The parent class, `TParser`, provides a more conventional combinator interface for constructing parsers: this is actually mainly used to build the internal parser for reading the rule language, making `TMetaParser somewhat meta-circular.) A parser instance consumes a `TToken` array, and returns a `TParseNode` tree.

Defining a parser to scan the same simple math expression above looks like this:

	Type Simple Extends TMetaParser
	
		Field grammar:TMap {..
			Expression = "SumExpr"..
		..
			SumExpr    = "ShiftExpr (%add ShiftExpr)* : @L @R ^"..
			ShiftExpr  = "MulExpr (%shl MulExpr)* : @L @R ^"..
			MulExpr    = "Atom (%mul Atom)* : @L @R ^"..
			Atom       = "FunCall | BracketExp | %number"..
			FunCall    = "%function %!lparen FunCommaArg* Expression %rparen : @name - @args < -"..
			  FunCommaArg = "Expression %comma : @ - ^"..
			BracketExp = "%lparen ! Expression %!rparen : - @ - ^"..
		}
	
	End Type

	Local q:Simple = New Simple, tree:TParseNode = q.Parse(toks)

The parser is automatically built up from the rules on instantiation. All of the mechanisms are generic and hidden inside the implementation.

The rule language is simple: names of rules on the left, expressions on the right. Rules are named directly in expressions. Terminal rules match individual tokens, as produced by the lexer: the name matches the name of the lexer rule's output. Terminal names are marked with `%`, e.g. `%comma`. Parentheses group, and the `*`, `+`, `?` and `|` operators work as you would expect in BNF.

The `!` operator marks an "error point" within a rule that indicates that should parsing fail beyond this point, the document is not valid (e.g. after opening parentheses, you have to close them again, so there's no point backtracking to before the left paren to try a different match). This improves the clarity and locality of error messages. Terminals can also be marked as mandatory with `%!`, e.g. `%!lparen` within `FunCall` indicates that if we don't find an opening parenthesis, error out with a message that we were expecting one.

The colon at the end of a rule marks the start of a "filter" string; if the rule up to that point matched successfully, the filter will then be applied to the match to drop unnecessary elements early, and give names to the ones we keep. e.g. in a parenthesized expression, the two `-` indicate that we no longer need to keep the parentheses and can just retain the expression itself marked with `@`. The `^` indicates that if the match is reduced to one element, it should be folded up into the enclosing match for expediency. So the parser can also handle simple tree processing and cutting down the size of the output early. (Filter strings are optional.)

More information on the parser rule syntax can be found in the separate document "parserules.md".


**The FOLD engine**

`TFold.bmx` defines classes that can iterate either up or down over a tree produced by the parser, and take action on elements by matching their type names to actions provided by a delegate object. The delegate object provides methods, annotated with the types each method should act upon, and the FOLD engine applies the methods to the elements of the tree as it reaches them. The FOLD engine's main use is to separate the act of recursing through a tree from the actions to be taken upon that tree, to keep the concerns cleanly separated. This also makes it far easier to work with the tree bottom-up (which results in every node having normalized/processed children and is thus far more efficient for most tasks than working top-down, as no structure checks are necessary).

The result of applying the FOLD engine to a tree varies, but in general it willbe a rewritten version of the same tree. It is useful for simple constant evaluation and normalizing code structures (e.g. ensuring every variable has an initializer, converting all loops to a uniform structure, eliminating the most obvious dead branches, etc.).

The FOLD engine involves large blocks of code and is best viewed as a separate example.


Two examples are provided: a simple example to parse an expression string, and a more complete mathematical expression evaluator (using FOLD to evaluate math expressions via rewriting).

TMeta is robust, tested, and ready for production use. It is used for real in the [YBC](https://github.com/Leushenko/ybc) and [Blue Moon](https://github.com/Leushenko/blue-moon) projects. Its performance on Lua code in Blue Moon has been good, suitable for use as part of a JIT engine.

TMeta and FOLD are dedicated to the public domain by the author, Alex "Yasha" Gilding.

