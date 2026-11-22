# ChatGPT plan sign-in feedback

**Goal** People see the plan requirement before connecting. A completed sign-in with missing plan permission explains why ChatGPT still cannot analyze anything.

**Design** Use the approved “Requires ChatGPT Go or higher.” copy alongside existing sign-in actions. When sign-in succeeds without plan permission, retain the signed-in account and explain how to authorize plan use. Keep the existing ineligible-plan recovery, local estimates and saved meal capture available. Account eligibility and successful sign-in are separate outcomes.

The owner selected upfront disclosure with the existing recovery flow over adding an account switch. Upfront copy alone would still leave a successful sign-in without plan permission unexplained.

- [x] Add a synthetic OAuth regression that expects explicit permission feedback after sign-in and relaunch.
- [x] Present the requirement and missing-permission feedback through existing actions in onboarding, Settings, Coach and meal detail. Localize the copy in every bundled language.

Verify the connection suites and affected onboarding journeys with XcodeBuildMCP, run the short simulator smoke check, and inspect the English and Hebrew connection screens on the simulator.

The established eligibility and recovery contract is in the [ChatGPT plan behavior design](../specs/2026-11-17-chatgpt-free-tier-design.md). The Go tier wording is the owner’s requested disclosure. Live account eligibility needs separate verification.
