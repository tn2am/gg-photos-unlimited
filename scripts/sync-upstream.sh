#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n $(git -C GotohpCore/upstream status --porcelain) ]]; then echo 'Upstream submodule has local changes' >&2; exit 1; fi
git -C GotohpCore/upstream fetch origin main
ref=${1:-origin/main}
git -C GotohpCore/upstream checkout --detach "$ref"
git -C GotohpCore/upstream rev-parse HEAD > GotohpCore/UPSTREAM_REVISION
python3 scripts/prepare-core.py
go mod tidy
go test -race -tags cli ./...
go test -tags cli app/backend
echo 'Review upstream diff, projection adaptations and device results before committing the revision.'
