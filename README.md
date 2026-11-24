# Foro Nexo en Docker

Cuatro imágenes construidas desde código: Usuarios, Contenido, Moderación y
Angular servido por Caddy. El proxy conserva las rutas de las APIs. Angular
mantiene sus datos locales, separado del backend, como permite la pauta.

Esta carpeta coordina los proyectos existentes en SEMANA 2 y SEMANA 5. Mantén
esa estructura relativa al copiar las fuentes. No se despliega el ejemplo del
arquetipo como cuarto backend.

## Estado y alcance

La prueba local Demo usa H2 y cuentas ficticias, no Oracle. Las imágenes y el
proxy son los mismos que se utilizan en Oracle; cambia la configuración y el
montaje del wallet. La conexión Oracle real debe probarse con sus propias claves
antes de declararla aprobada. Estado verificado: 29 comprobaciones locales con Oracle y persistencia aprobadas. La VM ya ejecuta los cuatro servicios y el acceso HTTPS publico se comprobo; 24 comprobaciones autenticadas desde Internet aprobadas; OCIR sigue pendiente.

Los contenedores de otras actividades se conservan. Todos los comandos se
limitan a los proyectos `foro-nexo-demo` o `foro-nexo-oracle`. No usar
`docker system prune`, paradas globales ni eliminación de volúmenes ajenos.

## Requisitos

- Docker Desktop con contenedores Linux y Docker Compose v2 o posterior.
- Internet en la construcción inicial para las imágenes y dependencias oficiales.
- PowerShell 5.1 o 7 para los scripts locales.
- Para Oracle: wallet existente y contraseñas de FORO_USUARIOS, FORO_CONTENIDO y
  FORO_MODERACION, introducidas localmente, nunca en el chat.

Las imágenes base están fijadas por digest en los Dockerfiles y registradas en
`images.lock.json`. Se comprobaron manifiestos Linux amd64 y arm64/v8. La
construcción local verificada es amd64; en una VM Arm se deben construir de forma
nativa o publicar imágenes para arm64, no copiar directamente una imagen amd64.

## Demostración local con H2

```powershell
Set-Location 'C:\Users\fasc8\OneDrive\Documentos\DUOC\DESARROLLO DE SOFTWARE III\SEMANA 5\despliegue'
.\scripts\Preparar-Configuracion.ps1 -Modo Demo
docker compose --parallel 1 --project-name foro-nexo-demo --env-file runtime/demo/compose.env -f compose.yml -f compose.demo.yml -f compose.local.yml build
docker compose --project-name foro-nexo-demo --env-file runtime/demo/compose.env -f compose.yml -f compose.demo.yml -f compose.local.yml up -d --wait --wait-timeout 240
```

Si Demo ya está preparada, omite el primer script: rechaza carpetas existentes
para conservar las claves, no para rotarlas silenciosamente. Si 8090 está
ocupado, usa `-Puerto` al preparar una carpeta nueva o modifica únicamente
LOCAL_HTTP_PORT en compose.env y actualiza BaseUrl al probar.

Abrir `http://127.0.0.1:8090`. Las cuentas de la interfaz Angular se muestran en
su login y son independientes de las cuentas del backend. La cuenta backend
Demo se configura con correo `admin-docker@example.test` y una contraseña
aleatoria privada: el script de pruebas la lee sin mostrarla. No utilizarla como
administrador real ni publicar Demo en Internet.

```powershell
.\scripts\Probar-Docker.ps1 -Modo Demo -ProbarDependencia
```

Comprueba portada, ruta Angular profunda, API desconocida, login, registro,
categoría, tema, comentario, permisos, baneo y restauración independiente.
Con ProbarDependencia detiene solo Moderación del proyecto Demo, exige 503 al
consultar Contenido y vuelve a iniciarla incluso si falla la prueba. El resultado
se guarda sin tokens en runtime/demo/resultado-http.json.

