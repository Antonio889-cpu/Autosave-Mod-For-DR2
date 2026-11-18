@echo off
setlocal
cd /d "%~dp0"
set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%"
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat" >nul || exit /b 1
if not exist out mkdir out

cl /nologo /W4 /O2 /MT /Foout\ /Feout\test_vfs.exe test_vfs.c || exit /b 1
out\test_vfs.exe || exit /b 1

cl /nologo /W3 /O2 /MT /LD /Foout\ /Feout\d3dx9_43.dll dr2_autosave.c kernel32.lib user32.lib gdi32.lib shell32.lib /link /DEF:dr2_autosave.def || exit /b 1
