
' TMeta example 2
' read mathematical expressions and evaluate them
' evaluation is handled by tree rewriting using FOLD
' tree rewriting is really intended more for normalization and other structural
' changes, but it's a perfectly adequate way to evaluate constant expressions

Import "TMeta.bmx"
SuperStrict

Private		'TFold is intended to be kept private so it can use short, convenient names without polluting the program
Include "TFold.bmx"
Public

' This example is quite long. There are four main blocks: the lexer, the parser, the normalizer, and the evaluator

' The lexer is at the bottom and is only slightly more interesting than the one from example 1
' The parser is second from the bottom as it is essentially also a complete version of the grammar from that example

' At the top we have the input loop, taking strings from stdin and evaluating them
' uncomment the print lines to see intermediate steps

' Next are the definitions of the normalization pass and the evaluation pass
' These are FOLD delegates and are most interesting


' input loop
Local q:Simple = New Simple, lex:TLexer = GetLexer()
Print "~nEnter a math expression to evaluate"
Print "Available functions are sin, cos, tan, min, max, log"
Print "'halt' or 'quit' to end~n"
Repeat
	Try
		Local s:String = Input(">")
		If s = "quit" Or s = "halt" Then Exit
		
		Local tree:TParseNode = q.Parse(lex.ScanString(s))
	'	Print "parse:~n" + tree.ToString()
		
		Local tbl:NodeTable = Node.FromParse(tree), r:Node = tbl.n
		r = Node.Fold(r, New NormalizeFold)
	'	Print "normalize:~n" + r.ToString()
		
		r = Node.Fold(r, New EvalFold)
	'	Print "eval:~n" + r.ToString()
		
		Local val:Float = Leaf(r).val.ToFloat()
		Print "val: " + val
	Catch err:Object
		Print err.ToString()
	End Try
Forever

Print "~ndone."
End

' Normalization delegate
' this delegate works bottom-up to restructure math operations so that they are cleaner
' once they are properly structured, they will be easy to evaluate
' you can see if you uncomment the print lines that the AST is much smaller after this
' has had a chance to simplify it and tidy it

' The method to call on a given node is determined by the annotation
' A method will be called if it is named the same as a node type, or the node type
' appears in its metadata list
' This lets us use one method for all the different types of binary operation without
' needing to reduce the number of distinct types, avoiding data loss
Type NormalizeFold
	Method LeftAssociative:Node(n:Rose) { SumExpr MulExpr ShiftExpr RelExpr Expr }	'restructure left-associative operations from a list to a tree
		Local l:Node = n.Get("L"), r:Rose = Rose(n.Get("R"))
		For Local c:Int = 0 Until r.arg.Length
			Local rarg:Rose = Rose(r.arg[c])
			l = Rose.Make(rarg.arg[0].key, [l, rarg.arg[1]], ["L", "R"])
		Next
		Return l
	End Method
	Method RightAssociative:Node(n:Rose) { CatExpr PowExpr }	'properly structure right-associative operations
		Local l:Node = n.Get("L"), r:Rose = Rose(n.Get("R"))
		Return Rose.Make(r.arg[0].key, [l, r.arg[1]], ["L", "R"])
	End Method
End Type

' Evaluation delegate
' this delegate also works bottom up, so that all values are fully computed before being passed
' to the operation that wants to work with them
' it treats all values as floats
' available functions are sin, cos, tan, min, max and log

