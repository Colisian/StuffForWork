
Const ADS_UF_PASSWD_CANT_CHANGE = &H10040

Dim objNetwork, strComputerName, strLocalAccount, objFSO, objTextFile,objShell,strReg
Set objNetwork = CreateObject("WScript.Network")
strComputer = objNetwork.ComputerName 

Set objFSO = CreateObject("Scripting.FileSystemObject") 
Set objTextFile = objFSO.OpenTextFile("\\ussshare.lib.umd.edu\sccmshare\Public_Software\LibGuestCreation\libguest.txt",1)
strPassword = "56F8BE64B7ADF164A085525C2E6D77B2F17F32E2B1537568580B92BCF5631DDE!a"

' suppress errors
On Error Resume Next

Do Until objTextFile.AtEndOfStream
   
 strLocalAccount = objTextFile.Readline

 Set objSystem = GetObject("WinNT://" & strComputer)
 Set objUser = objSystem.Create("user", strLocalAccount)
 objUser.SetPassword strPassword
 objUser.Description = "Library Local Guest Account"
 objPasswordCantChangeFlag = ADS_UF_PASSWD_CANT_CHANGE
 objUser.Put "userFlags", objPasswordCantChangeFlag
 objUser.SetInfo


 Set objShell = WScript.CreateObject("WScript.Shell")
 strReg = "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\UserList\" & strLocalAccount & "@UMD.EDU"
 objShell.RegWrite strReg, strLocalAccount , "REG_SZ"
	
Loop
objTextFile.close