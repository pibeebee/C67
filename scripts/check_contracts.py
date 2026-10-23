"""Validate the contract, fixture schemas, and copies embedded in the Swift package."""
from pathlib import Path
import json
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate
from fixture_support import render_seed

root = Path(__file__).resolve().parents[1]
spec = json.loads((root / "contracts/api/openapi.json").read_text())
validate(spec)
for filename, schema in [
    ("rundowns.json", {"type": "array", "items": {"$ref": "#/components/schemas/Rundown"}}),
    ("trip.json", {"$ref": "#/components/schemas/Trip"}),
]:
    schema = {**schema, "components": spec["components"]}
    data = json.loads((root / "contracts/fixtures" / filename).read_text())
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(data)
source = root / "contracts/fixtures/rundowns.json"
copy = root / "ios-backend/Sources/Data/Fixtures/rundowns.json"
assert source.read_bytes() == copy.read_bytes(), "Run scripts/sync_fixtures.py"
assert (root / "server/supabase/seed.sql").read_text() == render_seed(json.loads(source.read_text())), "Run scripts/sync_fixtures.py"
print("PASS: OpenAPI, fixture schemas, bundled fixture copy, and synthetic SQL seed")
