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

`end` and `stop` finish the whole program.

## Conditions

Block `if ... then` ends with `end if`. It accepts any number of `elseif`
branches and an optional final `else`. Conditions are checked in order until
one succeeds, and only that branch runs.

```basic
if health <= 0 then
  action = 0
elseif health < 20 then
  action = 1
else
  action = 2
end if

if action = 1 then retreat = 1: speed = 2 else speed = 1
```

A single-line `if` extends through the physical end of its line, including
colon-separated statements. It has no `end if`. Nested single-line `if`
statements associate `else` with the nearest unmatched `if`. Block statements
such as `for`, `do`, and `select case` belong outside single-line branches.
A trailing `rem` or apostrophe comment after a block header is allowed.

`select case` evaluates its selector once and runs the first matching case.
Cases accept individual values, comma-separated alternatives, inclusive
ranges with `to`, and comparisons with `is`. `case else` is optional and must
be last. Case expressions are checked in order and stop after a match.

```basic
select case health
case 0
  action = 0
case 1 to 20, 25
  action = 1
case is >= 80
  action = 2
case else
  action = 3
end select
```

## Loops

`while ... wend` tests its condition before each iteration.

`for counter = start to finish step increment` evaluates the start, finish,
and increment once on entry. The increment defaults to 1. Positive increments
continue while the counter is at most the finish value, and negative
increments continue while it is at least the finish value. A range facing the
wrong direction is skipped.

```basic
for player = 0 to 3
  scores(player) = scores(player) + 1
next player

for player = 3 to 0 step -1
  if scores(player) > 10 then exit for
next
```

`next` optionally names its counter. `next inner, outer` closes nested loops
in that order. Nested `for` loops must use different counter names. Counters
may be globals or `sub` parameters. `exit for` leaves the nearest enclosing
`for`, even when another kind of loop is nested inside it.

Counters use the VM's wrapping int32 arithmetic. A zero step or counter
overflow can make a loop repeat until its instruction or work limit is hit.
Use bounds and increments that stay within the int32 range for finite loops.

`do ... loop` can test a `while` or `until` condition at either the beginning
or the end, or omit the condition. A condition at the end allows the body to
run at least once. Using both an entry and an exit condition is an error.

```basic
do until target = 0
  target = target - 1
loop

do
  attempts = attempts + 1
  if attempts = 3 then exit do
loop while attempts < 10
```

`exit do` leaves the nearest enclosing `do`. Every loop remains subject to
the runtime budgets, including an empty unconditional `do ... loop`.

## Labels and jumps

Named labels end in `:` and are case-insensitive. Decimal line numbers at the
start of a physical line also define labels. Line numbers are non-negative
int32 values and do not change source execution order. Multiple labels may
refer to the same statement.

```basic
10 attempts = 0
again:
attempts = attempts + 1
if attempts < 3 then goto again
goto finished
finished:
end
```

`goto` accepts a label name or line number. Forward and backward jumps work.
Single-line `if` also accepts shorthand targets, such as
`if ready then 100 else waitHere`.

`gosub` saves a return address before jumping. `return` resumes after that
call, and `return target` consumes the saved return address and jumps to the
specified label instead.

```basic
gosub award
goto finished
award:
score = score + 10
return
finished:
end
```

Labels are local to the main program or their containing `sub`. Jumps and
`gosub` cannot cross those boundaries. Undefined and duplicate labels are
compile errors. Returning without a matching call raises `BasicError`.

`on expression goto first, second` and `on expression gosub first, second`
evaluate the expression once and select a target by its one-based index.
Values outside the target list, including zero and negative values, fall
through to the next statement.

All jump targets enter metered bytecode blocks. `gosub` and ordinary `sub`
calls share the configured call-depth and register-memory limits. `gosub`
preserves the caller's loop and selector registers while sharing globals and
propagating changes to `sub` parameters on return.

A jump into a block bypasses that block's initialization. Enter `for` and
`select case` through their headers to initialize their captured values.
These values occupy dedicated registers, included in the runtime memory
limit and the compiler's register limit.

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
call depth. `exit sub` and `end sub` exit the entire procedure, including any
pending `gosub` calls inside it. For compatibility with earlier versions of
this library, a bare `return` also exits a `sub` when there is no pending
`gosub` in that call. Native host functions can return integers and can appear
in expressions.

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

There are no floating-point values, multidimensional arrays, native string
variables, script-defined value-returning functions, `on error` handlers, or
built-in file, network, or console input operations. The host chooses the
native capabilities exposed to scripts.
