# Compatible con Windows PowerShell 5.1; no imprime ni versiona claves.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Demo','Oracle')][string]$Modo,
    [string]$Directorio,
    [string]$WalletPath = 'C:\Wallet_BIBLIOTECA',
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Alias = 'biblioteca_low',
    [ValidateRange(1024,65535)][int]$Puerto = 8090,
    [switch]$ValidarSolamente
)
$ErrorActionPreference = 'Stop'
if (-not $Directorio) { $Directorio = Join-Path $PSScriptRoot ('../runtime/' + $Modo.ToLowerInvariant()) }
$taskDir = [IO.Path]::GetFullPath($Directorio)
$taskSecrets = Join-Path $taskDir 'secrets'
$taskEnvFile = Join-Path $taskDir 'compose.env'
if ($Modo -eq 'Oracle') {
    $taskWallet = [IO.Path]::GetFullPath($WalletPath)
    $taskTnsPath = Join-Path $taskWallet 'tnsnames.ora'
    if (-not (Test-Path -LiteralPath $taskTnsPath -PathType Leaf)) { throw 'El wallet no contiene tnsnames.ora.' }
    if ([IO.File]::ReadAllText($taskTnsPath) -notmatch ('(?mi)^\s*'+[regex]::Escape($Alias)+'\s*=')) { throw 'El alias no existe en el wallet.' }
}
if (Test-Path -LiteralPath $taskDir) { throw ('La carpeta ya existe. Se conserva sin cambiar claves: ' + $taskDir) }
if ($ValidarSolamente) { [pscustomobject]@{Modo=$Modo;Directorio=$taskDir;Puerto=$Puerto;Alias=$Alias}; return }
New-Item -ItemType Directory -Path $taskSecrets -Force | Out-Null
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $taskAcl = [Security.AccessControl.DirectorySecurity]::new()
    $taskAcl.SetAccessRuleProtection($true,$false)
    $taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $taskAcl.SetOwner($taskIdentity)
    $taskInheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($taskSid in @($taskIdentity,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $taskRule = [Security.AccessControl.FileSystemAccessRule]::new($taskSid,[Security.AccessControl.FileSystemRights]::FullControl,$taskInheritance,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $taskAcl.AddAccessRule($taskRule)
    }
    Set-Acl -LiteralPath $taskDir -AclObject $taskAcl
} else { throw 'Este preparador se ejecuta en Windows. Para Linux usa las instrucciones de permisos del README.' }
$taskUtf8 = [Text.UTF8Encoding]::new($false)
$taskRng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $taskBytes = New-Object byte[] 32
    $taskRng.GetBytes($taskBytes)
    [IO.File]::WriteAllText((Join-Path $taskSecrets 'jwt-secret-base64'),[Convert]::ToBase64String($taskBytes),$taskUtf8)
    [Array]::Clear($taskBytes,0,$taskBytes.Length)
    foreach ($taskService in @('usuarios','contenido','moderacion')) {
        if ($Modo -eq 'Demo') { $taskValue = 'DemoAa1!' + [Guid]::NewGuid().ToString('N') }
        else {
            $taskSecure = Read-Host ('Contrasena de FORO_' + $taskService.ToUpperInvariant() + ', sin comillas') -AsSecureString
            try {
                if ($taskSecure.Length -eq 0) { throw 'La contrasena no puede estar vacia.' }
                $taskValue = [Net.NetworkCredential]::new('', $taskSecure).Password
            } finally { $taskSecure.Dispose() }
        }
        [IO.File]::WriteAllText((Join-Path $taskSecrets ($taskService + '-db-password')),$taskValue,$taskUtf8)
        $taskValue = $null
    }
    [IO.File]::WriteAllText((Join-Path $taskSecrets 'bootstrap-admin-password'),('DemoAa1!'+[Guid]::NewGuid().ToString('N')),$taskUtf8)
    $taskEnv = @("FORO_SECRETS_DIR='$($taskSecrets.Replace('\','/').Replace("'","\'"))'", "LOCAL_HTTP_PORT=$Puerto")
    if ($Modo -eq 'Oracle') { $taskEnv += @("ORACLE_WALLET_DIR='$($taskWallet.Replace('\','/').Replace("'","\'"))'", "ORACLE_TNS_ALIAS=$Alias") }
    [IO.File]::WriteAllText($taskEnvFile,($taskEnv -join "`n")+"`n",$taskUtf8)
    [IO.File]::WriteAllText((Join-Path $taskDir 'modo.txt'),$Modo,$taskUtf8)
    Write-Output ('Configuracion ' + $Modo + ' preparada. No se imprimieron claves.')
    Write-Output ('Archivo para --env-file: ' + $taskEnvFile)
} finally { $taskRng.Dispose() }
