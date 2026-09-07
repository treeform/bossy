<img src="docs/basicBanner.svg" alt="basic, an embeddable BASIC VM for Nim">

![Github Actions](https://github.com/treeform/basic/workflows/Github%20Actions/badge.svg)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/treeform/basic)
![GitHub Repo stars](https://img.shields.io/github/stars/treeform/basic)
![GitHub](https://img.shields.io/github/license/treeform/basic)
![GitHub issues](https://img.shields.io/github/issues/treeform/basic)

# basic - A sandboxed BASIC VM for game modes and bots.

Basic is designed for safely running game modes, bots, and other scripts
downloaded from other people. Embed it in a Nim game and expose only the data
and actions each script is allowed to use. Configurable execution and memory
limits keep script workloads bounded.

Compile a script once and create independent runtimes for players or bots.
The library uses [Fixxy](https://github.com/treeform/fixxy) for deterministic
Q16.16 arithmetic and requires Nim 2.2.10 or newer.

## About

Scripts support int32 and fixed-point arithmetic, arrays, structured control flow,
subroutines, native callbacks, bounded output, and optional strings
represented by integer handles.

The sandbox gives the game control over each script's capabilities and cost:

- Scripts have no built-in file, network, or operating system access. They
  interact with the game through the host data and callbacks you register.
- Instruction and work budgets stop runaway loops with a catchable
  `BasicError`, so the host can handle a failed bot or game mode.
- Runtime storage, arrays, call depth, string storage, and output have
  configurable limits. Array and string access use explicit bounds checks.
- Each runtime owns its numeric state. The host decides which game state
  scripts can observe or change.

This repository is private while the package is reviewed. It has not been
submitted to the Nimble package index.

> **AI disclaimer: This package and its documentation were prepared with AI
> assistance.**

## Install

Clone with an account that has repository access. Run these commands from
your Nimby workspace directory:

```sh
git clone git@github.com:treeform/basic.git
nimby install basic/basic.nimble
```

Installation also requires access to the private `treeform/fixxy` dependency.
The optional benchmarks use `benchy`.

## Quick start

```nim
import basic

block:
  let program = compile("answer = 6 * 7")
  var runtime = initRuntime(program)
  discard runtime.run
  echo runtime.getGlobal("answer") # Prints 42.
```

For BASIC `print` statements, pass a `PrintProc` to `run`. The default discards
output while still charging its limits. [hello.nim](examples/hello.nim) shows
how to write text, numbers, and newline events to the terminal.

## Embed in Nim

Register read-only host data with `addData` and native functions with
`addFunction`. Host functions accept `openArray[int32]`, return `int32`, and
have a declared work cost. Compile against that host, then bind a compatible
host when creating each runtime.

```nim
import basic

proc double(arguments: openArray[int32]): int32 =
  ## Doubles an int32 with wrapping arithmetic.
  arguments[0] *% 2

block:
  var host = initHost()
  discard host.addData("delta", 3)
  discard host.addFunction("double", 1, double, workUnits = 4)
  let program = compile("total = total + double(delta)", host)
  var runtime = initRuntime(program, host)
  discard runtime.run
  doAssert runtime.getGlobal("total") == 6

  runtime.setData("delta", 5)
  runtime.restart
  discard runtime.run
  doAssert runtime.getGlobal("total") == 16
```

`restart` replenishes execution budgets and preserves globals and arrays.
`reset` also clears globals and arrays. Both retain the runtime's current host
data and callback bindings. Changes to a `Host` affect future runtimes. Use
`runtime.setData` to update an existing runtime.

Each runtime has its own numeric state and can share the compiled `Program`.
Callbacks can still share captured Nim state. Create separate callback state
and string pools when runtimes need to be isolated.

## Runtime and memory limits

Pass the same customized `Limits` to `compile` and `initRuntime`. Start with
`defaultLimits()` and adjust source size, bytecode size, array capacity,
globals, syntax depth, call depth, logical runtime memory, instruction count,
work units, or output limits as needed. Invalid scripts and exceeded limits
raise `BasicError`.

The defaults include:

| Resource | Default limit |
| --- | --- |
| Source size | 1 MiB |
| VM instructions per execution budget | 10,000,000 |
| VM work units per execution budget | 10,000,000 |
| Logical runtime memory | 64 MiB |
| Call depth | 64 frames |
| Print output per execution budget | 1 MiB and 100,000 events |
| Optional string pool | 64 KiB and 256 handles |
| Individual string length | 1,024 bytes |

Choose budgets that fit your game's update loop and number of active bots.
`restart` and `reset` replenish the execution and output budgets, allowing
the host to grant a fresh budget for each turn or decision. Work units charge
operations according to their cost, including the declared cost of native
callbacks. These are deterministic operation limits, not a wall-clock timeout.

The VM allocates its numeric runtime storage up front. Its memory limit
accounts for logical storage such as globals, arrays, registers, and call
frames. It excludes compiled programs, compiler allocations, allocator
overhead, and native callback memory. Optional strings have separate
`StringLimits`. Account for these separately when setting a total memory
budget for many scripts.

Native callbacks are trusted Nim code and define the sandbox's capabilities.
Validate their arguments and bound their time, allocations, and side effects.
Their declared work cost does not interrupt a callback while it runs. Only
register operations that downloaded scripts should be allowed to perform.

`run` executes until completion or an error. It does not yield after a budget
is exhausted. On an error, state can contain partial changes. Use `restart`
or `reset` before running again and choose how your application handles any
host effects already performed.

## Strings

Create a `StringPool`, call `host.addStringFunctions(pool)`, compile with that
host, then call `pool.bindProgram(program)` before running. See
[strings.nim](examples/strings.nim) for a complete example.

`strNew("hello")` creates a string handle. A quoted argument itself is a
compile-time literal ID, so functions that expect handles need `strNew`.
Use `pool.putString` to inject host text and `pool.getString` to read a result.
`putString` truncates text to the configured single-string length limit.

Reset the pool between runs as appropriate. Handles are pool indices and are
reused after a reset. Never retain handles across a pool reset, including in
globals or arrays preserved by `restart`. Reinitialize those values before
reading them. String operations address bytes, and case conversion is ASCII.

## Documentation

- [BASIC language reference](docs/language.md).
- [Host callbacks and persistent execution](examples/hosts.nim).
- [Fixed-point values and numeric callbacks](examples/fixed.nim).
- [String pool example](examples/strings.nim).

Build the API reference locally:

```sh
nim doc --index:on --project --out:.gh-pages src/basic.nim
```

Open `.gh-pages/basic.html`. The Docs workflow also saves the generated API
reference as a workflow artifact. Publishing with GitHub Pages is skipped
while the repository is private.

## Development

From the repository root:

```sh
nim check src/basic.nim
nim r tests/tests.nim
nim r -d:release tests/tests.nim
nim r -d:fixedChecks tests/tests.nim
nim r examples/hello.nim
nim r examples/hosts.nim
nim r examples/strings.nim
```

The tests cover language behavior, host bindings, independent runtimes,
resource limits, malformed source, and string operations. CI runs on Linux,
macOS, and Windows with Nim's default memory manager and thread settings.

Install the optional benchmark dependency from the workspace parent:

```sh
nimby install benchy
```

Then run from the repository root:

```sh
nim r -d:release tests/bench_basic.nim
```
