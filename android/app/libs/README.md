# libs/

This directory is intentionally empty.

The project previously used `mlc4j.aar` (MLC LLM runtime), but the native
inference layer was migrated to **MediaPipe Tasks GenAI** (`tasks-genai`),
which is pulled from Maven Central automatically during the Gradle build.

No manual AAR downloads are required. Just run:

```bash
flutter build apk --release --target-platform android-arm64
```
