import
  std/strutils,
  bassy

proc execute(source: string): Runtime =
  ## Compiles and executes a control-flow example with default limits.
  result = initRuntime(compile(source))
  discard result.run

proc rejects(source, message: string) =
  ## Requires a compile-time BASIC error with the expected diagnostic.
  try:
    discard compile(source)
    doAssert false, "Expected a compile error for: " & source
  except BasicError as error:
    doAssert message in error.msg, error.msg

proc stops(source, message: string, limits = defaultLimits()) =
  ## Requires a controlled runtime error without allowing a host defect.
  var runtime = initRuntime(compile(source, limits), limits)
  try:
    discard runtime.run
    doAssert false, "Expected a runtime error for: " & source
  except BasicError as error:
    doAssert message in error.msg, error.msg

echo "Testing single-line IF branches and nearest ELSE binding"
block:
  let runtime = execute("""
if true then a = 1: b = 2 else a = 9: b = 9
if false then c = 9: d = 9 else c = 3: d = 4
if true then if false then e = 9 else e = 5 else e = 8
if false then if true then f = 9 else f = 8 else f = 6
if false then g = 9 ' Ignore this branch.
g = g + 7
if true then h = 8: rem The rest of this line is a comment.
i = 9
if true then print else print "wrong"
if false then print "wrong"; else print "";
""")
  for i, name in ["a", "b", "c", "d", "e", "f", "g", "h", "i"]:
    doAssert runtime.getGlobal(name) == int32(i + 1)

echo "Testing block ELSEIF chains, blank lines, and nested inline IF"
block:
  let program = compile("""
if choice = 0 then
  answer = 10

elseif choice = 1 then
  if true then answer = 11 else answer = 99
elseif choice = 2 then
  answer = 12
else rem Fallback choice.
  answer = 13

end if
""")
  for i in 0 .. 3:
    var runtime = initRuntime(program)
    runtime.setGlobal("choice", int32(i))
    discard runtime.run
    doAssert runtime.getGlobal("answer") == int32(10 + i)
  let commented = execute("""
if false then rem First condition.
  answer = 9
elseif true then rem Second condition.
  answer = 42
end if
""")
  doAssert commented.getGlobal("answer") == 42

echo "Testing FOR directions, skipped loops, captured values, and NEXT lists"
block:
  let runtime = execute("""
limit = 3
stride = 1
for i = 1 to limit step stride
  total = total + i
  limit = 0
  stride = -1
next i
for j = 3 to 1 step -1
  descending = descending + j
next
for k = 3 to 1
  skipped = skipped + 1
next k
for k = 1 to 3 step -1
  skipped = skipped + 1
next
for x = 1 to 2
  for y = 1 to 3
    for z = 1 to 2
      nested = nested + 1
    next z, y, x
sub count(p)
  for p = 2 to 4
    localTotal = localTotal + p
  next p
  after = p
end sub
count(99)
""")
  doAssert runtime.getGlobal("total") == 6
  doAssert runtime.getGlobal("descending") == 6
  doAssert runtime.getGlobal("skipped") == 0
  doAssert runtime.getGlobal("nested") == 12
  doAssert runtime.getGlobal("localTotal") == 9
  doAssert runtime.getGlobal("after") == 5
  doAssert runtime.getGlobal("i") == 4
  doAssert runtime.getGlobal("j") == 0

echo "Testing DO entry and exit conditions and targeted loop exits"
block:
  let runtime = execute("""
do while a < 3
  a = a + 1
loop
do until b = 3
  b = b + 1
loop
do
  c = c + 1
loop while c < 3
do
  d = d + 1
loop until d = 3
do while false
  skipped = 1
loop
do until true
  skipped = 1
loop
do
  once = once + 1
loop while false
do
  outer = outer + 1
  for i = 1 to 4
    if i = 2 then exit do
  next
loop
for j = 1 to 4
  do
    if j = 1 then exit for
  loop
next j
for k = 1 to 3
  for m = 1 to 3
    hits = hits + 1
    exit for
  next m
next k
""")
  for name in ["a", "b", "c", "d"]:
    doAssert runtime.getGlobal(name) == 3
  doAssert runtime.getGlobal("skipped") == 0
  doAssert runtime.getGlobal("once") == 1
  doAssert runtime.getGlobal("outer") == 1
  doAssert runtime.getGlobal("j") == 1
  doAssert runtime.getGlobal("hits") == 3

