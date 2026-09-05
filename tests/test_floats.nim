import
  std/[math, strutils],
  basic

proc errorContains(action: proc() {.closure.}, expected: string): bool =
  ## Checks that invalid numeric operations remain catchable BASIC errors.
  try:
    action()
  except BasicError as error:
    result = expected in error.msg

proc execute(source: string): Runtime =
  ## Compiles and executes one numeric test script.
  result = initRuntime(compile(source))
  discard result.run

echo "Testing floating literals, mixed arithmetic, and division"
block:
  let runtime = execute("""
a = 1.5
b = .25
c = 2.
d = 1e-2
e = 2.5D+1
f = 2d-1
large = 2147483648.0
sum = a + b
product = a * 2
difference = 2 - a
negative = -a
fraction = 3 / 2
runtimeFraction = product / 2
integer = 7 \ 2
remainder = 7.0 mod 2.0
wrapped = 2147483647 + 1
promoted = 2147483647 + 1.0
boolean = a > b and not 0.0
zero = 1e-512
""")
  for (name, expected) in [
    ("a", 1.5), ("b", 0.25), ("c", 2.0), ("d", 0.01),
    ("e", 25.0), ("f", 0.2), ("large", 2147483648.0),
    ("sum", 1.75), ("product", 3.0), ("difference", 0.5),
    ("negative", -1.5), ("fraction", 1.5), ("runtimeFraction", 1.5),
    ("promoted", 2147483648.0), ("zero", 0.0)
  ]:
    let value = runtime.getGlobalValue(name)
    doAssert value.kind == FloatValue
    doAssert value.asFloat == expected, name
  doAssert runtime.getGlobal("integer") == 3
  doAssert runtime.getGlobal("remainder") == 1
  doAssert runtime.getGlobal("wrapped") == low(int32)
  doAssert runtime.getGlobal("boolean") == -1
  doAssert runtime.getGlobalValue("boolean").kind == IntegerValue
  doAssert errorContains(
    proc() = discard runtime.getGlobal("fraction"), "exact int32"
  )

