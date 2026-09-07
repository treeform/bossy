import bossy

proc advance(arguments: openArray[Value]): Value =
  ## Moves a coordinate using speed and elapsed time from the host.
  arguments[0] + arguments[1] * arguments[2]

block:
  var host = initHost()
  discard host.addData("delta", 0.25'fx)
  discard host.addFunction("advance", 3, advance, workUnits = 4)
  let program = compile("""
x = advance(x, 1.5, delta)
""", host)
  var runtime = initRuntime(program, host)
  discard runtime.run
  doAssert runtime.getGlobalValue("x").asFixed == 0.375'fx
  echo "Coordinate: ", runtime.getGlobalValue("x")
  runtime.restart
  discard runtime.run
  doAssert runtime.getGlobalValue("x").asFixed == 0.75'fx

block:
  var limits = defaultLimits()
  limits.disableFixed = true
  let program = compile("coordinate = 3 / 2", limits)
  var runtime = initRuntime(program, limits)
  discard runtime.run
  doAssert runtime.getGlobal("coordinate") == 1
  echo "Integer coordinate: ", runtime.getGlobal("coordinate")
