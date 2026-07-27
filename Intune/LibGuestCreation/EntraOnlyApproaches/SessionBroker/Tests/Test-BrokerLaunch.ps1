<#
.SYNOPSIS
    Exercises the CreateProcessWithLogonW path directly, with no gate and no UI.

.DESCRIPTION
    Loads LibGuestBrokerNative.cs and calls StartSession against whatever
    credential you supply, reporting the raw result: Win32 error, resolved token
    SID, and resolved account name.

    The point is to separate three failure modes that are easy to confuse when the
    full broker misbehaves:

      1. Does the native layer work at all? (P/Invoke, job object, token readback)
      2. Does Windows accept this credential?
      3. Does the session gate pass on this machine?

    This script answers 1 and 2 on any ordinary Windows box using a throwaway local
    account, so only 3 genuinely requires the Shared PC device. Run it before
    spending a trip to LIBR8ZCBLK4.

.PARAMETER UserName
    Bare SAM name for a local account test, or full UPN for the real thing.

.PARAMETER Domain
    Machine name when testing a local account. Omit for a UPN: CreateProcessWithLogonW
    requires a null domain when the username is a UPN.

.PARAMETER ApplicationPath
    Absolute path to launch. Defaults to whoami.exe.

.PARAMETER Arguments
    Fixed arguments. Never patron-supplied in production.

.PARAMETER Mode
    IdentityTest leaves the process suspended, reads its token, and tears it down,
    so nothing executes as the target user. Session resumes the process and waits.

.PARAMETER TimeoutSeconds
    Session mode only. How long to wait for the launched process to exit.

.EXAMPLE
    # Local-account smoke test on a dev VM. Proves the native layer works.
    net user libtest 'SomeThrowawayPassword!' /add
    .\Test-BrokerLaunch.ps1 -UserName libtest -Domain $env:COMPUTERNAME

.EXAMPLE
    # The real Phase 1 check on LIBR8ZCBLK4, with a live SIMS password.
    .\Test-BrokerLaunch.ps1 -UserName libguest1@UMD.EDU

