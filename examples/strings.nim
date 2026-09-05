import basic

block:
  var host = initHost()
  let pool = initStringPool()
  host.addStringFunctions(pool)
  discard host.addData("incoming")
  let program = compile("""
amount = strVal(strWord(incoming, 1))
reply = strCatInt(strNew("Received "), amount)
""", host)
  pool.bindProgram(program)
  var runtime = initRuntime(program, host)
  runtime.setData("incoming", pool.putString("send 42"))
  discard runtime.run
  doAssert pool.getString(runtime.getGlobal("reply")) == "Received 42"
  echo pool.getString(runtime.getGlobal("reply"))

  pool.reset
  runtime.reset
  runtime.setData("incoming", pool.putString("send 7"))
  discard runtime.run
  doAssert pool.getString(runtime.getGlobal("reply")) == "Received 7"
