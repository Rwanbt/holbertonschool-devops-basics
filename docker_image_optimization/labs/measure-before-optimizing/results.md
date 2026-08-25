# Task 0 - Measure Before You Optimize

## Measured Baseline Evidence

- **Image Size**: `380969088` bytes (~363 MB) — collected via `docker image inspect image-lab:baseline --format '{{.Size}}'`.
- **Configured Runtime User**: `""` (empty string) — collected via `docker image inspect image-lab:baseline --format '{{json .Config.User}}'`. An empty `User` field means the container process runs as `root` by default.
- **Largest non-base layer instruction**: `COPY . .` — `8.44 MB` layer, observed via `docker image history image-lab:baseline --no-trunc`. For reference, the other non-base layers are `RUN python -m compileall /app` at `1.25 MB` and `WORKDIR /app` at `8.19 kB`.

## Unnecessary Files Copied (`COPY . .`)

1. `reports/test-data.bin` — 8,388,608 bytes (8.0 MB) of synthetic test data shipped into `/app/reports/`. The runtime API only serves `/health` and `/items`; this binary is never read by `app.py` and exists solely as a lab fixture.
2. `tests/` directory — contains `test_app.py` and is shipped verbatim into the runtime image. The application process (`python app.py`) never imports it, so the whole directory is dead weight in production. The same observation applies to `docs/architecture.md`, `local-notes.txt`, `Dockerfile.baseline`, and `results.md`, which `COPY . .` also drags in.

## Optimization Targets (Based on Evidence)

1. **Target 1: Narrow the build context with a `.dockerignore` and targeted `COPY`.**
   - *Evidence*: the `COPY . .` step is the largest non-base layer (`8.44 MB`) and an in-container listing of `/app` confirms that `reports/test-data.bin` (8 MB) plus `tests/`, `docs/`, `local-notes.txt`, `Dockerfile.baseline`, and `results.md` are all shipped into the runtime image. Excluding them (or copying only `app.py`) removes the dominant non-base contribution to the 380,969,088-byte image and makes the build cache far more stable.
2. **Target 2: Drop or scope the `python -m compileall /app` instruction.**
   - *Evidence*: `docker image history image-lab:baseline` shows the `RUN python -m compileall /app` layer weighs `1.25 MB` and produces `__pycache__` artifacts for both `app.py` and `tests/test_app.py`. Since `CMD ["python", "app.py"]` loads the source on every start, the bytecode cache is unused at runtime and only inflates the image and attack surface.
3. **Target 3: Run the container as a non-root user.**
   - *Evidence*: `docker image inspect image-lab:baseline --format '{{json .Config.User}}'` returns `""`, confirming the process runs as `root`. Combined with the bloated `python:3.12-bookworm` base image, this yields a privileged, oversized runtime. Adding a dedicated `USER` (and trimming the base image in a later task) directly addresses the measured privilege and size debt.