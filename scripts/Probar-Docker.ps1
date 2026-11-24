# Pruebas HTTP por el proxy. Tokens y contrasenas solo se usan en memoria.
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8090',
    [ValidateSet('Demo','Oracle')][string]$Modo = 'Demo',
    [string]$AdminCorreo,
    [string]$Directorio,
    [string]$Resultado,
    [switch]$ProbarDependencia,
    [switch]$ProbarPersistencia
)
$ErrorActionPreference = 'Stop'
$taskUri = [Uri]$BaseUrl
if (-not $taskUri.IsAbsoluteUri -or $taskUri.Scheme -notin @('http','https') -or $taskUri.UserInfo -or $taskUri.Query -or $taskUri.Fragment -or $taskUri.AbsolutePath -ne '/') { throw 'BaseUrl debe ser un origen HTTP/HTTPS sin credenciales, ruta ni query.' }
$taskLocal = $taskUri.Host -in @('127.0.0.1','localhost','::1')
if (($Modo -eq 'Demo' -or $ProbarDependencia -or $ProbarPersistencia) -and -not $taskLocal) { throw 'Demo y control de contenedores se prueban solo contra localhost. Para consulta remota usa Oracle sin los switches de reinicio.' }
if (-not $taskLocal -and $taskUri.Scheme -ne 'https') { throw 'Las pruebas publicas requieren HTTPS.' }
if ($ProbarPersistencia -and $Modo -ne 'Oracle') { throw 'La persistencia tras reinicio solo se acredita en Oracle, no en H2.' }
$taskDeployment = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Directorio) { $Directorio = Join-Path $taskDeployment ('runtime/' + $Modo.ToLowerInvariant()) }
$Directorio = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Directorio)
if (-not $Resultado) { $Resultado = Join-Path $Directorio 'resultado-http.json' }
$Resultado = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Resultado)
$taskEnvFile = Join-Path $Directorio 'compose.env'
$taskProject = 'foro-nexo-' + $Modo.ToLowerInvariant()
$taskCompose = @('compose','--project-name',$taskProject,'--env-file',$taskEnvFile,'-f',(Join-Path $taskDeployment 'compose.yml'),'-f',(Join-Path $taskDeployment ('compose.' + $Modo.ToLowerInvariant() + '.yml')),'-f',(Join-Path $taskDeployment 'compose.local.yml'))
$taskSteps = [Collections.Generic.List[object]]::new()
Add-Type -AssemblyName System.Net.Http
$taskHandler = [Net.Http.HttpClientHandler]::new()
$taskHandler.AllowAutoRedirect = $false
$taskClient = [Net.Http.HttpClient]::new($taskHandler)
$taskClient.Timeout = [TimeSpan]::FromSeconds(35)
$taskTokenAdmin = $null
$taskTokenUser = $null
$taskPassword = $null
$taskModeracionStopped = $false
function Request-Foro {
    param([string]$Nombre,[string]$Metodo,[string]$Ruta,[int]$Esperado,[string]$Token,[object]$Datos)
    $taskRequest = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Metodo), ($BaseUrl.TrimEnd('/') + $Ruta))
    try {
        if ($Token) { $taskRequest.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Token) }
        if ($null -ne $Datos) { $taskRequest.Content = [Net.Http.StringContent]::new(($Datos | ConvertTo-Json -Depth 12 -Compress),[Text.Encoding]::UTF8,'application/json') }
        $taskResponse = $taskClient.SendAsync($taskRequest).GetAwaiter().GetResult()
        try {
            $taskStatus = [int]$taskResponse.StatusCode
            if ($taskStatus -ne $Esperado) { throw ("${Nombre}: se esperaba HTTP $Esperado, se obtuvo $taskStatus ($Metodo $Ruta). No se imprimio el cuerpo para proteger tokens.") }
            $taskBody = $taskResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $taskContentType = [string]$taskResponse.Content.Headers.ContentType
            $taskJson = $null
            if ($taskContentType -match 'json' -and $taskBody) { $taskJson = $taskBody | ConvertFrom-Json }
            $taskSteps.Add([pscustomobject]@{prueba=$Nombre;http=$taskStatus})
            return [pscustomobject]@{Status=$taskStatus;Json=$taskJson;Text=$taskBody;ContentType=$taskContentType}
        } finally { $taskResponse.Dispose() }
    } finally { $taskRequest.Dispose() }
}
function Assert-Foro([bool]$Condicion,[string]$Mensaje) { if (-not $Condicion) { throw $Mensaje } }
function Invoke-ForoCompose {
    param([string[]]$Operacion,[string]$RutaLog)
    # Compose escribe progreso normal en stderr. PS5.1 lo convierte en
    # NativeCommandError; el exito se decide por el codigo, no por ese flujo.
    $taskPreviousPreference = $ErrorActionPreference
    $taskNativeCode = -1
    try {
        $ErrorActionPreference = 'Continue'
        & docker @taskCompose @Operacion *> $RutaLog
        $taskNativeCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $taskPreviousPreference }
    if ($taskNativeCode -ne 0) { throw ('Docker Compose fallo al ejecutar ' + ($Operacion -join ' ') + '. Revisa el log de dependencia.') }
}
try {
    # Verificar identidad del destino antes de leer o enviar claves.
    $taskHome = Request-Foro 'Portada Angular' GET '/' 200
    Assert-Foro ($taskHome.Text -match '<title>Foro Nexo') 'El origen no corresponde al frontend esperado.'
    $taskDeep = Request-Foro 'Ruta Angular profunda' GET '/perfil' 200
    Assert-Foro ($taskDeep.ContentType -match 'text/html') 'Falta fallback SPA.'
    $taskUnknown = Request-Foro 'API desconocida' GET '/api/ruta-inexistente-docker' 404
    Assert-Foro ($taskUnknown.ContentType -match 'application/problem\+json') 'Una API desconocida no debe recibir index.html.'
    Request-Foro 'Contenido exige token' GET '/api/temas' 401 | Out-Null
    if ($Modo -eq 'Demo') {
        $AdminCorreo = 'admin-docker@example.test'
        $taskPassword = [IO.File]::ReadAllText((Join-Path $Directorio 'secrets/bootstrap-admin-password'))
    } else {
        if (-not $AdminCorreo) { $AdminCorreo = Read-Host 'Correo del administrador DE LA APLICACION' }
        $taskSecure = Read-Host 'Contrasena de esa cuenta del foro, sin comillas' -AsSecureString
        try { $taskPassword = [Net.NetworkCredential]::new('', $taskSecure).Password } finally { $taskSecure.Dispose() }
    }
    $taskLogin = Request-Foro 'Login administrador' POST '/api/auth/login' 200 '' @{correo=$AdminCorreo;password=$taskPassword}
    $taskPassword = $null
    $taskTokenAdmin = $taskLogin.Json.accessToken
    Assert-Foro ([bool]$taskTokenAdmin) 'El login no devolvio accessToken.'
    $taskStamp = [Guid]::NewGuid().ToString('N')
    $taskAuthorMail = 'docker-' + $taskStamp + '@example.test'
    $taskAuthorPassword = 'PruebaAa1!' + $taskStamp
    Request-Foro 'Registrar autor' POST '/api/auth/registro' 201 '' @{nombre='Autor Docker';correo=$taskAuthorMail;password=$taskAuthorPassword} | Out-Null
    $taskLoginUser = Request-Foro 'Login autor' POST '/api/auth/login' 200 '' @{correo=$taskAuthorMail;password=$taskAuthorPassword}
    $taskAuthorPassword = $null
    $taskTokenUser = $taskLoginUser.Json.accessToken
    Assert-Foro ([bool]$taskTokenUser) 'El login de autor no devolvio accessToken.'
    $taskCategory = Request-Foro 'Crear categoria' POST '/api/categorias' 201 $taskTokenAdmin @{nombre=('Docker ' + $taskStamp.Substring(0,8))}
    $taskTopic = Request-Foro 'Publicar tema' POST '/api/temas' 201 $taskTokenUser @{titulo='Prueba Docker por proxy';contenido='Contenido que debe conservarse en Docker';categoriaId=$taskCategory.Json.id}
    $taskTopicId = [long]$taskTopic.Json.id
    $taskComment = Request-Foro 'Publicar comentario' POST "/api/temas/$taskTopicId/comentarios" 201 $taskTokenUser @{contenido='Comentario conservado en Docker'}
    $taskCommentId = [long]$taskComment.Json.id
    Request-Foro 'Usuario no puede banear' PUT "/api/moderacion/temas/$taskTopicId" 403 $taskTokenUser @{baneado=$true;motivo='Intento sin permiso'} | Out-Null
    Request-Foro 'Banear comentario' PUT "/api/moderacion/comentarios/$taskCommentId" 200 $taskTokenAdmin @{baneado=$true;motivo='Revision Docker de comentario'} | Out-Null
    Request-Foro 'Comentario oculto' GET "/api/comentarios/$taskCommentId" 404 $taskTokenUser | Out-Null
    Request-Foro 'Banear tema' PUT "/api/moderacion/temas/$taskTopicId" 200 $taskTokenAdmin @{baneado=$true;motivo='Revision Docker de tema'} | Out-Null
    Request-Foro 'Tema oculto' GET "/api/temas/$taskTopicId" 404 $taskTokenUser | Out-Null
    $taskList = Request-Foro 'Listado excluye tema baneado' GET '/api/temas' 200 $taskTokenUser
    Assert-Foro (-not (@($taskList.Json | ForEach-Object {$_.id}) -contains $taskTopicId)) 'Se mostro el tema baneado.'
    Request-Foro 'No comentar tema baneado' POST "/api/temas/$taskTopicId/comentarios" 404 $taskTokenUser @{contenido='Respuesta bloqueada'} | Out-Null
    Request-Foro 'Decisiones administrativas' GET '/api/moderacion/decisiones?baneado=true' 200 $taskTokenAdmin | Out-Null
    Request-Foro 'Restaurar tema' PUT "/api/moderacion/temas/$taskTopicId" 200 $taskTokenAdmin @{baneado=$false;motivo='Tema revisado en Docker'} | Out-Null
    $taskRestored = Request-Foro 'Tema restaurado conserva contenido' GET "/api/temas/$taskTopicId" 200 $taskTokenUser
    Assert-Foro ($taskRestored.Json.contenido -eq $taskTopic.Json.contenido) 'El tema perdio su contenido.'
    $taskComments = Request-Foro 'Comentario permanece baneado' GET "/api/temas/$taskTopicId/comentarios" 200 $taskTokenUser
    Assert-Foro (-not (@($taskComments.Json | ForEach-Object {$_.id}) -contains $taskCommentId)) 'Restaurar tema restauro indebidamente el comentario.'
    Request-Foro 'Restaurar comentario' PUT "/api/moderacion/comentarios/$taskCommentId" 200 $taskTokenAdmin @{baneado=$false;motivo='Comentario revisado en Docker'} | Out-Null
    $taskRestoredComment = Request-Foro 'Comentario conserva contenido' GET "/api/comentarios/$taskCommentId" 200 $taskTokenUser
    Assert-Foro ($taskRestoredComment.Json.contenido -eq $taskComment.Json.contenido) 'El comentario perdio su contenido.'
    Request-Foro 'Usuario no consulta decisiones' GET '/api/moderacion/decisiones' 403 $taskTokenUser | Out-Null
    if ($ProbarDependencia -or $ProbarPersistencia) {
        if ($ProbarPersistencia) {
            $taskBefore = Request-Foro 'Decisiones antes de reinicio' GET '/api/moderacion/decisiones?baneado=false' 200 $taskTokenAdmin
            $taskBeforeRows = @($taskBefore.Json | Where-Object {($_.tipo -eq 'TEMA' -and $_.recursoId -eq $taskTopicId) -or ($_.tipo -eq 'COMENTARIO' -and $_.recursoId -eq $taskCommentId)})
            Assert-Foro ($taskBeforeRows.Count -eq 2) 'Deben existir las dos decisiones antes del reinicio.'
            $taskSaved = @($taskBeforeRows | Sort-Object id | ConvertTo-Json -Depth 8 -Compress)
        }
        $taskModeracionStopped = $true
        Invoke-ForoCompose -Operacion @('stop','moderacion') -RutaLog (Join-Path $Directorio 'dependencia.log')
        Request-Foro 'Fallo cerrado sin Moderacion' GET "/api/temas/$taskTopicId" 503 $taskTokenUser | Out-Null
        Invoke-ForoCompose -Operacion @('start','moderacion') -RutaLog (Join-Path $Directorio 'reinicio.log')
        $taskModeracionStopped = $false
        $taskDeadline = [DateTime]::UtcNow.AddSeconds(120)
        $taskReady = $false
        do {
            try { $null = Request-Foro 'Tema disponible tras reinicio' GET "/api/temas/$taskTopicId" 200 $taskTokenUser; $taskReady=$true } catch { Start-Sleep -Seconds 1 }
        } while (-not $taskReady -and [DateTime]::UtcNow -lt $taskDeadline)
        Assert-Foro $taskReady 'Moderacion no volvio a responder.'
        if ($ProbarPersistencia) {
            $taskAfter = Request-Foro 'Decisiones despues de reinicio' GET '/api/moderacion/decisiones?baneado=false' 200 $taskTokenAdmin
            $taskAfterRows = @($taskAfter.Json | Where-Object {($_.tipo -eq 'TEMA' -and $_.recursoId -eq $taskTopicId) -or ($_.tipo -eq 'COMENTARIO' -and $_.recursoId -eq $taskCommentId)})
            Assert-Foro ($taskAfterRows.Count -eq 2) 'Deben conservarse las dos decisiones despues del reinicio.'
            $taskSavedAfter = @($taskAfterRows | Sort-Object id | ConvertTo-Json -Depth 8 -Compress)
            Assert-Foro (($taskSaved -join '') -eq ($taskSavedAfter -join '')) 'Las decisiones no conservaron sus valores tras reiniciar.'
            Request-Foro 'Comentario disponible tras reinicio' GET "/api/comentarios/$taskCommentId" 200 $taskTokenUser | Out-Null
        }
    }
    $taskSummary = [ordered]@{modo=$Modo;baseUrl=$BaseUrl;aprobadas=$taskSteps.Count;temaId=$taskTopicId;comentarioId=$taskCommentId;persistenciaOracleProbada=[bool]$ProbarPersistencia;pruebas=$taskSteps.ToArray()}
    $taskParent = Split-Path -Parent ([IO.Path]::GetFullPath($Resultado))
    New-Item -ItemType Directory -Path $taskParent -Force | Out-Null
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Resultado),($taskSummary|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    Write-Output ("PASS: $($taskSteps.Count) comprobaciones HTTP en modo $Modo. Resultado sin tokens: $Resultado")
} finally {
    if ($taskModeracionStopped) {
        try { Invoke-ForoCompose -Operacion @('start','moderacion') -RutaLog (Join-Path $Directorio 'recuperacion.log') }
        catch { Write-Warning 'No se pudo recuperar Moderacion automaticamente. Inicia solo el servicio moderacion del proyecto correspondiente.' }
    }
    $taskTokenAdmin=$null; $taskTokenUser=$null; $taskPassword=$null
    $taskClient.Dispose(); $taskHandler.Dispose()
}
