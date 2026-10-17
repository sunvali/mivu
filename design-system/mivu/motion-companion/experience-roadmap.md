# Experience roadmap

Date: 17 October 2026. Status: approved Pip integration plus **deferred proposals**.
Read the [source audit](experience-audit.md) first. Existing Precision Glass
journeys remain the implementation baseline. This document does not accept
replacement screens on the owner's behalf.

## Delivery boundaries

| Phase | Scope and reason | Acceptance | Decision |
| --- | --- | --- | --- |
| P0 Current companion | Selected Pip at Today 64 pt, Coach 40 pt/48 pt minimum strip, static Settings preview; truthful saved/reviewed reactions and motion policy | Exact event/lifecycle tests, authored compatible rig/fallbacks, fresh native checks; hardware performance recorded separately | Approved by existing motion brief; implementation may proceed |
| P1 Clarity | A1 review receipt, then separately considered A2 contextual recovery, A3 semantic error color and A5 date readability | Same record/state semantics, retained drafts, keyboard/VoiceOver/error checks in both appearances | A1 approved within Pip; other changes proposed/deferred |
| P2 Find and correct | J5 meal-text search decision; J3 action hierarchy and focused estimate presentation | Concrete journey boards/storyboard; explicit matching, correction and stale-state semantics; owner review before behavioral work | Deferred; no search or wholesale review replacement in Pip PR |
| P3 Report and setup | J6 coverage comprehension; J7 destination summaries and cancellation copy | Native evidence establishes actual friction, then separate bounded per-flow plan | Deferred; analytical/profile/backup contracts remain authoritative |

Pip identity is settled. Production turnaround, seven posed static appearance
pairs, actual 40/64/80-point proofs, editable rig and exported asset belong to
the asset-authoring task. Existing concept sheets are references, not completed
production or a new character-choice gate.

## Journey proposals and preserved hierarchy

| Journey | Concrete need | Proposed hierarchy / access | Feedback and replacement boundary |
| --- | --- | --- | --- |
| J1 Today | Read day and saved state quickly | Date + fixed Pip slot, recorded summary/goal/coverage, meals, weight; retain bottom Log meal and four tabs | Local receipt remains linked; no dashboard rewrite; date readability deferred |
| J2 Capture | Understand input saved before estimate accepted | Native sheet: note/photos → waking day/review preference → toolbar Save | Preserve draft/failure; explain review separately; replacement capture wizard deferred |
| J3 Review/correction | Know whether acceptance committed and which record changed | Proposal totals/items → Mark reviewed; committed items/provenance; scoped actions | Native success text after commit; A4 consolidation proposed only; no invented rollback |
| J4 Coach | Save immediately and recover without losing reading position | Conversation/linked receipts → fixed Pip/status strip → single composer | Same history paging/follow semantics; contextual action design deferred |
| J5 Diary | Find an older record without confusing missing days with zero | Date lookup → recorded day → meal; historical Add to this day | Date filter retained; text search needs separate design/implementation decision |
| J6 Progress | Distinguish recorded chart from eligible average | Period → average/denominator → chart + text data → weight/workout/goals → coverage detail | No celebratory metric feedback; no calculation or chart-framework replacement |
| J7 Settings | Distinguish local diary, provider and backup state | Profile → setup destinations → support; retain root sheet/native pushed detail | Static Pip row/name; no second fake character; setup reordering/restore redesign deferred |

Native interaction discipline from Apple, Google, Uber and Instagram is a
quality aspiration: immediate feedback, predictable back, explicit state and
stable reading context. This is neither cloned branding nor a measured product
equivalence claim. Native iPhone conventions and Mivu's privacy/data contracts
take precedence over imported interaction patterns.

## State and adaptation requirements

The proposed spec's [state matrix](../../../docs/superpowers/specs/2026-10-17-experience-redesign.md#state-matrix)
covers default, empty, populated, loading, error, offline and recovery for all
seven journeys. Existing [Precision Glass tokens](../precision-glass/tokens.json)
remain authoritative: SF system body 17 pt, secondary 15, metadata 13; scalable
48-point metric; 4/8/12/16/20/24/32 spacing; 20-point content inset; 44-point
minimum controls and 52-point standalone primary actions. Native Form/List and
system controls own their adaptive geometry. Content is opaque; glass belongs
to native navigation/controls. Do not add a new font or a material per state.

For largest text, stack date/companion and numeric columns, wrap status text,
grow the Coach strip without shrinking text, and keep Save/Cancel reachable
with keyboard shown. Retain system input/keyboard navigation, read-only date
context and scrolling forms. Inspect the smallest supported iPhone as well as
the simulator selected for baseline; fixed phone concept dimensions do not
establish these checks.

## Design package and review ledger

| Deliverable | Existing evidence | Status / next owner |
| --- | --- | --- |
| Seven journey inventory | Audit J1–J7 and source links | Source complete; root records simulator observations separately |
| Written state/transition package | Proposed spec linked below | Proposed; broader-flow acceptance pending concrete design review |
| Today/Coach visual language | Paired concepts under `precision-glass/assets/`; selected Pip references | Existing concept authority, not fresh native evidence |
| All seven full-size light/dark screens | Older implementation PDF covers six surfaces; no new full set in this task | Pending for any replacement journey; do not claim delivery from text storyboard |
| Linked transition storyboard | Proposed spec J1–J7 paths | Written paths delivered; actual per-state boards/native recordings pending |
| Reusable controls/tokens/copy | Current Precision Glass components/tokens/state matrix plus motion spec | Retain; any conflict resolved explicitly before implementation |
| Pip production sheet/rig | Selected identity and MOTION.md | Task 4; no asset changes or alternatives in this source audit |

Accepted: selected Pip, approved placements/motion/event semantics, current
Precision Glass palette and journeys. Revised for execution: the broad audit is
documentation work alongside bounded Pip integration; it is not a redesign
dependency for the catalog/policy/receipt foundations. Deferred: all replacement
flows, meal-text search, capture wizard, full history/rollback and setup/report
reorganization. No deferred item has been silently accepted or implemented.

Each future flow change needs one bounded brief with named screens, complete
state boards in both appearances, keyboard/largest-text layouts, transition
storyboard, explicit accept/revise/defer outcome, safety invariants and focused
native tests. A generic full-app redesign request is not that implementation plan.
