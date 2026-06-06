# LiteRT-LM In-Process Gemma Local AI

## Goal

Replace the Gemma LiteRT CLI subprocess path with an in-process LiteRT-LM C API integration. Tungsten should load `liblitert-lm.dylib`, keep the engine resident between sidebar questions, send instructions as the system message, and receive clean JSON responses without benchmark/stdout cleanup.

## Scope

- Update tests so the runtime artifact is a dylib, not `litert_lm_main`.
- Add a native runtime wrapper that uses `dlopen`/`dlsym` against LiteRT-LM C API symbols.
- Cache the native engine behind an actor so local questions are serialized and do not reinitialize the model on every prompt.
- Install the stable macOS arm64 PyPI wheel runtime by extracting `litert_lm/liblitert-lm.dylib`.
- Remove the Gemma CLI runner and static checks for `litert_lm_main`/`--input_prompt_file`.

## Verification

- `swiftc ... Tests/AIResponseCoordinatorTests.swift`
- `bash Tests/LocalAISettingsTests.sh`
- `bash Tests/ThreadBrowserLifecycleTests.sh`
- `bash Tests/CEFBrowserLifecycleTests.sh`
- `./scripts/build-debug.sh`
- `git diff --check`
