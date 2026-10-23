from pathlib import Path
import json
import shutil
from fixture_support import render_seed
root = Path(__file__).resolve().parents[1]
source = root / "contracts/fixtures/rundowns.json"
shutil.copyfile(source, root / "ios-backend/Sources/Data/Fixtures/rundowns.json")
(root / "server/supabase/seed.sql").write_text(render_seed(json.loads(source.read_text())))
print("Updated the Swift package resource and synthetic SQL seed")
