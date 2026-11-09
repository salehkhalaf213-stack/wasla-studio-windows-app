@echo off
setlocal
cd /d "%~dp0"
echo ==========================================
echo   WASLA STUDIO - Windows EXE Builder
echo ==========================================
where node >nul 2>nul || (echo [ERROR] Install Node.js 22 first.& pause & exit /b 1)
where rustc >nul 2>nul || (echo [ERROR] Install Rust stable with MSVC toolchain first.& pause & exit /b 1)
if not exist node_modules\ (
  echo Installing dependencies...
  call npm install
  if errorlevel 1 (echo [ERROR] npm install failed.& pause & exit /b 1)
)
echo Building NSIS installer...
call npm run tauri -- build --bundles nsis
if errorlevel 1 (echo [ERROR] Build failed. Check README_AR.md for prerequisites.& pause & exit /b 1)
echo.
echo Build completed. Look in src-tauri\target\release\bundle\nsis\
explorer "%~dp0src-tauri\target\release\bundle\nsis"
pause
