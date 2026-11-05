#!/usr/bin/env python3
"""Use a temporary Python env: tokenizers, numpy, onnxruntime==1.24.2.
Reports numerical disagreement rather than claiming bitwise parity across native builds.
"""
import json
from pathlib import Path
import subprocess
import sys
import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

binary=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1]/"Packages/PreferenceLearning/Sources/PreferenceLearning/Resources/Model"
t=Tokenizer.from_file(str(root/"tokenizer.json"))
token_values=json.loads(subprocess.check_output([str(binary),"--tokens"]))
tokens=[dict(text=text,matches=ids==t.encode("query: "+text).ids,swift=ids,reference=t.encode("query: "+text).ids) for text,ids in token_values.items()]
samples=json.loads(subprocess.check_output([str(binary),"--parity"]))
options=ort.SessionOptions();options.intra_op_num_threads=2
s=ort.InferenceSession(str(root/"model.onnx"),sess_options=options,providers=["CPUExecutionProvider"])
vectors=[]
for item in samples:
    ids=t.encode(("query: " if item["query"] else "passage: ")+item["text"]).ids
    a=np.array([ids],dtype=np.int64)
    hidden=s.run(None,dict(input_ids=a,attention_mask=np.ones_like(a),token_type_ids=np.zeros_like(a)))[0]
    expected=hidden.mean(axis=1)[0];expected/=np.linalg.norm(expected)
    actual=np.array(item["vector"])
    vectors.append(dict(text=item["text"],sameTokens=ids==item["tokens"],maxAbsoluteError=float(np.max(np.abs(expected-actual))),cosine=float(np.dot(expected,actual)/(np.linalg.norm(expected)*np.linalg.norm(actual)))))
result=dict(referenceRuntime=ort.__version__,tokenChecks=tokens,vectors=vectors,scope="Seven tokenizer samples and two numerical probes; no bitwise cross-build equivalence or recommendation accuracy claim")
(out/"reference-check.json").write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps(result,indent=2))
assert all(t["matches"] for t in tokens)
assert all(v["sameTokens"] for v in vectors)
