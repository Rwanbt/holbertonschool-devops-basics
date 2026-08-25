# Cache Observations

- **Unoptimized source-only rebuild result**: after a single comment was added to `src/server.js`, the unoptimized build (`COPY . .` before `npm ci`) re-ran the dependency step. Output:

  ```
  #9  [3/4] COPY . .
  #9  DONE 0.1s
  #10 [4/4] RUN npm ci --omit=dev && node -e "setTimeout(() => {}, 3000)"
  #10 0.910
  #10 0.910 added 1 package, and audited 3 packages in 625ms
  #10 DONE 4.0s
  ```

  Because `COPY . .` re-hashes the whole build context, *any* change inside the project tree — even a comment in `src/server.js` — invalidates the layer that feeds `npm ci`, and the expensive dependency step is forced to run again.

- **Cached `Dockerfile.cached` first build result**: dependency manifests and the local `message-format` package are copied before `npm ci --omit=dev`, and source/tests are copied afterwards. The first build runs `npm ci` from scratch:

  ```
  #11 [5/7] RUN npm ci --omit=dev && node -e "setTimeout(() => {}, 3000)"
  #11 0.901 added 1 package, and audited 3 packages in 675ms
  #11 DONE 4.2s
  ```

- **Cached `Dockerfile.cached` source-only rebuild result**: after adding only a comment line to `src/server.js`, the same `docker build -f Dockerfile.cached -t cache-lab:cached .` command (no `--no-cache`) reports:

  ```
  #8  [2/7] WORKDIR /app                                              CACHED
  #9  [3/7] COPY package.json package-lock.json ./                     CACHED
  #10 [4/7] COPY packages/message-format ./packages/message-format     CACHED
  #11 [5/7] RUN npm ci --omit=dev && node -e "setTimeout(() => {}, 3000)"   CACHED
  #12 [6/7] COPY src ./src                                            DONE 0.0s
  #13 [7/7] COPY test ./test                                          DONE 0.1s
  ```

  Only `COPY src` and `COPY test` were rebuilt — the manifest, local-dependency, and `npm ci` layers were reused from the cache. The supplied 3-second `setTimeout` no-op after `npm ci` is the visible proxy for the cost we avoided: in the unoptimized build it would have re-run for every source-only commit; here it is skipped entirely.

- **Why the dependency layer remained cached**: BuildKit's cache key for a step is the SHA256 of (a) the parent layer's cache ID and (b) the build-context inputs the step directly reads. In `Dockerfile.cached`, `RUN npm ci --omit=dev` only reads `package.json`, `package-lock.json`, and the contents of `packages/message-format/`. A comment change in `src/server.js` modifies a file that lives in a later `COPY` step, so neither the input set nor the content hashes upstream of `npm ci` change, and the cache hit is preserved. In `Dockerfile.unoptimized`, `COPY . .` reads the *whole* build context, so any project change re-hashes that layer and breaks the chain.

- **Change that would invalidate the dependency layer**: any modification to a file that is read *before* `npm ci`:
  - editing `package.json` (adding/removing a dependency or `scripts` entry);
  - editing `package-lock.json` (even a comment line or whitespace, because the lockfile hash changes);
  - editing anything under `packages/message-format/` (the `file:packages/message-format` link target is part of the dependency tree).
  Any of these will re-run `npm ci`, and so will pinning a different Node base image (`FROM node:22-bookworm-slim` → a new patch version) because the parent layer's cache ID changes.

## Runtime evidence

Running the cached image and querying `/health` through Docker, per the exercise script:

```
$ docker network create cache-lab-net
$ docker run --rm -d --name cache-lab --network cache-lab-net cache-lab:cached
$ docker run --rm --network cache-lab-net busybox:1.37 sh -c '
    i=0
    until [ "$i" -ge 20 ]; do
      wget -qO- http://cache-lab:8080/health && exit 0
      i=$((i + 1))
      sleep 1
    done
    exit 1
  '
{"service":"cache-lab","status":"ok"}
$ docker rm -f cache-lab
$ docker network rm cache-lab-net
```

The response body matches the contract (`{"service":"cache-lab","status":"ok"}`), confirming the cached build still produces a working image.