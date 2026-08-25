#!/bin/sh
set -eu
if [ -f /app/local-only/context-noise.bin ]; then
    printf '%s\n' 'context-contains-local-only-data'
else
    printf '%s\n' 'context-clean'
fi
