# Feature parity: iOS and Android

Parity baseline: commit `dd5e8c34`. Rows with scope `baseline` block the first
Android release; `post-baseline` rows are tracked only. Design and rules:
[Android app design](superpowers/specs/2026-10-23-android-app-design.md). The
checker is `scripts/ci/parity.py`, run by CI.

Statuses: `done`, `partial`, `pending`, `equivalent`, `blocked`, `n/a`. `done`
and `equivalent` need a verification record that names the passing tests and a
40-character source SHA. Evidence format:
`iOS: <record> [TestA, TestB] · Android: <record> [TestC]`.

## Features

| ID | Feature | Scope | Spec | iOS | Android | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| onboarding | Onboarding hosted by Pip | baseline | [spec](superpowers/specs/2026-10-20-onboarding-design.md) | partial | pending | - | No verification record at the baseline. |
| today | Today summary, meals, Log meal | baseline | [spec](superpowers/specs/2026-10-17-experience-redesign.md) | partial | pending | iOS: docs/verification/2026-10-19-summary-cards-navigation.md | Record gives seven UI methods cumulatively, not named; no full-suite pass. |
| day-rollover | Day rollover and morning check-in | baseline | [spec](superpowers/specs/2026-10-20-day-rollover-design.md) | partial | pending | - | No verification record at the baseline. |
| diary | Diary week strip and meal detail | baseline | [spec](superpowers/specs/2026-10-20-diary-redesign-design.md) | partial | pending | iOS: docs/verification/2026-10-21-diary-redesign.md | Record has no source SHA. |
| meal-edit | Meal composer, manual nutrition, correction | baseline | [spec](superpowers/specs/2026-10-19-reliable-entry-design.md) | partial | pending | iOS: docs/verification/2026-10-19-reliable-entry.md | Record is in progress with failing runs. |
| coach-capture | Coach text and photo capture, saved before analysis | baseline | [spec](superpowers/specs/2026-10-12-conversational-coach-design.md) | partial | pending | iOS: docs/verification/2026-10-12-coach-core.md | Record names no individual passing tests. |
| coach-history | Coach chat history, 100-exchange window, jump to latest | baseline | [spec](superpowers/specs/2026-10-18-coach-chat-history-design.md) | partial | pending | iOS: docs/verification/2026-10-18-coach-chat-history.md | Record mixes passing and failing runs. |
| coach-reply | Coach reply to a message or Diary record | baseline | [spec](superpowers/specs/2026-10-21-coach-reply-design.md) | done | pending | iOS: docs/verification/2026-10-21-coach-reply.md [CoachReplyTests, CoachReplyComposerTests, CoachReplyContextTests, CoachReplyUITests] | Record lists pre-existing unrelated failures. |
| coach-context | Coach understands intent and acts on it | baseline | [spec](superpowers/specs/2026-10-21-coach-context-design.md) | partial | pending | iOS: docs/verification/2026-10-21-coach-context.md | Record has no source SHA. |
| coach-voice | Coach voice logging and redesigned composer | baseline | - | partial | pending | - | No verification record at the baseline. |
| coach-edit-parity | Every manual edit also works through Coach | baseline | [doc](development/coach-edit-parity.md) | partial | pending | iOS: docs/verification/2026-10-14-coach-edit-parity.md | Record says later patches were not fully re-verified. |
| progress | Progress goals, weight, charts, plateau readiness | baseline | [spec](superpowers/specs/2026-10-23-progress-insights-design.md) | partial | pending | - | No verification record at the baseline. |
| chatgpt-connection | ChatGPT connection: sign-in, models, revoke | baseline | [spec](superpowers/specs/2026-10-11-food-logger-design.md) | partial | pending | iOS: docs/verification/2026-10-11-native-connection-proof.md | Proof covers sign-in only; live provider behavior unverified. Android gated by Phase 0. |
| openai-consent | OpenAI data consent | baseline | [spec](superpowers/specs/2026-10-11-food-logger-design.md) | partial | pending | - | No verification record at the baseline. |
| settings | Settings, profiles, daily targets | baseline | - | partial | pending | - | No verification record at the baseline. |
| folder-backup | Backup to a chosen folder | baseline | [spec](superpowers/specs/2026-10-11-food-logger-design.md) | partial | pending | iOS: docs/verification/2026-10-12-native-mvp-acceptance.md | Files-provider journey unverified. Android: Drive folder picking unverified. |
| archive | Archive export and import | baseline | [spec](superpowers/specs/2026-10-11-food-logger-design.md) | partial | pending | iOS: docs/verification/2026-10-12-native-mvp-acceptance.md | Automated tests passed; provider journey unverified. |
| reports | Diary reports as PDF or CSV | baseline | [spec](superpowers/specs/2026-10-11-food-logger-design.md) | partial | pending | iOS: docs/verification/2026-10-12-core-checkpoint.md | Record is an earlier checkpoint. |
| analyzed-notification | Notification when a meal is analyzed | baseline | - | partial | pending | - | No verification record at the baseline. |
| quick-capture | Quick capture: Shortcuts, Action button, quick actions | baseline | [spec](superpowers/specs/2026-10-21-pip-entry-points-design.md) | partial | pending | - | No verification record at the baseline. |
| widgets | Widgets: calories, Log Food, Coach | baseline | [spec](superpowers/specs/2026-10-20-widget-design.md) | partial | pending | iOS: docs/verification/2026-10-20-widgets.md | Record has no source SHA. |
| live-activity | Live Activity: calories left in Dynamic Island | baseline | [spec](superpowers/specs/2026-10-21-dynamic-island-design.md) | partial | n/a | iOS: docs/verification/2026-10-21-dynamic-island.md | Android: the calories widget covers glanceable calories left; Live Updates suit time-bound tasks, not an all-day counter. Revisit if build research shows otherwise. |
| pip | Pip rig, gestures, blink, moments | baseline | [spec](superpowers/specs/2026-10-19-pip-layered-rig-design.md) | partial | pending | iOS: docs/verification/2026-10-19-pip-layered-rig.md | Record has one SHA and no named passing tests. |
| app-icon | App icon (Pip portrait) | baseline | - | partial | pending | iOS: docs/verification/2026-10-20-pip-app-icon.md | Asset-only change; no named test. |
| sample-mode | Sample mode (debug launch flag) | baseline | [spec](superpowers/specs/2026-10-12-sample-mvp-addendum.md) | partial | pending | - | No verification record at the baseline. |
| store-readiness | Store readiness: privacy and review requirements | baseline | [doc](development/app-store-submission.md) | partial | pending | - | Android: Play Data safety, policy and listing items. |
| report-coach-reply | Report a Coach reply | baseline | - | pending | pending | - | Only if the Play AI-generated content policy applies; not on iOS. |
| siri-coach | Siri prompts sent to Coach | post-baseline | [spec](superpowers/specs/2026-10-23-siri-coach-design.md) | done | pending | iOS: docs/verification/2026-10-23-siri-coach.md [TellCoachTests, CoachUITests, QuickLogUITests] | Merged after the baseline (#54). |
| connection-plan-use | ChatGPT plan use shown in Coach, confirmed once | post-baseline | - | partial | pending | - | Merged after the baseline (#52); no verification record. |
| progress-chart-first | Chart-first Progress with Pip presenting | post-baseline | [spec](superpowers/specs/2026-10-23-progress-insights-design.md) | partial | pending | iOS: docs/verification/2026-10-23-progress-insights.md | Merged after the baseline (#51); record has no source SHA. |
| coach-on-device | On-device Coach fallback, ChatGPT recommended | post-baseline | - | partial | pending | - | Merged after the baseline (#49); Android equivalent undecided. |
| profile-delete | Delete any local profile from the profiles list | post-baseline | - | partial | pending | - | Merged after the baseline (#50); no verification record. |
| coach-floating-composer | Composer floats over chat, camera in the field | post-baseline | - | partial | pending | - | Merged after the baseline (#46); no verification record. |
| pip-entry-points | One way to log with Pip, quoted Ask Pip | post-baseline | [spec](superpowers/specs/2026-10-21-pip-entry-points-design.md) | partial | pending | iOS: docs/verification/2026-10-21-pip-entry-points.md | Merged after the baseline (#45); record has no full source SHA. |
