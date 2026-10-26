# ADR-0005 — Complete private backend slice before review PR

Status: Implemented; final CI and separately approved shared verification tracked in the completion task.
Date: 26 October 2026.

## Human decisions

Giovan requested closing PR #4, preserving work and completing roadmap stages 3B–7 before opening one new review PR. He selected a curated operator catalog, private owner albums, device-reported location at upload-session creation (no second location gate after worker delay), planned-only editing/merge, and no completed/skip/ended_early transition or public creator authoring. These decisions override the proposal's earlier finalization-location requirement for this implementation.

## Discovery

Published-only search uses simple-dictionary token AND matching and normalized exact-area filtering. Limits 1–50 and ID-descending keysets are bounded; opaque cursors pin normalized query/area. This is deterministic discovery, not relevance/popularity ranking, multilinguistic stemming, fuzzy place search or a geographic query. PostGIS is unnecessary until a spatial endpoint exists. Multiple synthetic fixtures are provisioned transactionally/in HTTP tests without changing the original seed or native mock resource.

## Edit and merge

Preview tokens pin owner, trip revision, explicit patch, source content and a 15-minute expiry. Apply locks the trip, rechecks owner/revision/source, then writes the graph and advances revision once. Input choices are title, start instant/zone, explicit retained stop occurrence order and source append. Append first keeps both occurrences with separate provenance; a follow-up retained-ID patch can choose A, B, both or an explicit ordering. No name/coordinate deduplication or silent field combination occurs. Changed adjacency discards all previous leg estimates; copied stop location/dwell provenance is retained. Scheduling is an explicit instant/date change, not a provider-driven route optimizer.

Creation and edit commands store immutable private owner/request receipts. Creation retries still return the original response after edits or journal revisions. Generation/changed-input collisions return 409; apply receipts remain readable by their original owner even after preview expiry. No receipt table is client-readable. Old persisted creation records receive receipts before edit RPCs become active. Private metadata is part of database backups.

All pending-upload or accepted-journal topology/time is protected under the trip lock. Title-only changes remain allowed. Journal acceptance does not set stop/trip completion states. Source-distribution rights, creator publishing/moderation, multi-day creation and automated replanning remain separate contracts.

## Private photo and album

A session binds a UUID command, owner/trip/stop, declared JPEG/PNG type and a recent reported-device location. Initial conservative technical limits: device sample age ≤30 seconds and future skew ≤10 seconds, accuracy 0–100m, distance+accuracy ≤100m, 20 sessions per account/hour, 15-minute create-only upload expiry, 5MiB file cap and 20MP decode cap. These are testable development defaults requiring physical-device/field tuning, not established measures of GPS truth. Raw coordinates are discarded; an input fingerprint supports exact retry comparison.

Raw and processed buckets are private. Only the exact owner-issued pending raw path can be inserted once; client overwrite/delete/raw download are denied. A submit command verifies object metadata, queues validation and exposes status. A service-only worker claims a leased job with bounded attempts. SQL locks never span image/Storage IO. The worker checks actual format, rejects fake/truncated/oversize/animated input, auto-rotates, bounds dimensions to 2048px, strips metadata and publishes a normalized JPEG. Only then does a service-only SQL command atomically accept journal metadata and increment the trip revision. Album/private-object reads require the owner. This does not certify image authenticity, sensor honesty or completion.

Worker lease expiry recovers interrupted attempts; stale worker finalization conflicts. Processed create-only objects are byte-checked on retry. A committed journal with leftover raw bytes is reconciled by cleanup. Expired/rejected sessions have a 24-hour cleanup grace; unowned jobs are eligible immediately. Cleanup deletes bytes through the Storage API before SQL job purging. It never SQL-deletes storage.objects. Original input EXIF is never served; processed private bytes can still be retained by an authorized downloader.

## Operations and evidence boundary

Worker deployment is a separate external Compose project with private env, one CPU/512MiB, read-only root, tmpfs, dropped capabilities, bounded logs and heartbeat health. No new public port, Redis, provider gateway, custom Node API server or Supabase restart is needed. Node/sharp is an image worker only.

Backup tooling creates exclusive private recovery points and validates archives. A restored matching-image clone must demonstrate persisted V1/V2 backfill, SQL suites and migration compatibility before applying all pending migrations. Read-only health tooling verifies catalog and RPC availability without printing sessions or account records. The runbook includes queue/worker failure diagnosis, object reconciliation, account cleanup and failure/rollback gates.

A same-host logical recovery point is not off-host disaster recovery, a measured RPO/RTO or production-load certification. Native login, physical iPhone upload/HEIC conversion, actual GPS behavior and field usability must be verified by the iOS owner. This server slice accepts JPEG/PNG only. CI and shared backend verification are recorded separately; neither makes native field integration complete.
