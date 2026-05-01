# Deployer

**A simple CI/CD tool for Swift server applications that deploys automatically when changes are pushed to an app's GitHub repository.**

With just one setup command, Deployer gets your server ready. It installs Swift, configures Nginx and GitHub webhooks, issues SSL certificates and keeps your app running on the latest commit. A live web panel shows every deployment as it happens. It streams build output, updates in real-time and provides start and stop buttons for your app.

<img width="957" height="880" alt="Deployer Panel" src="https://github.com/user-attachments/assets/ab34c33f-d84e-4893-a944-cc2b69401829" />

<br>

1. Code change is pushed to remote repository.
2. Push event is intercepted on server using webhooks.
3. Deployment pipeline is initiated:
     - pull changes from remote repository
     - build executable
     - move executable
     - check for queued deployments
     - re-run latest queued deployment
     - restart application

## Setup

Before setup, you will need:

- Ubuntu server with root access.
- Domain pointing to the server.
- Swift app in GitHub repository.

SSH into your server and run:

```bash
sudo bash <(curl -sSL https://mottzi.codes/deployer/setup.sh)
```

Deployer will walk you through the setup interactively, prompting for configuration (Press enter for defaults).

- Swift is installed via Swiftly.
- Nginx with TLS/SSL certificates via Let's encrypt.
- SSH deploy key is generated for registration with GitHub.
- GitHub webhook is created to watch for pushes.

Once setup completes, your app is live and Deployer is listening for pushes on main.

## Deployer Control

Setup installs **`deployerctl`** on the server. Example usage:

```bash
sudo deployerctl start  # starts deployer and app
sudo deployerctl status app 
sudo deployerctl stop deployer
deployerctl version
deployerctl help
```

| Action |  |
| --- | --- |
| `status` |
| `start` |
| `stop` |
| `restart` |
| `logs` | Ctrl-C to exit |
| `version` | Print the deployer version |
| `setup` | Rerun deployer setup |
| `update` | Update deployer |
| `remove` | Tear down deployer |
| `help`|
<!-- | | | -->

### Configuration

Runtime settings live in **`deployer.json`**, in the same directory as the `deployer` executable. For a default install, that is '/home/vapor/deployer/deployer.json'. Setup writes the first version; you can edit it when you need different settings. Restart Deployer after making changes.

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

## Deployment

The webhook endpoint validates HMAC-SHA256 signature before touching the queue, rejecting unsigned or malformed payloads. Manual deployment mode (default) waits for you to trigger a deployment on the web panel by pressing the play button. Automatic mode deploys a push instantly.

The pipeline runs three stages in sequence:

1. `git fetch` + detached `HEAD` checkout at the exact SHA.
2. `swift build -c <release|debug>`, output streamed live to connected clients.
3. Binary moves from `.build/` to `deploy/<app>`. 

A successful run marks the deployment `deployed`, demotes the previous live entry back to `success`, restarts the app and persists the full build transcript. The previous binary is backed up; if the move fails, rollback is automatic.

The `Queue` actor serializes all deployments so only one build runs at a time. While the queue is locked, the panel shows a live Locked / Unlocked badge. While a build is running, subsequent pushes are recorded as `canceled`. When the current job finishes, the queue drains to the newest canceled entry, skipping everything in between. 

Deployments are persisted with [Fluent](https://github.com/vapor/fluent) on SQLite; Deployer itself is built on [Vapor](https://github.com/vapor/vapor). On first launch, Deployer seeds the database with the latest commit in the target repository so the panel doesn't start empty. The `is_live` flag tracks the active deployment currently deployed and running on the server.

Deployer's panel uses [Mist](https://github.com/mottzi/Mist) to power real-time database driven UI updates over websockets, reflecting state change without polling or page reloads.

