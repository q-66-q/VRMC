# Protocol and Conformance Vectors

- **[PROTOCOL.md](PROTOCOL.md)** — normative wire format v1.0 (control, media, input,
  security, limits).
- **`tools/reference_codec.py`** — dependency-free Python reference encoder/decoder. It is the
  byte-layout authority for vectors and the mock host.
- **`tools/generate_vectors.py`** — regenerates the committed vectors.
- **`vectors/`** — canonical binary messages + SHA-256/size manifest. Swift and C++ tests must
  decode and re-encode them byte-for-byte.

Run:

```bash
./scripts/test_protocol.sh
# regenerate after an intentional, versioned change:
python3 protocol/tools/generate_vectors.py
```

Do not edit vectors by hand. A protocol change requires a minor/major decision, updated
spec, regenerated vectors, both language implementations, and `VERIFY.md` evidence.
