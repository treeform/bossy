# BASIC language reference

This is a small structured BASIC dialect for embedded scripts.

## Values and expressions

Identifiers and keywords are case-insensitive. Identifiers start with a
letter or underscore, followed by letters, digits, or underscores. Scalar
variables are implicitly declared and begin at zero. All values are signed
32-bit integers.

Addition, subtraction, multiplication, and negation wrap in two's complement.
`/` performs integer division, and `mod` computes the remainder. Division by
zero raises `BasicError`. Dividing the minimum int32 value by -1 returns the
minimum int32 value, and the corresponding remainder is zero.

Comparisons use `=`, `<>`, `<`, `<=`, `>`, and `>=`. Boolean operators are
`and`, `or`, `xor`, and `not`. Zero is false and any nonzero value is true.
Boolean results, `true`, and `false` are 1 and 0. Boolean operators evaluate
both operands. Use nested `if` statements when evaluating the right operand
would be unsafe or would perform an unwanted host action.

## Statements

Separate statements with newlines or `:`. Comments start with an apostrophe
or `rem` and continue to the end of the line. `let` is optional in assignments.

```basic
rem Fill five elements, indexed from 0 through 4.
dim scores(4)
i = 0
while i <= 4
  scores(i) = i * 10
  i = i + 1
wend

if scores(4) >= 40 then
  print "passed", scores(4)
else
  print "failed"
end if
```

`dim name(n)` declares a global one-dimensional array with an inclusive
constant upper bound. Indices run from 0 through n. Array bounds are checked
explicitly, including in release builds. Arrays and scalars occupy the shared
global namespace.

`if ... then` uses a block ending in `end if`, with an optional `else` block.
`while` uses a block ending in `wend`. `end` and `stop` finish
the whole program.

## Subroutines

```basic
sub addScore(amount)
  if amount <= 0 then
    exit sub
  end if
  score = score + amount
end sub

addScore(7)
call addScore(3)
```

Parameters are local integer values passed by value. Other scalar variables
are global. Subroutines can call each other and recurse within the configured
call depth. `return` and `exit sub` return without a value. Native host
functions can return integers and can appear in expressions.

## Output and literals

`print` emits text, integer, and newline events to the host's callback.
A comma inserts one space. A semicolon concatenates items, and a trailing
semicolon suppresses the newline. Double a quote inside a quoted literal
to include a quote character.

Quoted literals can appear in `print` and directly as call arguments. A
literal passed to a function becomes a compiled literal ID. A host callback
can resolve it with `program.literal(id)`. It is distinct from a string pool
handle.

## Optional string functions

These functions are available only after the host registers
`addStringFunctions`. All string offsets and lengths are byte-based.

| Function | Result |
| --- | --- |
| `strNew("text")` | Handle for a compiled literal, interned per pool reset. |
| `strLen(s)` | Byte length. |
| `strByte(s, i)` | Byte value at a zero-based index. |
| `strAsc(s)` | First byte, or -1 for an empty string. |
| `strChr(n)` | One-byte string for a value from 0 through 255. |
| `strFromInt(n)` | Decimal integer text. |
| `strVal(s)` | Leading integer, or 0 without digits, saturating on overflow. |
| `strCat(a, b)` | Concatenated strings. |
| `strCatInt(s, n)` | String followed by decimal integer text. |
| `strMid(s, start, length)` | Substring with clamped start and length. |
| `strFind(s, needle, start)` | Match offset from a clamped start, or -1. |
| `strEq(a, b)` | 1 if the string contents are equal, otherwise 0. |
| `strCmp(a, b)` | Lexical comparison as -1, 0, or 1. |
| `strWord(s, i)` | Zero-based whitespace-separated word, or an empty string. |
| `strWordCount(s)` | Number of whitespace-separated words. |
| `strUpper(s)` | ASCII uppercase text. |
| `strLower(s)` | ASCII lowercase text. |
| `strTrim(s)` | Text with surrounding whitespace removed. |

`strVal` accepts leading whitespace, an optional minus, and digits. It stops
at the first non-digit. A leading plus is not recognized.

String count, total stored bytes, single-string length, execution work, and
substring search comparisons are bounded. Handle 0 is the empty string and
counts toward the string limit. Compare string contents with `strEq`, since
equal text can have different handles.

## Unsupported features

There are no line numbers, labels, `goto`, `gosub`, `for` loops, floating-point
values, multidimensional arrays, script-defined value-returning functions,
or built-in file, network, or console input operations. The host chooses the
native capabilities exposed to scripts.