echo "Testing FOR matches a reference loop over signed ranges"
block:
  let program = compile("""
for i = first to last step stride
  total = total + i
  count = count + 1
next
""")
  var runtime = initRuntime(program)
  for first in -4 .. 4:
    for last in -4 .. 4:
      for stride in [-3, -2, -1, 1, 2, 3]:
        runtime.reset
        runtime.setGlobal("first", int32(first))
        runtime.setGlobal("last", int32(last))
        runtime.setGlobal("stride", int32(stride))
        discard runtime.run
        var
          value = first
          total = 0
          count = 0
        while (stride > 0 and value <= last) or
          (stride < 0 and value >= last):
            total += value
            inc count
            value += stride
        doAssert runtime.getGlobal("total") == int32(total)
        doAssert runtime.getGlobal("count") == int32(count)
        doAssert runtime.getGlobal("i") == int32(value)

echo "Testing SELECT CASE lists, ranges, comparisons, and first matches"
block:
  let program = compile("""
select case choice
case -2, -1
  answer = 1
case 0 to 2, 4
  answer = 2
case is >= 5
  select case choice
  case 5
    answer = 3
  case else
    answer = 4
  end select
case else
  answer = 5
end select
select case choice
end select
""")
  for (choice, expected) in [(-3, 5), (-1, 1), (0, 2), (3, 5), (4, 2),
    (5, 3), (9, 4)]:
      var runtime = initRuntime(program)
      runtime.setGlobal("choice", int32(choice))
      discard runtime.run
      doAssert runtime.getGlobal("answer") == int32(expected)
  for comparison in ["=", "<>", "<", "<=", ">", ">="]:
    let runtime = execute(
      "select case 3\ncase is " & comparison &
      " 3\nanswer = 1\ncase else\nanswer = 0\nend select"
    )
    doAssert runtime.getGlobal("answer") ==
      int32(comparison in ["=", "<=", ">="])

echo "Testing control expressions are evaluated once and CASE is lazy"
block:
  var
    host = initHost()
    calls = 0
  let tick: HostProc = proc(arguments: openArray[int32]): int32 =
    ## Counts evaluations and returns the requested expression value.
    inc calls
    arguments[0]
  discard host.addFunction("tick", 1, tick)
  let program = compile("""
for i = tick(1) to tick(3) step tick(1)
  total = total + i
next
select case tick(2)
case tick(2), tick(99)
  answer = 1
case tick(2)
  answer = 9
end select
if tick(0) then
  branch = 9
elseif tick(1) then
  branch = 1
elseif tick(1) then
  branch = 9
end if
""", host)
  var runtime = initRuntime(program, host)
  discard runtime.run
  doAssert calls == 7
  doAssert runtime.getGlobal("total") == 6
  doAssert runtime.getGlobal("answer") == 1
  doAssert runtime.getGlobal("branch") == 1

echo "Testing named and numbered jumps, declarations, and shorthand IF"
block:
  let runtime = execute("""
10 dim values(1)
20 goto Start
30 values(0) = 99
35 Start:
40 count = count + 1
50 if count < 3 then 40 else Done
Done: values(0) = count
60 goto 90
70 values(1) = 99
90 values(1) = 7
100 end
""")
  doAssert runtime.getArray("values", 0) == 3
  doAssert runtime.getArray("values", 1) == 7
  let local = execute("""
goto start
start: demo()
end
sub demo()
  goto START
  wrong = 1
start:
  result = 42
end sub
""")
  doAssert local.getGlobal("result") == 42
  doAssert local.getGlobal("wrong") == 0

