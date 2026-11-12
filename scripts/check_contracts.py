"""Validate the contract, fixture schemas, and copies embedded in the Swift package."""
from pathlib import Path
import json
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate
from fixture_support import render_seed

root = Path(__file__).resolve().parents[1]
spec = json.loads((root / "contracts/api/openapi.json").read_text())
validate(spec)
Draft202012Validator({"$ref": "#/components/schemas/PocketCatalog", "components": spec["components"]},
                     format_checker=FormatChecker()).validate(json.loads(
    (root / "packages/PocketEngine/Sources/PocketEngine/Resources/catalog.json").read_text()))
for filename, schema in [
    ("planning-input.json", {"$ref": "#/components/schemas/PlanningInput"}),
    ("planning-result.json", {"$ref": "#/components/schemas/PlanningResult"}),
    ("planning-job.json", {"$ref": "#/components/schemas/PlanningJob"}),
    ("personal-planning-trip.json", {"$ref": "#/components/schemas/PersonalPlanningTrip"}),
    ("journal-upload.json", {"$ref": "#/components/schemas/JournalUploadSession"}),
    ("route-template-separate.json", {"$ref": "#/components/schemas/RouteTemplate"}),
    ("route-template-first-stop.json", {"$ref": "#/components/schemas/RouteTemplate"}),
    ("trip-graph.json", {"$ref": "#/components/schemas/TripGraph"}),
    ("trip-graph-legacy.json", {"$ref": "#/components/schemas/TripGraph"}),
    ("rundowns.json", {"type": "array", "items": {"$ref": "#/components/schemas/Rundown"}}),
    ("trip.json", {"$ref": "#/components/schemas/Trip"}),
    ("trip-page.json", {"$ref": "#/components/schemas/TripPage"}),
    ("trip-snapshot-v2.json", {"$ref": "#/components/schemas/TripSnapshotV2"}),
    ("trip-snapshot-v2-legacy.json", {"$ref": "#/components/schemas/TripSnapshotV2"}),
]:
    schema = {**schema, "components": spec["components"]}
    data = json.loads((root / "contracts/fixtures" / filename).read_text())
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(data)
source = root / "contracts/fixtures/rundowns.json"
copy = root / "ios-backend/Sources/Data/Fixtures/rundowns.json"
assert source.read_bytes() == copy.read_bytes(), "Run scripts/sync_fixtures.py"
for filename in ["planning-input.json", "planning-result.json", "planning-job.json", "personal-planning-trip.json"]:
    assert (root / "contracts/fixtures" / filename).read_bytes() == (root / "ios-backend/Sources/Data/Fixtures" / filename).read_bytes(), "Run scripts/sync_fixtures.py"
assert (root / "server/supabase/seed.sql").read_text() == render_seed(json.loads(source.read_text())), "Run scripts/sync_fixtures.py"
print("PASS: legacy and Pocket OpenAPI, fixture/catalog schemas, bundled fixture copy, and synthetic SQL seed")
