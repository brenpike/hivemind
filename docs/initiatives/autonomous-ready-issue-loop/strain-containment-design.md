# Solution design: Lair strain containment

This is the solution design for issue #646, the strain containment part of the Lair, epic #603. It was split from #633 by the user's answer of 2026-11-22 (review record, Decisions asked, "Round 3 questions", Q1). It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the parent [solution design](solution-design.md) rather than restating them, and cites ADR-0045 as "ADR-0045 decision N". The design review is recorded in the [strain containment review record](strain-containment-review-record.md).

It designs the mechanism of the parent design's Seams between the part designs, item 6, which states the requirement and points here. Its inputs are:

- the user's answer 1A of 2026-11-22 at #633's integration review round 1 ([review record](review-record.md), Decisions asked, "Round 1 questions", Q1): #604 builds per-platform containment of `control/` and of the Lair's tmux servers, #608's preflight probe `sandbox` stops the Lair when containment cannot be confirmed, and the merge lane's cache sits under `control/`;
- the ADR-0045 amendment of 2026-11-22, "the Lair's strains can read its key where no sandbox hides its processes" (process reach), with the ADR-0045 amendment of 2026-11-21, "sessions running as the user can forge Lair markers";
- the inherited findings of #633's integration review, mapped under Inherited findings.

For its scope it extends or overrides these parts of the three frozen part designs. Each override lands through the dated solution-design entry under Changes to shared documents.

- [Strain launch](strain-launch-design.md):
  - Contracts and seams, "Strain environment": two names are no longer passed, and some values become Lair-set literals (Contracts and seams, "Environment literals");
  - Components "Strain launch and settings": the launch command is wrapped by the platform launcher, and "Environment preflight" runs inside the sandbox, in two probe sessions, with the probe `sandbox` and a case id in its stop cause;
  - Components "Start points": in Lair mode, `push-branch.sh` records no upstream and `create-working-branch.sh` changes none;
  - Contracts and seams, "Strain settings": the fragment sets `sandbox.enabled` to false;
  - State and ownership: the spawn record gains the admin folder name, and the preflight folder holds no result file;
  - Trust boundaries, "Strain containment": its statement that a strain can read any file the user can holds outside what this design hides; "Named residual: the tmux global environment" narrows to a strain that escapes containment;
  - Lifecycle steps 2 and 5: spawn runs inside the sandbox, and clean-up also removes the per-strain folders, by recorded paths only.
- [Claim integrity](claim-integrity-design.md):
  - Components "Lair state root": the state root gains `sandbox/` and `relay.sock`, and `control/` gains `lair.sock`, `probe.sock` and the probe's scratch files;
  - Lifecycle, Start step 3: the socket path check covers the new sockets;
  - Contracts and seams, "Assumptions about #630": Containment of the key and the halt file, Process reach, Tmux reach and Result file per strain are met on Linux by this design, and on macOS as Trust boundaries states.
- [Merge lane](merge-lane-design.md):
  - Contracts and seams, "Assumptions about #630", "A strain writes nothing outside its worktree and the shared object and ref store": met on Linux, and on macOS as Trust boundaries states;
  - Trust boundaries, "Residual: a strain that writes the tick's inputs": it narrows to a strain that escapes containment.

Every other part of the three part designs stands.

## Context and code truth

The design builds on this code, as it stands on trunk.

- `plugin/skills/spawn-brood/scripts/spawn-brood.sh`:
  - requires `tmux` (line 221) and anchors on the caller's `git rev-parse --show-toplevel` (line 406);
  - puts each worktree at `<top>/.claude/worktrees/<brood-id>/<short>` (line 464) and the brood state at `<top>/.hivemind/broods/<brood-id>/` (line 578), with `strain-settings.json` there (line 614);
  - creates the worktree with `git worktree add --detach "$wt" "$base_commit"` (line 719). So the strain's git admin folder is `<common>/worktrees/<name>/` inside the main checkout's git common directory, and its objects and refs are the common directory's;
  - builds the launch command from fixed literals, `claude --permission-mode auto`, plus `--settings` with a relative path when settings were written (lines 641 and 649);
  - starts the session with `tmux new-session -d -s "$tmux_session" -c "$wt" "$strain_launch_cmd"` (lines 912 to 913). It passes no `-L` or `-S`, so every strain runs on the user's default tmux server. Strain launch cites lines 933 to 934 for this call; the call has since moved;
  - waits for `hivemind:overlord` in the pane as its ready text (`READY_SUBSTRING`, line 210, polled at line 1163).
- Strain launch's Contract "Strain environment" starts each strain from `env -i` plus a fixed list of names. The list passes `TMPDIR`, `XDG_RUNTIME_DIR`, `SSH_AUTH_SOCK`, `DBUS_SESSION_BUS_ADDRESS` ("the keyring `gh` and git credential helpers use"), `GH_TOKEN`, `GITHUB_TOKEN`, `GH_CONFIG_DIR`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`, the proxy names, `OPENAI_API_KEY` and `CODEX_HOME`, each only when set in the tmux server's environment. Its environment preflight runs `gh_auth`, `git_remote` and `local_review` in one throwaway tmux session on the strains' server, with a clean start, a run nonce and a 900-second deadline, and writes its result file to `.hivemind/lair/preflight/` in the Lair's checkout.
- Claim integrity's state root is `<home>/.local/state/hivemind/lair/<repo-key>/`, outside every checkout. Its `control/` folder, mode 0700, holds `lock`, `marker.key`, `marker.key.new`, the halt file `halt`, `write-check`, `scan.sock` (the scanner's private tmux server) and `cache/`. Seams item 6 of the parent design puts the merge lane's cache under `control/`, and its item 14 adds `control/digest/` (#611). Start step 3 refuses a state root whose `control/scan.sock` path is over 103 bytes, "the shorter socket-path limit of the two platforms" (claim-integrity-design.md line 282).
- The merge lane assumes "a strain writes nothing outside its worktree and the shared object and ref store" (merge-lane-design.md line 338). Where that fails, its residual "a strain that writes the tick's inputs" (line 378) names the user settings files, its cache, another run's result file, the `PATH` directories, the plugin's script directory, `gh`'s config folder and `$HOME/.jq`. Its own git reads use a bare repository the Lair owns, with `gc.auto=0`, `maintenance.auto=false` and replace objects off (line 285).
- `plugin/skills/push-branch/scripts/push-branch.sh` records `branch.<b>.remote` and `branch.<b>.merge` with `git config` after a successful push in origin or explicit mode (lines 457 to 459). A failed write is the blocker `pushed, but the upstream could not be recorded` (line 281). That config is the common directory's `config`, shared by every worktree.
- `plugin/skills/create-working-branch/scripts/create-working-branch.sh` creates a new branch with `git switch --no-track -c` (line 109), which writes no config. Its upstream rule unsets a malformed upstream of an existing branch with `git config --unset-all` (header lines 111 to 114, call at line 286).
- No sandbox code exists on trunk. Nothing under `plugin/` or `tools/` names `bwrap`, `bubblewrap`, `sandbox-exec` or Landlock.

Platform facts this design relies on:

