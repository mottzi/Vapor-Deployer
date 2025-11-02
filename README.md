This repository demonstrates one possible approach of implementing a simple CI/CD system that automatically self-deploys Swift web server applications when changes are pushed to the remote github repository. It uses the Vapor framework. 

> [!WARNING]
> This is a proof-of-concept implementation and ready for production! 

## Overview

1. Local changes are pushed to remote github repository
2. Push event is intercepted using webhooks
3. Deployment pipeline is initiated:
     - pull changes from remote repository
     - build executable
     - move executable
     - check for queued deployments
     - re-run latest queued deployment
     - restart application

The system implements a simple deployment dashboard. This dashboard uses the "HTML over the wire" paradigm to provide real time status updates without requiring page reloads.

## Demo

In this demo video, I push several build versions in rapid succession, changing the response string of the /test endpoint with each push. 

You can see how the successive push events are processed into the deployment queue and how their statuses change. When a new push event is registered while the previous deployment is still running, the system will temporarily cancel that push event, re-trying when the pipeline is freed up.

After the last deployment has finished processing, you can see the correct output of the /test endpoint.

https://github.com/user-attachments/assets/2258e6db-c42a-4ff6-9d8f-2a4def7b4e34

## Architecture

### Deployment Pipeline

The system processes deployments through the following sequence:

1. **Webhook Reception**: GitHub sends a push event to the webhook receiver endpoint `/pushevent`. The receiver validates the signature using a secret environment value.

2. **Deployment Creation**: Upon successful validation, the system creates a new deployment record in the SQLite database with status "running" or "canceled" depending on whether another deployment is already in progress.

3. **Pipeline Execution**: If the deployment status is "running", the pipeline executes the deployment process:
   - Performs a git pull to fetch the latest code
   - Builds the application using Swift build tools
   - Moves the built executable to the deployment directory
   - Updates the deployment status in the database

4. **Real-time Updates**: As the deployment status changes while moving through the steps above, the database middleware captures these changes and broadcasts them via WebSockets to all connected dashboard clients.

5. **Queue Processing**: After a successful deployment, the system checks for any queued (canceled) deployments and automatically re-initiates the latest one.

6. **Application Restart**: If no queued deployments exist, the system restarts the application to apply the latest changes.

### Deploymet Status

The system maintains a database of deployments and their commit messages, duration, and current status which can be one of the follwing:

- **running**: Deployment is in progress
- **canceled** / **queued**: Deployment was queued (another deployment was running)
- **success**: Deployment completed successfully
- **failed**: Deployment failed
- **stale**: Deployment has been running for too long (>30 min)
- **deployed**: Current active deployment

### Files

**Configuration**

- **deployment.swift**
  Registers all routes related to deployment functionality, including the GitHub webhook endpoint, the deployment panel endpoint, and the websocket endpoint for real time panel updates

**Deployment**

- **Deployment.swift**: Defines the core deployment model, database schema, and helper methods for data presentation.

- **DeploymentWebhook.swift**: Processes incoming GitHub webhook, validates request signature, and initiates the deployment process.

- **DeploymentPipeline.swift**: Implements the deployment pipeline logic, handling the sequence of operations (pull, build, move, restart) and deployment queue management.

- **DeploymentClients.swift**: Manages WebSocket client connections with thread-safe operations for broadcasting deployment updates.

- **DeploymentListener.swift**: Database middleware that intercepts deployment status updates and broadcasts changes in real time to connected clients.
  
- **DeploymentMessage.swift**: Defines the message protocol for WebSocket communication between server and clients.

**Frontend Templates**

- **panel.leaf**: Main dashboard template that displays the deployment list and current deployment status.

- **row.leaf**: Template fragment for rendering individual deployment entries in the dashboard.

**Frontend JavaScript**

- **panel.js**
  Client-side JavaScript that establishes WebSocket connections and updates the UI/DOM in real-time as deployment states change.
