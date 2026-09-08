import
  std/strutils,
  bassy

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

echo "Testing fixed-point literals, mixed arithmetic, and division"
block:
  let runtime = execute("""
a = 1.5
b = .25
c = 2.
d = 1e-2
e = 2.5D+1
f = 2d-1
large = 32767.0
sum = a + b
product = a * 2
difference = 2 - a
negative = -a
fraction = 3 / 2
runtimeFraction = product / 2
integer = 7 \ 2
remainder = 7.0 mod 2.0
wrapped = 2147483647 + 1
promoted = 32000 + 1.0
boolean = a > b and not 0.0
zero = 1e-512
""")
  for (name, expected) in [
    ("a", 1.5'fx), ("b", 0.25'fx), ("c", 2.0'fx), ("d", 0.01'fx),
    ("e", 25.0'fx), ("f", 0.2'fx), ("large", 32767.0'fx),
    ("sum", 1.75'fx), ("product", 3.0'fx), ("difference", 0.5'fx),
    ("negative", -1.5'fx), ("fraction", 1.5'fx), ("runtimeFraction", 1.5'fx),
    ("promoted", 32001.0'fx), ("zero", 0.0'fx)
  ]:
    let value = runtime.getGlobalValue(name)
    doAssert value.kind == FixedValue
    doAssert value.asFixed == expected, name
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
  for (left, right) in [(1.5'fx, 0.5'fx), (-2.25'fx, 3.0'fx), (0.0'fx, -0.125'fx)]:
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

  for value in [toValue(-1.5'fx), toValue(0.0'fx), toValue(0.5'fx), toValue(3'i32)]:
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

echo "Testing fixed-point values in arrays, fused operations, SUB, GOSUB, and loops"
block:
  var host = initHost()
  discard host.addData("delta", 0.25'fx)
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
  doAssert runtime.getArrayValue("values", 1).asFixed == 1.75'fx
  doAssert runtime.getGlobalValue("copy").asFixed == 3.0'fx
  doAssert runtime.getGlobalValue("parameterTotal").asFixed == 0.25'fx
  doAssert runtime.getGlobalValue("parameterAfter").asFixed == 1.0'fx
  doAssert runtime.getGlobalValue("ascending").asFixed == 2.5'fx
  doAssert runtime.getGlobalValue("descending").asFixed == 2.5'fx
  doAssert runtime.getGlobal("selected") == 1
  doAssert runtime.getGlobal("counter") == 1
  runtime.setArray("values", 0, 2.75'fx)
  doAssert runtime.getArrayValue("values", 0).asFixed == 2.75'fx
  doAssert errorContains(
    proc() = discard runtime.getArray("values", 0), "exact int32"
  )
  runtime.restart
  doAssert runtime.getArrayValue("values", 0).asFixed == 2.75'fx
  runtime.reset
  doAssert runtime.getArrayValue("values", 0).kind == IntegerValue
  doAssert runtime.getArray("values", 0) == 0
  doAssert runtime.getGlobalValue("copy").kind == IntegerValue
  discard runtime.run
  doAssert runtime.getGlobalValue("copy").asFixed == 3.0'fx

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
      0.25'fx
    identity: HostProc = proc(args: openArray[int32]): int32 =
      ## Preserves compatibility with integer-only native functions.
      args[0]
  discard host.addData("delta", 0.5'fx)
  discard host.addFunction("add", 2, add, workUnits = 4)
  discard host.addFunction("quarter", 0, quarter)
  discard host.addFunction("identity", 1, identity)
  doAssert host.getDataValue("delta").asFixed == 0.5'fx
  doAssert errorContains(
    proc() = discard host.getData("delta"), "exact int32"
  )
  host.setData("delta", 0.75'fx)
  let program = compile("""
result = add(0.25, add(delta, quarter()))
add(1.0, 2)
whole = identity(2.0)
""", host)
  var runtime = initRuntime(program, host)
  doAssert runtime.getDataValue("delta").asFixed == 0.75'fx
  runtime.setData("delta", 1.0'fx)
  runtime.setData(program.hostDataIndex("delta"), 0.5'fx)
  discard runtime.run
  doAssert runtime.getGlobalValue("result").asFixed == 1.0'fx
  doAssert runtime.getGlobal("whole") == 2
  doAssert calls == 3
  runtime.restart
  doAssert runtime.getDataValue("delta").asFixed == 0.5'fx
  runtime.reset
  doAssert runtime.getDataValue("delta").asFixed == 0.5'fx
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

echo "Testing exact integer boundaries and fixed-point range rejection"
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
  for value in [0.1'fx, -0.1'fx]:
    doAssert errorContains(proc() = discard toValue(value).asInt, "exact int32")
  for value in [32767.0'fx, -32768.0'fx, 0.0'fx, -0.0'fx]:
    doAssert toValue(value).asInt == value.toInt
  for value in [high(int32), low(int32), 32768'i32, -32769'i32]:
    doAssert errorContains(
      proc() = discard toValue(value).asFixed, "fixed-point range"
    )
  for source in [
    "x = 1.0 / 0", "x = 1.0\ny = x / 0.0",
    "x = 1 / -0.0", "x = 1.0 mod 0", "x = 1 \\ 0"
  ]:
    doAssert errorContains(proc() = discard execute(source), "division by zero")
  for source in [
    "x = 1e309", "x = 32768.0", "x = -32768.1",
    "x = 2147483648.0", "x = 32768 + 0.5",
    "x = 32768\ny = x * 0.5", "x = 1 / 32768"
  ]:
    doAssert errorContains(proc() = discard execute(source), "range")
  var
    host = initHost()
    calls = 0
  let exact: HostProc = proc(args: openArray[int32]): int32 =
    ## Records that conversion succeeded before executing native code.
    inc calls
    args[0]
  discard host.addFunction("exact", 1, exact)
  for value in ["0.5", "32767.5"]:
    var runtime = initRuntime(compile("exact(" & value & ")", host), host)
    doAssert errorContains(proc() = discard runtime.run, "exact int32")
  doAssert calls == 0
  let pool = initStringPool()
  host.addStringFunctions(pool)
  let program = compile("n = strLen(0.5)", host)
  pool.bindProgram(program)
  var runtime = initRuntime(program, host)
  doAssert errorContains(proc() = discard runtime.run, "exact int32")

echo "Testing fixed-point print formatting and output budgets"
block:
  let program = compile("print 1.5; 0.25; -2.0; 1e4; -0.0")
  var
    output = ""
    fixedValues: seq[Fixed]
    runtime = initRuntime(program)
  let logger: PrintProc = proc(event: PrintEvent) =
    ## Preserves the exact text used for output accounting.
    case event.kind
    of TextPrint:
      output.add event.text
    of FixedPrint:
      fixedValues.add event.fixedValue
      output.add event.text
    of ValuePrint:
      output.add $event.value
    of NewlinePrint:
      output.add '\n'
  let stats = runtime.run(logger)
  doAssert fixedValues == @[1.5'fx, 0.25'fx, -2.0'fx, 10000.0'fx, -0.0'fx]
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
  doAssert fixedValues.len == 5

echo "Testing fixed-point values remain bounded by memory, work, and call limits"
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
    "for x = 1.0 to 1.0 step 0.0\nnext",
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
  limits.disableFixed = true
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
  for value in [0.0'fx, 0.5'fx, 1.0'fx]:
    doAssert errorContains(proc() = runtime.setGlobal("x", value), "disabled")
    doAssert errorContains(
      proc() = inherited.setArray("a", 0, value), "disabled"
    )
  inherited.reset
  inherited.restart
  doAssert errorContains(proc() = inherited.setGlobal("x", 0.0'fx), "disabled")
  doAssert errorContains(
    proc() = discard initRuntime(compile("x = 1 / 2"), limits),
    "compile BASIC with disableFixed"
  )
  var host = initHost()
  discard host.addData("delta", 0.5'fx)
  doAssert errorContains(
    proc() = discard compile("x = delta", host, limits), "disabled"
  )
  host.setData("delta", 1)
  let bound = compile("x = delta", host, limits)
  host.setData("delta", 0.0'fx)
  doAssert errorContains(proc() = discard initRuntime(bound, host), "disabled")
  host.setData("delta", 1)
  var boundRuntime = initRuntime(bound, host)
  doAssert errorContains(
    proc() = boundRuntime.setData("delta", 1.0'fx), "disabled"
  )
  doAssert errorContains(
    proc() = boundRuntime.setData(bound.hostDataIndex("delta"), 0.5'fx), "disabled"
  )
  let numeric: NumericHostProc = proc(args: openArray[Value]): Value =
    ## Attempts to return a fixed-point value even when its result is discarded.
    0.5'fx
  discard host.addFunction("numeric", 0, numeric)
  for source in ["x = numeric()", "numeric()"]:
    var callback = initRuntime(compile(source, host, limits), host)
    doAssert errorContains(proc() = discard callback.run, "disabled")

echo "Testing malformed fixed-point literals cannot escape BASIC errors"
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

static:
  doAssert not compiles(toValue(1.0))
  doAssert not compiles(toValue(1.0'f))
  doAssert compiles(toValue(1.0'fx))

echo "Testing fixed-point literal boundaries and exact comparisons"
block:
  let runtime = execute("""
minimum = -32768.0
exponentMinimum = -3.2768D4
maximum = 32767.9999847412109375
quantum = 0.0000152587890625
exponentStep = 1.52587890625e-5
positiveZero = 1e-512
negativeZero = -1e-512
zero = 0e512
below = -2147483648 < minimum
above = 2147483647 > maximum
different = 65536 <> 0.0
equal = -32768 = minimum
""")
  doAssert runtime.getGlobalValue("minimum").asFixed == FixedMinimum
  doAssert runtime.getGlobalValue("exponentMinimum").asFixed == FixedMinimum
  doAssert runtime.getGlobalValue("maximum").asFixed == FixedMaximum
  doAssert runtime.getGlobalValue("quantum").asFixed == FixedEpsilon
  doAssert runtime.getGlobalValue("exponentStep").asFixed == FixedEpsilon
  for name in ["positiveZero", "negativeZero", "zero"]:
    doAssert runtime.getGlobalValue(name).asFixed == FixedZero
  for name in ["below", "above", "different", "equal"]:
    doAssert runtime.getGlobal(name) == -1
  for expression in ["32767.999999", "-32768.01", "3.2768e4"]:
    doAssert errorContains(
      proc() = discard execute("x = " & expression), "range"
    )
  let program = compile("""
lower = integer < decimal
same = integer = decimal
higher = integer > decimal
if integer < decimal then branch = -1
""")
  for integer in [low(int32), -32768'i32, 0'i32, 32767'i32, high(int32)]:
    for decimal in [FixedMinimum, -FixedEpsilon, FixedZero, FixedMaximum]:
      var compared = initRuntime(program)
      compared.setGlobal("integer", integer)
      compared.setGlobal("decimal", decimal)
      discard compared.run
      let
        left = int64(integer) * 65536
        right = int64(int32(decimal))
      doAssert compared.getGlobal("lower") == -int32(left < right)
      doAssert compared.getGlobal("same") == -int32(left == right)
      doAssert compared.getGlobal("higher") == -int32(left > right)
      doAssert compared.getGlobal("branch") == -int32(left < right)

echo "Testing fixed-point overflow and quantized zero divisors"
block:
  for expression in ["1.0 / 1e-512", "1 / 0.0000001"]:
    doAssert errorContains(
      proc() = discard execute("x = " & expression), "division by zero"
    )
  for (expression, expected) in [
    ("32767.0 + 1.0", FixedMinimum),
    ("-32768.0 - 1.0", 32767.0'fx),
    ("16384.0 * 2.0", FixedMinimum),
    ("16384.0 / 0.5", FixedMinimum)
  ]:
    let parts = expression.splitWhitespace
    for source in [
      "x = " & expression,
      "left = " & parts[0] & "\nx = left " & parts[1 .. ^1].join(" ")
    ]:
      when defined(fixedChecks):
        doAssert errorContains(proc() = discard execute(source), "overflow")
      else:
        doAssert execute(source).getGlobalValue("x").asFixed == expected

echo "Testing deterministic state across two thousand restarts"
block:
  var host = initHost()
  discard host.addData("tick")
  let program = compile("""
dim values(3)
value = value * 1.01 + 0.0000152587890625
value = value / 1.125 - 0.03125
values(0) = value
values(1) = value * -0.5
values(2) = value + tick / 128
values(3) = value / 3
print value
""", host)
  var
    runtime = initRuntime(program, host)
    other = initRuntime(program, host)
    hash = 0xcbf29ce484222325'u64
  runtime.setGlobal("value", 0.125'fx)
  other.setGlobal("value", 0.125'fx)
  for tick in 1 .. 2000:
    runtime.restart
    other.restart
    runtime.setData("tick", tick)
    other.setData("tick", tick)
    doAssert runtime.run == other.run
    for i in 0 .. 3:
      let value = runtime.getArrayValue("values", int32(i))
      doAssert value == other.getArrayValue("values", int32(i))
      hash = (hash xor uint64(cast[uint32](int32(value.asFixed)))) *
        0x100000001b3'u64
  # Pinned against a separate integer implementation of Q16.16 arithmetic.
  doAssert hash == 0x208814b536cb8f69'u64, toHex(hash)
  doAssert runtime.getGlobalValue("value").asFixed == Fixed(-20020)

echo "Fixed-point tests passed"