- Claude Code's own `sandbox` setting covers shell commands only. Its file tools, MCP servers and hooks run outside it, with the user's full access ([Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing)). So a strain needs an outer wrapper around its whole command, not that setting. The same page says the Linux and WSL2 sandbox relies on bubblewrap and `socat`, that WSL1 and native Windows are not sandboxed, and that tools which ignore proxy variables cannot connect through its proxy.
- Bubblewrap makes user, PID, IPC, UTS and network namespaces, mounts a fresh `/proc`, a new `/dev`, tmpfs folders and read-only or writable binds, kills the sandbox when its parent dies (`--die-with-parent`), loads a compiled cBPF seccomp program (`--seccomp FD`), and can block the sandbox until a file descriptor has data (`--block-fd`) and report the child's process id (`--info-fd`) ([bwrap(1)](https://manpages.debian.org/testing/bubblewrap/bwrap.1)). A new network namespace holds only a loopback device. Its man page recommends `--new-session`, or a seccomp rule against the `TIOCSTI` ioctl, so a sandbox cannot push input into its terminal.
- A network namespace isolates the abstract Unix socket namespace ([network_namespaces(7)](https://man7.org/linux/man-pages/man7/network_namespaces.7.html)).
- Seccomp cannot see operations requested through io_uring, and `IORING_OP_SOCKET` is io_uring's form of `socket()` ([LWN](https://lwn.net/Articles/1054225/)).
- Unprivileged user namespaces can be blocked. Ubuntu 23.10 added `kernel.apparmor_restrict_unprivileged_userns` and Ubuntu 24.04 turns it on by default; bubblewrap then needs an AppArmor profile ([Ubuntu discourse](https://discourse.ubuntu.com/t/understanding-apparmor-user-namespace-restriction/58007), [Launchpad bug 2046477](https://bugs.launchpad.net/bugs/2046477)).
- Landlock's scope for abstract Unix sockets arrived with Landlock ABI 6, in Linux 6.12 ([kernel Landlock docs](https://www.kernel.org/doc/html/next/userspace-api/landlock.html)). This design does not use Landlock; the fact is context for the choice under Decisions.
- macOS `sandbox-exec` is deprecated, and Apple's developer support calls it unsupported for this use ([Apple forum thread 854443](https://developer.apple.com/forums/thread/854443)). A process that already has a sandbox cannot apply another, and a child inherits its parent's sandbox ([Sandboxing on macOS](https://bdash.net.nz/posts/sandboxing-on-macos/)). So a tool that starts its own `sandbox-exec` inside a strain fails.
- On WSL2, Windows programs run through `binfmt_misc` and WSL's `/init`, which finds an interop server on a Unix socket under `/run/WSL`, named by `WSL_INTEROP` or found by process id ([WSL interop](https://wsl.dev/technical-documentation/interop/), [Microsoft Learn](https://learn.microsoft.com/windows/wsl/interop)).
- tmux keeps its default sockets in a `tmux-<uid>` folder under `TMUX_TMPDIR`, or `/tmp` when it is unset; `-L` names another socket in that folder and `-S` takes a full path ([tmux(1)](https://man7.org/linux/man-pages/man1/tmux.1.html)).
- `gh` stores its token in the system credential store by default: the Keychain on macOS, the Secret Service keyring (GNOME Keyring) on Linux. `--insecure-storage`, or a store that is not available, keeps it in plain text in `hosts.yml` ([gh auth login](https://cli.github.com/manual/gh_auth_login), [GitHub CLI 2.26.0](https://github.com/cli/cli/releases/tag/v2.26.0)).
- An empty `credential.helper` value resets the list of helpers git has read so far ([gitcredentials](https://git-scm.com/docs/gitcredentials)). `GIT_CONFIG_COUNT` with `GIT_CONFIG_KEY_<n>` and `GIT_CONFIG_VALUE_<n>` adds config entries from the environment ([git commit d8d7715](https://googlers.googlesource.com/jrn/git/+/d8d77153eafdb0fc334e827976f09e4bdff26b58)).
- Claude Code honors `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` and their lowercase forms, and does not support SOCKS. A variable set in the launch environment wins over the same key in a settings file's `env` ([Claude Code network configuration](https://code.claude.com/docs/en/network-config)).
- Claude Code keeps credentials in the macOS Keychain, and on Linux in `~/.claude/.credentials.json`, which moves under `CLAUDE_CONFIG_DIR` when that is set. `CLAUDE_CODE_OAUTH_TOKEN`, made by `claude setup-token`, is a long-lived token for scripts ([Claude Code authentication](https://code.claude.com/docs/en/authentication)).

Facts this design could not confirm from a source are live-probe assumptions of #604 (Verification strategy, "Live-probe assumptions"). Each one fails closed.

## Requirement

The Lair keeps every strain and remediation strain to what it may reach. A strain reaches only what this section allows. Anything else is out of reach whether or not this design names it. The invariants say what the strain can reach, one per scope bullet of #646; they are never a list of hidden targets.

- **I1, `control/`.** No strain can read, write or delete anything under the state root's `control/` folder: the marker key, the halt file, the lock, the sockets, the merge lane's cache and the decision digest. On Linux the strain's view holds no state root at all. On macOS the profile denies reads and writes under `control/`.
- **I2, services that run commands.** No strain can reach a tmux server, or any service that runs commands outside its sandbox. On Linux a strain can create no Unix socket at all, so it reaches no path socket, abstract socket or group-openable system socket, `/run/docker.sock` included. Its network namespace holds only loopback, and its one way out is the Lair's proxy, which refuses local addresses. On macOS the profile denies every Unix socket connect but the name service; TCP to local services is in the macOS residual.
- **I3, siblings.** No strain can write another strain's worktree, per-worktree admin folder, per-strain folders, strain record folder, or result, liveness or launch files. This holds for a sibling that starts after it.
- **I4, shared run-or-load config.** No strain can write a shared file that another process later runs or loads as config: the git common directory's `config`, `hooks/` and `info/`, and its `objects/info/`; the main checkout's `.claude/`; `.hivemind/broods/`; the user's Claude Code settings and plugin folder and `~/.claude.json`; the directories on `PATH`; `gh`'s config folder; and `$HOME/.jq`. The rule is the allowlist of I5: a path outside it is read-only, so the list names examples, not the boundary.
- **I5, the write allowlist.** A strain writes only:
  - its own worktree;
  - its own per-worktree admin folder `<common>/worktrees/<name>/`;
  - the shared object store `<common>/objects/`, with `objects/info/` read-only, and the shared ref store `<common>/refs/` and `<common>/logs/`;
  - its per-strain scratch folder and its per-strain Claude Code state folder, both under the state root, outside `control/`.

  On Linux it also writes the private tmpfs folders its sandbox mounts, which no other process sees.
- **I6, keyring and session bus.** No strain reaches the session bus, the Secret Service keyring or an SSH agent on Linux. Its GitHub credentials come by the fallback order of Components "Keyring and session bus". On macOS it reaches the user's Keychain through the Keychain service, as any of the user's sessions does.

No invariant rests on an environment value. The environment literals make the strain's tools work inside the sandbox; the namespaces, mounts, seccomp filter and profile do the containing.

## Components

### Linux launcher

Built by #604. On Linux, WSL2 included, bubblewrap wraps the whole strain command, `env -i ... claude ...`, so `claude`, its hooks, its MCP servers, its tools and every process they start run inside one sandbox.

- **Namespaces.** User, PID, IPC, UTS and network namespaces, each named by its own flag, never a `-try` form that goes on without it. So a namespace bubblewrap cannot make fails the launch.
- **Lifetime.** `--die-with-parent`: the sandbox ends when the pane's process ends. The pane runs bubblewrap as its only process, so no process outside the sandbox reads the pane's terminal.
- **Process view.** A fresh `/proc` for the new PID namespace and a new `/dev`. No Lair process, sibling strain or user process is visible or can be signalled.
- **File view.**
  - The root is bound read-only (`--ro-bind / /`).
  - Fresh tmpfs folders cover `/tmp`, `/var/tmp`, `/run`, `/var/run` where it is not a link to `/run`, `/dev/shm`, `$XDG_RUNTIME_DIR`, `$TMUX_TMPDIR` when set outside those, and, on WSL2, `/mnt/wslg`. These hide other processes' temporary files, shared memory and runtime folders, and give the strain private writable copies.
  - A fresh tmpfs covers the whole state root, so `control/`, `scan/`, the relay socket and every sibling's per-strain folders are absent from the view.
  - Writable binds then add exactly the allowlist of I5, at their real paths.
  - A read-only bind covers `<common>/objects/info/` after the writable bind of `<common>/objects/`. The Lair creates that folder before the launch when it is absent.
- **Seccomp filter.** A compiled cBPF program, loaded with `--seccomp`, that:
  - denies `socket()` with the domain `AF_UNIX`, so the strain can create no Unix socket and reach none, path or abstract; `socketpair()` stays allowed, since it reaches nothing outside the pair;
  - denies `io_uring_setup()`, since io_uring can make a socket that seccomp does not see;
  - denies `ioctl()` with `TIOCSTI` or `TIOCLINUX`, so the strain cannot push input into a terminal;
  - kills a call made through any system call ABI other than the native one, such as i386 or x32 calls on x86_64, so the filter cannot be stepped around;
  - allows every other call.

  A fixed script builds the program for x86_64 and aarch64. On any other architecture it refuses, and the launch fails.
- **Terminal.** The launcher does not use `--new-session`, so the interactive TUI keeps its controlling terminal and resize signals. The filter's `TIOCSTI` rule is bubblewrap's documented alternative.
- **WSL2.** The `/run` tmpfs hides `/run/WSL`, `env -i` drops `WSL_INTEROP`, and the filter denies the Unix socket `/init` needs. So a strain cannot start a Windows program. `/mnt/c` and the other Windows drives stay readable and are read-only.
- **The launch command.** A fixed builder script makes the launcher argv from the spawn record and the Lair's state root (Contracts and seams, "Launcher argv"). The tmux command string holds only fixed literals, the asserted brood id, and paths that are each one double-quoted word behind the charset gate.
- **Mounts the strain cannot undo.** Bubblewrap's mounts are locked against a namespace the strain makes inside its sandbox ([mount_namespaces(7)](https://man7.org/linux/man-pages/man7/mount_namespaces.7.html), "Restrictions on mount namespaces"). So a nested namespace cannot unmount the tmpfs over the state root to reveal `control/`.

### Linux egress

Built by #604. The relay's implementation is #604's choice under these properties.

- The strain's network namespace holds only loopback. A server the strain starts on loopback is its own, and no other process can reach it.
- Its one way out is a forwarder that the Lair attaches to the strain's network namespace from outside, after the sandbox starts and before its command runs: it joins only that namespace, listens on a fixed loopback port inside it, and relays each connection to the Lair's proxy over the Lair's relay socket. The forwarder stays outside the strain's PID and mount namespaces, so the strain cannot signal it or replace its socket. The sandbox command blocks until the forwarder is attached (`--block-fd`, with `--info-fd` for the process id, or an equal mechanism).
- The fixed port is a constant of the launcher. It is always free, because every strain's namespace is new.
- The proxy runs outside every sandbox for the Lair session. It accepts HTTP `CONNECT` and plain HTTP requests, resolves each name itself, and checks the address it will connect to after resolution. It refuses loopback, link-local and unspecified addresses, every address of the host's own interfaces and, on WSL2, the Windows host's address. It does not open TLS. It reaches remote hosts through the user's own proxy settings when they are set.
- The strain's proxy variables are literals that name the forwarder (Contracts and seams, "Environment literals"). The namespace has no name resolver, so names resolve only at the proxy.
- A tool that ignores proxy variables cannot connect anywhere but its own loopback. That is a stated property, not a fault: such a tool fails visibly in the strain.
- There is no host allowlist: a strain reaches any remote host through the proxy. That is the egress residual under Trust boundaries.

### GitHub remotes

Built by #604. The strain has no SSH agent socket, so git reaches GitHub over HTTPS with `gh` as its credential helper.

- `GIT_CONFIG_*` literals rewrite `git@<host>:` and `ssh://git@<host>/` to `https://<host>/` with `url.https://<host>/.insteadOf`. `<host>` is the repository's host, which #608 fixes at Lair start (merge lane, "Merge environment", "The host binding"), lowercased, behind the gate `^[a-z0-9.-]+$`.
- They set `credential.helper` first to an empty value, which drops every helper git read before, then to `!gh auth git-credential`. `gh` resolves through `PATH`, whose directories the strain cannot write (I4).
- A remote on another host, or one that answers only over SSH, fails. The preflight's `git_remote` probe catches it (P26 degradation).

### macOS launcher

Built by #604. macOS has no namespaces, so the strain runs under a Seatbelt profile through `sandbox-exec`.

- **The profile.** A fixed script generates it per strain into the per-strain folder, outside the strain's writable folders. Each path in it is one quoted string behind the charset gate. The profile:
  - allows by default, then denies every file write and allows writes only to the allowlist of I5 and to the device files a terminal program needs, such as `/dev/null` and the pane's terminal;
  - denies every read and write under `<state root>/control/`;
  - denies every Unix socket connect, then allows only the name service socket the system resolver needs;
  - denies sending a signal to, and reading process information of, any process outside the profile, where the profile language has that operation;
  - allows the Keychain lookups `gh` and Claude Code make, through the Keychain service.
- **What it does not claim.** The profile does not stop a strain from asking `launchd`, LaunchServices or Apple Events to run a command outside the profile, and it does not hide the Lair's processes. Such an escape, and process reach, fall under both ADR-0045 amendments: the 2026-11-21 amendment on forged markers ("a Lair-started session that escapes its containment" can sign markers that count) and the 2026-11-22 amendment on process reach (a strain can read the key out of the Lair's processes where no sandbox hides them).
- **No nesting.** A tool inside the strain that starts its own `sandbox-exec` fails. A local review tool that does so fails the preflight's `local_review` probe, which runs inside the sandbox (Components "Probe `sandbox`"). If such a tool still fails inside a strain, `run-review.sh` reports `skipped: tool-failed`, so the pull request is not in the auto tier and goes to `lair:review` (ADR-0045 decision 12).
- **No proxy.** A macOS strain reaches the network directly, with the proxy names passed as strain launch lists them. TCP to a local service is inside the macOS residual.

### Write allowlist

Built by #604. These are the writable binds on Linux and the allowed write paths on macOS.

- **Own worktree**, `<checkout>/.claude/worktrees/<brood-id>/<short>/`.
- **Own admin folder**, `<common>/worktrees/<name>/`, where git keeps the worktree's `HEAD`, index, `FETCH_HEAD`, `ORIG_HEAD` and `logs/HEAD`.
- **The shared object store** `<common>/objects/`, with `<common>/objects/info/` read-only, so no strain can write an `alternates` file, a commit-graph file or another file there that every git process of the checkout loads.
- **The shared ref store** `<common>/refs/` and `<common>/logs/`, or `<common>/reftable/` for a repository on the reftable backend. `<common>/packed-refs` lives in the read-only common directory, so a strain cannot delete a packed ref.
- **The per-strain scratch folder** `<state root>/sandbox/<nonce>/scratch/`, named by `TMPDIR`, with `XDG_CACHE_HOME` at `scratch/cache/`.
- **The per-strain Claude Code state folder** `<state root>/sandbox/<nonce>/claude/`, named by `CLAUDE_CONFIG_DIR`.

`<nonce>` is the strain record's nonce, strain launch's `lair_nonce`. The Lair creates both per-strain folders, mode 0700, before the spawn, and removes them at clean-up. The per-strain folder itself is not writable to the strain.

Three git settings follow from the read-only common directory:

- `gc.auto=0` and `maintenance.auto=false` are environment literals, so no strain starts a gc or maintenance run on the shared store. The merge lane sets the same pair for its own repository.
- `fetch.prune=false` is a literal, so a fetch never tries to delete a packed remote-tracking ref.
- `core.fsmonitor=false` is a literal, so git starts no monitor daemon, which needs a Unix socket.

Clean-up takes every path from the spawn record, never from the strain-writable admin folder: the worktree path, and the admin folder name, which `spawn-brood.sh` reads with `git rev-parse --git-dir` in the new worktree right after `git worktree add`, before the session starts. A strain can rewrite its admin folder's `gitdir` file, so the Lair never reads it to find what to remove. The Lair checks with `lstat` that each path is a directory, not a link, removes it, then runs `git worktree prune`.

### Claude Code state and auth

Built by #604.

- `CLAUDE_CONFIG_DIR` names the per-strain Claude Code state folder. Before the spawn the Lair fills it with:
  - read-only views of the user's Claude Code settings file, memory file, `plugins/`, and user-level agents, commands and skills: read-only binds on Linux; links on macOS, whose targets the profile keeps read-only;
  - a copy of the user's `~/.claude.json`, so the strain starts with the user's onboarding and trust state and writes only its copy.
- No strain writes the user's Claude Code settings, plugin folder, `~/.claude.json` or credential store.
- **Auth needs no write to the user's store.** An OAuth refresh made from a copied refresh token rotates the user's own token away, whether or not the copy is written back. So on Linux a strain authenticates only with `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` from the tmux server's environment. The Lair never copies or binds `~/.claude/.credentials.json`.
- On macOS the strain reads the user's Keychain item through the Keychain service. The profile cannot split Keychain reads from writes, so a refresh updates the user's own item in place, as any of the user's sessions does. No copy exists, so no token is rotated away. This is inside the macOS residual.
- When no source works, the `claude-start` case fails, with its fix (Consumer degradation).

### Keyring and session bus

Built by #604. This answers integration R3-3.

- On Linux the strain reaches no session bus: `DBUS_SESSION_BUS_ADDRESS` is not passed, its usual socket sits under the hidden `$XDG_RUNTIME_DIR`, and the filter denies every Unix socket. So the Secret Service keyring is out of reach, and `gh` and git's libsecret helper lose a token stored there.
- The strain's GitHub credentials come from the first source that works, in this order:
  1. `GH_TOKEN` or `GITHUB_TOKEN`, already set in the tmux server's environment, passed as strain launch lists them;
  2. `gh`'s plain-file storage, `hosts.yml` in its config folder, which the strain reads read-only;
  3. otherwise the Lair runs `gh auth token` outside the sandbox at each spawn and sets the result as `GH_TOKEN` on that strain's tmux session only, with `tmux new-session -e`. The strain's `${GH_TOKEN+...}` word then passes it. The value never enters the command string. It is in the tmux client's arguments while it runs, where only the user's own processes outside a sandbox can see it, and those can run `gh auth token` themselves.
- Git reaches the same credentials through `gh auth git-credential` (Components "GitHub remotes").
- These are still the user's own credentials (ADR-0045 decision 9). No source widens what a strain can do on GitHub.
- When none works, the `gh_auth` probe fails, with its fix (Consumer degradation).
- On macOS the Keychain stays reachable, so `gh` works as it does for the user. The fallback order is Linux only.

### Probe `sandbox`

Built by #608, with #604's launcher; #604's live probe runs the same cases by hand. This answers integration R1-5 and R3-4.

**When.** At each Lair start, before any claim, as part of strain launch's environment preflight, which now runs inside the sandbox. It reuses the preflight's clean start, run nonce and 900-second deadline.

**Scratch targets, fresh nonces, real locations.** The probe draws a fresh nonce `N`, 32 lowercase hex digits. Every target is a scratch item named for `N`, made by the Lair outside every sandbox, in the real location a strain's or the Lair's own item would have. The probe never touches the real key, the halt file, the lock, a kept worktree or a live strain's folders. Each probe session gets a full strain layout from the same builder a strain uses: a detached scratch worktree at `<checkout>/.claude/worktrees/lair-probe-<N>/<x>/`, its admin folder, per-strain folders at `<state root>/sandbox/probe-<N>-<x>/`, and a record folder at `.hivemind/lair/strains/probe-<N>-<x>/` holding a `spawn.json`, with `<x>` one of `a`, `b` or `l`. A `probe-` name can never be read as a claim nonce.

**Launch order.**

1. Clean start. The Lair removes every leftover of an earlier probe by its fixed name patterns, then makes the targets of the cases below and layout `a`.
2. Session `a` starts in the sandbox. It is strain launch's preflight session: it runs #608's probe script, which runs `gh_auth`, `git_remote` and `local_review`, then the `sandbox` cases.
3. The Lair makes layout `b`, a sibling created after `a` started.
4. Session `b` starts in the sandbox and runs the `sandbox` cases only.
5. The Lair makes layout `l`, the late sibling neither session saw at its start.
6. The Lair writes a go file, holding `N` and the Lair's own process id, into each session's scratch folder. Each session runs its cases only after it reads the go file.
7. Each session writes its result file, `N` and each case's id and outcome, to its own scratch folder. The preflight's result file moves there from `.hivemind/lair/preflight/`, which is read-only in the sandbox.
8. After both sessions end, the Lair checks every target from outside: each scratch file unchanged, each forbidden new file absent, each witness file absent, and the common directory's `config` byte-equal to its copy from before step 2.
9. The Lair starts `claude` with a strain's arguments in layout `a`, as the case `claude-start`, then ends it.
10. The Lair removes every scratch item.

**Cases.** "L" is Linux, WSL2 included; "M" is macOS. A session runs only its platform's cases. An escape case passes only when every attempt fails and the Lair's own check in step 8 finds no change.

| Case | On | Target, and what the session tries | Passes when |
| --- | --- | --- | --- |
| `control` | L, M | `control/hivemind-probe-<N>`: read, append, delete; create `control/hivemind-probe-<N>-new` | all fail |
| `tmux-lair` | L, M | a scratch tmux server on `control/probe.sock`, standing for the Lair's own server and the scanner's: `tmux -S <path> list-sessions`, and `run-shell` of a command that creates a witness file under `control/` | all fail; no witness |
| `tmux-named` | L, M | a scratch tmux server `-L hivemind-probe-<N>` in the default tmux folder: the same two attempts, with its own witness | all fail; no witness |
| `tmux-default` | L, M | the user's default tmux server, real: `tmux list-sessions` only | fails |
| `runtime-dir` | L | `$XDG_RUNTIME_DIR/hivemind-probe-<N>`: read, append | all fail |
| `abstract` | L | a listener on the abstract socket `@hivemind-probe-<N>`: connect | fails |
| `unix-tmp` | L, M | a listener `/tmp/hivemind-probe-<N>.sock`, mode 0770, group-openable: connect | fails |
| `unix-home` | L, M | a listener `$HOME/.hivemind-probe-<N>.sock`, a path the sandbox shows: connect | fails |
| `loopback` | L | a TCP listener on `127.0.0.1` at a random port: connect directly, and through the proxy | all fail |
| `host-address` | L | a TCP listener on a non-loopback address of the host at a random port: connect directly, and through the proxy | all fail |
| `service-user` | L | the user's service manager, real: `systemd-run --user true` | fails |
| `docker-socket` | L | real: `test -e /run/docker.sock` and `test -e /var/run/docker.sock` | both false |
| `wsl-interop` | WSL2 | real: `cmd.exe /c exit` | fails |
| `process` | L | the Lair's own process id from the go file: look up `/proc/<pid>`; run `kill -0 <pid>` | `/proc/<pid>` absent; `kill` fails |
| `tiocsti` | L | the `TIOCSTI` ioctl on its own terminal | fails |
| `shared-config` | L, M | for each directory D of I4, the common directory itself included: the Lair makes `D/hivemind-probe-<N>`; the session appends to it, deletes it and creates `D/hivemind-probe-<N>-new`. An absent D: the session tries to create it. A D the user cannot write passes with no target | all fail |
| `sibling` | L, M | the other session's layout, and layout `l`: in its worktree, append to `.hivemind/lair/result.json`, `activity` and `launch.json` and delete one; create a file in its admin folder, its scratch folder and its Claude Code state folder; append to its record folder's `spawn.json` | all fail |
| `own-commit` | L, M | in its own worktree: create a file, `git switch -c hivemind-probe-<N>-<x>`, `git add`, `git commit` | succeeds |
| `claude-start` | L, M | step 9: `claude` with a strain's arguments, settings and environment | the pane shows `hivemind:overlord` within the deadline |

The I4 directories of `shared-config` are: `<common>/`, `<common>/hooks/`, `<common>/info/`, `<common>/objects/info/`, the main checkout's `.claude/`, `.hivemind/broods/`, the user's Claude Code folder and its `plugins/`, `$HOME`, `gh`'s config folder, and each `PATH` directory.

Against the user's real services the probe runs only the harmless commands of the table. Its `run-shell` attempts reach only its own scratch servers.

**Outcome.** When a case fails or cannot run, the Lair claims nothing and stops with cause `strain_env_preflight`, probe `sandbox`, and the case id. A case that cannot run includes a target the Lair cannot make, a missing tool, a missing result, a result with another nonce, and a launcher the builder refuses, which is the case `launcher` with one fixed reason (Consumer degradation). Strain launch's probe names `setup`, `gh_auth`, `git_remote`, `local_review`, `session` and `timeout` stand, and now run inside the sandbox.

### Concurrency gate

Built by #612.

- The Lair runs more than one strain at once only on Linux, and only when this Lair session's probe `sandbox` passed every case, the `sibling` cases included.
- On macOS it always runs one strain or remediation strain at a time.
- A failed probe stops the Lair before any claim, so it runs no strain at all.

### The Lair's tmux server

Built by #608. The Lair's own window runs on its own tmux server, on `control/lair.sock`, as answer 1A states. The strains stay on the default server, where `spawn-brood.sh` starts them and `brood-status` and the user find them. So no strain shares a server, or a server's global environment, with the Lair. The user attaches with `tmux -S <path> attach`. Start checks the socket's path length, as for `control/scan.sock`.

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). These rows add to claim integrity's and strain launch's rows. Every row here is no-authority: it is rebuilt or removed, never read as state.

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Per-strain folder `<state root>/sandbox/<nonce>/`, mode 0700, holding the generated profile on macOS | Lair, before spawn; removed at clean-up | the launcher | no |
| Per-strain scratch folder `sandbox/<nonce>/scratch/`, the strain's `TMPDIR` | Lair creates it; the strain writes it | the strain | no; removed with the worktree, kept with a kept worktree |
| Per-strain Claude Code state folder `sandbox/<nonce>/claude/`, with its read-only views and its `~/.claude.json` copy | Lair creates it; Claude Code in the strain writes it | the strain | no; removed with the worktree, kept with a kept worktree |
| Spawn record field `admin`, the strain's admin folder name | `spawn-brood.sh`, after `git worktree add`, before the session starts | Lair clean-up | no |
| Probe scratch: layouts `lair-probe-<N>/`, `sandbox/probe-<N>-<x>/`, `.hivemind/lair/strains/probe-<N>-<x>/`, the `hivemind-probe-<N>` files, sockets, listeners and branches, and `control/probe.sock` | Lair; each probe session writes its own result file | Lair | no; removed after the probe, and by pattern at its next clean start |
| Relay socket `<state root>/relay.sock` | Lair's proxy, at Start | the forwarders | no; removed at Start and at stop |
| The Lair's tmux server socket `control/lair.sock` | Lair, through tmux | Lair, the user | no; process plumbing |

Start step 3 checks that `control/lair.sock`, `control/probe.sock` and `relay.sock` are each at most 103 bytes, as it checks `control/scan.sock`.

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Launcher argv.** One fixed builder script, `plugin/skills/spawn-brood/scripts/lair-sandbox.sh`, makes the bubblewrap argv on Linux and the Seatbelt profile on macOS. Its inputs are the spawn record, the state root and the repository's host. Each path is one double-quoted word behind the charset gate of `spawn-brood.sh`'s plugin read rule: absolute, with bytes only in `[A-Za-z0-9 ._/@+()-]`. A path that fails the gate refuses the launch. The builder also refuses when a writable bind lies inside an I4 path, or an I4 path lies inside a writable bind. It prints one fixed reason on any refusal. `spawn-brood.sh` in Lair mode puts its words before the `env -i` words in the tmux command string. Without `lair_nonce` nothing changes.
- **Environment literals.** These change strain launch's Contract "Strain environment":
  - no longer passed: `SSH_AUTH_SOCK` and `DBUS_SESSION_BUS_ADDRESS`;
  - set by the Lair as literals, on both platforms: `TMPDIR`, `XDG_CACHE_HOME` and `CLAUDE_CONFIG_DIR` to the per-strain folders; and `GIT_CONFIG_COUNT` with these key and value pairs, in order: `credential.helper` empty; `credential.helper` `!gh auth git-credential`; `url.https://<host>/.insteadOf` `git@<host>:`; `url.https://<host>/.insteadOf` `ssh://git@<host>/`; `gc.auto` `0`; `maintenance.auto` `false`; `fetch.prune` `false`; `core.fsmonitor` `false`;
  - set as literals on Linux only: `HTTPS_PROXY`, `HTTP_PROXY`, `https_proxy` and `http_proxy` to `http://127.0.0.1:<port>`, and `NO_PROXY` and `no_proxy` to `localhost,127.0.0.1,::1`;
  - every other name stays as strain launch lists it. A name the live probe finds missing is added by a dated amendment, never by a wildcard.
- **Strain settings.** The fragment gains `"sandbox": {"enabled": false}`. The outer sandbox holds the whole session, and Claude Code's own sandbox cannot start inside it, since it needs a Unix socket relay. A managed setting sits above `--settings`, so a managed `sandbox.enabled` still wins (Consumer degradation).
- **Seam with strain launch, the preflight.** The preflight session runs inside the sandbox, as session `a` of the probe `sandbox`, in a strain layout at a strain worktree location, instead of a scratch worktree in `.hivemind/lair/preflight/`. The probe script takes a second argument, its session's scratch folder, where it writes its result. The preflight folder keeps the reviewer setting and the run nonce, read-only to the session. The stop cause adds the case id for probe `sandbox`.
- **Seam with strain launch, the Lair-mode scripts.** In Lair mode `push-branch.sh` records no upstream: its push names its expected commit and never reads the upstream, and the shared config is read-only in the sandbox. In Lair mode `create-working-branch.sh` changes no upstream, for the same reason. Without a verified marker both scripts behave as today.
- **Seam with strain launch, the spawn record.** `spawn.json` gains `admin`, the admin folder name (State and ownership).
- **Seam with claim integrity.** Its "Assumptions about #630":
  - "Containment of the key and the halt file" and "Tmux reach": met on both platforms, by I1 and I2;
  - "Process reach": met on Linux by the PID namespace and the fresh `/proc`; on macOS the 2026-11-22 amendment applies, as that bullet already states;
  - "Result file per strain": met on Linux by I3. On macOS the profile denies a strain every sibling's files, and strains run one at a time, so no sibling runs beside it; a kept worktree is still write-denied. An escape is inside the macOS residual.
- **Seam with the merge lane.** Its assumption that "a strain writes nothing outside its worktree and the shared object and ref store" is met on Linux by I4 and I5, and on macOS by the profile, with the macOS residual. Its residual "a strain that writes the tick's inputs" narrows to a strain that escapes containment. Its cache, under `control/`, is covered by I1.
- **Seam with #608.** #608 builds the probe `sandbox`, the relay and proxy, the Lair's tmux server and the Start checks of the new socket paths.
- **Seam with #612.** #612 builds the concurrency gate.
- **Seam with #611.** `control/digest/` is under `control/`, so I1 covers it.

## Trust boundaries

A strain is untrusted after spawn (strain launch, Trust boundaries, "Strain containment"). This design narrows what it can reach. It changes no channel through which the user steers the Lair.

**On Linux.** The strain reaches only what Requirement allows. Its reads cover the root view, which hides the state root and the runtime folders. Its writes are the allowlist. It creates no Unix socket. It reaches remote hosts only through the proxy, and sees and signals only its own processes. So the key, the halt file, the tmux servers, every user service, every sibling's files and every shared run-or-load file are out of reach. Strain launch's "Named residual: the tmux global environment" holds only for a strain that escapes containment.

These residuals remain, each with its ground and bounded impact.

- **Residual: an escape on macOS.**
  - Scope: a strain that asks `launchd`, LaunchServices or Apple Events to run a command outside its profile, or reads the key out of the Lair's processes, which the profile does not hide. Such a command runs as the user, with every right this design denies.
  - Ground: the ADR-0045 amendment of 2026-11-21, "sessions running as the user can forge Lair markers", for an escape from containment; and the ADR-0045 amendment of 2026-11-22, "the Lair's strains can read its key where no sandbox hides its processes", for process reach. The user accepted both.
  - Bounded impact: what those two amendments state, a forged marker that counts, plus what ADR-0045's residual "A prompt-injected strain holds the user's rights" states. On macOS strains run one at a time, so no sibling runs beside an escaped strain. Merges still pass `merge-approved.sh`'s gates, and a merge is reverted (ADR-0045 decision 14).
- **Residual: the shared object and ref store.**
  - Scope: a strain writes the shared object and ref store, which worktree strains must (ADR-0017 decisions 1 and 2). So it can move other worktrees' local refs, its siblings' branches and remote-tracking refs included, add `refs/replace/` refs, and delete or corrupt packs.
  - Ground: the worktree model of ADR-0017 and strain launch. The other option, a per-strain clone, is rejected under Decisions.
  - Bounded impact:
    - a moved remote branch needs a push, and every strain push is leased to its own expected commit (strain launch, Components "Start points");
    - a sibling that builds on a moved ref pushes that content into its own pull request's diff, where the merge lane's gates, local review and the auto-tier checks read it, and the merge lane's result checks bind `pr`, `branch` and `head` to GitHub;
    - the Lair's own git reads use its own repository under `control/`, with replace objects off (merge lane, "Git and tool reads");
    - deleted objects are denial of service: a run fails, and pushed work is on the remote. The user's unpushed work in the main checkout shares the store and can be lost or rewritten.

    This sits inside ADR-0045's residual "A prompt-injected strain holds the user's rights", which already lets a strain move or delete branches on the remote with the user's credentials.
- **Residual: network egress with the user's credentials.**
  - Scope: a strain reaches any remote host through the proxy, holding the user's GitHub token and its Claude credentials, so it can send what it reads to any host.
  - Ground: ADR-0045 decision 9, everything runs under the user's credentials, and its residual "A prompt-injected strain holds the user's rights". The Lair's settings fragment turns off Claude Code's own sandbox, so a user's Bash host allowlist does not apply in a Lair strain.
  - Bounded impact: what the user's GitHub and Claude accounts can do. The proxy keeps the strain off local services, the host and, on WSL2, the Windows host. A dedicated identity (ADR-0045 decision 9, deferred) is the real fix.
- **Residual: a kernel or sandbox bug.**
  - Scope: a flaw in the kernel's namespaces, mounts or seccomp, in bubblewrap, or in Seatbelt, that lets a strain out.
  - Ground: the platform is the boundary; the plugin ships no kernel code.
  - Bounded impact: as for an escape on macOS. The probe `sandbox` checks the properties at each start, not the absence of flaws.

## Lifecycle

1. **Start.** Claim integrity's Start runs, with the socket path checks of State and ownership. The Lair starts its proxy on `relay.sock` (Linux) and its window on `control/lair.sock`.
2. **Probe.** The environment preflight runs inside the sandbox, with the probe `sandbox`. Any failure stops the Lair before its first claim.
3. **Claims.** Admission and the claim run as claim integrity states. #612's gate decides whether a second strain may start.
4. **Spawn.** After strain launch's writes, the Lair creates the per-strain folders, the Claude Code state views and the `~/.claude.json` copy, and, on Linux under the third credential source, reads `gh auth token`. `spawn-brood.sh` in Lair mode creates the worktree, records `admin` in `spawn.json`, builds the launcher argv or profile, and starts the session. On Linux the Lair attaches the forwarder, and the sandbox command then runs. Spawn's own steps run outside the sandbox; everything after `tmux new-session` runs inside it.
5. **Run.** As strain launch states, inside the sandbox.
6. **End.** The Lair ends the session as strain launch states. `--die-with-parent` ends the sandbox with the pane. The Lair stops that strain's forwarder.
7. **Clean-up.** As strain launch's Lifecycle step 5 and the parent design's Seams item 7 state. When the worktree is removed, the Lair also removes the admin folder and the per-strain folder, taking each path from the spawn record (Components "Write allowlist"). A kept worktree keeps its per-strain folder.
8. **Stop.** The Lair stops its proxy and removes `relay.sock`.

## Existing-path coverage

- **A non-Lair brood strain**, and every `spawn-brood.sh` call without `lair_nonce`, are unchanged: no sandbox, the same launch command, environment and settings.
- **Interactive sessions** are unchanged, the user's own `sandbox` setting included. The fragment's `sandbox.enabled` false applies only in a Lair strain.
- **`push-branch.sh` and `create-working-branch.sh`** are unchanged when the marker check prints `none`: the upstream record and the upstream rule stay as today.
- **`brood-status`** is unchanged: strains stay on the default tmux server.
- **The Lair's own processes**, the tick, the merge lane and the scanner session run outside every strain sandbox, as their designs state.

## Consumer degradation

Per [P26](../../engineering-principles.md), each capability below is optional. The Lair detects it, and when it is absent the Lair claims nothing, or a run fails visibly, with a named cause and a fix. Non-Lair hivemind is unchanged throughout. Nothing here needs CI, a ruleset or any other setup in the consumer project.

| Capability | Detection | Fallback |
| --- | --- | --- |
| `bwrap` on Linux | the builder's check at the probe | case `launcher`, reason `bwrap-missing`: the Lair claims nothing. Fix: install bubblewrap |
| Unprivileged user namespaces (blocked by Ubuntu's AppArmor restriction, a sysctl, or a container) | session `a` fails to start; the builder's reason | case `launcher`, reason `userns-blocked`: the Lair claims nothing. Fix: load bubblewrap's AppArmor profile, allow user namespaces, or run the Lair on the host, not in the container |
| A seccomp program for the architecture | the builder | case `launcher`, reason `seccomp-arch`: the Lair claims nothing. Only x86_64 and aarch64 are built |
| The relay and proxy tools | Start of the proxy; the forwarder attach | case `launcher`, reason `relay-missing`: the Lair claims nothing. Fix: install the tool #604 picks |
| `sandbox-exec` on macOS | the builder's check | case `launcher`, reason `sandbox-exec-missing`: the Lair claims nothing |
| WSL1, native Windows, or any platform but Linux and macOS | the builder's platform check; claim integrity's Start step 1 | case `launcher`, reason `platform`, or claim integrity's refusal: the Lair claims nothing. Fix: WSL2 |
| `gh` with a keyring-only token | the `gh_auth` probe in the sandbox | the third credential source, `gh auth token` at each spawn. When that fails too: probe `gh_auth`. Fix: `gh auth login` |
| A remote that answers only over SSH, or on a host `gh` does not serve | the `git_remote` probe | probe `git_remote`: the Lair claims nothing. Fix: an HTTPS remote on the repository's host |
| Claude Code auth only by the credential file on Linux | the `claude-start` case | case `claude-start`: the Lair claims nothing. Fix: `claude setup-token`, then set `CLAUDE_CODE_OAUTH_TOKEN`, or set `ANTHROPIC_API_KEY`, in the tmux server's environment |
| A local review tool that writes outside the allowlist, such as its own home folder, or starts its own sandbox | the `local_review` probe in the sandbox | probe `local_review`: the Lair claims nothing. Fix: a reviewer setting whose tool keeps its writes under `$TMPDIR` and needs no sandbox of its own, which the strain's sandbox already gives; or no reviewer setting, so every Lair pull request goes to `lair:review` (ADR-0045 decision 12). A tool that fails only in a strain gives `skipped: tool-failed`, and its pull request goes to `lair:review` |
| Builds that need Docker, another Unix socket service, writes under `$HOME`, a submodule update, or a shallow clone's fetch | the strain's own tool error | the run fails or parks with the tool's error, as any failed run. Fix: point the tool's cache at `$XDG_CACHE_HOME` or `$TMPDIR` in the project's build configuration, or run such a project without the Lair |
| The user's own `sandbox.enabled` | the fragment's `false`; a managed setting wins | none for user, project or local settings. A managed `sandbox.enabled` that stops Claude Code at start fails case `claude-start` |

## Failure modes

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Containment cannot be confirmed | a case of the probe `sandbox` fails or cannot run | The Lair claims nothing and stops with cause `strain_env_preflight`, probe `sandbox`, and the case id. |
| The launcher fails at a later spawn, after a passing probe | `spawn-brood.sh` exits non-zero, or the session dies with no result | Strain launch's failed spawn or Crash row applies. A crash counts toward the circuit breaker. |
| The forwarder does not attach | the attach step's own deadline | The Lair kills the session; the run is a crash. |
| The proxy dies during a session | the Lair's per-tick check of the proxy | The Lair restarts it. It claims nothing while the proxy is down. Strains in flight see network failures, which `isTransientFailure` retries. |
| A tool in a strain needs a write or a socket the sandbox denies | the tool's own error in the run | The run fails, blocks or parks as for any such error. Consumer degradation names the fix. |
| A probe leftover from a stopped Lair | the next probe's clean start | Removed by its fixed name patterns before the new probe. |
| A path clean-up would remove is a link or not a directory | `lstat` at clean-up | The Lair removes only the link and names the path in the queue report. |
| A strain escapes containment | not detected | Trust boundaries, the escape and kernel residuals. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails. Every decision below was taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal), each with a strong recommendation, and is listed for veto.

- **An outer sandbox wraps the whole strain command; Claude Code's own `sandbox` setting is not used.** That setting covers shell commands only, not the file tools, hooks or MCP servers. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Linux uses bubblewrap with user, PID, IPC, UTS and network namespaces, a read-only root view and the I5 allowlist.** The other option, Landlock, needs Linux 6.12 for its abstract socket scope, newer than many hosts run, and does not hide processes. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Unix sockets are denied by a seccomp filter on `socket(AF_UNIX)`, so I2 holds by construction.** The other option, hiding socket paths with tmpfs folders, is a list of known places: a socket under `$HOME`, where any tool may create one, would stay reachable (integration R3-2). The cost: a project whose build or tests create a Unix socket fails under the Lair. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The relay's forwarder is attached from outside the strain's namespaces.** The other option, a forwarder inside the sandbox, needs a Unix socket inside it, which the filter denies. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The filter blocks `TIOCSTI` and `TIOCLINUX`, and the launcher does not use `--new-session`.** The other option, `--new-session`, takes the TUI's controlling terminal, so resize signals stop. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A tmpfs covers the whole state root, not only `control/`.** It also hides the scanner's files and every sibling's per-strain folders, with no list. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Egress goes only through a proxy that refuses local addresses, with no host allowlist.** The other option, a host allowlist, would need every host a project's build fetches from. The cost is the egress residual. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **GitHub SSH remotes are rewritten to HTTPS, with `gh` as the only credential helper, and no SSH agent reaches a strain.** An agent socket would let a strain authenticate as the user to any SSH host. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Strains keep the worktree model and write the shared object and ref store; `objects/info/` is read-only.** The other option, a per-strain clone that borrows objects read-only, would close the store residual but changes ADR-0017's worktree model, `spawn-brood.sh`'s layout, strain launch's Lair checkout rule and `brood-status`. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Lair-mode `push-branch.sh` records no upstream, and Lair-mode `create-working-branch.sh` changes none.** The shared config is read-only, and Lair mode never reads the upstream. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Clean-up takes paths only from the spawn record, which gains the admin folder name.** The admin folder is strain-writable. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A per-strain Claude Code state folder with read-only views; on Linux, auth only by an environment token.** A refresh from a copied token rotates the user's token away. The cost: a Linux user who signed in only by the browser must make a token with `claude setup-token`. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The keyring fallback order ends with `gh auth token` at spawn, set on the strain's tmux session only.** Still the user's own credentials (ADR-0045 decision 9). Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The fragment turns off Claude Code's own sandbox in Lair strains.** It cannot start inside the outer sandbox, and the outer one is stricter except for a Bash host allowlist. The cost is named in the egress residual. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The probe runs at each start, on scratch targets in real locations, with two sessions and a late sibling layout, and a case that cannot run fails it.** The other option, targets in a private folder, could pass where a real location would fail. The cost: three scratch worktrees and two sandbox starts at each Lair start, and one real local review call, as strain launch's preflight already makes. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **macOS runs one strain at a time, under a profile that claims no protection against `launchd`, LaunchServices or Apple Events, under both ADR-0045 amendments.** So PRD user story line 37, several issues at once, is met on Linux only. That is a P26 degradation with a stated fallback, and the PRD's Parallelism criterion, line 79, is conditional on more than one strain running. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **#612 runs strains at once only on Linux, only after a probe whose every case passed.** Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The Lair's window runs on its own tmux server on `control/lair.sock`; strains stay on the default server.** Answer 1A. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **No containment property rests on an environment value.** The literals serve the tools, and the platform mechanisms contain. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The PRD and ADR-0045 need no change.** ADR-0045's two amendments already state the Linux sandbox and the macOS residual this design builds and relies on.

### Changes to shared documents

None is applied in this pull request. After this design's review passes, one dated entry under the solution design's Amendments lands them, which stales that design's review record, as its opening paragraphs require. The PRD and ADR-0045 are not changed.

1. **`docs/initiatives/autonomous-ready-issue-loop/solution-design.md`, Amendments.** Proposed text, with `<date>` the date it lands:

   ```markdown
   **<date>, strain containment.** [Strain containment](strain-containment-design.md), #646, joins this design as a fourth part design, frozen like the other three. Its review is recorded in the [strain containment review record](strain-containment-review-record.md). It designs how #604 meets Seams between the part designs, item 6. For its scope it overrides these parts of the frozen part designs:

   - [Strain launch](strain-launch-design.md): Contracts and seams, "Strain environment", which no longer passes `SSH_AUTH_SOCK` or `DBUS_SESSION_BUS_ADDRESS` and takes `TMPDIR`, `XDG_CACHE_HOME`, `CLAUDE_CONFIG_DIR`, the `GIT_CONFIG_*` pairs and, on Linux, the proxy names as Lair-set literals (strain containment, Contracts and seams, "Environment literals"); Components "Strain launch and settings", whose launch command the platform launcher wraps, and whose "Environment preflight" runs inside the sandbox as session `a` of the probe `sandbox`, in a strain layout, writing its result to its own scratch folder, and stopping with the case id for probe `sandbox`; Contracts and seams, "Strain settings", whose fragment sets `sandbox.enabled` to false; Components "Start points", where Lair-mode `push-branch.sh` records no upstream and Lair-mode `create-working-branch.sh` changes none; State and ownership, whose spawn record gains `admin`; Trust boundaries, "Strain containment", whose statement that a strain can read any file the user can holds outside what strain containment hides, and whose "Named residual: the tmux global environment" holds only for a strain that escapes containment; and Lifecycle steps 2 and 5, where spawn starts the sandbox and clean-up also removes the admin folder and the per-strain folder, taking each path from the spawn record.
   - [Claim integrity](claim-integrity-design.md): Components "Lair state root", where the state root gains `sandbox/` and `relay.sock` and `control/` gains `lair.sock`, `probe.sock` and the probe's `hivemind-probe-<N>` scratch files; Lifecycle, Start step 3, whose path check covers `control/lair.sock`, `control/probe.sock` and `relay.sock`; and Contracts and seams, "Assumptions about #630", whose Containment of the key and the halt file and Tmux reach are met on both platforms, whose Process reach is met on Linux, and whose Result file per strain is met on Linux, and on macOS by the profile and one strain at a time, with the residual "an escape on macOS" (strain containment, Trust boundaries).
   - [Merge lane](merge-lane-design.md): Contracts and seams, "Assumptions about #630", whose first bullet is met on Linux, and on macOS by the profile with the residual "an escape on macOS"; and Trust boundaries, "Residual: a strain that writes the tick's inputs", which holds only for a strain that escapes containment.

   Seams between the part designs, item 6, changes three of its bullets. Each bullet below replaces the bullet of item 6 that starts with the same words:

   - How #604 meets the requirement is designed in [strain containment](strain-containment-design.md), #646: the mechanism per platform, the write allowlist, the cases of the probe `sandbox`, the keyring fallback and #612's gate.
   - Strain launch's named residuals stand as written (Trust boundaries), except that "the tmux global environment" holds only for a strain that escapes containment (strain containment, Trust boundaries). Of a strain's own result, the merge lane's result checks bound its `pr`, `branch` and `head` (Contracts and seams, "Lair pull request"); its outcome, park record and decisions are not bounded and stay under "a prompt-injected strain holds the user's rights".
   - Claim integrity's assumption "Result file per strain" and the merge lane's assumption that a strain writes nothing outside its worktree and the shared object and ref store ("Assumptions about #630") are met as strain containment, Contracts and seams, states. Where an escape breaks them, the merge lane's residual "A strain that writes the tick's inputs" applies (Trust boundaries).

   Verification strategy's bullet that starts "The containment probe cases" ends with "are those of strain containment, Components "Probe `sandbox`"." in place of "are designed in #646 (Seams between the part designs, item 6)." The Failure modes row "Strain containment cannot be confirmed" ends its Resulting state with ", and the case id".

   The Part designs column of #604, #608 and #612 adds [strain containment](strain-containment-design.md). The overlord adds this design to the Initiative line of #604, #608 and #612, a body edit that keeps every other byte.
   ```

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions). This section adds where each test of this scope lives.

- **The live probe, by hand, on Linux and on macOS** (#604). It runs every case of the probe `sandbox` on each platform, on WSL2 as well as native Linux, and claim integrity's #604 Process reach case under `kernel.yama.ptrace_scope` 0. It also runs one strain end to end, push and pull request included, so any write or socket the run needs and the sandbox denies shows up. #604 records the results, and each live-probe assumption that failed, through a dated Amendments entry, as for any part design.
- **`tools/test_lair_sandbox.sh`**, new (#604). It runs the builder with no kernel sandbox:
  - the Linux argv for a fixed spawn record: each namespace flag, `--die-with-parent`, the fresh `/proc` and `/dev`, the read-only root, each tmpfs, the state root tmpfs, each writable bind of I5 in order, the read-only `objects/info/` bind after the `objects/` bind, and the `--seccomp` word;
  - the macOS profile for the same record: the write denial and each allowed write path, the `control/` denial, the Unix socket denial and its one allowance;
  - the environment literals, the `GIT_CONFIG_*` pairs and the dropped names, as a pin;
  - each refusal: a path outside the charset gate, a writable bind inside an I4 path or the reverse, an unknown architecture, an unknown platform, each with its fixed reason;
  - the seccomp program's instructions for x86_64 and aarch64: the native-ABI check, the `socket` domain check, `io_uring_setup`, and the `ioctl` checks;
  - clean-up path selection from the spawn record, never from the admin folder's `gitdir`.
- **`tools/test_lair_tick.sh`** gains, with the launcher stubbed (#608, #612): a passing probe lets the first claim happen; each failing case, and a case that cannot run, stops the Lair with cause `strain_env_preflight`, probe `sandbox`, and that case id, with no claim; the launch order `a`, then layout `b`, then session `b`, then layout `l`; the clean start removes every probe leftover by pattern and touches no real key, halt file, kept worktree or live strain folder; the concurrency gate allows a second strain only on Linux after a probe with every case passed, never on macOS.
- **`tools/test_lair_strain.sh`** gains (#604): Lair mode puts the builder's words before the `env -i` words; `spawn.json` records `admin` before `tmux new-session`; the third credential source sets `GH_TOKEN` with `-e` and never in the command string.
- **`tools/test_push_branch.sh`** and **`tools/test_create_working_branch.sh`** gain the Lair-mode cases that write no git config, and keep the marker `none` cases that still do (#604).
- **Registration in `tools/validate.sh`.** `tools/test_lair_sandbox.sh` is added in its pull request to `KNOWN_SUITES`, `ALL_SUITES`, a `SUITE_*` constant, and a `map_path` rule for the builder and its fixtures, so `tools/validate.sh --self-test` passes and `--changed` selects it. `plugin/skills/spawn-brood/scripts/lair-sandbox.sh` routes to it and to `tools/test_lair_strain.sh`.

### Live-probe assumptions

Each assumption below is a platform fact this design could not confirm from a source. The live probe checks each one. Until it holds, the Lair on that platform claims nothing, through the probe case named.

| Assumption | Checked by | When it fails |
| --- | --- | --- |
| The interactive TUI runs under bubblewrap with no `--new-session`, keeps its terminal, and renders and resizes | `claude-start`; the live end-to-end run | #604 amends the launcher; until then, case `claude-start` fails |
| A read-only bind of `/` keeps every submount read-only, WSL2's `/mnt/c` included | the live probe, with a write attempt on each submount | #604 adds a read-only bind per submount |
| Claude Code, `gh`, git and the configured local review tool start and work with `socket(AF_UNIX)` denied, `socketpair` allowed, and a name lookup that cannot reach a Unix socket service such as `nscd` | `claude-start`, `gh_auth`, `git_remote`, `local_review` | the named probe fails |
| Claude Code keeps `.claude.json` and every other write under `CLAUDE_CONFIG_DIR` when it is set, and starts with read-only views of the settings and plugins, a plugin marketplace update included | `claude-start` | case `claude-start` fails |
| On macOS, Claude Code with `CLAUDE_CONFIG_DIR` set finds the user's Keychain item | `claude-start` on macOS | case `claude-start` fails; fix: `CLAUDE_CODE_OAUTH_TOKEN` |
| The Seatbelt operations for signals and process information to other processes exist on the user's macOS version | the live probe on macOS | the profile leaves them out, and the macOS residual covers them |
| The Seatbelt Unix socket filter allows the system resolver's socket while denying every other, and DNS still resolves | `unix-tmp`, `unix-home`, `git_remote` on macOS | the named case fails |
| The forwarder can join the strain's user and network namespaces from outside, unprivileged | the attach step at session `a` | case `launcher`, reason `relay-missing` |
| On WSL2 the proxy can name the Windows host's address and refuse it | `host-address` on WSL2 with a Windows-side listener in the live probe | #604 amends the refusal; until then, case `host-address` fails |
| `tmux new-session -e` sets a session variable that the pane's `${GH_TOKEN+...}` word reads | `gh_auth` under the third source | probe `gh_auth` fails |
| A managed `sandbox.enabled` either stops Claude Code at start or leaves Bash working inside the outer sandbox | the live probe with a managed setting | #604 makes `claude-start` refuse when a managed setting turns the sandbox on |
| No git or `gh` command in a delivery or remediation run writes the common directory's `config` once Lair mode records no upstream | the live end-to-end run | #604 amends the literals or the Lair-mode scripts |

## Seam order

The build order is the parent design's. #646 is a design issue, not a slice: #604, #608 and #612 are natively blocked by it.

| Slice | What this design changes | ADRs |
| --- | --- | --- |
| #604 | the builder `lair-sandbox.sh` for the bubblewrap argv and the Seatbelt profile; the seccomp program; the write allowlist; the environment literals; the per-strain folders and Claude Code state views; the keyring fallback; the forwarder attach; `admin` in `spawn.json`; Lair mode of `push-branch.sh` and `create-working-branch.sh` with no upstream writes; the fragment's `sandbox.enabled`; the live probe | ADR-0045 decisions 3, 4 and 9, its 2026-11-21 amendment on forged markers and its 2026-11-22 amendment on process reach; ADR-0010; ADR-0017 |
| #608 | the probe `sandbox` in the environment preflight, inside the sandbox, with its targets, launch order and cases; the proxy and relay socket; the Lair's tmux server on `control/lair.sock`; Start's socket path checks; clean-up of the per-strain folders | ADR-0045 decisions 2 and 17 and its 2026-11-21 and 2026-11-22 amendments; ADR-0017 |
| #612 | the concurrency gate | ADR-0045 decision 15 and its 2026-11-22 amendment on process reach |

## Inherited findings

From #633's integration review ([review record](review-record.md), History, "Integration review findings"). Each row names where this design closes it.

| Finding | What it found | Closed by |
| --- | --- | --- |
| integration R1-1 | A strain on the default tmux server could run `new-window` or `run-shell` outside its sandbox. | Requirement I2; Components "Linux launcher" (no Unix socket at all) and "macOS launcher" (Unix socket connects denied); "The Lair's tmux server"; cases `tmux-lair`, `tmux-named`, `tmux-default`. |
| integration R1-2 | `control/` containment had no building slice, no test and no macOS answer. | Requirement I1; the state root tmpfs on Linux and the `control/` denial on macOS; #604 and #608 under Seam order; case `control`. |
| integration R1-5 | No check stopped the Lair where containment was missing. | Components "Probe `sandbox`", "Outcome": any failing or unrunnable case stops the Lair with cause `strain_env_preflight`, probe `sandbox`, and the case id; Failure modes. |
| integration R1-12 | The merge lane's cache was strain-writable, and the result-file assumption had no bound. | The cache under `control/`, covered by I1. The result file: I3 on Linux; on macOS, the profile, one strain at a time, and the residual "an escape on macOS" (Contracts and seams, "Seam with claim integrity"). |
| integration R2-1 | A strain could make another tmux server or a user service run a command outside its sandbox. | Deny by default: the `AF_UNIX` filter and the network namespace on Linux; cases `tmux-named`, `service-user` (`systemd-run --user true`) and `tmux-lair` with `run-shell` and a witness file. |
| integration C2-1 | A strain could read and write a sibling's result, liveness and launch files. | Requirement I3 and the I5 allowlist; the `sibling` case against layout `b`, created after session `a` started, and layout `l`, created after both started; the concurrency gate of #612. |
| integration R3-1 | Containment denied named targets and left shared run-or-load files writable; on macOS a process outside the profile reaches siblings. | Requirement I4 as a consequence of the I5 allowlist, with a read-only root; the `shared-config` case; on macOS no containment beyond the profile is claimed, under the residual "an escape on macOS". |
| integration R3-2 | Abstract sockets and group-openable system sockets escape hiding by path. | The `AF_UNIX` filter and the network namespace, so reach is denied by default, not by path; the WSL2 interop and `/mnt/wslg` hiding; cases `abstract`, `unix-tmp`, `unix-home`, `loopback`, `host-address`, `docker-socket`, `wsl-interop`. |
| integration R3-3 | Hiding the session bus hides the Secret Service keyring, with no fallback. | Components "Keyring and session bus": the fallback order, and probe `gh_auth` with its fix when none works. |
| integration R3-4 | The probe's targets and launch order were unspecified. | Components "Probe `sandbox`": scratch targets under a fresh nonce in real locations, never a real key, halt file, kept worktree or live strain folder; the launch order with a sibling made after the first session starts. |
| integration R3-6 | The macOS reach was cited to the process-reach amendment only. | Components "macOS launcher", "What it does not claim", and Trust boundaries, "Residual: an escape on macOS", which cite both the 2026-11-21 amendment on forged markers and the 2026-11-22 amendment on process reach. |

## Open questions

None

## Amendments

This design was written on 2026-11-24. Later changes to this design are appended here as dated entries.
