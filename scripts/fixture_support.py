"""Render the synthetic database seed from the authoritative catalog fixture."""
import json

def render_seed(rundowns):
    lines = ["-- Synthetic development content. No accounts, credentials or real user data."]
    for item in rundowns:
        values = [item["id"], item["title"], item["area"], item["summary"], json.dumps(item["stops"])]
        quoted = ["'" + value.replace("'", "''") + "'" for value in values]
        lines.append("insert into public.rundown_versions(id, title, area, summary, stops, published)\n"
                     + "values (" + ", ".join(quoted) + ", true);")
    return "\n".join(lines) + "\n"
