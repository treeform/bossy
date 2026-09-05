import basic

proc double(arguments: openArray[int32]): int32 =
  ## Doubles an int32 using the same wrapping arithmetic as BASIC.
  arguments[0] *% 2

block:
  var host = initHost()
  discard host.addData("delta", 3)
  discard host.addFunction("double", 1, double, workUnits = 4)
  let program = compile("""
total = total + double(delta)
""", host)
  var
    runtime = initRuntime(program, host)
    other = initRuntime(program, host)
  discard runtime.run
  doAssert runtime.getGlobal("total") == 6

  runtime.setData("delta", 5)
  runtime.restart
  discard runtime.run
  doAssert runtime.getGlobal("total") == 16

  discard other.run
  doAssert other.getGlobal("total") == 6
  echo "Persistent total: ", runtime.getGlobal("total")

  runtime.reset
  discard runtime.run
  doAssert runtime.getGlobal("total") == 10
