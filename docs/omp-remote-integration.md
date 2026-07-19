# Oh My Pi remote integration research

Date: 2026-07-18

## Finding

`dnakov/litter` has no OMP-specific issue, pull request, or code path at the time of this review. Its Pi support is keyed to the `pi` agent and launches a Pi-compatible RPC child. GitHub Discussions are disabled for the repository, so there is no discussion queue to inspect.

Sources:

- Litter repository: <https://github.com/dnakov/litter>
- Litter issue search for `omp`: <https://api.github.com/search/issues?q=repo%3Adnakov%2Flitter+omp>
- Litter issue search for `oh-my-pi`: <https://api.github.com/search/issues?q=repo%3Adnakov%2Flitter+%22oh-my-pi%22>
- Discussions endpoint: GitHub returns HTTP 410 (`Discussions are disabled for this repo`).

## Existing Litter/Alleycat transport

The shipped `kittylitter` crate is a three-line wrapper around the external `dnakov/alleycat` daemon. The daemon advertises a compile-time agent manifest and dispatches each agent to a bridge implementation.

Current Pi path:

1. Alleycat registers `AgentKind::Pi` and advertises manifest name `pi` / wire `jsonl`.
2. The Pi bridge launches `<configured-bin> --mode rpc` with a process launcher that preserves the user's environment.
3. It sends newline-delimited JSON commands, correlates response IDs, and translates Pi agent/session events into the Codex-compatible wire used by Litter clients.
4. Litter's iOS/Android clients already consume dynamic agent metadata; their pre-pair chooser lists are static presentation-only seeds.

Relevant upstream implementation sources:

- <https://github.com/dnakov/alleycat/blob/main/crates/alleycat/src/agents.rs>
- <https://github.com/dnakov/alleycat/blob/main/crates/alleycat/src/agent_manifest.rs>
- <https://github.com/dnakov/alleycat/blob/main/crates/pi-bridge/src/pool/process.rs>
- <https://github.com/dnakov/alleycat/blob/main/crates/pi-bridge/src/pool/pi_protocol.rs>
- <https://github.com/dnakov/alleycat/blob/main/crates/pi-bridge/src/translate/events.rs>
- Litter wrapper: `services/kittylitter/Cargo.toml`

## Pi versus OMP RPC

Original Pi documents RPC mode as `pi --mode rpc`; OMP retains that mode and explicitly describes it as a Pi-derived NDJSON protocol:

- Original Pi RPC reference: <https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md>
- OMP RPC reference: <https://github.com/can1357/oh-my-pi/blob/main/docs/rpc.md>
- OMP RPC types: <https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/modes/rpc/rpc-types.ts>
- OMP RPC runtime: <https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/modes/rpc/rpc-mode.ts>

The overlap is substantial: `prompt`, `steer`, `follow_up`, `abort`, `new_session`, model/thinking commands, session events, tool events, and extension UI frames retain the Pi shape. OMP is not wire-identical, though. It adds or renames commands and frames including `abort_and_prompt`, `get_available_commands`, `branch`, `get_branch_messages`, `handoff`, todo/host-tool/host-URI commands, `interrupt_mode`, `subagent_*`, `available_commands_update`, `prompt_result`, `session_info_update`, and `config_update`. A Pi-only deserializer will warn/drop those frames and cannot provide complete OMP behavior without an OMP-specific protocol adapter.

## OMP's own remote surfaces

OMP exposes two supported process transports:

- `omp --mode rpc`: Pi-shaped agent RPC over stdin/stdout. Best for a dedicated OMP RPC bridge, but it requires a second protocol implementation or a versioned capability-aware adapter in Alleycat.
- `omp acp`: Agent Client Protocol (ACP) over JSON-RPC stdio. OMP's ACP implementation advertises session load/list/resume/fork/close, model and thinking config options, prompts, cancellation, mode changes, file/tool operations, and streamed session updates.

OMP's `session/close` is not a delete operation: a closed session remains in `session/list` because its JSONL history is still persisted. The OMP Alleycat integration therefore maps `thread/archive` to OMP's built-in `/session delete` command, loading the session first when necessary and then closing the ACP record. A fresh `thread/list` no longer returns the deleted session. This is intentionally OMP-specific; generic ACP agents still return `METHOD_NOT_FOUND`, and OMP deletion is permanent, so `thread/unarchive` remains unsupported.

OMP's live `/collab` feature is different: it shares an already-running interactive session through an encrypted relay and browser/terminal guests. It is peer session sharing, not a host-owned child-process transport. It cannot replace kittylitter's process bridge because kittylitter needs to launch, own, resume, and multiplex independent agent sessions on the host.

