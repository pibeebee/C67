"""XcodeGen preparation hook: add a dictionary-valued capability to the new project.

Some XcodeGen versions stringify nested target attributes. This hook only edits
the generated project; it does not build, sign, resolve packages or call providers.
"""
from pathlib import Path
import re

project = Path(__file__).resolve().parent.parent / "C67TripIntegration.xcodeproj/project.pbxproj"
text = project.read_text()
target = re.search(
    r"^\t\t([A-F0-9]{24}) /\* C67TripIntegration \*/ = \{\n\t\t\tisa = PBXNativeTarget;",
    text, re.MULTILINE,
)
if target is None:
    raise SystemExit("Cannot locate the generated P3 target; no project change made.")
needle = "\t\t\t\t\t" + target.group(1) + " = {\n"
if text.count(needle) != 1:
    raise SystemExit("Cannot locate unique P3 target attributes; no project change made.")
addition = (
    '\t\t\t\t\t\tSystemCapabilities = {\n'
    '\t\t\t\t\t\t\tcom.apple.WeatherKit = {\n'
    '\t\t\t\t\t\t\t\tenabled = 1;\n'
    '\t\t\t\t\t\t\t};\n'
    '\t\t\t\t\t\t};\n'
)
if addition not in text:
    project.write_text(text.replace(needle, needle + addition))
