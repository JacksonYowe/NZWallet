#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/nzwallet-tests.XXXXXX")
trap 'rm -rf "$test_build_dir"' EXIT HUP INT TERM
cd "$repo_dir"
swiftc -swift-version 5 -o "$test_build_dir/core-tests" \
  Sources/Core/Crypto.swift "TEST FILES CHANGE FOR DEPLOYMENT/TEST_FILE_ONLY.swift" Sources/Core/Models.swift \
  Sources/Core/Verifier.swift Sources/Core/WalletStore.swift Sources/Core/MDL/*.swift \
  Tests/MDLProtocolTests.swift Tests/main.swift
"$test_build_dir/core-tests"