Sources:

- OMP README entry points and ACP: <https://github.com/can1357/oh-my-pi/blob/main/README.md#four-entry-points-interactive-one-shot-rpc-and-acp>
- OMP ACP mode: <https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/modes/acp/acp-mode.ts>
- OMP ACP agent: <https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/modes/acp/acp-agent.ts>
- OMP collaboration overview: <https://github.com/can1357/oh-my-pi/blob/main/docs/collab.md>

## Chosen implementation

Use OMP's native ACP entry point (`omp acp`) behind Alleycat's existing generic `AcpBridge`, rather than pretending OMP is Pi or silently dropping OMP RPC frames. The generic ACP bridge already supports the process argument vector (`agent_bin` plus `agent_args`), ACP session lifecycle, Codex-compatible translation, and the same local/SSH launcher abstraction used by other Alleycat agents.

The implementation therefore adds a first-class `omp` manifest/config/agent kind to the Alleycat dependency, builds `AcpBridge::builder().agent_bin(omp).agent_args(["acp"])`, and points this Litter fork's kittylitter dependency at the corresponding Alleycat fork. Litter client seed lists will include `omp` so the pre-pair UI reflects the new runtime; connected metadata remains authoritative.

Known ACP tradeoffs are protocol-level rather than OMP-specific: the existing adapter does not expose Codex-only token/rate-limit/reasoning notifications where ACP has no equivalent. OMP's ACP `initialize` and session methods provide the required remote lifecycle and model/thinking configuration path.

## Proposed upstream PR split

No PRs are opened by this work. Litter's contribution rules require an issue
first, one concern per PR, and no dependency PR bundled with feature work. Use
this sequence:

1. **Litter issue prerequisite** — open a focused Litter issue for OMP
   remote-agent integration and obtain maintainer direction before opening
   either Litter PR. An Alleycat issue or upstream discussion is recommended
   for the bridge change, but no inspected Alleycat policy makes it a hard
   prerequisite.
2. **Alleycat OMP ACP lifecycle PR** — upstream the OMP manifest/config/bridge,
   the session-delete prompt strategy, the paginated post-prompt absence check,
   and deterministic success/failure tests. This must merge before any Litter
   dependency change.
3. **Litter dependency-only PR** — after the Alleycat PR merges, start from
   current `dnakov/litter` `main` and refresh only
   `services/kittylitter/Cargo.lock` to the merged `dnakov/alleycat` `main`
   commit. Upstream `Cargo.toml`, updater, and wrapper README already target
   `dnakov/alleycat` `main`; do not change them or include OMP feature edits.
4. **Litter OMP integration PR** — after the dependency-only PR merges, add
   the iOS/Android `omp` presentation seeds and update the KittyLitter package
   description to list OMP. Do not modify the dependency stanza, lockfile,
   dependency updater, or release README in this PR; link the required Litter
   issue.
   The PR body must include a `Screenshots` section with separate iOS and
   Android `Works with` chooser captures; leave both checklist items pending
   until the captures are actually taken.

Merge gates:

- `cargo test -p alleycat-acp-bridge --test omp_session_lifecycle`
- `BRIDGE_CONFORMANCE_SKIP_UPSTREAM_SCHEMA=1 cargo test --workspace --exclude alleycat-opencode-bridge`
- A live `omp` probe must return `{}` for `thread/archive`, emit
  `thread/archived` only after the absence check, and return an empty
  `thread/list` after reconnect.

Current baseline: the local fork's combined OMP commit pins a personal
Alleycat branch and the live rebuilt-local-Alleycat gate passes. Actual
`dnakov/litter` `main` still targets `dnakov/alleycat` `main`; its KittyLitter
gate becomes valid only after the dependency-only lockfile refresh merges.

Archive invariant: `thread/archived` and bridge-state cleanup are allowed only
after the post-prompt paginated `session/list` no longer contains the target.
A consumed no-op delete that leaves the session listed returns an RPC error and
emits no archive notification.

## Current PR readiness

Snapshot: 2026-07-19.

The GitHub Litter fork's `main` carries the published OMP wiring and
validation record. Its KittyLitter lockfile pins `johannhipp/alleycat`
`f06cfe7201948e4a812585f54af9bb8b5b242a15`. It is not the upstream PR base.
The actual upstream `dnakov/litter` files retain the `dnakov/alleycat` `main`
dependency, updater, and wrapper README; use that baseline when preparing the
two Litter PRs.
The OMP bridge, session-delete implementation, and their tests are committed
on the personal Alleycat fork, but are not merged upstream.

Explicit blockers before upstream PRs:

