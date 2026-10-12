# Mivu core tracking checkpoint

**Status: not achieved.** This living checkpoint separates source implementation from local, hosted, merged, and provider evidence. P1 branch work is not mainline delivery. Update this after conversational Task 3 and integration; do not use it to claim core completion.

| Core capability | Source status | Local evidence | CI / merge / live evidence | Delivery status |
|---|---|---|---|---|
| Food by text, including multiple foods | Implemented | Full local suite: 302 passed, 0 failed, 1 skipped at `5eacf91b72a83e34629d61e41604248852cac061` | PR #6 merged as `099e72694e4f27cc97b5c36453428df1f8009201`; PR run and main run each report 302/0/1 | Merged to main; live provider recognition unverified |
| Photo capture, offline recovery, persistent receipts | Implemented | Included in the same full local suite and source revision | Included in PR #6 and both hosted runs above | Merged to main; live image inference, physical camera, and Files-provider recovery unverified |
| Food correction and day totals/history | Implemented | Included in the same full local suite; synthetic engine tests use production persistence | Included in PR #6 and both hosted runs above | Merged to main; hosted simulator checks do not establish live provider behavior |
| Dated goals and stored progress records | Implemented | Combined storage/analytics covering gate: 103 passed, 0 failed, 0 skipped | Source commit `a186421ebe850bd267c957ac37766a7a5014ac87`; independently reviewed as Ship; not merged | Branch only; integration and hosted PR checks pending |
| Weight entry and correction | Implemented | Combined storage/analytics covering gate: 103/0/0; analytics covering gate: 80/0/0 | Same P1 branch evidence; not merged | Branch only; conversational weight operations are missing |
| Workout storage and history data | Implemented | Combined storage/analytics covering gate: 103/0/0; analytics covering gate: 80/0/0 | Same P1 branch evidence; not merged | Branch only; conversational workout operations are missing |
| Daily, weekly, and 30-day reports | Implemented | Analytics and shared pending-input correction covered by 80/0/0 | Source commit `fe0cbd6c20b0783e97c98fe602fc6f8c3649d755`; independently reviewed as Ship; not merged | Branch only; native UI and integration remain unfinished |
| Goals, weight, workout, and progress native UI | Partially implemented | UI work is in its first review-fix round; no final acceptance result recorded here | In a separate working checkout; not merged | In progress; finish current UI task first |
| Conversational weight, workout, and progress context/retrieval | Missing | Not started | No CI, PR, or merge evidence | P1 Task 3 remains |
| End-to-end core integration and aggregate acceptance | Missing | Not run | No final review, PR CI, or merge evidence | P1 Task 5 remains |

The P0 local evidence is from [conversational food tracking verification](2026-10-12-coach-core.md). Its hosted evidence is [PR run 38279845129](https://github.com/yakov103/mivu/actions/runs/38279845129) and [main run 38281956485](https://github.com/yakov103/mivu/actions/runs/38281956485). The P1 local counts and review states are recorded in the [P1 implementation plan](../superpowers/plans/2026-10-12-coach-p1.md). The local suites use synthetic inputs with native persistence; they do not prove real provider text or image results.

Live text/image provider behavior, owner consent, Files-provider export/restore, physical camera, VoiceOver on device, and signed-phone artifacts remain unverified. These are evidence gaps, not completed acceptance criteria.

**Owner priority:** finish the current native UI Task 4, then finish the remaining P0/P1 core work and integration. Ask the owner before starting P2 or P3. Deferred scope includes persistent coaching preferences or memory, automated coaching summaries, advanced coaching/reviews, external fitness imports, reminders, supplements, and meal planning. Do not mark this checkpoint ready or complete until required core verification and delivery evidence are recorded.
