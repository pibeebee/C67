# Itinerary editor safety follow-up

The editor now refuses to capture a new plan while a draft is active, preventing the earlier silent deletion. A new normal plan requires resolving the draft first. TransJakarta requests in the normal planner require an explicit backend capability; older backends do not advertise it.

Live editor state stays in memory only. It is not restored after the app closes. This conservative PoC scope prevents the editor's new revision store from persisting provider snapshots, but does not establish compliance of other existing logs, provider use, or the whole application. Synthetic fixture storage remains available to tests. A durable, provider-reviewed ID-based recovery design remains future work.

Local verification on 2026-11-10 used Xcode 27.2 and synthetic fixtures. Context Lab Swift package tests passed after the checksum-verified E5 resources were restored. A first attempt failed because a model resource was absent in the isolated worktree; it passed on rerun. On an isolated iPhone 18 Pro Max simulator (iOS 27.2), 11 editor model/UI tests passed, including live-editor non-persistence in a synthetic setup. The Python verification suite passed 56 tests; portability and evidence checks passed. Provider calls, mixed-version HTTP integration, physical-device and production acceptance were not performed. Earlier reports remain historical and are not evidence for this revision.

The first hosted Context Lab fixture run failed at compilation because the runner's native Swift build treated `main.swift` and `@main` as conflicting. The verification script now supplies `-parse-as-library`, and the Context Lab check runs as its own job. Native-build regression tests were repeated locally; hosted CI must be checked separately on the new commit.