1. Litter's `CONTRIBUTING.md` requires an issue before non-trivial work. No
   focused Litter OMP issue exists yet; the current upstream issue search has
   no OMP or `oh-my-pi` candidate. An Alleycat issue or discussion remains
   recommended, not a blocker imposed by an inspected Alleycat policy.
2. Alleycat's OMP support and session-delete strategy are not merged upstream.
   The Litter dependency-only PR cannot start until that change is merged,
   because its only change is the resulting `Cargo.lock` refresh.
3. The local fork's combined commit must not be submitted as-is. Rebase the
   Litter work on upstream `dnakov/litter` `main` and carry the dependency
   lockfile hunk separately from the OMP presentation hunk.
4. Litter's rule against depending on unmerged PRs means the integration PR
   must wait until the dependency-only PR has merged; no parallel Litter PRs.

Readiness sequence:

1. Open the required focused Litter issue and obtain maintainer direction.
   Separately open or join an Alleycat upstream discussion if maintainers want
   that context tracked there.
2. Merge the Alleycat OMP ACP lifecycle PR.
3. Submit and merge the Litter dependency-only PR from upstream `main`: update
   only `services/kittylitter/Cargo.lock` to the merged Alleycat `main` commit.
4. After that PR merges, submit the Litter OMP integration PR: add the
   iOS/Android `omp` presentation seeds and package description metadata, with
   no dependency, lockfile, updater, or release-README changes.
5. Run the focused ACP test, workspace gate, live approved-Alleycat probe,
   KittyLitter probe, and mobile build lanes before final submission.

## Local mobile E2E validation

Date: 2026-07-19

The local-only transport gate was exercised against a local `iroh-relay`
instance on `127.0.0.1:3340`. The rebuilt Alleycat daemon used
`ALLEYCAT_RELAY_URL=http://127.0.0.1:3340/` and an isolated
`HOME=/tmp/kitty-omp-local-home`; no public relay or real remote host was
dialed.

Host and protocol checks passed:

- `alleycat pair` returned a node id, token, and the local relay URL.
- `alleycat probe --linger-secs 1` connected over the local relay and listed
  `omp` with `wire=jsonl` and `available=true`.
- The rebuilt ACP bridge returned
  `{"exitCode":0,"stdout":"probe-ok","stderr":""}` for a buffered
  `command/exec` request running `/usr/bin/printf`.
- `cargo check -p alleycat-acp-bridge` passed.
- `cargo test -p alleycat-acp-bridge command_exec_tests` passed.
- `cargo test -p alleycat-acp-bridge --test omp_session_lifecycle` passed
  (5 tests), including the failed-turn cleanup regression.
- `BRIDGE_CONFORMANCE_SKIP_UPSTREAM_SCHEMA=1 cargo test --workspace
  --exclude alleycat-opencode-bridge` passed (569 tests).

The ACP bridge now implements buffered Codex `command/exec` through its
configured `ProcessLauncher`. It preserves exit code/stdout/stderr, applies
the Codex output cap and timeout defaults, and returns explicit
`METHOD_NOT_FOUND` errors for PTY, stdin-streaming, and stdout/stderr-streaming
requests. The mobile directory picker uses this buffered path.

The local no-model failure path was also smoke-tested through `alleycat
probe`: it returned the expected JSON-RPC error after emitting
`turn/completed` with `status: "failed"` and a final
`thread/status/changed` with `status.type: "idle"`.

Android validation passed on the `litter-api35` Android 15 arm64 emulator
(`emulator-5554`):

- `./gradlew :app:assembleDebug` completed successfully.
- The rebuilt APK installed and launched.
- The Android Add Server sheet rendered the `Pair with kittylitter` card with
  the OMP presentation icon. Capture:
  `artifacts/android-local-run/works-with-chooser.png`.
- The OMP model chooser listed `Omp Omp`, and the remote project picker loaded
  `/tmp/kitty-omp-local-home` plus its `Library` directory through
  `command/exec`. Captures:
  `artifacts/android-local-run/directory-picker-rebuilt.png` and
  `artifacts/android-local-run/project-selected.png`.
- Submitting a prompt created an OMP session, but the isolated host correctly
  rejected execution because no model or API key was configured. The captured
  UI error is in `artifacts/android-local-run/omp-prompt-result-rebuilt.png`;
  the host log reports: `No model selected. Use /login, set an API key
  environment variable, or create .../.omp/agent/agent.db`.

The required iOS validation could not run on this workstation. `xcodebuild`
reported that the active developer directory is Command Line Tools, and
`xcrun simctl` was unavailable. No iOS app artifact or `Works with` capture
was fabricated; the iOS screenshot checklist remains blocked on a full Xcode
installation.
