# libs/

This directory holds `mlc4j.aar` — the MLC LLM Android runtime.

**This file is NOT committed** (it's ~60 MB and binary).
It is downloaded automatically by the CI workflow (`build.yml`) before building.

## To build locally

Download it manually:

```bash
curl -L -o android/app/libs/mlc4j.aar \
  https://github.com/mlc-ai/mlc-llm/releases/download/v0.1.1/mlc4j-v0.1.1.aar
```

Then run:
```bash
flutter build apk --release --target-platform android-arm64
```