' Again, it combines all types of binary operation into one method for convenience
' without losing any data in the tree itself about the type and precedence
Type EvalFold
	Method BinMathOp:Node(n:Rose) { plus minus mul div kmod pow kshl kshr eq neq leq geq lt gt }
		Local l:Double = Double(Leaf(n.arg[0]).val), r:Double = Double(Leaf(n.arg[1]).val)
		Select n.key
			Case "plus"  ; l :+ r
			Case "minus" ; l :- r
			Case "mul"   ; l :* r
			Case "div"   ; l :/ r
			Case "kmod"  ; l = l Mod r
			Case "pow"   ; l = l ^ r
			Case "kshl"  ; l = Int(l) Shl Int(r)
			Case "kshr"  ; l = Int(l) Shr Int(r)
			Case "eq"    ; l = (l = r)
			Case "neq"   ; l = l <> r
			Case "leq"   ; l = l <= r
			Case "geq"   ; l = l >= r
			Case "lt"    ; l = l < r
			Case "gt"    ; l = l > r
		End Select
		Return Leaf.Make("number", l)
	End Method
	Method FunCall:Node(n:Rose)
		Local args:Rose = Rose(n.Get("args")), vals:Float[args.arg.Length]
		For Local i:Int = 0 Until vals.Length
			vals[i] = Leaf(args.arg[i]).val.ToFloat()	'extract argument values
		Next
		Local f:String = Leaf(n.Get("name")).val	'extract function
		
		If f = "max" Or f = "min" Then noArgs(2, vals, f) Else noArgs(1, vals, f)	'check number of arguments is correct
		
		Local ret:Float
		Select f
			Case "sin" ; ret = Sin(vals[0])
			Case "cos" ; ret = Cos(vals[0])
			Case "tan" ; ret = Tan(vals[0])
			Case "min" ; ret = Min(vals[0], vals[1])
			Case "max" ; ret = Max(vals[0], vals[1])
			Case "log" ; ret = Log(vals[0])
			Default
				Throw "unrecognized function: '" + f + "'"
		End Select
		
		Return Leaf.Make("number", String(ret))
		
		Function noArgs(n:Int, a:Float[], f:String)
			If a.Length <> n Then Throw "wrong number of args (" + a.Length + ") to function '" + f + "'"
		End Function
	End Method
End Type

' more complete grammar that lets us use the full range of math operators
Type Simple Extends TMetaParser
	Field grammar:TMap {..
		Expr = "RelExpr"..
	..
		RelExpr = "SumExpr ((%lt | %gt | %leq | %geq | %neq | %eq) SumExpr)* : @L @R ^"..
		SumExpr = "ShiftExpr ((%plus | %minus) ShiftExpr)* : @L @R ^"..
		ShiftExpr  = "MulExpr ((%kshl | %kshr) MulExpr)* : @L @R ^"..
		MulExpr = "PowExpr ((%mul | %div | %kmod) PowExpr)* : @L @R ^"..
		PowExpr = "Atom (%pow PowExpr)? : @L @R ^"..
	..
		Atom       = "FunCall | BracketExp | %number"..
		FunCall    = "%function %!lparen FunCommaArg* Expr %rparen : @name - @args < -"..
		  FunCommaArg = "Expr %comma : @ - ^"..
		BracketExp = "%lparen ! Expr %!rparen : - @ - ^"..
	}
End Type

' similar lexer to the previous example
' this time we've optimized the recognition of int and float-format numbers, by providing start-classes
' this speeds up the regex engine somewhat when the first character can vary
Function GetLexer:TLexer()
	Global Store(l:TLexer) = TLexAction.Store, Discard(l:TLexer) = TLexAction.Discard, Mode(l:TLexer) = TLexAction.Mode
	
	Global l:TLexer = TLexer.withRules([..
		R("[0-9]*", Store, "number", "0123456789"),..	'Simple Int
		R("0[xX][0-9a-fA-F]+", Store, "number"),..	'Hex Int (style: 0xABC12)
		R("[0-9]*\.[0-9]+([eE]-?[0-9][0-9]*)?", Store, "number", "0123456789"),..		'Float, simple or scientific
	..
		R("/\*", Mode, "COMMENT", ""),..		'Note that the star must be escaped
		R(".", Discard, "", "COMMENT"),..	'Match any charcater, but throw it away in comment mode only
		R("\*/", Mode, "", "COMMENT"),..		'Return to mode 0 on hitting */
		R("//[^n]*n", Discard),..			'Line comment: match up to end of line
	..
		S("+", Store, "plus"),..		'Any Regex operators need to be escaped with \
		S("-",  Store, "minus"),..
		S("*", Store, "mul"),..
		S("/",  Store, "div"),..
		S("%",  Store, "kmod"),..
		S("<<", Store, "kshl"),..
		S(">>", Store, "kshr"),..
		S("^", Store, "pow"),..
		S("=",  Store, "eq"),..
		S("!=", Store, "neq"),..
		S("<=", Store, "leq"),..
		S(">=", Store, "geq"),..
		S("<", Store, "lt"),..
		S(">", Store, "gt"),..
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

