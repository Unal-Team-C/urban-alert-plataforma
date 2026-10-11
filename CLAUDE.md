# CLAUDE.md

Plataforma compartida de UrbanAlert en AWS (cuenta 348364742283, us-east-2): la red (VPC con subredes privadas y
salida a internet) y el Amazon API Gateway por el que se exponen todos los microservicios. Los microservicios
(p. ej. `Unal-Team-C/urban-alert-geoespacial`) viven en sus propios repos y consumen las salidas de esta plataforma.

- Terraform se aplica solo desde GitHub Actions (rol OIDC compartido, subject inmutable `repo:Unal-Team-C@335834608/...`).
- Estado remoto: `s3://urban-alert-tfstate-348364742283/plataforma/terraform.tfstate`.
- Recursos de arranque: `infra/bootstrap/README.md` (política de la plataforma) y `urban-alert-geoespacial/infra/bootstrap/` (OIDC, rol, bucket).

## Estructura (spec `specs/001-red-api-gateway/`)

- `infra/plataforma`: único stack (red, NAT, endpoint S3, HTTP API, VPC Link, logs, parámetros SSM). Pruebas con `mock_provider` en `tests/` (un archivo por área: red, salida, gateway, contrato).
- `infra/ejemplo-consumidor`: referencia de integración de un microservicio (rutas, Host del ALB de Express, rutas IAM). Se prueba aquí y **nunca se aplica**.
- `scripts/`: `guard-plan.sh` (bloquea reemplazos de recursos compartidos), `check-dependents.sh` (antes de destruir), `smoke-gateway.sh` (tras el apply), `buscar-listener-express.sh` (para los consumidores); pruebas en `scripts/tests/run.sh` con fixtures.
- Workflows: `.github/workflows/provision.yml` (push a `main`) y `deprovision.yml` (manual, confirmación `urban-alert-plataforma`).
- Contrato con los microservicios: parámetros SSM `/urban-alert/plataforma/*` (no renombrar sin coordinar, constitución P9). Guía: `docs/integracion.md`.

## Validación local (Podman, sin instalar nada)

`podman machine start` y, desde la raíz:

- `podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5 -chdir=infra/<stack> init -backend=false` y luego `validate` / `test`; `fmt -check -recursive infra`
- `bash scripts/tests/run.sh`
- `podman run --rm -v "$PWD":/repo -w /repo docker.io/rhysd/actionlint:1.7.7`
- `podman run --rm -v "$PWD":/mnt -w /mnt docker.io/koalaman/shellcheck:v0.10.0 scripts/*.sh scripts/tests/*.sh`

## Gotchas

- macOS trae bash 3.2: los scripts no usan `mapfile` ni otras funciones de bash 4.
- Con `mock_provider` el proveedor valida el formato de los ARN: los tests definen un `mock_resource` con un ARN realista para el grupo de logs.
- `.terraform.lock.hcl` lleva hashes de `linux_amd64`, `linux_arm64` y `darwin_arm64`; si cambia el proveedor, regenerarlo con `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64` (el CI usa `init -lockfile=readonly`).
- Push por HTTPS sin credencial en el llavero: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main`.

## Desarrollo guiado por especificaciones (SDD)

Este proyecto usa un arnés SDD con persistencia en disco para sobrevivir a interrupciones de sesión.
El protocolo es obligatorio en todas las sesiones:

@.sdd/PROTOCOL.md