H2 pierde datos al reiniciar su servicio. Un reinicio H2 no acredita persistencia
Oracle; por eso ProbarPersistencia se rechaza en Demo.

## Ejecución local con Oracle

Primero prepara una carpeta privada distinta, por ejemplo usando el puerto 8091
para no interferir con la Demo:

```powershell
.\scripts\Preparar-Configuracion.ps1 -Modo Oracle -Puerto 8091
```

Pedirá las tres contraseñas de esquemas, sin comillas. Reutiliza
`C:\Wallet_BIBLIOTECA` y `biblioteca_low`. `-WalletPath` y `-Alias` permiten otros
valores. Valida tnsnames.ora y el alias antes de solicitar claves. El script no
crea esquemas, no cambia contraseñas y no escribe dentro del wallet.

Después:

```powershell
docker compose --project-name foro-nexo-oracle --env-file runtime/oracle/compose.env -f compose.yml -f compose.oracle.yml -f compose.local.yml up -d --wait --wait-timeout 240
.\scripts\Probar-Docker.ps1 -Modo Oracle -BaseUrl 'http://127.0.0.1:8091' -ProbarPersistencia
```

El segundo comando solicita correo y contraseña del administrador **de la
aplicación**, no ADMIN de Oracle. Crea un usuario, categoría y contenido de
prueba, y verifica que las decisiones sobreviven al reiniciar solo Moderación.
Los tokens se usan en memoria y no aparecen en el resultado. Los esquemas
existentes deben contener sus tablas: Oracle usa ddl-auto=validate, no las crea.
Bootstrap de administrador queda deshabilitado en Oracle y Cloud.

No mezcles compose.demo.yml con Oracle. El override Oracle fuerza su perfil y
desactiva bootstrap incluso si se añadió Demo antes; los comandos documentados
usan únicamente el modo correcto.

En Postman puedes usar la colección de Moderación existente. Asigna las tres
variables usuarios_url/contenido_url/moderacion_url al mismo origen del proxy,
por ejemplo `http://127.0.0.1:8091`. Se mantienen los paths originales y Bearer.

## Secretos y archivos privados

Preparar-Configuracion crea runtime/<modo>/secrets y compose.env. En Windows
restringe la carpeta a tu usuario, SYSTEM y administradores. Guarda sin imprimir:

| Archivo privado | Propiedad montada en /run/secrets |
|---|---|
| usuarios-db-password | spring.datasource.password en Usuarios |
| contenido-db-password | spring.datasource.password en Contenido |
| moderacion-db-password | spring.datasource.password en Moderación |
| jwt-secret-base64 | security.jwt.secret-base64 en Usuarios |
| bootstrap-admin-password | app.bootstrap.password, solo activo en Demo |

Spring configtree carga los archivos, evitando pasar sus valores como variables
de entorno. La clave JWT persiste en el host al reiniciar contenedores. Las
claves de Oracle y el wallet nunca se copian durante el build. No compartas
runtime, wallets, logs con tokens o exportaciones Postman con credenciales.

Los .dockerignore permiten solo los archivos necesarios para compilar y excluyen
configuración privada, certificados, wallets y ZIPs de wallet. También se usa
COPY explícito. Los backends ejecutan como UID/GID 10001, con raíz de solo lectura,
tmpfs para /tmp y sin capacidades. Los secretos montados solo están disponibles
en los servicios que los necesitan.

En Linux, Compose monta secretos de archivo conservando los permisos del host.
Un archivo 0600 de ubuntu no será legible por UID 10001. Tras transferirlos al
destino aprobado, usa un padre privado 0700; el subdirectorio de secretos/wallet
montado debe permitir lectura/travesía al UID del contenedor. Una opción es
subdirectorios 0555 y archivos 0444 bajo un padre 0700, accesible solo al dueño
en el host. No se requiere abrir permisos globales del home o de otros proyectos.

