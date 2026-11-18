@echo off
setlocal
cd /d "%~dp0"
call "%~dp0build.bat" || exit /b 1
cd /d "%~dp0"
"C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe" setup\DR2AutosaveSetup.csproj /nologo /v:minimal /p:Configuration=Release || exit /b 1
if not exist dist mkdir dist
copy /y out\setup\DR2_Autosave_Setup.exe dist\ >nul || exit /b 1
echo Package ready: %~dp0dist\DR2_Autosave_Setup.exe
