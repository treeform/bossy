# Extraction notes

The initial interpreter is copied without changes from
`Metta-AI/polyworld`, commit
`ee61b5c7adfe7d5590326509b9540f877f5bb2cc`.

| Polyworld source | Standalone destination |
| --- | --- |
| `src/polyworld/basic.nim` | `src/basic.nim` |
| `tests/test_basic.nim` | `tests/tests.nim` |
| `tests/bench_basic.nim` | `tests/bench_basic.nim` |

The source module's Git blob is
`3ee856596ec2b7ad6b9afdd782a35ddffa0205d3`.
At the initial extraction commit, `d0b3f19`, the copied tests and benchmarks
only changed `import polyworld/basic` to `import basic`. Package metadata,
workflows, examples, and documentation were new. Subsequent commits extend
the standalone language and tests. The package keeps the minimum Nim version of
2.2.10.

The project was subsequently renamed from `basic` to `bossy`. The current
entry module is `src/bossy.nim`, support modules live in `src/bossy/`, and the
benchmark is `tests/bench_bossy.nim`. Host applications now use `import bossy`.
The paths in the extraction table above record the original destinations.

Polyworld retains its interpreter, tests, benchmarks, and imports. Adoption
of this package in Polyworld and submission to the Nimble package index are
separate future steps after review. This initial extraction does not claim
compatibility with a full historical BASIC dialect.

The string pool uses integer indices as handles. Some inherited source
comments say stale handles fail after a reset. That holds only while the old
index is out of range. A subsequent allocation can reuse the index. Hosts
must discard or replace all handles across pool resets, as described in the
README. The extraction preserves this existing behavior.
