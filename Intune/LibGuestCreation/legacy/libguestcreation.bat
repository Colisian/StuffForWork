@echo off
regedit /s "\\ussshare.lib.umd.edu\sccmshare\Public_Software\LibGuestCreation\kerberos.reg"
cscript "\\ussshare.lib.umd.edu\sccmshare\Public_Software\LibGuestCreation\libguest.vbs"