echo "Testing folded and executed numeric expressions agree"
block:
  for (left, right) in [(1.5, 0.5), (-2.25, 3.0), (0.0, -0.125)]:
    for op in ["+", "-", "*", "/", "=", "<>", "<", "<=", ">", ">=",
        "and", "or", "xor"]:
      let source =
        "folded = (" & $left & ") " & op & " (" & $right & ")\n" &
        "executed = left " & op & " right\n"
      var runtime = initRuntime(compile(source))
      runtime.setGlobal("left", left)
      runtime.setGlobal("right", right)
      discard runtime.run
      let
        folded = runtime.getGlobalValue("folded")
        executed = runtime.getGlobalValue("executed")
      doAssert folded == executed, source
      doAssert folded.kind == executed.kind

  for value in [toValue(-1.5), toValue(0.0), toValue(0.5), toValue(3'i32)]:
    for op in ["=", "<>", "<", "<=", ">", ">="]:
      for reversed in [false, true]:
        let condition =
          if reversed:
            "1 " & op & " value"
          else:
            "value " & op & " 1"
        var runtime = initRuntime(compile(
          "expected = " & condition & "\n" &
          "if " & condition & " then actual = -1 else actual = 0"
        ))
        runtime.setGlobal("value", value)
        discard runtime.run
        doAssert runtime.getGlobal("actual") == runtime.getGlobal("expected")

echo "Testing floats in arrays, fused operations, SUB, GOSUB, and loops"
block:
  var host = initHost()
  discard host.addData("delta", 0.25)
  var runtime = initRuntime(compile("""
dim values(3)
sub accumulate(amount)
  parameterTotal = parameterTotal + amount
  for k = 0.25 to 0.5 step 0.25
    gosub doubleAmount
    parameterAfter = amount
  next
  exit sub
doubleAmount:
  amount = amount * 2
  return
end sub
index = 1
increment = 0.5
values(index) = 1.25
values(index) = values(index) + increment
total = total + values(index)
total = total + delta
total = total + 1
copy = total
accumulate(0.25)
for t = 0.25 to 1.0 step 0.25
  ascending = ascending + t
next
for t = 1.0 to 0.25 step -0.25
  descending = descending + t
next
select case ascending
case 2.0 to 2.5
  selected = 1
case else
  selected = 0
end select
do
  counter = counter + 0.25
loop until counter >= 1
""", host), host)
  discard runtime.run
  doAssert runtime.getArrayValue("values", 1).asFloat == 1.75
  doAssert runtime.getGlobalValue("copy").asFloat == 3.0
  doAssert runtime.getGlobalValue("parameterTotal").asFloat == 0.25
  doAssert runtime.getGlobalValue("parameterAfter").asFloat == 1.0
  doAssert runtime.getGlobalValue("ascending").asFloat == 2.5
  doAssert runtime.getGlobalValue("descending").asFloat == 2.5
  doAssert runtime.getGlobal("selected") == 1
  doAssert runtime.getGlobal("counter") == 1
  runtime.setArray("values", 0, 2.75)
  doAssert runtime.getArrayValue("values", 0).asFloat == 2.75
  doAssert errorContains(
    proc() = discard runtime.getArray("values", 0), "exact int32"
  )
  runtime.restart
  doAssert runtime.getArrayValue("values", 0).asFloat == 2.75
  runtime.reset
  doAssert runtime.getArrayValue("values", 0).kind == IntegerValue
  doAssert runtime.getArray("values", 0) == 0
  doAssert runtime.getGlobalValue("copy").kind == IntegerValue
  discard runtime.run
  doAssert runtime.getGlobalValue("copy").asFloat == 3.0

echo "Testing numeric callbacks, nested calls, and host data"
block:
  var
    host = initHost()
    calls = 0
  let
    add: NumericHostProc = proc(args: openArray[Value]): Value =
      ## Adds mixed arguments without narrowing.
      inc calls
      args[0] + args[1]
    quarter: NumericHostProc = proc(args: openArray[Value]): Value =
      ## Supplies a fraction from a zero-argument callback.
      doAssert args.len == 0
      0.25
    identity: HostProc = proc(args: openArray[int32]): int32 =
      ## Preserves compatibility with integer-only native functions.
      args[0]
  discard host.addData("delta", 0.5)
  discard host.addFunction("add", 2, add, workUnits = 4)
  discard host.addFunction("quarter", 0, quarter)
  discard host.addFunction("identity", 1, identity)
  doAssert host.getDataValue("delta").asFloat == 0.5
  doAssert errorContains(
    proc() = discard host.getData("delta"), "exact int32"
  )
  host.setData("delta", 0.75)
  let program = compile("""
result = add(0.25, add(delta, quarter()))
add(1.0, 2)
whole = identity(2.0)
""", host)
  var runtime = initRuntime(program, host)
  doAssert runtime.getDataValue("delta").asFloat == 0.75
  runtime.setData("delta", 1.0)
  runtime.setData(program.hostDataIndex("delta"), 0.5)
  discard runtime.run
  doAssert runtime.getGlobalValue("result").asFloat == 1.0
  doAssert runtime.getGlobal("whole") == 2
  doAssert calls == 3
  runtime.restart
  doAssert runtime.getDataValue("delta").asFloat == 0.5
  runtime.reset
  doAssert runtime.getDataValue("delta").asFloat == 0.5
  doAssert errorContains(
    proc() = discard runtime.getData("delta"), "exact int32"
  )
  var limited = defaultLimits()
  limited.maxWorkUnits = 1
  var blocked = initRuntime(program, host, limited)
  doAssert errorContains(proc() = discard blocked.run, "work limit")
  doAssert calls == 3
  var incompatible = initHost()
  discard incompatible.addData("delta")
  let old: HostProc = proc(args: openArray[int32]): int32 =
    ## Supplies the wrong callback representation for schema validation.
    0
  discard incompatible.addFunction("add", 2, old, workUnits = 4)
  discard incompatible.addFunction("quarter", 0, quarter)
  discard incompatible.addFunction("identity", 1, identity)
  doAssert errorContains(
    proc() = discard initRuntime(program, incompatible), "incompatible"
  )

echo "Testing exact integer boundaries and non-finite rejection"
block:
  for source in [
    "dim a(1)\na(0.5) = 1", "dim a(1)\nx = a(0.5)",
    "dim a(1)\ni = 0.5\na(i) = a(i) + i",
    "dim a(1)\ni = 0.5\ntotal = total + a(i)",
    "x = 1.5 mod 2", "x = 1.5\ny = x mod 2",
    "x = 1.5\nif x mod 2 = 0 then y = 1",
    "x = 1.5 \\ 2", "x = 1.5\ny = x \\ 2"
  ]:
    doAssert errorContains(proc() = discard execute(source), "exact int32")
  for value in [Inf, NegInf, NaN]:
    doAssert errorContains(proc() = discard toValue(value), "finite")
  for value in [2147483648.0, -2147483649.0, 0.1, -0.1]:
    doAssert errorContains(proc() = discard toValue(value).asInt, "exact int32")
  for value in [2147483647.0, -2147483648.0, 0.0, -0.0]:
    doAssert toValue(value).asInt == int32(value)
  for source in [
    "x = 1.0 / 0", "x = 1.0\ny = x / 0.0",
    "x = 1 / -0.0", "x = 1.0 mod 0", "x = 1 \\ 0"
  ]:
    doAssert errorContains(proc() = discard execute(source), "division by zero")
  for source in [
    "x = 1e309", "x = 1e308 * 2", "x = 1e308\ny = x * 2",
    "x = 1e308 + 1e308", "x = -1e308\nx = x - 1e308",
    "x = 1e308 / 1e-308"
  ]:
    doAssert errorContains(proc() = discard execute(source), "finite")
  var
    host = initHost()
    calls = 0
  let exact: HostProc = proc(args: openArray[int32]): int32 =
    ## Records that conversion succeeded before executing native code.
    inc calls
    args[0]
  discard host.addFunction("exact", 1, exact)
  for value in ["0.5", "2147483648.0"]:
    var runtime = initRuntime(compile("exact(" & value & ")", host), host)
    doAssert errorContains(proc() = discard runtime.run, "exact int32")
  doAssert calls == 0
  let pool = initStringPool()
  host.addStringFunctions(pool)
  let program = compile("n = strLen(0.5)", host)
  pool.bindProgram(program)
  var runtime = initRuntime(program, host)
  doAssert errorContains(proc() = discard runtime.run, "exact int32")

echo "Testing float print formatting and output budgets"
block:
  let program = compile("print 1.5; 0.25; -2.0; 1e100; -0.0")
  var
    output = ""
    floats: seq[float64]
    runtime = initRuntime(program)
  let logger: PrintProc = proc(event: PrintEvent) =
    ## Preserves the exact text used for output accounting.
    case event.kind
    of TextPrint:
      output.add event.text
    of FloatPrint:
      floats.add event.floatValue
      output.add event.text
    of ValuePrint:
      output.add $event.value
    of NewlinePrint:
      output.add '\n'
  let stats = runtime.run(logger)
  doAssert floats == @[1.5, 0.25, -2.0, 1e100, -0.0]
  doAssert stats.printBytes == output.len
  doAssert stats.printEvents == 6
  var limits = defaultLimits()
  limits.maxPrintBytes = stats.printBytes
  var exact = initRuntime(program, limits)
  doAssert exact.run.printBytes == stats.printBytes
  dec limits.maxPrintBytes
  var short = initRuntime(program, limits)
  doAssert errorContains(proc() = discard short.run, "print byte limit")
  limits.maxPrintBytes = stats.printBytes
  limits.maxPrintEvents = 0
  var noEvents = initRuntime(program, limits)
  doAssert errorContains(proc() = discard noEvents.run(logger), "print event")
  doAssert floats.len == 5

echo "Testing floats remain bounded by memory, work, and call limits"
block:
  let program = compile("dim values(10)\nx = 0.5")
  var limits = defaultLimits()
  let bytes = initRuntime(program).memoryBytes
  limits.maxMemoryBytes = bytes
  var runtime = initRuntime(program, limits)
  discard runtime.run
  doAssert runtime.memoryBytes == bytes
  let larger = initRuntime(compile("dim values(11)\nx = 0.5"))
  doAssert larger.memoryBytes - bytes == 16
  dec limits.maxMemoryBytes
  doAssert errorContains(
    proc() = discard initRuntime(program, limits), "memory limit"
  )
  for source in [
    "for x = 1e100 to 1e100 step 0.25\nnext",
    "x = 0.0\ndo\nx = x + .25\nloop",
    "again: x = x + 0.5\ngoto again"
  ]:
    var execution = defaultLimits()
    execution.maxWorkUnits = 100
    var looped = initRuntime(compile(source), execution)
    doAssert errorContains(proc() = discard looped.run, "work limit")
  limits = defaultLimits()
  limits.maxCallDepth = 3
  var recurse = initRuntime(compile("""
sub recursive(value)
  recursive(value + 0.5)
end sub
recursive(0.25)
"""), limits)
  doAssert errorContains(proc() = discard recurse.run, "call depth")

echo "Testing integer-only policy survives runtime creation and host entry"
block:
  var limits = defaultLimits()
  limits.disableFloats = true
  for source in [
    "x = 1.0", "x = .5", "x = 1e0", "x = 0.0",
    "if 0 then x = .5", "print 0.0"
  ]:
    doAssert errorContains(proc() = discard compile(source, limits), "disabled")
  let program = compile("""
dim a(1)
x = 3 / 2
y = 3
z = y / 2
small = -2147483648 / -1
remainder = -2147483648 mod -1
wrapped = 2147483647 + 1
""", limits)
  var
    runtime = initRuntime(program, limits)
    inherited = initRuntime(program)
  let stats = runtime.run
  doAssert inherited.run == stats
  for name in ["x", "y", "z", "small", "remainder", "wrapped"]:
    doAssert runtime.getGlobalValue(name).kind == IntegerValue
    doAssert runtime.getGlobal(name) == inherited.getGlobal(name)
  doAssert runtime.getGlobal("x") == 1
  doAssert runtime.getGlobal("z") == 1
  doAssert runtime.getGlobal("small") == low(int32)
  doAssert runtime.getGlobal("wrapped") == low(int32)
  doAssert runtime.getGlobal("remainder") == 0
  for value in [0.0, 0.5, 1.0]:
    doAssert errorContains(proc() = runtime.setGlobal("x", value), "disabled")
    doAssert errorContains(
      proc() = inherited.setArray("a", 0, value), "disabled"
    )
  inherited.reset
  inherited.restart
  doAssert errorContains(proc() = inherited.setGlobal("x", 0.0), "disabled")
  doAssert errorContains(
    proc() = discard initRuntime(compile("x = 1 / 2"), limits),
    "compile BASIC with disableFloats"
  )
  var host = initHost()
  discard host.addData("delta", 0.5)
  doAssert errorContains(
    proc() = discard compile("x = delta", host, limits), "disabled"
  )
  host.setData("delta", 1)
  let bound = compile("x = delta", host, limits)
  host.setData("delta", 0.0)
  doAssert errorContains(proc() = discard initRuntime(bound, host), "disabled")
  host.setData("delta", 1)
  var boundRuntime = initRuntime(bound, host)
  doAssert errorContains(
    proc() = boundRuntime.setData("delta", 1.0), "disabled"
  )
  doAssert errorContains(
    proc() = boundRuntime.setData(bound.hostDataIndex("delta"), 0.5), "disabled"
  )
  let numeric: NumericHostProc = proc(args: openArray[Value]): Value =
    ## Attempts to return a float even when its result is discarded.
    0.5
  discard host.addFunction("numeric", 0, numeric)
  for source in ["x = numeric()", "numeric()"]:
    var callback = initRuntime(compile(source, host, limits), host)
    doAssert errorContains(proc() = discard callback.run, "disabled")

echo "Testing malformed floating literals cannot escape BASIC errors"
block:
  for literal in [
    ".", "1e", "1e+", "1d-", "1.2.3", ".e1", "1e513",
    "1e" & "9".repeat(1000), "0." & "0".repeat(1000)
  ]:
    doAssert errorContains(proc() = discard compile("x = " & literal), "")
  const Alphabet = "0123456789.eEdD+-*/\\() "
  var state = 0x13579bdf'u32
  for sample in 0 ..< 2000:
    var source = "x = "
    for i in 0 ..< 1 + sample mod 70:
      state = state xor (state shl 13)
      state = state xor (state shr 17)
      state = state xor (state shl 5)
      source.add Alphabet[int(state mod uint32(Alphabet.len))]
    try:
      discard compile(source)
    except BasicError:
      discard

echo "Floating-point tests passed"
