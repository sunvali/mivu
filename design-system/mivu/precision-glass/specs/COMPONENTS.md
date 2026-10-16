# Components, interaction and accessibility

## C01 App shell
Native TabView with four sections; each owns a NavigationStack and restored scroll/selection state. Roots use large collapsing titles and a trailing profile button. VoiceOver label: "Profile and settings". Root content respects the safe area and native scroll-edge effects. No custom bottom-bar drawing or back gesture interception.

## C02 Intake summary
Large tabular number + visible unit + "Recorded intake". Optional dated goal and arithmetic difference. Below goal: "720 to goal"; above goal: "120 above goal", never a misleading negative progress label. If no goal, hide progress denominator and use "Set a goal" secondary link. If no known estimate, show an em dash and "Not estimated yet"; distinguish a known zero from missing data. Do not suppress pending count.

## C03 Ledger row
Leading time or symbol, primary name, secondary state, trailing value with unit and disclosure. Entire row is a button with44 pt minimum target. Values right-aligned only at standard sizes; stack at accessibility sizes. Loading one row does not blank the whole list. Optional photo thumbnail cannot displace the title/value.

## C04 Status message
Symbol + exact state text + one recovery action when relevant. State is never color-only. Separate durable capture from analysis and backup. Announce a successful local save once, politely; do not announce each streaming token. Spinner only while actual work runs. No fabricated percentage.

## C05 Capture composer
Note field, attached photos with removal controls, Camera and Photo library actions, waking-day assignment. Save requires a nonblank note or attachment. Save acknowledges local persistence before dismissing. Keyboard-safe scrolling; focused field remains visible; toolbar dismissal for numeric keyboard. Save disabled while committing; protect from repeated taps.

## C06 Edit form
Native Form, labeled TextFields/pickers, field-specific helper/error text and Cancel/Save. Blank optional fields mean unset. Units always visible. Validate with existing domain functions. On failure keep the entered draft. Dirty interactive dismiss gets an explicit discard choice. On stale revision show the latest record and preserve the draft for manual reconciliation; never silently overwrite.

## C07 Nutrition evidence
Show provenance per ingredient where available. Labels: "Estimated", "Entered by you", "From label", "From source", "Sample". Source details include stored source title/reference when present; no invented citation/confidence score. Reviewed remains separate. Quantity changes preserve unknown fields; no fabricated zero nutrients.

## C08 Chart
Use native charting with real data. Y-axis baseline0 for intake bars. Missing/untracked days are gaps and labeled; pending/partial data visually distinct. Goal is a dated rule, not a universal line when goals changed within the period. Use stepped goal segments or a selected-day reference. Always provide text summary and accessible data table. Weight axis may be truncated only with visible scale; no extrapolation across unmeasured days.

## C09 Primary action
One primary action per context. Use platform button styles and semantic tint. Default 52 pt target; natural expansion for large text. Save is in a sheet toolbar; do not duplicate a full-width Save at the bottom. Repeated lower "Log weight" CTA and top plus should not coexist in final build: use one reachable action (bottom for the illustrated weight screen).

## C10 Menus and confirmations
Native Menu/confirmationDialog/alert. Destructive label names the object: Delete meal, Delete profile, Restore diary. Explain scope and preserve Cancel. Move meal uses an explicit day picker. Prefer action names over "Are you sure?" Do not invent Undo if the store lacks reversible deletion.

## C11 Coach receipt
Conversation plus a linked saved-record receipt. Distinguish "Saved", "Updated", "Needs review" and "Not applied". Route to the same record ID used by Diary. Ambiguous requests ask a concise question with relevant record choices. Photos added to an existing meal require explicit association. Correction suggestions are not silently applied unless current product semantics authorize them.

## C12 Profile/settings rows
Grouped list with current-value summaries, stable disclosure and clear origin-return behavior. Use person.crop.circle when no user-supplied avatar exists. No invented people or profile-photo upload feature. Connection icons use SF Symbols; a provider logo is optional only with approved brand assets.

## Motion and feedback
System navigation, sheet, menu and tab transitions. Short 120-180 ms crossfades for inline state replacement; do not animate numeric totals counting from zero. Native spring response for controls; no parallax, looping shimmer or celebratory confetti. Reduce Motion uses immediate state replacement or crossfade. Haptic success only after committed capture/save, not every field edit. Error haptic only for a failed explicit action; no repeated background buzzing.

## Accessibility acceptance
- Body text uses system 17 pt default and scales through accessibility5.
- Every action44x44 pt minimum; maintain adequate separation.
- Normal text target 4.5:1; large text/non-text UI3:1 where applicable. Verify composited glass over actual content, not just token pairs.
- VoiceOver order: title, summary, coverage, records, actions, navigation. Combine each ledger row into a meaningful label/value; keep its actions discoverable.
- Example: "Lunch, 1:10 PM, 640 kilocalories, estimated, reviewed, button."
- Visible text labels on all tabs. Custom symbols have labels; decorative images hidden from accessibility.
- Reduce Transparency: native solid/adaptive backgrounds; no unsupported custom blur. Increase Contrast strengthens separators and labels. Color differentiation off still conveys status.
- Keyboard, Full Keyboard Access and Switch Control can reach Save/Cancel and errors.
- Small iPhone and largest Dynamic Type: no clipped units, offscreen Save, inaccessible photo removal, or bars obscuring content.
- English LTR now. Future RTL requires an explicit mirroring and localization pass, not only translating strings.
