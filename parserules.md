
This is a more detailed explanation of the TMeta grammar syntax and rule generation. This is based on the documentation for the original, combinator-based version of the parser engine, as written for Blitz3D. Refer [back to it](http://www.blitzbasic.com/codearcs/codearcs.php?code=2990) for even more detail and history.

Rules are defined using the five rule operators:

- concatenation (things following each other - this is usually implicit in BNF and similar syntaxes)
- alternative: one of the listed options. Bar operator `|` in common syntax
- optional: is allowed to not be present. Suffixed `?` in common syntax
- repetition: is repeated ZERO or more times. The `*` operator
- plus: non-optional repetition (one-or-more). `+` in common syntax

The combinator API also provides an error operator, but that's not very useful in practice and is left out of the declarative version of the interface.

The components of a rule are separated by spaces. A terminal is represented by a name prefixed with a `%`, e.g. `%comma`. To raise an error on failing to match a terminal, add `!` to the prefix (e.g. `%!number`).

Named rules can also have an optional "filter" component: a filter can rename (`@name`) or drop (`-`) elements from the resulting match. Elements that aren't renamed, but kept with a simple `@`, are numbered according to their position from the start of the match. (Names are attached to elements in the parse tree for easy retrieval/indexing.) It can also fold elements into their predecessors (`<`); if the predecessor is a list created with a repetition operator, the element will be stuck on the end and numbered accordingly (this is useful when you need a slightly different rule for whatever marks the end of a list so it can't be part of the repetition, e.g. no comma).

Filters are separated from the main rule body by a colon, `:`.

So:

- `"atom comma atom"` produces a match with the values named `"0"`, `"1"`, `"2"`
- `"atom comma atom : @left - @right"` produces a match with the atoms named `"left"` and `"right"`, and no comma remaining in the output - it is filtered out
- Any values not accounted for beyond the end of the filter are numbered according to the default scheme

By default, nested elements of named rules are "folded up": if the result consists of only one element, it is returned directly to the containing rule in order to keep the result tree flatter (or at least, manageably small - otherwise even very simple expressions would produce very deeply nested results as the entire operator precedence table was preserved). Named rules can also be set to "fold" by passing `^` as the last element of the filter, after the rename/drop elements. If the result contains more than one node, the match will never fold, even if specifically requested to do so with `^`.

In particular, "nil" matches from `?` or `*` don't count towards the number of matches when deciding whether to fold, so if half of an expression is optional, and missing, the other half can be folded up - but the layer can still appear in the tree if there would be content there. This is what lets us skip many of the layers of the operator precedence table.

If the exclamation mark `!` appears on its own as an element of a rule, in the event that the rule fails to return a match after that point, instead of resetting and trying something else, the parser will error out. This is handy for something like e.g. a `Type` or `Function` declaration, where you know what the object *has* to be, from the first word: you don't want it to try a different pattern if the match fails, because you already know there must be an error around here, and this way you can give a more localized error message.

Note that while ostensibly designed as an runtime builder, this is really intended as just a more declarative way of expressing static parsers in Blitz code (moving parser construction to runtime eliminates extra build steps associated with parser generation). As a result, the internal rule definition functions use `RunTimeError` to signal problems (the parser engine itself uses regular catchable exceptions to report errors in the *input stream* without crashing). In other words, verify that your grammar and so on is correct before releasing your program! This is not really intended for dynamically loading new language grammars on the fly (at that point, you have to admit defeat and say "just go and use Lisp!").

**Warning:** There are two major restrictions upon the rules that can be expressed by this API. Firstly, the parser engine that interprets the rules uses something akin to recursive descent (LL/top down); this means no left-recursive rules or you'll get an infinite loop that never matches anything. Secondly, the parser engine uses actual recursion (because looping is a PITA for such things), so make sure to make use of the `*`/`+` operators rather than using deep recursion to describe repetitive or list-like structures, or there will be a very real risk of stack overflow.

