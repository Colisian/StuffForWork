@echo off
rem Silent uninstall script for QGIS versions (for Intune Win32 app)

setlocal enabledelayedexpansion
set "GUID1={0446700B-6EF9-1014-AB41-BEABDF7FB718}"
set "GUID2={D1F2F3CD-75D9-1014-AC52-BB4ECD31B53F}"
set "LOG=%TEMP%\QGIS_uninstall_%COMPUTERNAME%_%RANDOM%.log"
echo %date% %time% - QGIS uninstall started > "%LOG%"

rem 0 = success/no errors, non-zero = last failing msiexec code
set "ERRORCODE=0"

call :CheckAndUninstall "%GUID1%"
call :CheckAndUninstall "%GUID2%"

rem Remove Program Files QGIS folders except the one we want to keep
set "KEEP_NAME=QGIS 3.44.3"
set "REMOVAL_FAILED=0"

rem Check both Program Files locations
for %%P in ("%ProgramFiles%") do (
    if exist "%%~P" (
        for /d %%D in ("%%~P\QGIS *") do (
            set "BNAME=%%~nxD"
            if /I not "!BNAME!"=="!KEEP_NAME!" (
                echo %date% %time% - Removing folder "%%~D" >> "%LOG%"
                rd /s /q "%%~D" 2>> "%LOG%"
                if errorlevel 1 (
                    echo %date% %time% - FAILED to remove "%%~D" >> "%LOG%"
                    set "REMOVAL_FAILED=1"
                ) else (
                    echo %date% %time% - Removed "%%~D" >> "%LOG%"
                )
            ) else (
                echo %date% %time% - Skipping keep folder "%%~D" >> "%LOG%"
            )
        )
    )
)

rem Also check Program Files (x86) if defined (64-bit machines)
if defined ProgramFiles(x86) (
    for %%P in ("%ProgramFiles(x86)%") do (
        if exist "%%~P" (
            for /d %%D in ("%%~P\QGIS *") do (
                set "BNAME=%%~nxD"
                if /I not "!BNAME!"=="!KEEP_NAME!" (
                    echo %date% %time% - Removing folder "%%~D" >> "%LOG%"
                    rd /s /q "%%~D" 2>> "%LOG%"
                    if errorlevel 1 (
                        echo %date% %time% - FAILED to remove "%%~D" >> "%LOG%"
                        set "REMOVAL_FAILED=1"
                    ) else (
                        echo %date% %time% - Removed "%%~D" >> "%LOG%"
                    )
                ) else (
                    echo %date% %time% - Skipping keep folder "%%~D" >> "%LOG%"
                )
            )
        )
    )
)

if "!REMOVAL_FAILED!"=="1" (
    rem mark an error if no other errors present
    if "%ERRORCODE%"=="0" set "ERRORCODE=1"
)

if "%ERRORCODE%"=="0" (
    echo %date% %time% - All uninstalls succeeded or not present. >> "%LOG%"
    exit /b 0
) else (
    echo %date% %time% - One or more uninstalls/removals failed. Last error=%ERRORCODE% >> "%LOG%"
    exit /b %ERRORCODE%
)

:CheckAndUninstall
set "GUID=%~1"
echo %date% %time% - Checking %GUID% >> "%LOG%"

rem Check both 64-bit and 32-bit uninstall registry locations
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\%GUID%" >nul 2>&1
if errorlevel 1 (
    reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\%GUID%" >nul 2>&1
    if errorlevel 1 (
        echo %date% %time% - %GUID% not found (skipping) >> "%LOG%"
        goto :eof
    )
)

echo %date% %time% - %GUID% found, starting silent uninstall... >> "%LOG%"
msiexec /x%GUID% /qn /norestart /l*v "%TEMP%\qgis_uninstall_%GUID%.log"
set "RC=%ERRORLEVEL%"
echo %date% %time% - msiexec returned %RC% for %GUID% >> "%LOG%"

if not "%RC%"=="0" (
    set "ERRORCODE=%RC%"
) else (
    echo %date% %time% - Uninstall succeeded for %GUID% >> "%LOG%"
)

goto :eof