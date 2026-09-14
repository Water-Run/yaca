# Context read-only manager checkpoint — 2026-09-14

The WSL work through `0d4b2b1` and its uncommitted Context REPL draft were recovered
without changing the remote workspace. N1 now connects `--context-repl recent|full`
to the production terminal loop, including incomplete catalog scans.

The manager displays the requested initial view and supports help, list, search,
inspect, refresh and quit. Listing and search are bounded to 100 displayed rows;
search reports the actual match count and only marks genuinely omitted matches
as truncated. A recent view can use the configured smaller limit.

Inspection uses the index resolver's owned selection and `verify_target` directly:
`resolve` already captures the credential in its private selection table. It does
not reconstruct a snapshot from display rows or resolve a replacement after a
race. Inspection displays reverified metadata only; it never opens XML bodies.
Unavailable matches display metadata with an explicit unavailable result.

Unconnected mutation, export and continuation commands fail explicitly and leave
the loop usable. Cancellation, EOF, scan failures and broken stdout preserve typed
errors and close every opened terminal. Missing configuration does not prevent
read-only catalog management.

Validation on modern Linux, serialized through the resource guard:

- Targeted bootstrap and REPL surface suites: 42/42 cases.
- Full isolated Lua suite: 489/489 cases.
- Design contracts: 7612 assertions with xmllint available.
- Proof evidence: 56 assertions; coding readiness: 553 assertions.
- TP-003, TP-006, TP-008, TP-010 and RP-001: PASS.

Next checkpoint: N2 rename, auto-rename metadata and permanent delete, using real
ModelView publication and the existing target/writer transaction contracts.
Cross-workspace rebind, import and repair remain N3. Online Stage 2/3 production
adapters and target qualification remain open. Gate A/B pass; Release Gate R is
closed. This checkpoint does not qualify XP, Win7 or CentOS 7 release archives.