.EXAMPLE
    # Watch a real application run as the target identity.
    .\Test-BrokerLaunch.ps1 -UserName libtest -Domain $env:COMPUTERNAME -Mode Session `
        -ApplicationPath "$env:SystemRoot\System32\notepad.exe"

.NOTES
    Author:  Oji / UMD Libraries
    Date:    2026-07-26
    Version: 0.2.0

    Windows only. Requires the Secondary Logon service and a non-SYSTEM caller.
    Prompts for the password; never accepts it as a parameter, so it cannot land
    in command lines, transcripts, or PSReadLine history.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UserName,

    [string]$Domain,

    [string]$ApplicationPath = "$env:SystemRoot\System32\whoami.exe",

    [string]$Arguments = '',

    [ValidateSet('IdentityTest', 'Session', 'LaunchAndExit')]
    [string]$Mode = 'IdentityTest',

    [int]$TimeoutSeconds = 120
)

begin {
    $ErrorActionPreference = 'Stop'
}

end {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        throw 'This script requires Windows.'
    }

    $nativeSource = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Prototype') 'LibGuestBrokerNative.cs'
    if (-not (Test-Path -LiteralPath $nativeSource -PathType Leaf)) {
        throw "Native launcher source not found: $nativeSource"
    }
    if (-not (Test-Path -LiteralPath $ApplicationPath -PathType Leaf)) {
        throw "Application not found: $ApplicationPath"
    }

    Write-Host "`n=== Preflight ===" -ForegroundColor Cyan

    $secondaryLogon = Get-Service -Name 'seclogon' -ErrorAction SilentlyContinue
    if (-not $secondaryLogon) {
        throw 'The Secondary Logon service is not installed. CreateProcessWithLogonW cannot work.'
    }
    if ($secondaryLogon.StartType -eq 'Disabled') {
        throw 'The Secondary Logon service is Disabled. Enable it, or CreateProcessWithLogonW will fail on this machine.'
    }
    Write-Host ('  Secondary Logon : {0} / {1}' -f $secondaryLogon.StartType, $secondaryLogon.Status)

    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($currentIdentity.IsSystem) {
        throw 'CreateProcessWithLogonW cannot be called from a LocalSystem process.'
    }
    Write-Host ('  Running as      : {0}' -f $currentIdentity.Name)
    Write-Host ('  PowerShell      : {0} ({1})' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)

    # This is where the C# 5 assumption gets its real test. Windows PowerShell 5.1
    # compiles Add-Type sources with the in-box CodeDOM provider, not Roslyn.
    Write-Host "`n=== Compiling LibGuestBrokerNative.cs ===" -ForegroundColor Cyan
    if ('UMD.Libraries.LibGuest.BrokerLauncher' -as [type]) {
        Write-Host '  Already loaded in this session.'
    }
    else {
        Add-Type -Path $nativeSource
        Write-Host '  Compiled successfully.'
    }

    $targetLabel = if ($Domain) { '{0}\{1}' -f $Domain, $UserName } else { $UserName }
    Write-Host "`n=== Launch ===" -ForegroundColor Cyan
    Write-Host ('  Identity    : {0}' -f $targetLabel)
    Write-Host ('  Application : {0} {1}' -f $ApplicationPath, $Arguments)
    Write-Host ('  Mode        : {0}' -f $Mode)

    $securePassword = Read-Host -Prompt "`nPassword for $targetLabel" -AsSecureString
    if ($securePassword.Length -eq 0) {
        throw 'No password entered.'
    }

    try {
        $result = [UMD.Libraries.LibGuest.BrokerLauncher]::StartSession(
            $UserName,
            $Domain,
            $securePassword,
            $ApplicationPath,
            $Arguments,
            [System.IO.Path]::GetDirectoryName($ApplicationPath),
            ($Mode -ne 'IdentityTest'),
            ($Mode -eq 'Session')
        )
    }
    finally {
        $securePassword.Dispose()
    }

    Write-Host "`n=== Result ===" -ForegroundColor Cyan

    if (-not $result.Succeeded) {
        $win32Message = try { ([System.ComponentModel.Win32Exception]::new($result.Win32Error)).Message } catch { 'unknown' }
        Write-Host ('  FAILED at {0}' -f $result.FailureStage) -ForegroundColor Red
        Write-Host ('  Win32Error : {0} ({1})' -f $result.Win32Error, $win32Message) -ForegroundColor Red
        Write-Host ''
        switch ($result.Win32Error) {
            1326 { Write-Host '  Wrong username or password, or the KDC rejected the principal.' }
            1327 { Write-Host '  Account restriction. A blank password on an account that disallows one is a common cause.' }
            1331 { Write-Host '  The account is disabled.' }
            1909 { Write-Host '  The account is locked out.' }
            1311 { Write-Host '  No logon servers available. Check DNS SRV records and port 88 to the KDC.' }
            1355 { Write-Host '  The specified domain/realm does not exist or could not be contacted.' }
            1385 { Write-Host '  Logon type not granted. Check "Log on as a batch job" / interactive rights.' }
            1058 { Write-Host '  The Secondary Logon service is disabled.' }
            default { Write-Host '  See the Windows system error code reference for this value.' }
        }
        exit 1
    }

    Write-Host '  SUCCEEDED' -ForegroundColor Green
    Write-Host ('  ProcessId    : {0}' -f $result.ProcessId)
    Write-Host ('  TokenAccount : {0}' -f $result.TokenAccount)
    Write-Host ('  TokenSid     : {0}' -f $result.TokenSid)
    Write-Host ''
    Write-Host '  ^ TokenAccount is the whole point: it is the identity Windows actually' -ForegroundColor Yellow
    Write-Host '    produced. On LIBR8ZCBLK4 it must be the LOCAL libguestN matching the' -ForegroundColor Yellow
    Write-Host '    number you entered. Anything else means the Kerberos UserList mapping' -ForegroundColor Yellow
    Write-Host '    is wrong, and Phase 2 must not proceed.' -ForegroundColor Yellow

    if ($Mode -eq 'IdentityTest') {
        Write-Host "`n  Identity-test mode: the process was created suspended, inspected, and"
        Write-Host '  terminated. Nothing executed as the target user.'
        exit 0
    }

    if ($Mode -eq 'LaunchAndExit') {
        Write-Host "`n  Launch-and-exit mode: no job object was created and the handles have"
        Write-Host '  been released. The application keeps running now that this script is'
        Write-Host '  finished. There is no session timer and no cleanup.'
        exit 0
    }

    Write-Host "`n=== Session ===" -ForegroundColor Cyan
    Write-Host ('  Waiting up to {0}s for the application to exit.' -f $TimeoutSeconds)
    Write-Host '  Check Task Manager now: the launched process should show the target'
    Write-Host '  identity while this PowerShell window still shows yours.'
    Write-Host '  Press Ctrl+C to terminate the session early.'

    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if ([UMD.Libraries.LibGuest.BrokerLauncher]::WaitForSessionExit(1000)) {
                Write-Host "`n  Application exited on its own." -ForegroundColor Green
                break
            }
        }
        if ((Get-Date) -ge $deadline) {
            Write-Host "`n  Timeout reached. Terminating the job." -ForegroundColor Yellow
        }
    }
    finally {
        [UMD.Libraries.LibGuest.BrokerLauncher]::EndSession()
        Write-Host '  Session ended; job object closed.'
        Write-Host ''
        Write-Host '  Cleanup check: confirm no child processes of the launched application' -ForegroundColor Yellow
        Write-Host '  survived. If any did, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is not working' -ForegroundColor Yellow
        Write-Host '  and Phase 3 process supervision cannot be trusted.' -ForegroundColor Yellow
    }

    exit 0
}
