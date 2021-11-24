#!/bin/sh
set -x
set -e
set -o errexit
set -o nounset
# # bashism, wsl uses dash
# set -o pipefail

if [ -z "${PKG}" ]; then
    echo "PKG must be set"
    exit 1
fi
if [ -z "${BIN}" ]; then
    echo "BIN must be set"
    exit 1
fi
if [ -z "${GOOS}" ]; then
    echo "GOOS must be set"
    exit 1
fi
if [ -z "${GOARCH}" ]; then
    echo "GOARCH must be set"
    exit 1
fi
if [ -z "${VERSION}" ]; then
    echo "VERSION must be set"
    exit 1
fi
if [ -z "${REVISION}" ]; then
    echo "REVISION must be set"
    exit 1
fi

export CGO_ENABLED=0

GIT_SHA=$(git rev-parse HEAD)
GIT_DIRTY=$(git status --porcelain 2> /dev/null)
if [ -z "${GIT_DIRTY}" ]; then
  GIT_TREE_STATE=clean
else
  GIT_TREE_STATE=dirty
fi

BUILD_DATE=$(date '+%Y-%m-%d-%H:%M:%S')
LDFLAGS="-X main.Version=${VERSION}"
LDFLAGS="${LDFLAGS} -X main.BuildDate=${BUILD_DATE}"
LDFLAGS="${LDFLAGS} -X main.Revision=${REVISION}"
LDFLAGS="${LDFLAGS} -X main.Branch=${BRANCH}"
LDFLAGS="${LDFLAGS} -X main.BuildUser=${BUILDUSER}"

# To optimize the build for alpine linux
# LDFLAGS="${LDFLAGS} -w -linkmode external -extldflags \"-static\""

if [ -z "${OUTPUT_DIR:-}" ]; then
  OUTPUT_DIR=.
fi
OUTPUT=${OUTPUT_DIR}/${BIN}
if [ "${GOOS}" = "windows" ]; then
  OUTPUT="${OUTPUT}.exe"
fi

go build \
    -o ${OUTPUT} \
    -installsuffix "static" \
    -ldflags "${LDFLAGS}" \
    .