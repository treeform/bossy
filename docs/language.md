# BASIC language reference

This is a small structured BASIC dialect for embedded scripts.

## Values and expressions

Identifiers and keywords are case-insensitive. Identifiers start with a
letter or underscore, followed by letters, digits, or underscores. Scalar
variables are implicitly declared and begin as integer zero. A value holds
an `int32` or a finite `float64`. Floats are enabled by default. Arrays and
parameters can hold either kind.

Integer literals retain their int32 range. Decimal points or exponents make
floating-point literals, such as `1.5`, `.25`, `2.`, `1e-3`, or `2.5D+2`.
Both `E` and `D` select float64. A float literal is limited to 128 bytes and
an exponent magnitude of 512. Non-finite literals are rejected. Very small
values can underflow to zero.

Integer addition, subtraction, multiplication, and negation wrap in two's
complement. If either operand is a float, arithmetic promotes to float64.
`/` performs floating-point division, including `3 / 2 = 1.5`. Use `\` for
integer division toward zero. `mod` computes an integer remainder. Both
integer operators require exact int32 operands, accepting `3.0` and rejecting
`3.5`. Division by zero and non-finite results raise `BasicError`. Integer
division of the minimum int32 by -1 returns the minimum int32, and the
corresponding remainder is zero.

Floating-point arithmetic follows the host's float64 implementation and is
not a cross-platform determinism guarantee. Integer arithmetic keeps its
existing wrapping semantics, so `2147483647 + 1` wraps while
`2147483647 + 1.0` produces the float `2147483648.0`.

### Disabling floating-point execution

Set `limits.disableFloats = true` before compiling deterministic scripts:

```nim
var limits = defaultLimits()
limits.disableFloats = true
let program = compile("answer = 3 / 2", limits)
var runtime = initRuntime(program, limits)
discard runtime.run
doAssert runtime.getGlobal("answer") == 1
```

In this mode, float literals are rejected and `/` uses the original integer
division semantics. Globals, arrays, host data, and callback results cannot
receive float values, including whole-valued floats such as `1.0`. Integer
arithmetic, comparisons, and VM control flow execute without floating-point
operations.

The restriction is stored in the compiled program and persists through
`initRuntime`, `restart`, and `reset`. Creating a runtime with default limits
does not enable floats for an integer-only program. To run a float-enabled
program under integer-only limits, recompile it with `disableFloats`. Runtime
creation rejects that mismatch because constant folding already used the
selected division semantics. Trusted callbacks still need deterministic
implementations and inputs.

### Numeric values in Nim

Existing `getGlobal`, `getArray`, and `getData` return exact int32 values.
They raise `BasicError` for fractional or out-of-range floats. Use
`getGlobalValue`, `getArrayValue`, and `getDataValue` to read either numeric
kind, then inspect `.kind`, `.asFloat`, or `.asInt`. `.asFloat` widens int32
exactly. `.asInt` requires an exact integer in the int32 range.

Setters and `addData` accept integers or floats through checked `toValue`
converters. `NumericHostProc` accepts `openArray[Value]` and returns `Value`.
Register it with `addFunction`, just like an existing `HostProc`. Integer
callbacks remain available. All their arguments must convert exactly to
int32 before the callback runs, which also protects string handles from
silent truncation. A replacement host must match the compiled callback kind,
argument count, and work cost.

Numeric cells occupy 16 logical bytes in both modes. Host callback slots
occupy 32 bytes, and each argument scratch slot also reserves 4 bytes for
integer callback conversion. These preallocated buffers count toward
`maxMemoryBytes`. Arithmetic does not grow runtime storage. Compiled float
constants belong to the shared program, outside the runtime memory budget.
The instruction, work, call-depth, and output limits apply in both modes.
See [the numeric host example](../examples/floats.nim).

### Booleans and bitwise operators

Comparisons use `=`, `<>`, `<`, `<=`, `>`, and `>=`. They return integer -1
for true and 0 for false. The `true` and `false` constants use the same
representation. Conditions in `if`, `while`, and `until` consider every
nonzero value true, including fractional values such as `0.5`.

Logical operators work on all 32 bits of their integer operands:

| Operator | Operation | Example | Result |
| --- | --- | --- | --- |
| `not` | Complement every bit. | `not 1` | -2 |
| `and` | Keep bits present in both operands. | `6 and 3` | 2 |
| `or` | Keep bits present in either operand. | `6 or 3` | 7 |
| `xor` | Keep bits present in exactly one operand. | `6 xor 3` | 5 |
| `eqv` | Complement XOR. | `6 eqv 3` | -6 |
| `imp` | Complement the left operand, then OR. | `6 imp 3` | -5 |

With operands of -1 and 0, these operations also produce Boolean results.
Use `flags and mask` to test a bit mask. For other nonzero values, `not`
complements the bits instead of testing whether the value is zero. For
example, `not 1` is -2, which is still true in a condition. Use `value = 0`
to test falseness and `value <> 0` to normalize a value to -1 or 0.

Arithmetic binds more tightly than comparisons. Comparisons bind more
tightly than `not`, followed by `and`, `or`, `xor`, `eqv`, and `imp`, in that
order. Thus `not x = 1` means `not (x = 1)`, and `1 xor 1 or 1` is 0.
Parentheses override precedence. Binary logical operators evaluate both
operands, including host function calls. Use nested `if` statements when
evaluating the right operand would be unsafe or perform an unwanted action.

Float operands of logical operators are rounded to the nearest integer,
with exact halves rounded to the even integer. For example, `1.5 and -1`
is 2, `2.5 and -1` is 2, and `0.5 and -1` is 0. Operands outside the int32
range raise `BasicError`. Rounding applies only to logical operators.
Array indices, string handles, integer division, and integer host callbacks
continue to require exact int32 values. When floats are disabled, logical
operations use only integers.

In Nim, `toValue(true)` produces integer -1 and `toValue(false)` produces
zero. Setters and `NumericHostProc` results accept Nim Booleans through this
converter. Use `value.asBool` to test a numeric value as a condition without
rounding. Integer host callbacks that represent Boolean predicates should
return -1 or 0. The built-in `strEq` follows this convention. Ordinary numeric
callback results are preserved, including 1.

This changes earlier versions that returned 1 for true and treated logical
operators as truth tests. Update scripts that explicitly compare a Boolean
to 1, and use `value = 0` when you need a truth test instead of bitwise NOT.
`eqv` and `imp` are now reserved keywords.

The logical rules follow the [QuickBASIC language reference][logical-reference]
and its [documented rounding convention][rounding-reference]. The VM uses
32-bit integers for all bit operations.

[logical-reference]: https://www.pcjs.org/documents/books/mspl13/basic/qblang/
[rounding-reference]: https://jeffpar.github.io/kbarchive/kb/023/Q23389/

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
integer upper bound. Indices run from 0 through n and require exact int32
values. Fractional indices are rejected. Array bounds are checked
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

Counters use the VM's numeric arithmetic and accept fractional steps. A zero
step, integer wraparound, or a float step too small to change the counter can
keep a loop running until an execution budget stops it. Choose bounds and
increments that let the counter reach the end of the range.

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

Parameters are local numeric values passed by value. Other scalar variables
are global. Subroutines can call each other and recurse within the configured
call depth. `exit sub` and `end sub` exit the entire procedure, including any
pending `gosub` calls inside it. For compatibility with earlier versions of
this library, a bare `return` also exits a `sub` when there is no pending
`gosub` in that call. Native host functions can return numeric values and appear
in expressions.

## Output and literals

`print` emits text, integer, float, and newline events to the host's callback.
A `FloatPrint` event provides `floatValue` and its formatted `text`. Write
`text` to preserve the exact byte count charged to the output budget. Integer
output continues to use `ValuePrint` and `event.value`. Float formatting uses
a bounded temporary string, including when the output callback is omitted.
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
| `strEq(a, b)` | -1 if the string contents are equal, otherwise 0. |
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

There are no multidimensional arrays, native string
variables, script-defined value-returning functions, `on error` handlers, or
built-in file, network, or console input operations. The host chooses the
native capabilities exposed to scripts.
