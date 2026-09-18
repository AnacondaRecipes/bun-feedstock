@echo on

REM Bootstrap bun from the bun.native zip; the source tarball ships no binary.
set "BUN_BOOTSTRAP="
for /f "delims=" %%i in ('dir /b /s "%SRC_DIR%\bun.native\bun.exe" 2^>nul') do set "BUN_BOOTSTRAP=%%i"
if not defined BUN_BOOTSTRAP (
  echo could not find the bootstrap bun.exe under %SRC_DIR%\bun.native
  exit 1
)
for %%i in ("%BUN_BOOTSTRAP%") do set "PATH=%%~dpi;%PATH%"

REM The source tarball has no .git checkout, so the build cannot derive a
REM revision; supply the release commit.
set GIT_SHA=744846f844374847c902b5e7fd59b4342a51ef99

REM Use the conda LLVM/Rust toolchains instead of letting the build fetch its own.
REM On Windows conda installs these under Library\bin, not bin.
set BUN_TOOLCHAIN_LLVM=%BUILD_PREFIX%\Library
set BUN_TOOLCHAIN_RUST=%BUILD_PREFIX%
set BUN_TOOLCHAIN_CARGO=%BUILD_PREFIX%\Library\bin\cargo.exe
set "PATH=%BUILD_PREFIX%\Library\bin;%PATH%"

REM CI=true makes the build take its CI path rather than the local-dev path.
set CI=true

REM conda's rust-nightly does not ship the rust-src component, which the release
REM profile requires for -Zbuild-std (scripts/build/rust.ts).
if not exist "%BUILD_PREFIX%\lib\rustlib\src\rust\library\Cargo.lock" (
  curl -sSL -o rust-src-nightly.tar.gz "https://static.rust-lang.org/dist/2026-08-18/rust-src-nightly.tar.gz"
  if errorlevel 1 exit 1
  tar -xzf rust-src-nightly.tar.gz
  if errorlevel 1 exit 1
  if not exist "%BUILD_PREFIX%\lib\rustlib\src" mkdir "%BUILD_PREFIX%\lib\rustlib\src"
  xcopy /E /I /Y "rust-src-nightly\rust-src\lib\rustlib\src\rust" "%BUILD_PREFIX%\lib\rustlib\src\rust"
  if errorlevel 1 exit 1
)

bun scripts/build.ts --profile=release
if errorlevel 1 exit 1

if not exist %LIBRARY_BIN% mkdir %LIBRARY_BIN%
copy build\release\bun.exe %LIBRARY_BIN%\bun.exe
if errorlevel 1 exit 1

REM bunx is the same binary; it dispatches on argv[0].
copy build\release\bun.exe %LIBRARY_BIN%\bunx.exe
if errorlevel 1 exit 1

REM The shell completion text is architecture-independent.
mkdir "%PREFIX%\share\bash-completion\completions" 2>nul
mkdir "%PREFIX%\share\zsh\site-functions" 2>nul
mkdir "%PREFIX%\share\fish\vendor_completions.d" 2>nul

set SHELL=bash
"%LIBRARY_BIN%\bun.exe" completions > "%PREFIX%\share\bash-completion\completions\bun"
if errorlevel 1 exit 1
findstr /c:"_file_arguments()" "%PREFIX%\share\bash-completion\completions\bun" >nul
if errorlevel 1 exit 1

set SHELL=zsh
"%LIBRARY_BIN%\bun.exe" completions > "%PREFIX%\share\zsh\site-functions\_bun"
if errorlevel 1 exit 1
findstr /c:"_bun_add_completion" "%PREFIX%\share\zsh\site-functions\_bun" >nul
if errorlevel 1 exit 1

set SHELL=fish
"%LIBRARY_BIN%\bun.exe" completions > "%PREFIX%\share\fish\vendor_completions.d\bun.fish"
if errorlevel 1 exit 1
findstr /c:"__fish__get_bun_bins" "%PREFIX%\share\fish\vendor_completions.d\bun.fish" >nul
if errorlevel 1 exit 1
