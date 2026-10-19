# Navigation and summary layout

Approved 2026-10-19: use the owner's Airbnb Profile reference for spacious
summary cards on Today, Diary and Progress; keep Coach a conversation. This
refines Mivu's Precision identity, teal interaction tint and native glass controls.
It does not copy Airbnb branding, proprietary fonts, personal profile data or
travel-specific components. The supplied screenshot is the visual reference;
the historical Airbnb article below informs component consistency.

## Four predictable destinations

| Tab | User's task |
| --- | --- |
| Today | Understand the current tracking day and capture food. |
| Diary | Find and review dated records. |
| Progress | Understand trends, goals, measurements and workouts. |
| Coach | Capture, discuss and correct records in one continuous conversation. |

Each tab keeps its native navigation state. Opening Diary from a Progress
coverage explanation selects the existing Diary tab, rather than creating a
second Diary root inside Progress. Returning to Progress shows its report.
Settings returns to the originating section. Coach links remain explicit
cross-tab destinations with their draft and source context preserved.

A record opens as a detail within its destination. Editing uses the existing
native form/sheet with Cancel and Save. This task does not introduce a router,
additional tabs, a sidebar, or a new data hierarchy.

## Content hierarchy

Use one card for one meaningful summary or chart. Related facts stay together,
with generous separation between groups. Repeated meal/day/measurement rows
retain their native list behavior and meaningful grouping. Avoid nested cards
or a separate tile around each number. Existing semantics distinguish unknown,
partial and complete data; color never substitutes for those labels.

Coach keeps plain assistant prose and one compact committed receipt. The
48-point down-arrow button has no visible text and keeps the spoken “Jump to
latest” label. It remains a native button owned by the table so dragging over it
continues to scroll normally. Paging, stationary anchors and bounded loading
are unchanged.

## Research applied

- [Apple: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
  describes peer destinations that retain the navigation state of each section.
  Applied here: four stable roots and no duplicate Diary root inside Progress.
- [Apple: Explore navigation design for iOS](https://developer.apple.com/videos/play/wwdc2022/10001/)
  explains clear hierarchy, orientation and native return navigation. Applied
  here: titles match their selected destination and record details have an
  unambiguous return path.
- [Airbnb Design: Building a Visual Language](https://medium.com/airbnb-design/building-a-visual-language-behind-the-scenes-of-our-airbnb-design-system-224748775e4e)
  describes consistent components defined by purpose and required content.
  Applied here: shared summary-card treatment and the same spacing/type rules
  across the three summary screens, while conversation remains a different task.

The user's reported Progress-to-Diary tap sequence was observed on an older
physical build. Source inspection found a nested Diary route inside Progress;
that finding alone does not reproduce every possible cause of the report.
Native selected-tab/root and coverage-link regressions are required before
claiming the simplified route works. Simulator verification and source provenance
belong in the dated verification record; physical-device acceptance stays separate.
