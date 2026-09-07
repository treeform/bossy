# Determinism tests

`tests/test_determinism.nim` runs from `tests/tests.nim` and pins two digests:

- A 256-tick replay covering numeric globals, arrays, SUB and GOSUB execution,
  branches, host callback arguments and order, string values, print events,
  and instruction, work, and output accounting.
- 128 arithmetic expressions whose compile-time and runtime results must
  agree in both value kind and raw Q16.16 bits.

The replay must also match after dirtying and resetting a runtime, recompiling
the program, and interleaving unrelated runtimes. Its transcript records
observable values and output rather than pointers, object padding, or
temporary string storage identities. Inputs and callbacks are deterministic.
The existing 2,000-step numeric replay in `tests/test_fixed.nim` still runs.

Expected digests are fixed regression values. The folding digest was checked
against a separate integer reference. Do not automatically regenerate a
digest on failure. Review arithmetic, compiler, output, and metering changes
before intentionally updating the replay expectation.

Run `nim r tests/tests.nim` or `nim cpp -r -d:release tests/tests.nim`.
CI checks the same values on Linux, macOS, and Windows using C debug, release,
danger, and fixedChecks builds, plus C++ release builds.
