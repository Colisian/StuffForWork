@echo off
REM =========================================
REM SysAid Agent - Uninstaller
REM =========================================
wmic product where "name like '%%SysAid Agent%%'" call uninstall /nointeractive
exit /b 0
