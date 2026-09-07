import bossy

proc print(event: PrintEvent) =
  ## Writes BASIC output events to the terminal.
  case event.kind
  of TextPrint, FixedPrint:
    stdout.write event.text
  of ValuePrint:
    stdout.write event.value
  of NewlinePrint:
    stdout.write '\n'

block:
  let program = compile("""
dim squares(4)
i = 0
while i <= 4
  squares(i) = i * i
  i = i + 1
wend
print "The square of 4 is", squares(4)
""")
  var runtime = initRuntime(program)
  discard runtime.run(print)
  doAssert runtime.getArray("squares", 4) == 16
