import bassy

var
  host = initHost()
  runtime: Runtime

proc acknowledge(arguments: openArray[Value]): Value =
  ## Reads a script message and creates a reply in the same bounded store.
  let message = runtime.getString(arguments[0])
  runtime.putString("Received: " & message)

proc log(event: PrintEvent) =
  ## Writes the string example's output events.
  case event.kind
  of TextPrint, FixedPrint:
    stdout.write event.text
  of ValuePrint:
    stdout.write event.value
  of NewlinePrint:
    stdout.write "\n"

discard host.addData("player$", "Ada")
discard host.addFunction("acknowledge$", 1, acknowledge, 1024)

let program = compile("""
name$ = TRIM$(player$)
dim modes$(2)
modes$(0) = "defend"
modes$(1) = "attack"
modes$(2) = "explore"

sub greet(who$)
  print "Hello, " + who$ + "!"
end sub

greet(name$)
message$ = name$ + ": " + UCASE$(modes$(0))
reply$ = acknowledge$(message$)
print reply$
""", host)

runtime = initRuntime(program, host)
discard runtime.run(log)
doAssert runtime.getStringGlobal("reply$") == "Received: Ada: DEFEND"
