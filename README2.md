# Deployer

Deployer is a small server you install on your VPS. Once it's running, every push to your Swift app's GitHub repo shows up in a live panel in your browser. You watch the build stream as it happens, hit start or stop with a button, and roll back to any past version with one click.

Setup is a single command. The whole thing is one Swift binary and a SQLite file. No Docker, no YAML, no third-party CI to wire up.

[Watch it work](https://mottzi.codes/deployer_demo_original.mp4).

<img width="833" height="952" alt="Deployer Panel" src="https://github.com/user-attachments/assets/32b7fcf6-5d08-4b49-8e45-93d42bb25b76" />

<br>

What happens on a push:

1. GitHub fires the webhook to your server.
2. Deployer verifies the signature, then queues the commit.
3. The pipeline checks out the exact SHA, optionally runs `swift test`, and builds.
4. The new binary swaps in atomically, with the previous one kept as a backup.
5. The app restarts. The panel updates live the whole way.

## Setup

You need:

- An Ubuntu server with root access.
- A domain pointing at it.
- A Swift app in a GitHub repository.

SSH in and run:

```bash
bash <(curl -sSL https://mottzi.codes/deployer/setup.sh)
```

Setup is interactive. Press enter through the prompts to take the defaults, or override what you want. Behind the scenes it:

- Installs Swift via Swiftly.
- Sets up Nginx with TLS certificates from Let's Encrypt.
- Creates a dedicated service user and an SSH deploy key for GitHub.
- Registers the GitHub webhook for pushes on your branch.
- Hardens SSH and installs `deployerctl` for server-side control.

When setup finishes, your app is live and the panel is listening for the next push.

## What it does

### Live build output in the panel
Every `git fetch`, `swift build`, and binary swap streams into the panel as it happens. No more tailing logs over SSH while you wait. If the build fails, the full transcript stays attached to the row so you can read it back later.

### Manual or automatic deploys
Pick the mode that suits the project. **Manual** records pushes as rows and waits for you to click play. **Automatic** deploys every push the moment it lands. You can switch between them later without re-running setup.

### Start, stop, restart from the browser
The target app's service has buttons next to it on the panel. No SSH session for a routine restart.

### One-click rollback to any past build
Every successful build is archived on disk. If something breaks, restore an older binary from its row and the service swaps to it. No rebuild needed, no waiting.

### Run `swift test` on demand
Tests can run automatically before every build, or only when you press the Test button on a row. Results stick to the commit. If a commit already passed once, the next deploy skips re-running the same tests.

### Edit the target's environment variables in the panel
Open the settings page, edit your app's `.env`, hit save. The file is validated and written atomically. Hit restart and the change is live. No more SSHing in to edit a unit file.

### deployerctl for the server side
A small wrapper script for the things that belong in a terminal: starting and stopping services, tailing logs, rerunning setup, updating the deployer itself. Self-updates roll back automatically if the new version fails to come up.

## Under the hood

A few details that matter if you care about how it works.

- **Serialized build queue.** A `Queue` actor makes sure only one build runs at a time. While a build is in flight, new pushes are recorded as `canceled`. When the build finishes, the queue jumps to the newest canceled push and skips everything in between, so you always end on the latest commit and never queue up stale work.
- **Atomic binary swap with auto-rollback.** Before the new binary moves in, the live one is set aside as `.old`. If the move fails for any reason, the previous binary is restored before the error bubbles up.
- **Boot-drain replay.** If the server reboots or the deployer crashes mid-deploy, the next start picks up the most recent stranded push and resumes from there.
- **Signed webhooks only.** Every incoming webhook is verified with HMAC-SHA256 against the secret generated at setup. Unsigned or malformed payloads are rejected before they reach the queue.
- **Websocket-driven panel.** Real-time updates run on [Mist](https://github.com/mottzi/Mist), which pushes database changes to connected clients. No polling, no page reloads. Status badges, row transitions, and live build streams all share the same channel.
- **Stack.** Built on [Vapor](https://github.com/vapor/vapor) with [Fluent](https://github.com/vapor/fluent) on SQLite, served through Leaf templates.

## deployerctl

After setup, `deployerctl` is on the server's `PATH`. Most actions need `sudo`.

```bash
sudo deployerctl status              # show service status for deployer + app
sudo deployerctl restart app         # restart just the target app
sudo deployerctl logs deployer       # follow deployer logs (Ctrl-C to exit)
sudo deployerctl update              # update deployer to the latest release
```

| Action |  |
| --- | --- |
| `status` | Service status (deployer, app, or both) |
| `start` / `stop` / `restart` | Service lifecycle |
| `logs` | Tail the on-disk log file (Ctrl-C to exit) |
| `journal` | Recent systemd journal entries (systemd only) |
| `update` | Update the deployer, with auto-rollback on failure |
| `config` | View or change a field in `deployer.json` |
| `setup` | Rerun setup interactively |
| `remove` | Tear down the install |
| `version` | Print the deployer version |
| `help` | Print usage |

Targets are `deployer`, `app`, or `all` (default).

## Configuration

Runtime settings live in `deployer.json`, beside the deployer binary. A default install puts it at `/home/vapor/deployer/deployer.json`.

```json
{
    "buildFromSource": false,
    "dbFile": "deployer.db",
    "deployerDirectory": ".",
    "panelRoute": "/deployer",
    "port": 8081,
    "serviceManager": "systemd",
    "socketPath": "/deployer/ws",
    "target": {
        "appPort": 8080,
        "buildMode": "release",
        "deploymentMode": "manual",
        "directory": "../apps/MyProduct",
        "name": "MyProduct",
        "pusheventPath": "/pushevent/MyProduct"
    }
}
```

Most fields are wired into the live system at setup time (Nginx, systemd unit, clone path, webhook secret). Editing them by hand will drift the config from the install.

Six fields are safe to change at runtime and have a CLI for it:

```bash
sudo deployerctl config target.deploymentMode automatic
sudo deployerctl config target.testing true
```

The runtime-editable set: `deployerBranch`, `target.branch`, `target.buildMode`, `target.deploymentMode`, `target.binaryBehaviour`, `target.testing`. Each edit is validated against the same checks the deployer runs at boot, and you're offered a restart so the change goes live right away.

For anything else, just rerun setup:

```bash
sudo deployerctl setup
```

Setup remembers your previous answers and offers them as defaults. Changing one value is a matter of pressing enter through the rest.

## Limitations

A short list of things Deployer deliberately does not do:

- **One Ubuntu VPS at a time.** Setup provisions a single host with `apt`, systemd or supervisor, Nginx, and Let's Encrypt. No clusters, no Kubernetes, no macOS hosts.
- **One target per install.** A deployer manages one app. If you have two apps, run a second deployer for the other one.
- **One branch per target.** Pushes on other branches are ignored. No PR previews or per-branch environments today.

The smaller surface is most of the point. If your needs fit inside it, the whole system is something you can read and understand in an afternoon.
