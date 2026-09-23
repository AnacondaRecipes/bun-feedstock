@echo on

REM Bootstrap bun from the bun.native zip; the source tarball ships no binary.
set "BUN_BOOTSTRAP="
for /f "delims=" %%i in ('dir /b /s "%SRC_DIR%\bun.native\bun.exe" 2^>nul') do set "BUN_BOOTSTRAP=%%i"
if not defined BUN_BOOTSTRAP (
  echo could not find the bootstrap bun.exe under %SRC_DIR%\bun.native
  exit 1
)
for %%i in ("%BUN_BOOTSTRAP%") do set "PATH=%%~dpi;%PATH%"

REM The source tarball has no .git checkout; meta.yaml passes the release
REM commit via script_env.
if not defined GIT_SHA (
  echo GIT_SHA must be set by meta.yaml script_env
  exit 1
)

REM Use the conda LLVM/Rust toolchains instead of letting the build fetch its own.
REM On Windows conda installs these under Library\bin, not bin.
set BUN_TOOLCHAIN_LLVM=%BUILD_PREFIX%\Library
set BUN_TOOLCHAIN_RUST=%BUILD_PREFIX%\Library
set BUN_TOOLCHAIN_CARGO=%BUILD_PREFIX%\Library\bin\cargo.exe
set "PATH=%BUILD_PREFIX%\Library\bin;%PATH%"

REM The release profile (and the .bin\ shim) rebuild std/core with -Zbuild-std,
REM which needs the rust-src component (a separate meta.yaml source) inside the
REM rustc sysroot.
set "RUST_SYSROOT="
for /f "delims=" %%i in ('rustc --print sysroot') do set "RUST_SYSROOT=%%i"
if not defined RUST_SYSROOT exit 1
REM conda-build strips the tarball's single top-level directory; accept both.
set "RUST_SRC="
if exist "%SRC_DIR%\rust-src\rust-src\lib\rustlib\src\rust\library\Cargo.lock" set "RUST_SRC=%SRC_DIR%\rust-src\rust-src\lib\rustlib\src\rust"
if exist "%SRC_DIR%\rust-src\rust-src-nightly\rust-src\lib\rustlib\src\rust\library\Cargo.lock" set "RUST_SRC=%SRC_DIR%\rust-src\rust-src-nightly\rust-src\lib\rustlib\src\rust"
if not defined RUST_SRC (
  echo rust-src component not found under %SRC_DIR%\rust-src
  exit 1
)
if not exist "%RUST_SRC%\library\Cargo.lock" exit 1
xcopy /E /I /Q /Y "%RUST_SRC%" "%RUST_SYSROOT%\lib\rustlib\src\rust"
if errorlevel 1 exit 1

REM bun defaults every build to canary (scripts/build/config.ts); upstream's
REM release lanes pass --canary=off.
bun scripts/build.ts --profile=release --canary=off
if errorlevel 1 exit 1

if not exist %LIBRARY_BIN% mkdir %LIBRARY_BIN%
copy build\release\bun.exe %LIBRARY_BIN%\bun.exe
if errorlevel 1 exit 1

REM bunx is the same binary; it dispatches on argv[0].
copy build\release\bun.exe %LIBRARY_BIN%\bunx.exe
if errorlevel 1 exit 1

REM `bun completions` prints these files verbatim (include_bytes! in
REM src/runtime/cli/shell_completions.rs); on Windows the command itself only
REM reports that PowerShell is unsupported, so install them from the source
REM tree for bash/zsh/fish users (Git Bash, MSYS2).
for %%d in (zsh\site-functions bash-completion\completions fish\vendor_completions.d) do (
  if not exist "%LIBRARY_PREFIX%\share\%%d" mkdir "%LIBRARY_PREFIX%\share\%%d"
)
copy completions\bun.zsh "%LIBRARY_PREFIX%\share\zsh\site-functions\_bun"
if errorlevel 1 exit 1
copy completions\bun.bash "%LIBRARY_PREFIX%\share\bash-completion\completions\bun"
if errorlevel 1 exit 1
copy completions\bun.fish "%LIBRARY_PREFIX%\share\fish\vendor_completions.d\bun.fish"
if errorlevel 1 exit 1
