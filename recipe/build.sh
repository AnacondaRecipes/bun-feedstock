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

# The source tarball has no .git checkout; meta.yaml passes the release commit
# via script_env. Fail loudly rather than silently building revision "unknown".
: "${GIT_SHA:?GIT_SHA must be set by meta.yaml script_env}"

# Use the conda LLVM/Rust toolchains instead of letting the build fetch its own.
export BUN_TOOLCHAIN_LLVM="${BUILD_PREFIX}"
export BUN_TOOLCHAIN_RUST="${BUILD_PREFIX}"
export BUN_TOOLCHAIN_CARGO="${BUILD_PREFIX}/bin/cargo"

# -Zbuild-std needs rust-src (the rust-src-nightly build dep) in the sysroot.
test -f "$("${BUILD_PREFIX}/bin/rustc" --print sysroot)/lib/rustlib/src/rust/library/Cargo.lock"

# bun defaults every build to canary (scripts/build/config.ts), which tags the
# version "-canary.1", enables experimental features and points `bun upgrade`
# at the canary channel. Upstream's release lanes pass --canary=off.
bun_args=(--profile=release --canary=off)

if [[ "${target_platform}" == osx-* ]]; then
  # bun drives clang itself and ignores the conda-injected CPPFLAGS, so expose
  # the host prefix's ICU headers through clang's implicit include path.
  export CPATH="${PREFIX}/include${CPATH:+:${CPATH}}"

  # conda's clang passes `-lto_library <prefix>/lib/libLTO.21.1.dylib` to the
  # linker, and Apple's ld rejects that basename ("library filename must be
  # 'libLTO.dylib'"). Link with ld64.lld instead, via clang config files: clang
  # reads <driver>.cfg next to its binary, and options from a config file do
  # not trigger unused-argument warnings on compile-only invocations (-Werror).
  #
  # The -U entries are ICU symbols the prebuilt WebKit references but the
  # worker's older SDK libicucore stub does not list. The OS libicucore on the
  # 13.0 deployment floor exports all of them (the upstream release binary
  # imports the same 11 symbols with minos 13.0), so let dyld bind them at load.
  for drv in clang clang++; do
    {
      echo "-fuse-ld=lld"
      for sym in \
        unumrf_closeResult unumrf_openResult unumrf_resultAsValue \
        unumrf_formatDoubleRange unumrf_formatDecimalRange unumrf_close \
        unumrf_openForSkeletonWithCollapseAndIdentityFallback \
        ubrk_clone uplrules_selectForRange udtitvfmt_formatCalendarToResult \
        ucal_getTimeZoneOffsetFromLocal; do
        echo "-Wl,-U,_${sym}"
      done
    } >> "${BUILD_PREFIX}/bin/${drv}.cfg"
  done

  # bun refuses an SDK older than 13.0 unless --ci is set; --ci floors the
  # deployment target at 13.0 instead of probing the worker's older Xcode SDK.
  bun_args+=(--ci=true)
fi

bun scripts/build.ts "${bun_args[@]}"

mkdir -p "${PREFIX}/bin"
cp build/release/bun "${PREFIX}/bin/bun"
ln -sf bun "${PREFIX}/bin/bunx"

# `bun completions` prints these files verbatim (include_bytes! in
# src/runtime/cli/shell_completions.rs), so install them from the source tree.
mkdir -p "${PREFIX}/share/zsh/site-functions" \
  "${PREFIX}/share/bash-completion/completions" \
  "${PREFIX}/share/fish/vendor_completions.d"
cp completions/bun.zsh "${PREFIX}/share/zsh/site-functions/_bun"
cp completions/bun.bash "${PREFIX}/share/bash-completion/completions/bun"
cp completions/bun.fish "${PREFIX}/share/fish/vendor_completions.d/bun.fish"