El chequeo saludable de backend reconoce la respuesta 401 sin token; acredita
que el proceso atiende HTTP, no una transacción Oracle. Caddy tiene una sonda
privada en 127.0.0.1:2016; su salud no acredita emisión de certificado público.

## Puertos y red

| Servicio | Puerto interno | Publicado localmente |
|---|---:|---|
| usuarios | 8081 | No |
| contenido | 8082 | No |
| moderacion | 8083 | No |
| frontend/proxy | 8080 en local | 127.0.0.1:8090 o el elegido |

Los servicios se llaman por usuarios/contenido/moderacion dentro de la red del
proyecto. No usan localhost para llamadas entre contenedores. Contenido y
Moderación no tienen dependencia circular de arranque. Se limita cada pool JDBC
a tres conexiones y un mínimo de una, ajustable tras observar el entorno.

## Preparación para Oracle Cloud

Antes de crear recursos se revisarán región, cuota Always Free disponible, VM,
imagen, RAM, volumen, red, acceso SSH y coste estimado. La propuesta es A1 Arm,
2 OCPU y 8 GB RAM; disponibilidad y gratuidad deben confirmarse en la consola.
Si no hay capacidad gratuita, no se crea una VM de pago automáticamente.

La VM necesitará Docker/Compose, las fuentes con su estructura relativa y
archivos privados transferidos al servidor concreto autorizado. La carpeta
compose.env deberá usar rutas Linux; no copiar las rutas Windows sin adaptarlas.
SSH se limita a la IP del usuario y se publican solo 80/443 para web/TLS.

Angular necesita HTTPS válido en una URL pública para Web Crypto. Configura un
dominio con DNS hacia la VM y define PUBLIC_HOST sin protocolo, path ni puerto.
No basta exponer una IP pública por HTTP ni usar un certificado autofirmado.
Con dominio y recursos revisados, el comando remoto previsto es:

```sh
docker compose --parallel 1 --project-name foro-nexo-oracle --env-file /ruta/privada/compose.env -f compose.yml -f compose.oracle.yml -f compose.cloud.yml build
docker compose --project-name foro-nexo-oracle --env-file /ruta/privada/compose.env -f compose.yml -f compose.oracle.yml -f compose.cloud.yml up -d --wait --wait-timeout 240
```

Usa compose.cloud.yml **sin** compose.local.yml ni compose.demo.yml. Cloud fuerza
HTTPS y Oracle, y Caddy persiste certificados en volúmenes propios. Para Container
Registry, IMAGE_PREFIX e IMAGE_TAG permiten etiquetar con el repositorio OCIR
aprobado; la creación del repositorio, autenticación y publicación se realizarán
en esa etapa. Publicar imágenes por sí solo no equivale a una aplicación desplegada.

Después se verificará HTTPS desde fuera, Angular y Postman contra la URL pública,
incluyendo persistencia real. El estado real de la VM y HTTPS se registra abajo; esta seccion describe el procedimiento y no presupone
que la VM, el DNS, OCIR o el certificado ya estén configurados.

## Diagnóstico y parada, siempre con proyecto explícito

```powershell
docker compose --project-name foro-nexo-demo --env-file runtime/demo/compose.env -f compose.yml -f compose.demo.yml -f compose.local.yml ps
docker compose --project-name foro-nexo-demo --env-file runtime/demo/compose.env -f compose.yml -f compose.demo.yml -f compose.local.yml logs --tail 80
docker compose --project-name foro-nexo-demo --env-file runtime/demo/compose.env -f compose.yml -f compose.demo.yml -f compose.local.yml stop
```

Para Oracle sustituye proyecto/env/override por sus equivalentes. `stop` conserva
contenedores y volúmenes; no elimina bases Oracle. No compartas logs sin revisar
su contenido y nunca uses comandos globales para detener otras actividades.

