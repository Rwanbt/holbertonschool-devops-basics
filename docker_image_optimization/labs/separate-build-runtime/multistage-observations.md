# Multi-Stage Observations

- **Single-stage output**: `{"service":"greeter","status":"ok"}` (`docker run --rm multistage-lab:single`).
- **Multi-stage output**: `{"service":"greeter","status":"ok"}` (`docker run --rm multistage-lab:optimized`). Both images run the same compiled program and emit the same JSON payload.
- **Single-stage size in bytes**: `79053637` (~75.4 MiB) — `docker image inspect multistage-lab:single --format '{{.Size}}'`.
- **Multi-stage size in bytes**: `1355393` (~1.29 MiB) — `docker image inspect multistage-lab:optimized --format '{{.Size}}'`.
- **Size reduction**: `77698244` bytes (~74.1 MiB), i.e. the optimized image is ~98.3% smaller than the single-stage image. The bulk of what disappears is the Go toolchain (`golang:1.25-alpine` ships the compiler, linker, runtime sources, `git`, `ca-certificates`, `/usr/local/go`, `$GOPATH`, etc.) and the build cache that the single-stage Dockerfile leaves behind.
- **Configured runtime user**: `65532:65532` — `docker image inspect multistage-lab:optimized --format '{{.Config.User}}'` returns exactly the numeric UID/GID pair required by the exercise.
- **`/bin/sh` override result**: the override fails at container start:

  ```
  docker: Error response from daemon: failed to create task for container:
    failed to create shim task: OCI runtime create failed: runc create failed:
    unable to start container process: error during container init:
    exec: "/bin/sh": stat /bin/sh: no such file or directory
  ```

  Exit code `127` ("command not found"). This is the expected behaviour: the final stage is `FROM scratch`, so the only file on the image is the statically linked `greeter` binary. There is no `/bin/sh`, no `/etc/passwd`, no `/proc`, no `ca-certificates`, no glibc/musl loader beyond what is statically baked into the binary itself.

## Explanation

The single-stage Dockerfile keeps every artefact that the build needs in the runtime image: the Go compiler, the module cache, the working tree of `.go` files, the test binaries, the package metadata. The runtime image therefore weighs about 75 MiB even though the only thing it actually executes is a tiny static Go binary that prints one JSON line. The multistage build splits that work into two stages with `FROM ... AS builder` and a final `FROM scratch`. The `builder` stage does the expensive work — `go mod download` (cached behind `go.mod`), `go test ./...` (required by the exercise, not skipped), and `CGO_ENABLED=0 go build -o /out/greeter ./cmd/greeter` to produce a self-contained binary that does not need `libc` or any dynamic linker at runtime. The final stage declares no base filesystem at all; it only `COPY --from=builder /out/greeter /greeter` so the binary is the sole artefact that survives into the published image, and runs it under `USER 65532:65532`.

The `USER 65532:65532` directive is meaningful precisely *because* the image is `scratch`: there is no `/etc/passwd` to map that UID to a name, which is why the value has to be given numerically. With a normal base image we could write `USER app`; here we have to write the numeric pair so the kernel can still apply the non-root identity at exec time.

Why is the failed `/bin/sh` override expected? `scratch` is an empty image — it ships no shell, no libraries, no `/bin`, no `/etc`, no `/tmp`, nothing. So `docker run --entrypoint /bin/sh multistage-lab:optimized` cannot work: there is literally no `/bin/sh` binary on the image for runc to exec into. That is by design. The shell is not needed at runtime: the application is a single statically linked Go binary that the kernel can `execve` directly, which is exactly the path `ENTRYPOINT ["/greeter"]` takes. Adding a shell would inflate the image, widen the attack surface, and reintroduce a shell escape hatch — the opposite of what we optimised for.

That failure, however, does **not** replace functional testing of the application binary. The `docker run --rm multistage-lab:optimized` invocation — which prints `{"service":"greeter","status":"ok"}` and exits — is the test that proves the optimized image still behaves like the single-stage one: it loads the binary, the binary loads its embedded `message.JSON()` string, and stdout reaches the host. A missing-shell error tells us only that the filesystem layout is correct and that there is no shell to misuse; it tells us nothing about whether `message.JSON()` returns the expected string, whether the binary crashes on the target CPU, whether the statically linked runtime resolves symbols correctly, or whether any future code change keeps the contract. The actual behavioural guarantee comes from the `go test ./...` step that runs in the build stage **before** the binary is compiled, combined with the runtime invocation that proves the produced image still prints the expected JSON. So the missing-shell result is a *useful negative signal* about image hygiene, and the working run is the *positive signal* about behaviour; both are needed.