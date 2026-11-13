# Jakarta operational boundary mask

The application embeds the same coordinate arrays as jakarta.geojson so point validation works offline. The selected Jakarta feature was extracted without coordinate changes from the simplified geoBoundaries Indonesia ADM1 dataset.

- Source metadata: https://www.geoboundaries.org/api/current/gbOpen/IDN/ADM1/
- Frozen source: https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/IDN/ADM1/geoBoundaries-IDN-ADM1_simplified.geojson
- Boundary ID: IDN-ADM1-65028918; feature shapeISO ID-JK, Jakarta Special Capital Region.
- Geometry: MultiPolygon, 2 polygons, 381 vertices.
- Vintage represented by source: 2017; dataset build December 2023; retrieved4 November2026.
- Source attribution: OpenStreetMap contributors, Wambacher, geoBoundaries / William & Mary geoLab.
- License reported by source: Open Data Commons Open Database License 1.0 (ODbL-1.0).
- License text: https://opendatacommons.org/licenses/odbl/1-0/
- Source copyright: https://www.openstreetmap.org/copyright

The extracted database remains available under ODbL-1.0. See source-metadata.json for original metadata and jakarta.geojson for the redistributed feature.

This frozen, simplified mask is an operational PoC boundary, not a surveyed or current official legal boundary. Border points and small islands may require review. A search rectangle is only a hint. The mask restricts selected endpoint coordinates; it does not guarantee that every road segment stays inside the region.
