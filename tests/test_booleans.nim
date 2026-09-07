import
  std/strutils,
  bossy

proc execute(source: string, disableFixed = false): Runtime =
  ## Runs a Boolean example with the requested numeric policy.
  var limits = defaultLimits()
  limits.disableFixed = disableFixed
  result = initRuntime(compile(source, limits), limits)
  discard result.run

proc errorContains(action: proc() {.closure.}, expected: string): bool =
  ## Checks that invalid logical expressions raise controlled BASIC errors.
  try:
    action()
  except BasicError as error:
    result = expected in error.msg

echo "Testing BASIC Boolean constants, comparisons, and bit patterns"
block:
  for disabled in [false, true]:
    var limits = defaultLimits()
    limits.disableFixed = disabled
    for (expression, expected) in [
      ("true", -1), ("false", 0), ("not false", -1), ("not true", 0),
      ("2 = 2", -1), ("2 <> 2", 0), ("2 < 3", -1), ("2 <= 2", -1),
      ("3 > 2", -1), ("3 >= 3", -1), ("not 1", -2),
      ("63 and 16", 16), ("-1 and 8", 8), ("10 or 9", 11),
      ("10 xor 10", 0), ("not 10", -11), ("1 and 2", 0),
      ("not -2147483648", 2147483647), ("not 2147483647", -2147483648),
      ("-2147483648 or 2147483647", -1), ("-2147483648 and 1", 0)
    ]:
      let runtime = execute("answer = " & expression, disabled)
      doAssert runtime.getGlobal("answer") == expected, expression
      doAssert runtime.getGlobalValue("answer").kind == IntegerValue
    let comparisons = compile("""
equal = left = right
unequal = left <> right
less = left < right
atMost = left <= right
greater = left > right
atLeast = left >= right
""", limits)
    for left in [low(int32), -1'i32, 0'i32, 1'i32, high(int32)]:
      for right in [low(int32), -1'i32, 0'i32, 1'i32, high(int32)]:
        var runtime = initRuntime(comparisons, limits)
        runtime.setGlobal("left", left)
        runtime.setGlobal("right", right)
        discard runtime.run
        for (name, expected) in [
          ("equal", left == right), ("unequal", left != right),
          ("less", left < right), ("atMost", left <= right),
          ("greater", left > right), ("atLeast", left >= right)
        ]:
          let answer =
            if expected:
              -1
            else:
              0
          doAssert runtime.getGlobal(name) == answer

echo "Testing all six logical operators against the BASIC truth table"
block:
  const Operators = ["and", "or", "xor", "eqv", "imp"]
  for disabled in [false, true]:
    var limits = defaultLimits()
    limits.disableFixed = disabled
    for (left, right, expected) in [
      (-1, -1, [-1, -1, 0, -1, -1]),
      (-1, 0, [0, -1, -1, 0, 0]),
      (0, -1, [0, -1, -1, 0, -1]),
      (0, 0, [0, 0, 0, -1, -1]),
      (10, 9, [8, 11, 3, -4, -3]),
      (2147483647, -2147483648, [0, -1, -1, 0, -2147483648])
    ]:
      for i, op in Operators:
        let source =
          "folded = (" & $left & ") " & op & " (" & $right & ")\n" &
          "executed = left " & op & " right\n" &
          "inverse = not left\n"
        var runtime = initRuntime(compile(source, limits), limits)
        runtime.setGlobal("left", left)
        runtime.setGlobal("right", right)
        discard runtime.run
        doAssert runtime.getGlobal("folded") == expected[i], source
        doAssert runtime.getGlobal("executed") == expected[i], source
        doAssert runtime.getGlobal("inverse") == not int32(left), source

echo "Testing NOT, AND, OR, XOR, EQV, and IMP precedence"
block:
  for disabled in [false, true]:
    for (expression, expected) in [
      ("not 2 = 1", -1), ("not 1 + 1", -3), ("not not 5", 5),
      ("not 3 and 6", 4), ("1 or 3 and 2", 3), ("1 xor 1 or 1", 0),
      ("1 eqv 1 xor 1", -2), ("0 imp 0 eqv 1", -1),
      ("0 eqv 0 imp 0", 0), ("(1 xor 1) or 1", 1),
      ("not (1 and 2)", -1), ("not 1 < 2 and 3 >= 3", 0)
    ]:
      let runtime = execute("answer = " & expression, disabled)
      doAssert runtime.getGlobal("answer") == expected, expression
    let runtime = execute("""
a = 1
b = 2
c = 3
comparison = not a = b
arithmetic = not a + b
nested = not not c
mixed = a xor a or a
while not i = 3
  i = i + 1
wend
if 1 and 2 then branch = 10 else branch = 20
do until 2
  skipped = 1
loop
do
  once = once + 1
loop until 2
""", disabled)
    doAssert runtime.getGlobal("comparison") == -1
    doAssert runtime.getGlobal("arithmetic") == -4
    doAssert runtime.getGlobal("nested") == 3
    doAssert runtime.getGlobal("mixed") == 0
    doAssert runtime.getGlobal("i") == 3
    doAssert runtime.getGlobal("branch") == 20
    doAssert runtime.getGlobal("skipped") == 0
    doAssert runtime.getGlobal("once") == 1

echo "Testing fixed-point logical operands round ties to even"
block:
  for (value, rounded) in [
    (0.0'fx, 0), (-0.0'fx, 0), (0.49'fx, 0), (0.5'fx, 0), (0.51'fx, 1),
    (1.5'fx, 2), (2.5'fx, 2), (3.5'fx, 4), (4.5'fx, 4),
    (-0.49'fx, 0), (-0.5'fx, 0), (-0.51'fx, -1), (-1.5'fx, -2), (-2.5'fx, -2),
    (-3.5'fx, -4), (-4.5'fx, -4), (32766.5'fx, 32766),
    (32767.0'fx, 32767), (-32767.5'fx, -32768),
    (-32768.0'fx, -32768)
  ]:
    let source =
      "folded = (" & $value & ") and -1\n" &
      "executed = value and -1\n" &
      "inverse = not value\n" &
      "if value then branch = -1 else branch = 0"
    var runtime = initRuntime(compile(source))
    runtime.setGlobal("value", value)
    discard runtime.run
    doAssert runtime.getGlobal("folded") == rounded, $value
    doAssert runtime.getGlobal("executed") == rounded, $value
    doAssert runtime.getGlobal("inverse") == not int32(rounded), $value
    let answer =
      if value != 0.0'fx:
        -1
      else:
        0
    doAssert runtime.getGlobal("branch") == answer
  for value in ["2147483647.1", "2147483648.0", "-2147483648.1", "1e100"]:
    for expression in [
      "not value", "value and 0", "0 or value", "value xor 0",
      "0 eqv value", "0 imp value"
    ]:
      let
        folded = "answer = " & expression.replace("value", value)
        executed = "value = " & value & "\nanswer = " & expression
      doAssert errorContains(
        proc() = discard execute(folded),
        "range"
      )
      doAssert errorContains(
        proc() = discard execute(executed),
        "range"
      )

echo "Testing Boolean host values, callbacks, strings, and eager evaluation"
block:
  for disabled in [false, true]:
    var
      limits = defaultLimits()
      host = initHost()
      calls: seq[int32]
    limits.disableFixed = disabled
    let
      predicate: NumericHostProc = proc(args: openArray[Value]): Value =
        ## Returns a Nim Boolean through the BASIC value converter.
        args[0].asBool
      record: HostProc = proc(args: openArray[int32]): int32 =
        ## Records each operand evaluation and returns its bit pattern.
        calls.add args[0]
        args[0]
    discard host.addData("enabled", true)
    discard host.addFunction("predicate", 1, predicate)
    discard host.addFunction("record", 1, record)
    let pool = initStringPool()
    host.addStringFunctions(pool)
    let program = compile("""
hostValue = enabled
isTrue = predicate(2)
isFalse = predicate(0)
a = false and record(1)
b = true or record(2)
c = false imp record(3)
d = record(4) xor record(5)
same = strEq(strNew("same"), strNew("same"))
different = not strEq(strNew("same"), strNew("other"))
inverse = not strEq(strNew("same"), strNew("same"))
compare = strCmp(strNew("z"), strNew("a"))
""", host, limits)
    pool.bindProgram(program)
    var runtime = initRuntime(program, host, limits)
    discard runtime.run
    doAssert calls == @[1'i32, 2, 3, 4, 5]
    for name in ["hostValue", "isTrue", "same", "different"]:
      doAssert runtime.getGlobal(name) == -1
    doAssert runtime.getGlobal("isFalse") == 0
    doAssert runtime.getGlobal("inverse") == 0
    doAssert runtime.getGlobal("compare") == 1
    doAssert runtime.getGlobal("a") == 0
    doAssert runtime.getGlobal("b") == -1
    doAssert runtime.getGlobal("c") == -1
    doAssert runtime.getGlobal("d") == 1
    runtime.setGlobal("hostValue", false)
    doAssert not runtime.getGlobalValue("hostValue").asBool
    runtime.setData("enabled", false)
    doAssert runtime.getData("enabled") == 0
  for value in [toValue(-1), toValue(1), toValue(2), toValue(0.5'fx)]:
    doAssert value.asBool
  doAssert not toValue(0).asBool
  doAssert not toValue(0.0'fx).asBool
  doAssert toValue(true).asInt == -1
  doAssert toValue(false).asInt == 0

echo "Testing Boolean output and sandbox limits"
block:
  let program = compile("print true; false; 1 = 1; not 1")
  var
    runtime = initRuntime(program)
    values: seq[int32]
  let logger: PrintProc = proc(event: PrintEvent) =
    ## Captures integer print events for Boolean representation checks.
    if event.kind == ValuePrint:
      values.add event.value
  let stats = runtime.run(logger)
  doAssert values == @[-1'i32, 0, -1, -2]
  doAssert stats.printBytes == 8
  var limits = defaultLimits()
  limits.maxPrintBytes = 7
  var short = initRuntime(program, limits)
  doAssert errorContains(proc() = discard short.run, "print byte limit")
  limits = defaultLimits()
  limits.disableFixed = true
  limits.maxWorkUnits = 100
  var looped = initRuntime(compile("while not false\nwend", limits), limits)
  doAssert errorContains(proc() = discard looped.run, "work limit")
  for expression in ["not ".repeat(MaximumSyntaxDepth + 1) & "true",
    "not", "1 eqv", "1 imp", "and 1"]:
      doAssert errorContains(proc() = discard compile("x = " & expression), "")
  for name in ["eqv", "imp"]:
    doAssert errorContains(proc() = discard compile(name & " = 1"), "")
    var host = initHost()
    doAssert errorContains(proc() = discard host.addData(name), "reserved")

echo "Boolean tests passed"
