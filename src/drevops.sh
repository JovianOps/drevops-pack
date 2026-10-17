#!/usr/bin/env bash
#
# Host-side wrapper: runs the drevops-pack image against the current directory.
#
# Env:
#   DREVOPS_IMAGE            image to run (default: drevops-pack:latest)
#   DREVOPS_DOCKER=1         also mount the Docker socket (for tools that call docker)
#   DREVOPS_ENV_PASSTHROUGH  space-separated env var names to forward into the container
#
set -Eeuo pipefail

IMAGE="${DREVOPS_IMAGE:-drevops-pack:latest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "drevops: docker is required but was not found in PATH" >&2
  exit 127
fi

args=(run --rm --interactive
  --volume "${PWD}:/work" --workdir /work
  --user "$(id -u):$(id -g)" --env HOME=/tmp)

if [[ -t 0 && -t 1 ]]; then
  args+=(--tty)
fi

if [[ "${DREVOPS_DOCKER:-0}" == "1" ]]; then
  if [[ -S /var/run/docker.sock ]]; then
    args+=(--volume /var/run/docker.sock:/var/run/docker.sock)
  else
    echo "drevops: DREVOPS_DOCKER=1 but /var/run/docker.sock does not exist" >&2
    exit 1
  fi
fi

for var in ${DREVOPS_ENV_PASSTHROUGH:-}; do
  args+=(--env "$var")
done

exec docker "${args[@]}" "$IMAGE" "$@"