echo "Testing nested GOSUB, RETURN targets, and shared SUB parameters"
block:
  let runtime = execute("""
gosub first
result = result + 1
gosub redirect
wrong = 1
finish: demo(5)
end
first:
result = result + 10
gosub second
return
second:
result = result + 100
return
redirect:
return finish
sub demo(p)
  gosub bump
  parameter = p
  exit sub
bump:
  p = p + 1
  return
end sub
""")
  doAssert runtime.getGlobal("result") == 111
  doAssert runtime.getGlobal("wrong") == 0
  doAssert runtime.getGlobal("parameter") == 6

echo "Testing GOSUB shares call limits and preserves control registers"
block:
  let runtime = execute("""
for i = 1 to 3
  gosub worker
next
end
worker:
for j = 1 to 2
  total = total + i
next
return
""")
  doAssert runtime.getGlobal("total") == 12
  var limits = defaultLimits()
  limits.maxCallDepth = 3
  stops("again: gosub again", "call depth", limits)
  stops("return", "RETURN without")
  stops("return done\ndone: end", "RETURN label without")

echo "Testing EXIT SUB and END SUB unwind pending GOSUB frames"
block:
  let program = compile("""
for i = 1 to 100
  first()
  second()
next
finished = 1
end
sub first()
  gosub leave
  wrong = 1
leave:
  exit sub
end sub
sub second()
  gosub leave
  wrong = 1
leave:
end sub
""")
  var limits = defaultLimits()
  limits.maxCallDepth = 3
  var runtime = initRuntime(program, limits)
  discard runtime.run
  doAssert runtime.getGlobal("finished") == 1
  doAssert runtime.getGlobal("wrong") == 0

echo "Testing recursive GOSUB preserves the caller's captured FOR bound"
block:
  let runtime = execute("""
bound = 3
gosub worker
end
worker:
for i = 1 to bound
  if entered = 0 then
    entered = 1
    bound = 1
    gosub worker
    bound = 3
  end if
  total = total + 1
next
return
""")
  doAssert runtime.getGlobal("total") == 3
  doAssert runtime.getGlobal("i") == 4

echo "Testing GOSUB failure recovery and bounded register storage"
block:
  let program = compile("""
if mode = 0 then gosub again
answer = 42
end
again:
gosub again
return
""")
  var limits = defaultLimits()
  limits.maxCallDepth = 3
  var runtime = initRuntime(program, limits)
  try:
    discard runtime.run
    doAssert false
  except BasicError as error:
    doAssert "call depth" in error.msg
  runtime.restart
  runtime.setGlobal("mode", 1)
  discard runtime.run
  doAssert runtime.getGlobal("answer") == 42
  limits.maxMemoryBytes = runtime.memoryBytes - 1
  try:
    discard initRuntime(program, limits)
    doAssert false
  except BasicError as error:
    doAssert "memory limit" in error.msg

echo "Testing computed GOTO and GOSUB dispatch and fallthrough"
block:
  let program = compile("""
on choice gosub first, second
on choice goto finished, finished
outside = 1
goto finished
first:
result = 10
return
second:
result = 20
return
finished:
end
""")
  for choice in -1 .. 3:
    var runtime = initRuntime(program)
    runtime.setGlobal("choice", int32(choice))
    discard runtime.run
    if choice in 1 .. 2:
      doAssert runtime.getGlobal("result") == int32(choice * 10)
      doAssert runtime.getGlobal("outside") == 0
    else:
      doAssert runtime.getGlobal("result") == 0
      doAssert runtime.getGlobal("outside") == 1

