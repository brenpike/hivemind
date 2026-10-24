# Agent-invocable remote control via description scoping

**Status:** accepted — 2026-06-21

## Context

A new user-facing capability lets the user enable Claude "remote control" (RC) over a brood's strains by saying, in natural language, e.g. "enable RC for all strains". On that explicit request, the overlord/hatchery delivers a `/rc <strain-name>` slash command into each strain's live session so the user can drive those sessions remotely.

This must coexist with the ADR-0007 boundary: the hatchery is a read-only status dashboard, not an autonomous controller of its children. The capability cannot be allowed to become an autonomous step the hatchery takes on its own during normal coordination — but it MUST be runnable the moment the user asks for it in chat.

Two facts constrain the delivery mechanism. Claude Code has NO in-band API for one session to drive a running peer session, and an agent CANNOT emit a slash command in its own turn output to control itself (open upstream request anthropics/claude-code#34243). So the only way to deliver `/rc <strain-name>` into each strain's live session is external `tmux send-keys` — the same keystroke-injection mechanism `spawn-brood` already uses to drive children.

## Decision

Ship the capability as a NORMAL **agent-invocable** skill (`hivemind:enable-brood-remote`). The overlord/hatchery invokes it on the user's explicit natural-language request.

The ADR-0007 read-only-coordinator boundary is preserved NOT by blocking model invocation, but by SCOPING the skill's `description` so it triggers ONLY on an explicit user request to enable remote control — never as an autonomous step of normal coordination.

Delivery is external `tmux send-keys` of `/rc <strain-name>` into each target strain's live pane, reusing the spawn-brood keystroke-injection mechanism.

## Considered Options

| Option | Rejected because |
|---|---|
| `disable-model-invocation: true` (the user-only pattern the architecture zoom-out skill uses) | Would make the overlord unable to invoke the skill at all, defeating the requirement that the user can say "enable RC for all strains" and have it run. The boundary is the skill's TRIGGER scope, not its invocability |
| In-band / self-emitted slash command to drive each strain | No such API exists. An agent cannot emit a slash command in its own turn output to drive itself or a peer (upstream anthropics/claude-code#34243); external keystroke injection is the only available delivery path |

## Consequences

- The hatchery gains an agent-invocable action, but it fires only on the user's explicit RC request — the description scope keeps it out of the normal coordination path.
- Issuing the keystrokes on the user's explicit request is human-initiated addressing — equivalent to the user attaching to a pane and typing the slash command themselves. It does not make the coordinator an autonomous controller; the ADR-0007 boundary holds.
- Delivery reuses the existing spawn-brood `tmux send-keys` mechanism, adding no new control-plane primitive.

References: ADR-0007; `plugin/skills/enable-brood-remote/`; upstream anthropics/claude-code#34243.

## Amendment 2026-10-24

Slice 4 of https://github.com/brenpike/hivemind/issues/409 launches brood children in auto mode, and the user owns monitoring the brood (ADR-0037, Amendment 2026-10-24: brood children on the script engine (slice 4); ADR-0017, Amendment 2026-10-24).

- **spawn-brood turns remote control on by default.** After the manifest is written, spawn-brood sends `/rc <short>` to each strain that showed started-evidence and was alive when spawn ended, through `rc-brood.sh --only`, so it reuses the same pane-id delivery and adds no new control-plane primitive. A strain still starting when spawn ends gets none until the user asks for enable-brood-remote.
- **It stays human-initiated addressing.** The spawn itself is user-approved, and remote control on by default is the user's standing choice, made on 2026-10-24. Sending it at spawn is the same keystroke the user would type on attaching, so the coordinator does not become an autonomous controller, and ADR-0007 holds.
- **The skill stays explicit-request-only for later use.** `hivemind:enable-brood-remote` still fires only on the user's explicit request, for example to reach strains that started after spawn ended. Its description scope is unchanged.

Text: `plugin/skills/spawn-brood/scripts/spawn-brood.sh`, `plugin/skills/enable-brood-remote/scripts/rc-brood.sh` (`--only`).
