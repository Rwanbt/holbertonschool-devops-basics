# Layer Observations

- **Unoptimized checksum**: `a0e8bdd8a312de8e45d2cea454dee228ede781730bfc321d96a6fced1b634090` — `docker run --rm layer-lab:unoptimized` prints the SHA256 of the synthetic 6 MiB payload.
- **Optimized checksum**: `a0e8bdd8a312de8e45d2cea454dee228ede781730bfc321d96a6fced1b634090` — `docker run --rm layer-lab:optimized` prints the exact same string, proving the build artifact is functionally identical.
- **Unoptimized size in bytes**: `10084891` (~9.62 MiB) — `docker image inspect layer-lab:unoptimized --format '{{.Size}}'`.
- **Optimized size in bytes**: `3790446` (~3.62 MiB) — `docker image inspect layer-lab:optimized --format '{{.Size}}'`.
- **Size reduction in bytes**: `6294445` (~6.00 MiB), comfortably above the required `5242880` (5 MiB) threshold.

## Relevant history entries

`docker image history layer-lab:unoptimized`:

```
IMAGE          CREATED       CREATED BY                                          SIZE      COMMENT
7b882596cb4b   <build>       CMD ["cat" "/artifact.sha256"]                      0B        buildkit.dockerfile.v0
<missing>      <build>       RUN /bin/sh -c rm -f /tmp/build-payload.bin …       8.19kB    buildkit.dockerfile.v0
<missing>      <build>       RUN /bin/sh -c sha256sum /tmp/build-payload.bin …   8.19kB    buildkit.dockerfile.v0
<missing>      <build>       RUN /bin/sh -c cp /mnt/build-payload.bin /tmp/…     6.3MB     buildkit.dockerfile.v0
<missing>      base          CMD ["/bin/sh"]                                     0B        buildkit.dockerfile.v0
<missing>      base          ADD alpine-minirootfs-3.22.5-x86_64.tar.gz /…        8.96MB    buildkit.dockerfile.v0
```

`docker image history layer-lab:optimized`:

```
IMAGE          CREATED       CREATED BY                                          SIZE      COMMENT
50b23111bef6   <build>       CMD ["cat" "/artifact.sha256"]                      0B        buildkit.dockerfile.v0
<missing>      <build>       RUN /bin/sh -c cp /mnt/build-payload.bin /tmp/…     8.19kB    buildkit.dockerfile.v0
<missing>      base          CMD ["/bin/sh"]                                     0B        buildkit.dockerfile.v0
<missing>      base          ADD alpine-minirootfs-3.22.5-x86_64.tar.gz /…        8.96MB    buildkit.dockerfile.v0
```

The layer that retains `/tmp/build-payload.bin` in the unoptimized image is the **`RUN cp …` step, weighing 6.3 MB`**. The two follow-up `RUN sha256sum …` and `RUN rm -f …` layers only carry a tiny `8.19 kB` whiteout/audit record each, which is why `docker run` sees no `/tmp/build-payload.bin` (the `rm` layer adds a whiteout entry that hides the file at runtime) but `docker image history` still reports 6.3 MB of payload bytes stored in the earlier layer.

## Explanation

The unoptimized Dockerfile splits the work across three separate `RUN` instructions, and each one of them creates its own immutable layer in the image:

1. `RUN cp /mnt/build-payload.bin /tmp/build-payload.bin` — this layer **materialises the 6 MiB payload inside the layer's filesystem**. From the moment this layer is committed, the bytes are part of the image's storage and will be counted in `docker image inspect`/`docker image history`.
2. `RUN sha256sum … > /artifact.sha256` — a separate layer that records the small `/artifact.sha256` file on top.
3. `RUN rm -f /tmp/build-payload.bin` — yet another layer whose only contribution is a **whiteout entry** (`.wh.build-payload.bin`) that tells the overlay filesystem to mask `/tmp/build-payload.bin` when the image is finally assembled.

At runtime the union/overlay mount combines all three layers: the whiteout in layer 3 wins, so `/tmp/build-payload.bin` is invisible from inside the container — which is why both images print the same checksum and `find /` finds no trace of the file. But the **bytes stored in layer 1 are still there**: a Docker image is the immutable sum of its layers, never a deduplicated view. `docker image history` and the on-disk layer tarballs still carry the full 6 MiB payload; the `rm` only changes what the merged filesystem *exposes*, not what the registry has to *store and transfer*. This is the classic "I deleted it in a later layer, why is the image still huge?" trap.

The optimized Dockerfile fixes this at the source by performing `cp`, `sha256sum`, and `rm` inside a **single** `RUN` step. BuildKit commits exactly one layer that contains `/artifact.sha256` and never contains `/tmp/build-payload.bin` (the temporary copy exists only inside the build sandbox and is deleted before the layer is sealed). The 6 MiB of payload therefore never enters the image's layer storage: `docker image history` no longer reports the 6.3 MB step, and `docker image inspect` shrinks from `10084891` bytes down to `3790446` bytes — a `6294445`-byte saving, well above the 5 MiB threshold the exercise requires. Behaviourally the image is identical (same SHA256, same `CMD`, same `/artifact.sha256`); only the on-disk and on-wire size of the image changes.

So the lesson is: **"delete in a later layer" hides a file, but only "never write it in the first place" makes it disappear from the image.** Bind mounts (BuildKit's `--mount=type=bind`) are the scaffolding that lets a step read host data without committing it to a layer; merging everything that touches the temporary file into one `RUN` is what prevents the bytes from being sealed into the image in the first place.