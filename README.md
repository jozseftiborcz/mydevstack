# mydevstack

Personal development environment: a few shell tools for running
[Claude Code](https://claude.com/claude-code) agents inside tmux, the Claude
Code settings that wire them up, shell completions, and Lima VM definitions.

## Layout

```
Makefile                      install / uninstall / check
local-bin/                    executables installed into ~/.local/bin
  claude-tmux-state           Claude Code hook -> tmux @agent_* options
  tmux-agents                 list / attach to agents, create sessions
  implement-github-issues     one tmux window + Claude worktree per GitHub issue
completions/
  bash/                       bash completions (named after the command)
  zsh/                        zsh completions (_command, autoloaded from $fpath)
tools/
  completion-rc               adds/removes the completion-loading block in rc files
claude/
  settings.json               Claude Code settings (hooks, model, status line)
  statusline-command.sh       status line: model, context %, cost, git, rate limits
lima/
  dev-lima.yaml               Debian 13 arm64 dev VM (virtiofs mounts, agent forwarding)
  tinyidm-lima.yaml           Debian 13 multi-arch VM with full localhost port forwarding
```

## Installation

```sh
make check      # syntax-check scripts and completions
make list       # show what install would copy
make install    # install into ~/.local/bin plus bash/zsh completions
```

`make install` copies every executable in `local-bin/` to `~/.local/bin`,
installs the completions under `~/.local/share/bash-completion/completions`
and `~/.local/share/zsh/site-functions`, and then asks before adding a
marker-delimited block to `~/.bashrc` and `~/.zshrc` that loads them.

Useful variations:

```sh
make install YES=1          # answer the rc-file question up front
make install SKIP_RC=1      # never touch the rc files
make install PREFIX=/usr    # system-wide (BINDIR, BASHCOMPDIR, ZSHCOMPDIR also overridable)
make uninstall              # remove installed copies and the rc block
```

`~/.local/bin` is the default because `claude/settings.json` calls
`$HOME/.local/bin/claude-tmux-state` from every hook.

Dependencies: `bash`, `tmux`, `jq`; `implement-github-issues` also needs
`git`, `gh`, and a Claude Code CLI that supports `--worktree` and
`--permission-mode`.

## Claude Code integration

### claude-tmux-state (hook)

A Claude Code hook that records what each Claude session is doing as tmux
user options on the pane it runs in. `claude/settings.json` registers it for
every lifecycle event (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `PermissionRequest`, `Notification`, `MessageDisplay`,
`SubagentStart`, `SubagentStop`, `Stop`, `SessionEnd`, ...). Each fire
writes, in a single tmux invocation:

| Option                     | Content                                             |
| -------------------------- | --------------------------------------------------- |
| `@agent_state`             | `INPUT`, `ERROR`, `IDLE`, `BACKGROUND`, `RUNNING`, `OFFLINE` |
| `@agent_status_kind`       | e.g. `question`, `approval`, `tool`, `subagent`, `result`, `error` |
| `@agent_status_text`       | one-line description (tool being run, question asked, ...) |
| `@agent_subagents`         | subagents still running, as `agent_id=agent_type` entries |
| `@agent_state_agent`       | `agent_id` of the subagent that produced the state, empty for the main thread |
| `@agent_event`             | the hook event that produced the update             |
| `@agent_updated`           | epoch seconds                                       |
| `@agent_pane_id`, `@agent_window_*`, `@agent_session_*` | where the agent lives |
| `@agent_claude_session_id`, `@agent_prompt_id` | Claude-side identifiers   |

These can be used directly in tmux formats (`#{@agent_state}`) for a status
line or window list, and are what `tmux-agents` reads.

Subagents started with the `Agent` tool run in the background, and their
tool calls fire the same hooks with an `agent_id`. While any subagent is
running the state stays `RUNNING` with kind `subagent` (`Subagent Explore:
Grep: foo`, `Running 2 subagents: Explore, Plan`), including for the idle
notification Claude sends a minute after the main turn ends, and a prompt
waiting for the human (`INPUT`) is not overwritten by other agents' activity.
`@agent_subagents` is rebuilt from `background_tasks` on every `Stop` and
`SubagentStop`, so a subagent killed without a `SubagentStop` lingers only
until the next turn ends. Claude also runs internal helper agents after a
turn (no `SubagentStart`, no `agent_type`); their `SubagentStop` arrives
after the main `Stop` and is ignored so it cannot turn `IDLE` back into
`RUNNING`.

Claude also starts turns on its own: when a background task or subagent
finishes, when a teammate sends a message, or on a `/loop` wakeup. A
finished background Bash task fires `UserPromptSubmit` (checked with Claude
Code 2.1.280); the other triggers are unverified. As a fallback, the first
streamed line of any reply (`MessageDisplay`, index 0) moves the pane to
`RUNNING` unless the main thread already set it; later flushes exit before
touching tmux. The `agent_completed` notification sets `RUNNING` rather
than `IDLE`, since the main thread wakes up to handle the agent's result,
and the idle notification leaves `BACKGROUND` alone while background work
that `Stop` saw is still running.

Configuration (environment variables, read by the hook):

| Variable                          | Default | Purpose                                      |
| --------------------------------- | ------- | -------------------------------------------- |
| `CLAUDE_TMUX_SCOPE`               | `pane`  | write options at `pane`, `window`, or `session` scope; can also be set per target with the tmux option `@claude_state_scope` |
| `CLAUDE_TMUX_STATUS_MAX_LENGTH`   | `180`   | truncate `@agent_status_text`                |
| `CLAUDE_TMUX_SHOW_PROMPT`         | `0`     | include the user prompt in the status text   |
| `CLAUDE_TMUX_SHOW_COMMANDS`       | `0`     | include Bash commands in the status text     |
| `CLAUDE_TMUX_DEBUG_LOG`           | unset   | append hook payloads to this file            |

The hook is a no-op outside tmux or when `tmux`/`jq` are missing.

### tmux-agents

Lists the agents registered by the hook and attaches to one by number.
Agents that need a human (`INPUT`, `ERROR`) are listed first.

```
tmux-agents [list]        List agents (default).
tmux-agents list -l       List agents with every recorded field.
tmux-agents NUMBER        Attach to the agent shown with that number.
tmux-agents next          Attach to the first agent waiting for input.
tmux-agents new [NAME]    Create a tmux session in the current directory and attach.
tmux-agents new claude [NAME]
                          Same, with the window split: shell on the left,
                          Claude Code on the right, focus on Claude.
tmux-agents help          Show this help (also -h or --help).
```

`new` names the session after the current directory unless `NAME` is given,
and switches the client instead of nesting when already inside tmux.

### implement-github-issues

Opens one tmux window per selected GitHub issue, each running Claude Code in
its own worktree (`claude --worktree <n>-<slug> --permission-mode plan`) with
a prompt that asks it to investigate and produce a plan before touching any
files. Run it from inside the checkout of the repository the issues belong to.

```
implement-github-issues [options] <tmux-session> --label <label>
implement-github-issues [options] <tmux-session> <issue-number> [issue-number ...]

  -l, --label LABEL    select open issues with LABEL (repeat for AND)
  -L, --limit NUMBER   max issues from the label query (default 100)
      --attach         attach/switch to the session after launching
      --dry-run        print what would be launched
```

Examples:

```sh
implement-github-issues security-fixes --label security
implement-github-issues sprint-42 125 131 144
implement-github-issues security-fixes --label security --limit 50 --attach
```

Windows are named `i<number>-<slug>`; an issue that already has a window in
the session is skipped.

### settings.json and status line

`claude/settings.json` is the user-level Claude Code configuration: the hook
wiring above, `model: opus[1m]`, `effortLevel: high`, fullscreen TUI, and a
command status line. `claude/statusline-command.sh` renders the status line
from the JSON Claude passes on stdin: model, context usage, worktree, cost,
git branch with staged/modified counts, and 5-hour / 7-day rate-limit bars
with reset times.

Neither file is installed by the Makefile; copy them to `~/.claude/` by hand
and adjust the `statusLine.command` path.

## Shell completions

`completions/bash/<command>` and `completions/zsh/_<command>` exist for
`tmux-agents` and `implement-github-issues`. They complete subcommands,
options, agent numbers, tmux session names, and GitHub labels/issue numbers
where `gh` is available.

`tools/completion-rc` is the helper the Makefile uses to add or remove the
block that sources them from `~/.bashrc` / `~/.zshrc`. It never writes
without confirmation (or `--yes`), and prints the lines instead when there is
no terminal to ask on.

## Lima VMs

- `lima/dev-lima.yaml` - Debian 13 (trixie) arm64 cloud image, virtiofs
  mounts of `~/git` and a project directory, SSH agent forwarding, custom DNS.
- `lima/tinyidm-lima.yaml` - Debian 13 with amd64/arm64/ppc64el images and a
  daily-image fallback, `~/git` mounted at the same path inside the guest,
  every guest localhost port forwarded to the host, 4 CPUs / 8 GiB.

```sh
limactl start --name dev lima/dev-lima.yaml
limactl start --name tinyidm lima/tinyidm-lima.yaml
```
