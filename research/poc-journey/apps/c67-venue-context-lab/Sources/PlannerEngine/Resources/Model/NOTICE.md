# Local model and runtime provenance

This folder bundles public `intfloat/multilingual-e5-small` assets for the local experiment.

- Model revision: `614241f622f53c4eeff9890bdc4f31cfecc418b3`.
- Upstream model card: <https://huggingface.co/intfloat/multilingual-e5-small>.
- Model license metadata: MIT. The upstream Microsoft UNILM MIT license is included as `E5-LICENSE.txt`, sourced from <https://github.com/microsoft/unilm/blob/master/LICENSE>.
- `model.onnx` is the upstream `onnx/model_qint8_avx512_vnni.onnx` artifact. Its filename describes the upstream export; compatibility here was tested with ONNX Runtime CPU on Apple Silicon, Simulator and one iPhone. It does not imply AVX hardware on those devices.
- `manifest.json` contains pinned asset URLs, sizes and SHA-256 hashes, verified by `scripts/prepare-preference-model.py` and again when loading the model.
- ONNX Runtime Swift Package Manager: Microsoft, MIT, exact package 1.24.2: <https://github.com/microsoft/onnxruntime-swift-package-manager>.
- Tokenizers: Hugging Face `swift-transformers`, exact package 1.4.0: <https://github.com/huggingface/swift-transformers>. Dependency revisions and their upstream licenses remain available in SwiftPM checkouts and `Package.resolved`.

The model consumes supplied text to produce vectors. It does not retrieve venue facts or create routes, source identifiers or visiting times. Bundled fictional venue descriptions are experimental fixtures. No model-quality or user-benefit guarantee is implied by bundling these assets.
