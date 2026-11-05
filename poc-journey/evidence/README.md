# Evidence inventory and publication policy

The [publication manifest](publication-manifest.json) lists source-relative paths, original and published SHA256 hashes, disposition and transformations for every inventoried file. The original Mac files were not changed. Paths identify source roots by stable labels, not private home directories.

Evidence remains beside the originating application's reports to preserve useful links. The [stage index](index.json) provides entry points, and [relocation verification](relocation-verification.md) records newly executed checks on the imported copies.

## Included

Source, fixture inputs, outputs, prompt/rubric versions, metric/JUnit summaries, source hashes, safe provider records, screenshots and explicit failures. Public build/test extracts omit repetitive compiler command noise; their headers/manifest retain the original log hash. Model output and meaningful test failures are not rewritten into passing results.

## Excluded or restored separately

- `.env` and private signing/account/device dumps are never published.
- Opaque `.xcresult` bundles, compiled apps, caches, dependencies and unreviewed legacy group/location screenshots remain local. Safe extracted screenshots/test summaries are retained.
- Large E5 weights/tokenizer are restored by `scripts/bootstrap.py` from immutable upstream URLs with checksum verification. No Git LFS or separate private repository is required.
- Full third-party HTML/SDK captures are not redistributed; source URLs, hashes, factual extracts and the recorded toolchain remain.
- Unavailable external references are listed in the [gap ledger](../docs/missing-evidence.md). No placeholder file is evidence.

## Transformations

Publication copies redact unnecessary device identifiers, private infrastructure details, private email addresses and original home paths. JSON Data fields used for native reports/logs are decoded before redaction, then re-encoded; storage-envelope checksums are updated only when that envelope's payload changes. Original hashes remain historical identifiers, with new hashes for publication copies.

Maintained Swift copies follow C67's formatter. That can change source hashes without changing logic; the manifest records the publication version separately. Historical evaluated `.swift.txt` inputs remain archival source material. A current-source hash mismatch is not grounds to fabricate a historical pass.

The scoped `.gitattributes` preserves whitespace in historical output, attributed records and the upstream license instead of rewriting those artifacts to satisfy a patch whitespace check. Maintained source and newly authored handoff documentation retain the repository's normal checks.

PNG/JPEG metadata is stripped where present; no location-bearing legacy screenshots were assumed safe merely because they were in a PoC directory. Fixture/source dates and forecast provenance are preserved.

No release containing unreviewed raw data is created by this handoff. The excluded originals remain on the source machine, with their disposition recorded. A future safe release archive must be reviewed and hashed separately.
