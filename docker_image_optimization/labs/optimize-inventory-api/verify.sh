#!/usr/bin/env sh
set -eu

IMAGE="${1:-inventory-api:optimized}"
MODE="${2:-optimized}"
NETWORK="inventory-api-validation-$$"
CONTAINER="inventory-api-validation-$$"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker image inspect "$IMAGE" >/dev/null
docker network create "$NETWORK" >/dev/null
docker run -d --name "$CONTAINER" --network "$NETWORK" "$IMAGE" >/dev/null

attempt=0
health=""
while [ "$attempt" -lt 20 ]; do
    health="$(docker run --rm --network "$NETWORK" busybox:1.37 wget -qO- "http://$CONTAINER:8080/health" 2>/dev/null || true)"
    [ "$health" = '{"service":"inventory-api","status":"ok"}' ] && break
    attempt=$((attempt + 1))
    sleep 1
done

if [ "$health" != '{"service":"inventory-api","status":"ok"}' ]; then
    printf '%s\n' "FAIL health response: $health" >&2
    exit 1
fi

items="$(docker run --rm --network "$NETWORK" busybox:1.37 wget -qO- "http://$CONTAINER:8080/items")"
case "$items" in
    *'"id":1'*'"name":"layers"'*'"id":2'*'"name":"cache"'*) ;;
    *)
        printf '%s\n' "FAIL items response: $items" >&2
        exit 1
        ;;
esac

user="$(docker image inspect "$IMAGE" --format '{{.Config.User}}')"
size="$(docker image inspect "$IMAGE" --format '{{.Size}}')"

printf '%s\n' "PASS health: $health"
printf '%s\n' "PASS items: $items"
printf '%s\n' "INFO configured user: ${user:-<empty/root>}"
printf '%s\n' "INFO image size bytes: $size"

if [ "$MODE" = "optimized" ]; then
    if [ "$user" != "65532:65532" ]; then
        printf '%s\n' "FAIL configured user must be 65532:65532" >&2
        exit 1
    fi

    if docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'exit 0' >/dev/null 2>&1; then
        printf '%s\n' "FAIL optimized image unexpectedly contains /bin/sh" >&2
        exit 1
    fi
    printf '%s\n' 'PASS optimized image does not provide /bin/sh'

    if docker image inspect inventory-api:baseline >/dev/null 2>&1; then
        baseline_size="$(docker image inspect inventory-api:baseline --format '{{.Size}}')"
        printf '%s\n' "INFO baseline size bytes: $baseline_size"
        if [ "$size" -ge "$baseline_size" ]; then
            printf '%s\n' 'FAIL optimized image is not smaller than baseline' >&2
            exit 1
        fi
        printf '%s\n' 'PASS optimized image is smaller than baseline'
    else
        printf '%s\n' 'INFO baseline image not present; relative size comparison skipped'
    fi
fi