echo "Testing all backward branches remain metered in release builds"
block:
  var limits = defaultLimits()
  limits.maxInstructions = 200
  limits.maxWorkUnits = 10_000
  for source in [
    "again: goto again",
    "10 goto 10",
    "again: if true then again",
    "do\nloop",
    "do while true\nloop",
    "do\nloop until false",
    "for i = 1 to 3 step 0\nnext",
    "again: on 1 goto again",
    "again: gosub work\ngoto again\nwork: return",
    "for i = 2147483647 to 2147483647\nnext"
  ]:
    stops(source, "instruction limit", limits)
  limits.maxInstructions = 10_000
  limits.maxWorkUnits = 50
  stops("again: goto again", "work limit", limits)

echo "Testing invalid control flow raises BASIC errors"
block:
  for source in [
    "goto missing", "gosub missing", "return missing",
    "a: a: end", "10 end\n10 end", "goto -1", "goto 2147483648",
    "for i = 1 to 3", "for i = 1 to 3\nnext j", "next i",
    "for i = 1 to 2\nfor i = 1 to 2\nnext i,i",
    "for i = 1 to 2\nnext i,", "for i = 1 to 2\nnext i,j",
    "do", "loop", "do while true\nloop while true",
    "exit do", "exit for", "exit sub",
    "select case 1", "case 1", "select case 1\nprint 1\nend select",
    "select case 1\ncase else\ncase 1\nend select",
    "select case 1\ncase is + 1\nend select",
    "select case 1\ncase is = 1 to 3\nend select",
    "if true then x = 1\nend if", "elseif true then",
    "if true then for i = 1 to 2\nnext",
    "goto inside\nsub demo()\ninside: end sub",
    "outside: demo()\nsub demo()\ngoto outside\nend sub",
    "on 1 print 2", "on 1 goto missing,", "on goto target"
  ]:
    rejects(source, "")

echo "Testing control nesting and register limits"
block:
  var limits = defaultLimits()
  limits.maxSyntaxDepth = 4
  for source in [
    "do\n".repeat(5) & "exit do\n" & "loop\n".repeat(5),
    "if true then ".repeat(5) & "x = 1",
    "select case 1\ncase 1\n".repeat(5) & "end select\n".repeat(5)
  ]:
    try:
      discard compile(source, limits)
      doAssert false
    except BasicError as error:
      doAssert "syntax nesting" in error.msg
  limits = defaultLimits()
  limits.maxRegisters = 4
  try:
    discard compile("for i = 1 to 3\nfor j = 1 to 3\nnext j,i", limits)
    doAssert false
  except BasicError as error:
    doAssert "register" in error.msg

echo "Testing truncated control syntax cannot cause host defects"
block:
  for source in [
    "if true then a = 1: b = 2 else if false then a = 3 else b = 4\n",
    "for i = 1 to 3 step -1\nnext i\n",
    "select case 1\ncase 1 to 3, is >= 5\na = 2\nend select\n",
    "10 gosub target\n20 end\ntarget: return 20\n",
    "do until true\nexit do\nloop\n"
  ]:
    for i in 0 .. source.len:
      try:
        discard compile(source[0 ..< i])
      except BasicError:
        discard

echo "Testing mutated control programs keep failures inside BASIC"
block:
  var limits = defaultLimits()
  limits.maxCallDepth = 8
  limits.maxInstructions = 500
  limits.maxWorkUnits = 2_000
  for source in [
    "for i = 1 to 3\nif i = 2 then goto done\nnext\ndone: end",
    "10 gosub again\n20 end\nagain: on 1 goto finish\nfinish: return 20",
    "do until i = 3\ni = i + 1\nif i = 2 then exit do\nloop",
    "select case 1\ncase 1 to 3, is >= 5\nx = 2\ncase else\nx = 3\nend select"
  ]:
    for i in 0 ..< source.len:
      for replacement in ["", ":", "\n", "else", ",", "0"]:
        let changed = source[0 ..< i] & replacement & source[i + 1 .. ^1]
        try:
          var runtime = initRuntime(compile(changed, limits), limits)
          discard runtime.run
        except BasicError:
          discard

echo "Control flow tests passed"
