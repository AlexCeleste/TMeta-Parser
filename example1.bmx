
' TMeta example 1
' simple grammar for matching expressions

' scan a string and then print its parse tree
' (it's not a very good parse tree)

Import "TMeta.bmx"

' grammar is cut down for size, missing some operators not in the example string
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

Local q:Simple = New Simple

Local test:String = " 1 +2* f(4, 3 + 1)<< 4 + 5"
Print test + "~n"
Print q.Parse(GetLexer().ScanString(test)).ToString()

Function GetLexer:TLexer()
	Global Store(l:TLexer) = TLexAction.Store, Discard(l:TLexer) = TLexAction.Discard, Mode(l:TLexer) = TLexAction.Mode
	
	Global l:TLexer = TLexer.withRules([..
		R("[0-9]*", Store, "number"),..	'Simple Int
		R("0[xX][0-9a-fA-F]+", Store, "number"),..	'Hex Int (style: 0xABC12)
		R("[0-9]*\.[0-9]+([eE]-?[0-9][0-9]*)?", Store, "number"),..		'Float, simple or scientific
	..
		R("/\*", Mode, "COMMENT", ""),..		'Note that the star must be escaped
		R(".", Discard, "", "COMMENT"),..	'Match any charcater, but throw it away in comment mode only
		R("\*/", Mode, "", "COMMENT"),..		'Return to mode 0 on hitting */
		R("//[^n]*n", Discard),..			'Line comment: match up to end of line
	..
		S("+", Store, "add"),..		'Any Regex operators need to be escaped with \
		S("-",  Store, "sub"),..
		S("*", Store, "mul"),..
		S("/",  Store, "div"),..
		S("%",  Store, "mod"),..
		S("<<", Store, "shl"),..
		S(">>", Store, "shr"),..
		S("^", Store, "pow"),..
		S("=",  Store, "eql"),..
		S("!=", Store, "neq"),..
		S("<=", Store, "leq"),..
		S(">=", Store, "geq"),..
		S("(", Store, "lparen"),..
		S(")", Store, "rparen"),..
		S(",",  Store, "comma"),..
	..
		R("[a-z][a-z0-9_]*", Store, "function"),..
	..
		R("[^[:space:]]", TLexAction.Error)..		'Raise an error over any other printable character
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

