@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "USE_DEV=0"
set "DRY_RUN=0"

:parse_flags
if /i "%~1"=="--dev" (
    set "USE_DEV=1"
    shift
    goto :parse_flags
)
if /i "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    shift
    goto :parse_flags
)

set "MAP_ARG="
if not "%~1"=="" set "MAP_ARG=%~1"

if "%USE_DEV%"=="0" (
    if exist "%ROOT%BZ_MAP_MAG.exe" if exist "%ROOT%BZ_MAP_MAG.pck" (
        if "%DRY_RUN%"=="1" (
            if defined MAP_ARG (
                echo "%ROOT%BZ_MAP_MAG.exe" "%MAP_ARG%"
            ) else (
                echo "%ROOT%BZ_MAP_MAG.exe"
            )
            exit /b 0
        )
        if defined MAP_ARG (
            start "" /D "%ROOT%" "%ROOT%BZ_MAP_MAG.exe" "%MAP_ARG%"
        ) else (
            start "" /D "%ROOT%" "%ROOT%BZ_MAP_MAG.exe"
        )
        exit /b 0
    )
)

set "GODOT_EXE="
if defined BZ_MAP_MAG_GODOT if exist "%BZ_MAP_MAG_GODOT%" set "GODOT_EXE=%BZ_MAP_MAG_GODOT%"
if not defined GODOT_EXE (
    for /f "delims=" %%I in ('where godot.exe 2^>nul') do (
        if not defined GODOT_EXE set "GODOT_EXE=%%I"
    )
)
if not defined GODOT_EXE (
    if exist "V:\__STORE_V\_SOFT\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe" (
        set "GODOT_EXE=V:\__STORE_V\_SOFT\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"
    )
)

if not defined GODOT_EXE (
    echo [BZ_MAP_MAG] Neither BZ_MAP_MAG.exe nor Godot 4.7.2 was found.
    echo Set BZ_MAP_MAG_GODOT or run tools\Build-Desktop.ps1 -ToRoot.
    exit /b 1
)

if "%DRY_RUN%"=="1" (
    if defined MAP_ARG (
        echo "%GODOT_EXE%" --path "%ROOT%app" -- "%MAP_ARG%"
    ) else (
        echo "%GODOT_EXE%" --path "%ROOT%app"
    )
    exit /b 0
)
if defined MAP_ARG (
    start "" /D "%ROOT%" "%GODOT_EXE%" --path "%ROOT%app" -- "%MAP_ARG%"
) else (
    start "" /D "%ROOT%" "%GODOT_EXE%" --path "%ROOT%app"
)
exit /b 0
