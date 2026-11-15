@echo off
setlocal
rem Builds the windowless, optimized client and packs it with its assets and shaders:
rem   release.bat [version]
rem makes build\swgr-<version>.7z; the version defaults to the git short hash.
rem Blender sources under assets\3d stay out of the archive, the game loads the .obj files.

cd /d "%~dp0"

set "VERSION=%~1"
if "%VERSION%"=="" for /f %%h in ('git rev-parse --short HEAD 2^>nul') do set "VERSION=%%h"
if "%VERSION%"=="" set "VERSION=dev"

set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
where 7z >nul 2>nul && set "SEVENZIP=7z"
if not "%SEVENZIP%"=="7z" if not exist "%SEVENZIP%" (
	echo 7-Zip not found, neither on PATH nor in "%ProgramFiles%\7-Zip"
	exit /b 1
)

set "STAGE=build\release"
set "ARCHIVE=build\swgr-v%VERSION%-win.7z"

if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%" || exit /b 1

echo building swgr.exe
odin build . -subsystem:windows -o:speed -out:"%STAGE%\swgr.exe" || exit /b 1

echo copying assets and shaders
xcopy /e /i /q /y assets "%STAGE%\assets" >nul || exit /b 1
xcopy /e /i /q /y shaders "%STAGE%\shaders" >nul || exit /b 1
del /s /q "%STAGE%\assets\3d\*.blend*" >nul 2>nul
copy /y config.toml.example "%STAGE%\config.toml.example" >nul || exit /b 1

echo packing %ARCHIVE%
if exist "%ARCHIVE%" del /q "%ARCHIVE%"
"%SEVENZIP%" a -t7z -mx=9 "%ARCHIVE%" ".\%STAGE%\*" >nul || exit /b 1

for %%a in ("%ARCHIVE%") do echo done: %%~fa, %%~za bytes
endlocal
