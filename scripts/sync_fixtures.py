from pathlib import Path
import json
import shutil
from fixture_support import render_seed
root = Path(__file__).resolve().parents[1]
source = root / "contracts/fixtures/rundowns.json"
shutil.copyfile(source, root / "packages/C67Backend/Sources/Data/Fixtures/rundowns.json")
for filename in ["planning-input.json", "planning-result.json", "planning-job.json", "personal-planning-trip.json"]:
    shutil.copyfile(root / "contracts/fixtures" / filename, root / "packages/C67Backend/Sources/Data/Fixtures" / filename)
(root / "server/supabase/seed.sql").write_text(render_seed(json.loads(source.read_text())))
print("Updated the Swift package resource and synthetic SQL seed")
