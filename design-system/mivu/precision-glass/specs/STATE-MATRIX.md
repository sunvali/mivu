# State matrix and copy contract
Each state must exist in both light/dark and remain usable at accessibility text sizes. These are behavior contracts for the later build.

| Context / trigger | Visible state and copy | Available action | Persistence / recovery |
|---|---|---|---|
| Empty capture | "Add a photo or a meal description." | Add input; Save disabled | Keep draft |
| Local save running | "Saving..." only while committing | Prevent repeated Save | Do not dismiss early |
| Local save failed | "Couldn't save. Your input is still here." | Try again | No false receipt |
| captured | "Saved on this iPhone" | View meal | Existing ID acknowledged |
| waitingForConnection | "Waiting for connection" | Connect or reconnect when authorization missing | Resume same ID |
| analyzing | "Analyzing meal" | View saved meal | No fake percentage; do not claim estimate yet |
| awaitingReview | "Estimate ready to review" | Review estimate | Keep estimate label |
| saved | "Estimated · Reviewed" or actual provenance | Edit | Reviewed is not source verification |
| needsRetry | "Analysis couldn't finish. Your meal is saved." | Retry analysis | Idempotent retry, existing ID |
| cancelled | "Analysis stopped. Your meal is saved." | Resume/retry if supported | Capture survives |
| Missing nutrients | Em dash + "Not estimated yet" | Edit/retry as appropriate | Never convert unknown to zero |
| Empty Today | "Your first meal starts here" | Log meal | No invented sample totals |
| No goal | "No goal set" | Set goal (optional) | Hide goal ratio |
| Goal exceeded | "120 above goal" | View goal | Neutral tone; no red failure |
| Coverage unknown | "Coverage not set" | Choose coverage | No auto-completion |
| Coverage partial | "Partial day" | Edit coverage | Totals describe recorded meals only |
| Coverage untracked | "Untracked" | Record/edit coverage | Exclude from complete-day average |
| Complete with pending | "Complete · Analysis pending" | View pending meals | Exclude pending day from eligible average |
| Absent date | "No records" | Add record | Distinct from tracked zero intake |
| Zero eligible samples | "Not enough complete days" | View Diary | No average or false trend |
| Invalid numeric field | Inline field-specific error | Correct value | Save disabled; draft retained |
| Stale revision | "This meal changed while you were editing." | Review latest; keep draft | Never overwrite silently |
| Profile changes mid-edit | "The profile changed. Reopen this record." | Return to selected diary | Cancel wrong-owner mutation |
| Camera denied | "Camera access is off." | Open Settings; Photo library; Add note | Capture remains possible |
| Photo load failure | "Couldn't add this photo." | Retry/remove item | Keep other input |
| Offline network | "Your meal is saved. Analysis will resume when available." | Edit; connection action only if needed | No duplicate capture |
| Coach sending | "Saving your message..." then acknowledged state | Wait for local commit | Preserve message on failure |
| Coach ambiguous target | "Which lunch did you mean?" + relevant record choices | Choose target | No speculative change |
| Coach needs quantity | Specific question "How much rice?" | Reply/edit manually | Do not invent a precise amount |
| Coach mutation failed | "The change wasn't applied." | Retry/open record | No successful receipt |
| Authorization expired | "Reconnect for meal analysis" | Reauthorize | Captures unaffected |
| Usage limit | Actual provider notice, no invented reset time | Usage settings; try later | Retain saved captures |
| Connecting cancelled | "Not connected" | Continue with ChatGPT | No data loss |
| Model changed | Current actual model | Resume when authorized | Cancel stale worker result |
| No backup folder | "No backup folder selected" | Choose folder; Export | Local diary unaffected |
| Backup writing | "Backup pending" | View status | No remote-sync claim |
| Folder acknowledged | "Saved to backup folder" + time | Export/change folder | Remote upload unconfirmed |
| Folder unavailable | "Backup pending. Your local diary is saved." | Retry/change folder | Preserve diary |
| Backup conflict | "Backup copies conflict." | Export copy; resolve folder | Keep both, do not overwrite |
| Export cancelled/failed | "Export was not saved." | Export again | Local diary preserved |
| Archive invalid | "Couldn't read this diary archive." | Choose another | No mutation |
| Archive wrong existing profile | "Select that profile before restoring." | Return/select profile | No cross-profile replace |
| Restore preview | Explain replacement vs separate import | Restore/Cancel | Mutate only after validation/confirmation |
| Delete requested | Name record and scope | Delete/Cancel | Destructive style only at commit |
| Settings conflict | "Settings changed. Your draft is preserved." | Use latest saved settings | No silent overwrite |

## Copy style
Direct, factual, calm. Use "recorded", "estimated", "reviewed", "saved on this iPhone" and "complete day" precisely. Avoid "perfect", "healthy score", "guilt-free", "crushed it", "synced everywhere", "100% accurate" or medical reassurance.

Use a unit with every quantity. Format kcal as whole numbers for summaries; retain supported decimal precision for ingredient editing. Localize numeric separators while keeping supported language English. Dates show weekday and month in interface, canonical local-date strings remain in storage.

## State transitions
draft -> local commit -> captured -> waiting/analyzing -> awaitingReview -> saved.
Any analysis step can need retry or stop without undoing capture. Review and correction write through current domain APIs and revision guards. A separate backup status never replaces the meal lifecycle.

## Analytics contract
Period average includes only complete days without pending records and with a known value for the relevant nutrient. Each nutrient can have a different sample count; report its denominator. A complete-day count is not automatically an eligible-sample count. Preserve current analytics for goal adherence and weight windows; do not redesign calculations as part of the UI.
