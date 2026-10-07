# Critical Project Rules & Workflow Constraints

## 📋 Core App Workflow & Architecture Standard

### 1. The Two-Tier Masterlist Architecture
* **`COREnergy Engage Copy` / `COREnergy Engage` DocTypes**: Primary account and institution tracking for COREnergy profiling.
* **`Successful COREnergy Engagement` & `Unsuccessful COREnergy Engagement` DocTypes**: Geotagged field engagement logs (visit logs, photo evidence, geolocation, sales rep attribution, and call outcomes).
* **`Institution` DocType**: Universal institutional masterlist (4,006+ hospitals, clinics, and accounts) linked across engagement and profiling flows.

### 2. Application Workflow Rules
1. **Engagement Creation & Reporting**:
   * Successful calls route to `Successful COREnergy Engagement`.
   * Unsuccessful calls route to `Unsuccessful COREnergy Engagement` with mandatory latitude/longitude coordinates and server-validated reason options (`Prior appointment or letter needed`, `Contact not available`, `Company no longer operational`, etc.).
2. **Offline-First Resilience**:
   * All creations and updates write to SQLite (`DbHelper`) and local cache files (`engagements_cache.json`, `corenergy_engages_cache.json`, `institutions_cache.json`).
   * The application NEVER fails or crashes when disconnected; all transactions queue locally and auto-sync in FIFO order upon reconnect.

---

## 🧹 Mandatory Repository Cleanliness & Organization Standard

1. **Zero Clutter in Repository Root**:
   * The repository root must strictly contain ONLY core project configuration files: `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `README.md`, `CHANGELOG.md`, `VERSION`, `AGENTS.md`, `.gitignore`, `.metadata`.
2. **Dedicated Directories**:
   * **`docs/`**: All architectural specs, failover guides, and documentation.
   * **`releases/`**: All production APKs, IPAs, and release build artifacts.
   * **`scripts/`**: All Python maintenance, migration, and inspection scripts.
   * **`web_simulator/`**: Interactive browser PWA simulator, assets, and local server (`server.ps1`).
   * **`assets/`**: Bundled fallback JSON databases and image assets.
3. **Autonomous Proactive Maintenance**:
   * Never dump temporary scripts, test logs, or build binaries into the project root.

---

## 🔢 Mandatory Semantic Versioning & Release Tracking Standard

1. **Semantic Versioning Structure (`MAJOR.MINOR.PATCH`)**:
   * **`MAJOR` (`X.0.0`)**: Incremented for breaking changes or fundamental system upgrades.
   * **`MINOR` (`0.Y.0`)**: Incremented for new features, modules, or workflow integrations.
   * **`PATCH` (`0.0.Z`)**: Incremented (+1) for every bug fix, error removal, or stability patch.
2. **Synchronized Version Files**:
   * Whenever a version change occurs, update in lockstep:
     * `VERSION` (e.g. `V.0.2.0`)
     * `pubspec.yaml`
     * `CHANGELOG.md`
     * `releases/` (compiled APKs with verified version metadata)

---

## 🛡️ Mandatory 24/7 Production Resilience & Operational Continuity Guarantee

### 1. Operational Invariance (Untouched Code & Long-Term Deployment)
* The MCP COREnergy Profiling App and Territory Reconfiguration Web Portal are mission-critical enterprise systems requiring continuous 24/7 field operation.
* Even if the repository, codebase, or APIs remain untouched for months or years, the apps **must NEVER crash, freeze, or stop executing their complete workflows**.

### 2. Five Pillars of Production Resilience
1. **Cache-Aside & Stale-While-Revalidate Engine**:
   * All ERPNext queries automatically persist to local disk cache. When ERPNext v15 is temporarily offline or unreachable, cached records are served immediately.
2. **Autonomous Session & Cookie Renewal**:
   * When Frappe session cookies (`sid`) expire (HTTP 401/403), the app silently re-authenticates in the background with stored credentials and re-executes the user's action with zero UI disruption.
3. **Strict Timeouts & Transient Error Retry**:
   * All network operations enforce strict timeouts with automatic retry and exponential backoff. Low-connectivity hospital basements never hang indefinitely.
4. **Offline-First Submission Queue (Zero Data Loss Guarantee)**:
   * Every visit, engagement, and account modification writes to local SQLite before attempting network dispatch.
   * The background auto-sync timer monitors `/api/method/ping` and flushes queued data automatically upon reconnection.
5. **Defensive Schema Sanitization**:
   * All JSON deserializers use defensive null-coalescing, safe string trimming, and safe type conversion. Any future ERPNext DocType schema additions will never crash the mobile or web applications.
