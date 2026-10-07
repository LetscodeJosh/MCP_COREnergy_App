# 🛡️ 24/7 Production Resilience & Failover Architecture Specification

## Executive Summary
This document establishes the **Enterprise High Availability & Resilience Standard** for the **MCP Profiling App (Flutter Mobile)** and the **Territory Reconfiguration Web Portal**, ensuring uninterrupted, 24/7 field operation when deployed in production and connected to **ERPNext v15 (Frappe Framework)**.

Even if code and APIs are left untouched for months or years, these architectural safeguards prevent system downtime, data loss, API drift failures, and session lockouts.

---

## 🏗️ 1. Core Production Vulnerabilities & Architectural Countermeasures

| Vulnerability / Risk Scenario | Real-World Impact if Left Untouched | Built-in Countermeasure & Failover Mechanism |
| :--- | :--- | :--- |
| **1. Frappe Session Cookie Expiration** | Frappe session cookies (`sid`) expire after days/weeks, resulting in `401 Unauthorized` or `403 Invalid Session`. | **Autonomous Session Renewal Interceptor**: When a `401` or `403` occurs, the app silently re-authenticates in the background with encrypted stored credentials, obtains fresh session cookies and CSRF tokens, and re-executes the user's action with zero UI disruption. |
| **2. ERPNext Server Maintenance / Reboots** | Backup jobs, SSL renewal (Let's Encrypt every 90 days), or server reboots return `502 Bad Gateway` or `504 Gateway Timeout`. | **Cache-Aside & Stale-While-Revalidate Engine**: `FrappeRepository` automatically writes successful queries to local file storage. If ERPNext is unreachable or throws a 5xx error, the app serves cached records with an offline indicator so MedReps can search and profile doctors without interruption. |
| **3. Intermittent Field Cellular Drops** | MedReps in hospital basements or rural areas lose network connectivity during doctor profiling submissions. | **Zero-Data-Loss SQLite Offline Queue**: Submissions are written to SQLite (`DbHelper`) immediately. The background auto-sync timer monitors `/api/method/ping` and automatically flushes the queue as soon as internet connectivity returns. |
| **4. Frappe v15 DocType Schema Drift** | ERPNext administrators add or adjust custom fields in Frappe Desk months later, causing rigid JSON deserializers to crash. | **Enterprise `DataSanitizer` & Null-Safety Guard**: Deserializers (`COREnergyEngage.fromJson`, `Engagement.fromJson`, `Institution.fromJson`) use defensive parsing (`?? ''`, `?? []`, safe type conversions). Unknown fields are ignored safely without runtime exceptions. |
| **5. Host Server Reboot for Web App** | If SFE laptop or server restarts due to Windows Update, the portal stops serving requests. | **Watchdog Daemon & Standalone SPA Resilience**: Built-in auto-restart loop in `web_simulator/server.ps1` recovers the server. Even if disconnected, the Single Page Application operates client-side with `localStorage` persistence and UTF-8 BOM CSV exports. |
| **6. Workflow Lockouts (`Existing` vs `New HCP`)** | Improper workflow handling can cause "Not Saved" or permission rejections on the ERPNext server. | **Strict Server-Aligned Workflow**: Retains `doc.profile_action=="Existing HCP"` (automatic direct merge) and `doc.profile_action=="New HCP"` (managerial approval) 1:1 with Frappe `HCP Profile Submission WF`. |

---

## 📱 2. Mobile App (Flutter) Resilience Blueprint

### A. Defensive Repository Layer (`FrappeRepository<T>`)
Every entity (`COREnergy Engage`, `Engagement`, `Institution`, `Specialization`, `PSGC Location`) is managed through the enhanced repository:
```dart
// 1. Strict 15-second timeout on all network requests (never hangs indefinitely)
// 2. Up to 2 automatic retries on transient network drops with exponential backoff
// 3. Automatic local cache persistence on success (cacheKey: frappe_<docType>_list.json)
// 4. Automatic cache fallback when server is unreachable or offline
```

### B. Auto-Sync & Ping Mechanism
```dart
Timer.periodic(const Duration(seconds: 5), (timer) async {
  final isOnline = await checkOnlineStatus(); // GET /api/method/ping (4s timeout)
  if (isOnline) {
    final pending = await DbHelper.getPendingEngagements();
    if (pending.isNotEmpty) {
      await syncOfflineData();
    }
  }
});
```

---

## 💻 3. Territory Reconfiguration Web Portal 24/7 Resilience

### A. Resilient Authentication Engine
- Supports live authentication against `https://dev.pmii-marketing.com/api/method/login`.
- If remote ERPNext is unreachable or credentials are local SFE/Admin tokens, grants authorized session without blocking the user.
- Handles CORS preflight `OPTIONS` requests cleanly.

---

## 🔒 4. Maintenance & Operations Runbook

1. **ERPNext Server Upgrades**: When upgrading Frappe or ERPNext, the mobile app and web app require NO code modifications because all payloads are normalized defensively.
2. **Offline Field Audits**: Field reps can complete full profiling cycles offline. All records synchronize in FIFO order upon network reconnection.
3. **Database Backups**: Mobile SQLite database (`pims_mcp_offline.db`) is stored in the app's sandboxed document directory and survives app restarts.
