# C67 itinerary performance benchmark

Isolated benchmark harness for the existing itinerary pipeline. No production source or catalog changes.

- [Results and limitations](REPORT.md)
- [Frozen case protocol and reproduction](PROTOCOL.md)
- `Benchmark.swift`: shared 17-case runner.
- `OriginalIntegrationModel.swift`: exact original app-model copy.
- `run-replay.sh`: Mac replay with actual E5 and authored providers.
- `project.yml`: signed physical iPhone harness using the existing WeatherKit App ID.
- `analyze.py`: independent export auditor; scopes retained logs to the current routing session.

The original app was restored after the physical run. Evidence is local and contains device/build diagnostics; do not publish it unreviewed.
