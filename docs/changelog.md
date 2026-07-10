# Unreleased changes main...HEAD(dev)

### Operator Interface & UX

- Fix cleared Deployer and target-app log streams reappearing after toggling Wrap or another component render. Static Mist streams could be registered under separate `undefined` and `null` model-ID keys, leaving a stale retained snapshot behind after Clear. The vendored Mist client now canonicalizes absent model IDs before buffering stream content, so cleared consoles remain empty until new log lines arrive. The fix was deployed in commit `26b65a3` and verified on the VPS.
