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
set BUN_TOOLCHAIN_RUST=%BUILD_PREFIX%\Library
set BUN_TOOLCHAIN_CARGO=%BUILD_PREFIX%\Library\bin\cargo.exe
set "PATH=%BUILD_PREFIX%\Library\bin;%PATH%"

REM CI=true makes the build take its CI path rather than the local-dev path.
set CI=true

bun scripts/build.ts --profile=release
if errorlevel 1 exit 1

if not exist %LIBRARY_BIN% mkdir %LIBRARY_BIN%
copy build\release\bun.exe %LIBRARY_BIN%\bun.exe
if errorlevel 1 exit 1

REM bunx is the same binary; it dispatches on argv[0].
copy build\release\bun.exe %LIBRARY_BIN%\bunx.exe
if errorlevel 1 exit 1

REM `bun completions` only emits bash/zsh/fish scripts, and on Windows it always
REM targets PowerShell, which upstream has not implemented (oven-sh/bun#8939):
REM   error: PowerShell completions are not yet written for Bun.
REM Setting SHELL makes no difference, so there is nothing to install here.
