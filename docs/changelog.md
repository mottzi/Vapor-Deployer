# Unreleased changes main...HEAD(dev)

### Mist Frontend Resources

- Replace Deployer's committed `mist.js` and `morphdom.js` mirrors with Mist's typed `MistAssets` API. Both browser runtimes are now embedded in the Deployer executable from the exact Mist revision recorded in `Package.resolved`, so source/release installs, updates, and executable rollback carry matching Swift and JavaScript runtimes without a separate copy or resource bundle.
- Preserve the existing panel asset URLs while serving the embedded bytes with the JavaScript content type, `Cache-Control: no-cache`, strong SHA-256 ETags, `GET` and `HEAD` support, and conditional `304 Not Modified` responses.
- Remove `Public/deployer/mist.js` and `Public/deployer/morphdom.js`; Deployer's `Public` and `Resources` payloads now contain only Deployer-owned assets.

### Operator Interface & UX

- Fix cleared Deployer and target-app log streams reappearing after toggling Wrap or another component render. Static Mist streams could be registered under separate `undefined` and `null` model-ID keys, leaving a stale retained snapshot behind after Clear. The vendored Mist client now canonicalizes absent model IDs before buffering stream content, so cleared consoles remain empty until new log lines arrive. The fix was deployed in commit `26b65a3` and verified on the VPS.