Referencias: [build context](https://docs.docker.com/build/concepts/context/),
[secretos Compose](https://docs.docker.com/compose/how-tos/use-secrets/),
[configtree Spring](https://docs.spring.io/spring-boot/reference/features/external-config.html),
[Caddy HTTPS](https://caddyserver.com/docs/quick-starts/https).

## Estado Cloud verificado el 23 de noviembre de 2026

URL: https://foro-nexo.146-181-53-253.sslip.io
VM creada por el usuario: E3 Flex x86_64, 1 OCPU y 16 GB, Oracle Linux 9.8. E3 no es Always Free; controlar creditos y coste real en la cuenta. Docker Engine 29.10.0 y Compose 5.8.0, cuatro contenedores healthy con Oracle. Despliegue remoto: /home/opc/foro-nexo/despliegue; proyecto foro-nexo-oracle. Wallet y secretos en /home/opc/foro-nexo/private, sin versionar. Se transfirieron imagenes amd64 verificadas por SHA256, sin construir imagenes ARM.

HTTPS publico validado sin omitir certificados, HTTP redirige 308 a HTTPS. Portada y /perfil: 200 HTML; /api/temas y /api/moderacion/decisiones: 401; API desconocida: 404. Evidencia sin tokens: ../.verification/docker/cloud-https.json. Angular conserva datos locales y sus cuentas son independientes del administrador del backend.

Prueba autenticada publica aprobada: 24 comprobaciones. Para repetir, ejecutar desde PowerShell local (solicita clave del administrador del foro, no de Oracle):

```powershell
.\scripts\Probar-Docker.ps1 -Modo Oracle -BaseUrl 'https://foro-nexo.146-181-53-253.sslip.io' -Resultado '.\runtime\oracle\resultado-http-cloud.json'
```

No agregar ProbarPersistencia ni ProbarDependencia contra URL remota: esos switches controlan contenedores locales. La persistencia Oracle ya se probo en el despliegue local; no atribuir esa evidencia a un reinicio de la VM.

Pendiente: publicacion en Container Registry si la pauta lo exige, evidencias finales y empaquetado de entrega sin secretos. El nombre gratuito depende de la IP publica actual y del servicio DNS sslip.io.


## Repositorios y descarga para reproducir el proyecto

- Usuarios: https://github.com/felsalasc/foro-usuarios
- Contenido: https://github.com/felsalasc/foro-contenido
- Moderacion: https://github.com/felsalasc/foro-moderacion
- Angular: https://github.com/felsalasc/foro-frontend
- Arquetipo: https://github.com/felsalasc/foro-microservicio-archetype
- Docker Compose: https://github.com/felsalasc/foro-despliegue

Desde una carpeta nueva, en PowerShell, conserva esta estructura para que los contextos de construccion Compose apunten al codigo correcto. El nombre remoto foro-despliegue se clona en la carpeta local despliegue:

```powershell
New-Item -ItemType Directory -Path 'SEMANA 2','SEMANA 5' -Force
git clone https://github.com/felsalasc/foro-usuarios.git 'SEMANA 2/foro-usuarios'
git clone https://github.com/felsalasc/foro-contenido.git 'SEMANA 2/foro-contenido'
git clone https://github.com/felsalasc/foro-moderacion.git 'SEMANA 5/foro-moderacion'
git clone https://github.com/felsalasc/foro-frontend.git 'SEMANA 5/foro-frontend'
git clone https://github.com/felsalasc/foro-microservicio-archetype.git 'SEMANA 5/foro-microservicio-archetype'
git clone https://github.com/felsalasc/foro-despliegue.git 'SEMANA 5/despliegue'
Set-Location 'SEMANA 5/despliegue'
```

Continua con la preparacion Demo o con Oracle descrita arriba. Credenciales y wallet se proporcionan localmente: nunca se descargan desde Git. Los comandos con rutas personales corresponden al equipo original; ajustarlas al destino. Para ejecutar scripts Java fuera de Docker necesitas JDK 17; Iniciar-Oracle.ps1 acepta -JavaPath. La estrategia usada es main con commits revisados; no se atribuye un historial GitFlow retrospectivo.
