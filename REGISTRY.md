# Imagenes y despliegue mediante Oracle Container Registry

Registro regional: scl.ocir.io (Chile Central/Santiago).
Namespace: axbxf8fhbcck. Repositorios privados:
- foro-nexo/usuarios
- foro-nexo/contenido
- foro-nexo/moderacion
- foro-nexo/frontend

Release: s5-arquetipo. Los tres backends corresponden a la adopcion real del arquetipo, con 85+148+26 pruebas aprobadas. Frontend conserva el codigo validado, etiquetado con la misma version de release. Digests verificables: ocir-imagenes.json. No contiene tokens ni contrasenas.

## Publicar una nueva version

Construye las cuatro imagenes desde las fuentes, siguiendo README.md y fijando IMAGE_TAG a una etiqueta nueva. Requiere Docker Engine/Compose y los clones con la estructura documentada. Inicia sesion localmente; la contrasena solicitada es un auth token de OCI, nunca la contrasena de la consola:

```powershell
docker login scl.ocir.io --username '<namespace>/<dominio>/<usuarioOCI>'
```

Despues etiqueta y publica cada imagen (ejemplo Usuarios):

```powershell
docker tag foro-nexo/usuarios:s5-arquetipo scl.ocir.io/axbxf8fhbcck/foro-nexo/usuarios:s5-arquetipo
docker push scl.ocir.io/axbxf8fhbcck/foro-nexo/usuarios:s5-arquetipo
docker pull scl.ocir.io/axbxf8fhbcck/foro-nexo/usuarios:s5-arquetipo
```

Repite para contenido, moderacion y frontend. Para versiones futuras usa etiquetas nuevas y registra los nuevos digests. Antes del despliegue se comprobaron las capas y configuracion tras pull local; despues se compararon los cuatro RepoDigests en la VM con los de publicacion.

## Ejecutar en la VM

Mantener los secretos/wallet fuera de Git. El env de la VM usa:

```text
IMAGE_PREFIX=scl.ocir.io/axbxf8fhbcck/foro-nexo
IMAGE_TAG=s5-arquetipo
```

Los demas valores (rutas privadas Linux, alias y PUBLIC_HOST) se conservan. Una sesion de Docker local no autentica automaticamente a Docker en la VM. El usuario inicia sesion en la VM mediante sudo docker login, con el auth token introducido directamente en la terminal. No copiar tokens al repositorio, archivos de evidencia ni al chat.

En /home/opc/foro-nexo/despliegue:

```sh
sudo docker compose --project-name foro-nexo-oracle --env-file compose.env -f compose.yml -f compose.oracle.yml -f compose.cloud.yml pull
sudo docker compose --project-name foro-nexo-oracle --env-file compose.env -f compose.yml -f compose.oracle.yml -f compose.cloud.yml up -d --no-build --wait --wait-timeout 240
sudo docker compose --project-name foro-nexo-oracle --env-file compose.env -f compose.yml -f compose.oracle.yml -f compose.cloud.yml ps
```

Antes de actualizar se conserva compose.pre-ocir.env y las imagenes anteriores para restaurar. Los certificados Caddy y las tablas Oracle se conservan durante recreaciones. Cloud configura SERVER_FORWARD_HEADERS_STRATEGY=framework en los backends para que las cabeceras Location de recursos creados mantengan HTTPS detras de Caddy. Los puertos de backend no se publican directamente.

Cuando termine la descarga/despliegue, sudo docker logout scl.ocir.io retira la credencial guardada en la VM. Las imagenes descargadas y los contenedores siguen disponibles; una descarga futura privada requiere iniciar sesion otra vez.

Referencias: https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypushingimagesusingthedockercli.htm y https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypullingimagesusingthedockercli.htm
