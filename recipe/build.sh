#!/bin/bash
set -exuo pipefail

# Prebuilt bun extracted from the bun.native zip; only used to run the build
# script itself (the source tarball ships no bun binary).
BUN_BOOTSTRAP="$(find "${SRC_DIR}/bun.native" -maxdepth 2 -type f -name bun | head -1)"
if [[ -z "${BUN_BOOTSTRAP}" ]]; then
  echo "could not find the bootstrap bun under ${SRC_DIR}/bun.native" >&2
  exit 1
fi
export PATH="$(dirname "${BUN_BOOTSTRAP}"):${PATH}"

# The source tarball has no .git checkout, so the build cannot derive a
# revision; supply the release commit.
export GIT_SHA=744846f844374847c902b5e7fd59b4342a51ef99

# Use the conda LLVM/Rust toolchains instead of letting the build fetch its own.
export BUN_TOOLCHAIN_LLVM="${BUILD_PREFIX}"
export BUN_TOOLCHAIN_RUST="${BUILD_PREFIX}"
export BUN_TOOLCHAIN_CARGO="${BUILD_PREFIX}/bin/cargo"

# CI=true makes the build take its CI path: on macOS it uses the minimum
# supported deployment target (13.0) instead of probing the worker's older
# Xcode SDK, and fetches its own pinned SDK.
export CI=true

bun_args=(--profile=release)
if [[ "${target_platform}" == linux-* ]]; then
  # conda's LLVM toolchain does not ship the static libatomic bun links by
  # default, which fails the final link with `unable to find library -l:libatomic.a`.
  bun_args+=(--static-libatomic=off)
fi
if [[ "${target_platform}" == osx-* ]]; then
  # The CI build flags use the minimum supported macOS deployment target (13.0)
  # instead of probing the worker's older Xcode SDK.
  bun_args+=(--ci)
fi

bun scripts/build.ts "${bun_args[@]}"

mkdir -p "${PREFIX}/bin"
cp build/release/bun "${PREFIX}/bin/bun"
ln -sf bun "${PREFIX}/bin/bunx"

# The shell completion text is architecture-independent.
mkdir -p "${PREFIX}/share/zsh/site-functions"
SHELL=zsh "${PREFIX}/bin/bun" completions > "${PREFIX}/share/zsh/site-functions/_bun"
grep -q '_bun_add_completion' "${PREFIX}/share/zsh/site-functions/_bun"

mkdir -p "${PREFIX}/share/bash-completion/completions"
SHELL=bash "${PREFIX}/bin/bun" completions > "${PREFIX}/share/bash-completion/completions/bun"
grep -q '_file_arguments()' "${PREFIX}/share/bash-completion/completions/bun"

mkdir -p "${PREFIX}/share/fish/vendor_completions.d"
SHELL=fish "${PREFIX}/bin/bun" completions > "${PREFIX}/share/fish/vendor_completions.d/bun.fish"
grep -q '__fish__get_bun_bins' "${PREFIX}/share/fish/vendor_completions.d/bun.fish"
