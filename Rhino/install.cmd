@echo off
"%~dp0rhino_en-us_8.15.25019.13001.exe" -package -quiet LICENSE_METHOD=ZOO ZOO_SERVER=rhinolicenseserver.lib.umd.edu INSTALLDIR="C:\Program Files\Rhino 8" SEND_STATISTICS=0 ENABLE_AUTOMATIC_UPDATES=1
exit /b %errorlevel%

