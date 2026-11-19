from pathlib import Path
import json
from fixture_support import render_seed
root = Path(__file__).resolve().parents[1]
source = root / "contracts/fixtures/rundowns.json"
(root / "server/supabase/seed.sql").write_text(render_seed(json.loads(source.read_text())))
print("Updated the synthetic SQL seed")
