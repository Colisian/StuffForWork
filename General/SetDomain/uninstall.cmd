@echo off

REM Delete the DefaultDomainName registry key
REG DELETE "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DefaultDomainName /f