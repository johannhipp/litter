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
