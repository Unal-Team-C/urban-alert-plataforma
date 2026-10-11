# Tareas: Red y API Gateway compartidos de UrbanAlert

- **Plan**: ./plan.md
- **Estado**: aprobado <!-- borrador | aprobado -->

Leyenda: `[ ]` pendiente · `[~]` en progreso · `[x]` hecha · `[!]` bloqueada · `[-]` descartada · `[P]` paralelizable

Formato de cada tarea (una línea):
`- [ ] T001 [P] Descripción imperativa — archivos: ruta/a, ruta/b — cubre: RF-001 — verifica: <comando o criterio observable>`

Dependencias: cada fase depende de la anterior; dentro de una fase se ejecuta en orden salvo `[P]`.
Dependencias explícitas: añadir `— depende: T00X`.

**Herramientas de verificación local** (`podman machine start` previo; constitución §Calidad y pruebas):
- `$TF` = `podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5`; uso: `$TF -chdir=infra/<stack> init -backend=false`, `validate`, `test [-filter=tests/<archivo>]`; `$TF fmt -check -recursive infra`
- `podman run --rm -v "$PWD":/repo -w /repo docker.io/rhysd/actionlint:1.7.7`
- `podman run --rm -v "$PWD":/mnt -w /mnt docker.io/koalaman/shellcheck:stable scripts/*.sh scripts/tests/*.sh`
- Scripts: `bash scripts/tests/run.sh` (necesita `jq`, que está en macOS y en los runners)

Las pruebas de Terraform se dividen en un archivo por área (`red`, `salida`, `gateway`, `contrato`) para poder ejecutarlas con `-filter` a medida que se implementa cada una.

## Fase 1: Preparación

- [x] T001 [P] Crear la política de arranque del rol de GitHub (VPC, subredes, IGW, EIP, NAT, tablas de rutas, endpoints de VPC; `apigateway` sobre `/apis*`, `/vpclinks*` y `/tags*`; rol vinculado `ops.apigateway.amazonaws.com`; grupos de logs `/aws/apigateway/urban-alert-*` y entregas de logs; `ssm` sobre `parameter/urban-alert/*`; `elasticloadbalancing:Describe*`), y su README con los pasos manuales: adjuntar la política, corregir la confianza OIDC con el subject inmutable, crear el secreto `AWS_ROLE_ARN` y la variable `AWS_REGION` en este repo, y enlace a `urban-alert-geoespacial/infra/bootstrap/` — archivos: infra/bootstrap/github-platform-policy.json, infra/bootstrap/README.md — cubre: RF-014, RF-016 — verifica: `python3 -m json.tool infra/bootstrap/github-platform-policy.json >/dev/null`; `grep -c` encuentra `ec2:CreateVpc`, `ec2:CreateNatGateway`, `ec2:CreateVpcEndpoint`, `apigateway:POST`, `ssm:PutParameter`, `logs:CreateLogDelivery`, `elasticloadbalancing:DescribeListeners` y `ops.apigateway.amazonaws.com`; el README enumera los 4 pasos manuales
- [x] T002 [P] Crear el esqueleto del stack: `versions.tf` (TF `>= 1.10, < 2.0`, aws `~> 6.0`), `backend.tf` (bucket de estado, clave `plataforma/terraform.tfstate`, `encrypt`, `use_lockfile`), `providers.tf` (`default_tags` Project/ManagedBy/Stack=plataforma), `variables.tf` con las validaciones de plan §6 y `terraform.tfvars` — archivos: infra/plataforma/{versions,backend,providers,variables}.tf, infra/plataforma/terraform.tfvars — cubre: RF-009, RNF-006 — verifica: `$TF -chdir=infra/plataforma init -backend=false` y `validate` → «Success»; `$TF fmt -check -recursive infra` sin salida

## Fase 2: Pruebas

- [x] T003 Escribir las pruebas de red y salida con `mock_provider "aws"` y `override_data` de zonas: 2 subredes privadas `/20` en zonas distintas sin IP pública y con ruta `0.0.0.0/0` a un NAT; públicas sin IP pública automática; `numero_zonas = 1` rechazado; SG por defecto sin reglas; `nat_por_zona` false → 1 NAT, true → 2; endpoint S3 asociado a las tablas privadas — archivos: infra/plataforma/tests/red.tftest.hcl, infra/plataforma/tests/salida.tftest.hcl — cubre: RF-001, RF-002, RF-003, RNF-001, RNF-007 — verifica: `$TF -chdir=infra/plataforma test -filter=tests/red.tftest.hcl` falla solo por referencias a recursos aún no declarados (`aws_vpc.this`, `aws_subnet.privada`, …) — depende: T002
- [x] T004 Escribir las pruebas del gateway y del contrato: HTTP API sin authorizer ni ruta `$default`; stage `$default` con throttling (50/100) y logs de acceso JSON hacia el grupo `/aws/apigateway/urban-alert-gateway` (30 días; `retencion_logs_dias = 7` rechazado); CORS sin credenciales; VPC Link en las subredes privadas con un SG sin entrada y con salida solo 443 a la VPC; los 9 parámetros SSM con sus nombres exactos (plan §7) — archivos: infra/plataforma/tests/gateway.tftest.hcl, infra/plataforma/tests/contrato.tftest.hcl — cubre: RF-004, RF-005, RF-007, RF-008, RF-015, RF-017, RNF-005, RNF-006 — verifica: `test -filter=tests/gateway.tftest.hcl` falla solo por recursos no declarados — depende: T002
- [x] T005 [P] Escribir las pruebas de los scripts con fixtures: guarda (sin cambios → 0; reemplazo de `aws_vpc.this` → 1 con la dirección en la salida; mismo reemplazo con `permitir_reemplazo_compartido = true` → 0; borrado de un `aws_ssm_parameter` → 1); dependientes (VPC y API vacías → 0; SG ajeno → 1 con su id; ALB en la VPC → 1; ruta en la API → 1; ENI de NAT y de VPC Link ignoradas → 0) — archivos: scripts/tests/run.sh, scripts/tests/fixtures/** — cubre: RF-012, RF-013 — verifica: `bash scripts/tests/run.sh` falla porque no existen `scripts/guard-plan.sh` ni `scripts/check-dependents.sh`

## Fase 3: Núcleo

- [x] T006 Implementar la red: VPC `10.20.0.0/16` con DNS, subredes privadas y públicas por zona (`cidrsubnet`, plan §6), IGW, tabla pública con ruta al IGW, `aws_default_security_group` vacío — archivos: infra/plataforma/network.tf — cubre: RF-001, RF-002, RNF-001, RNF-007 — verifica: `$TF -chdir=infra/plataforma test -filter=tests/red.tftest.hcl` pasa
- [x] T007 Implementar la salida: EIP + NAT Gateway (1, o uno por zona con `nat_por_zona`), tablas privadas por zona con `0.0.0.0/0` → NAT, endpoint de gateway S3 en las tablas privadas — archivos: infra/plataforma/egress.tf — cubre: RF-003, RNF-004 — verifica: `test -filter=tests/salida.tftest.hcl` pasa
- [x] T008 Implementar el gateway: grupo de logs, HTTP API `urban-alert-gateway` con CORS, stage `$default` (`auto_deploy`, throttling, logs de acceso en JSON), SG del VPC Link y VPC Link v2 en las subredes privadas — archivos: infra/plataforma/logs.tf, infra/plataforma/gateway.tf — cubre: RF-004, RF-005, RF-007, RF-015, RF-017, RNF-005, RNF-006 — verifica: `test -filter=tests/gateway.tftest.hcl` pasa
- [x] T009 Implementar el contrato: los 9 parámetros SSM de plan §7 y las salidas de Terraform equivalentes (más `ssm_prefix`) — archivos: infra/plataforma/ssm.tf, infra/plataforma/outputs.tf — cubre: RF-008 — verifica: `$TF -chdir=infra/plataforma test` (todos los archivos) pasa; `validate` «Success»
- [x] T010 Generar `.terraform.lock.hcl` de la plataforma con hashes para `linux_amd64`, `linux_arm64` y `darwin_arm64` — archivos: infra/plataforma/.terraform.lock.hcl — cubre: RF-010 (P8) — verifica: `init -backend=false -lockfile=readonly` termina bien; `grep -c "h1:"` ≥ 3 para `hashicorp/aws`
- [x] T011 [P] Implementar `guard-plan.sh <plan.json>` (lista de direcciones protegidas del plan §7, excepción por `.variables.permitir_reemplazo_compartido.value`) — archivos: scripts/guard-plan.sh — cubre: RF-013 — verifica: los casos de guarda de `bash scripts/tests/run.sh` pasan; shellcheck sin avisos
- [x] T012 [P] Implementar `check-dependents.sh <vpc_id> <api_id>` con modo `--desde-dir <dir>` para las pruebas (SG, ALB y ENI ajenos de la VPC; rutas e integraciones de la API; exclusiones de plan D-009) — archivos: scripts/check-dependents.sh — cubre: RF-012 — verifica: todos los casos de `bash scripts/tests/run.sh` pasan; shellcheck sin avisos
- [x] T013 [P] Implementar `smoke-gateway.sh <api_endpoint>`: `/api/v1/__humo__` → 404, `http://` sin respuesta 2xx/3xx (timeout de 10 s) y los 9 parámetros de `ssm get-parameters-by-path /urban-alert/plataforma` — archivos: scripts/smoke-gateway.sh — cubre: RF-007, RF-008 — verifica: `bash -n` y shellcheck sin avisos (la ejecución real se verifica en T020)
- [x] T014 [P] Implementar `buscar-listener-express.sh <cluster> <servicio>` con la cadena de research R-1 (`ecs describe-services` → grupo objetivo → ALB → listener 443) y un mensaje de error en cada paso vacío — archivos: scripts/buscar-listener-express.sh — cubre: RF-006 — verifica: `bash -n` y shellcheck sin avisos (la ejecución real se verifica en T023)

## Fase 4: Integración

- [ ] T015 Escribir las pruebas del ejemplo de consumidor con `mock_provider` y `override_data` de los parámetros SSM: la integración usa `VPC_LINK`, el listener como `integration_uri`, `server_name_to_verify` y `overwrite:header.host` iguales al endpoint, payload `1.0` y `overwrite:path` a `/api/v1/geospatial/...` (incluido `$request.path.id`); rutas `GET /api/v1/geoespacial/reports` y `GET /api/v1/geoespacial/coordinates/{id}` con autorización `NONE`; `POST /api/v1/geoespacial/coordinates` con `AWS_IAM`; política `execute-api:Invoke` limitada a `<execution-arn>/$default/POST/api/v1/geoespacial/coordinates` — archivos: infra/ejemplo-consumidor/tests/ejemplo.tftest.hcl, infra/ejemplo-consumidor/versions.tf, infra/ejemplo-consumidor/variables.tf — cubre: RF-006, RF-018, RF-019 — verifica: `$TF -chdir=infra/ejemplo-consumidor test` falla solo por recursos no declarados
- [ ] T016 Implementar el ejemplo de consumidor (lectura de SSM, integraciones, rutas y política IAM para el rol que llama; comentario de cabecera que indica que nunca se aplica desde este repo) y su lockfile — archivos: infra/ejemplo-consumidor/main.tf, infra/ejemplo-consumidor/iam.tf, infra/ejemplo-consumidor/.terraform.lock.hcl — cubre: RF-006, RF-011, RF-018, RF-019 — verifica: `test` pasa; `validate` «Success»; `fmt -check` limpio — depende: T015
- [ ] T017 Escribir la guía de integración: leer las salidas de SSM; desplegar Express con **todas** las subredes privadas; obtener el endpoint y el listener (`buscar-listener-express.sh`, en un paso posterior al despliegue del servicio); convención de rutas RF-018 con reescritura de ruta, métodos y cabecera fija; rutas internas IAM y cómo firmar las llamadas entre servicios (SigV4 con el rol de tarea); aislamiento del ALB (D-013); `Host`/`Location` (riesgos del plan); permisos que necesita el rol; orden de desaprovisionamiento — archivos: docs/integracion.md — cubre: RF-011, RF-018, RF-019, MS-004 — verifica: cubre cada punto de RF-011 (lista de comprobación al final del documento) y enlaza a `infra/ejemplo-consumidor/` — depende: T016
- [ ] T018 Crear `provision.yml`: push a `main`; `concurrency: urban-alert-plataforma` sin cancelar; job `validate` (`fmt`, `validate` y `test` de ambos stacks con `-lockfile=readonly`, `scripts/tests/run.sh`, actionlint, shellcheck); job `provision` (OIDC con `secrets.AWS_ROLE_ARN`/`vars.AWS_REGION`, `setup-terraform` 1.16.5, `plan -out` → `show -json` → `guard-plan.sh` → `apply tfplan` → `smoke-gateway.sh` → resumen con las salidas en `$GITHUB_STEP_SUMMARY`) — archivos: .github/workflows/provision.yml — cubre: RF-010, RF-013, RF-014, RNF-002 — verifica: actionlint sin errores; `grep -c aws-access-key-id` = 0; el orden de los pasos coincide con plan D-008
- [ ] T019 Crear `deprovision.yml`: solo `workflow_dispatch` con el input `confirm`; primer paso que corta si `confirm != urban-alert-plataforma` o la rama no es `main`; misma `concurrency`; si el estado está vacío → «nada que eliminar» y sale con 0; `check-dependents.sh` → `terraform destroy -auto-approve` (con `permitir_reemplazo_compartido` irrelevante en destroy); resumen — archivos: .github/workflows/deprovision.yml — cubre: RF-012, RF-014, RF-016 — verifica: actionlint sin errores; no tiene `on: push`; la confirmación se comprueba antes de configurar las credenciales
- [ ] T020 Primer aprovisionamiento real: requiere que el usuario adjunte la política (T001), corrija la confianza OIDC, cree `AWS_ROLE_ARN`/`AWS_REGION` en el repo y autorice el push a `main` — archivos: (ninguno; evidencia en el journal) — cubre: HU-1, RF-001…RF-010, RF-015, MS-001, RNF-003 — verifica: run de Provision en verde en < 20 min; el humo pasa; el resumen muestra los 9 valores; `curl -s -o /dev/null -w '%{http_code}' <api>/api/v1/x` → 404
- [ ] T021 Relanzar Provision sobre el mismo commit — archivos: (ninguno) — cubre: RNF-002, RNF-003, MS-002 — verifica: el plan del segundo run dice `No changes` y termina en < 10 min — depende: T020
- [ ] T022 Lanzar Deprovision **sin** la confirmación correcta — archivos: (ninguno) — cubre: RF-012, HU-5 criterio 2 — verifica: el run termina indicando que falta la confirmación, sin pasos de AWS; la plataforma sigue respondiendo — depende: T020
- [ ] T023 Verificación conjunta con geoespacial (cuando su spec 002 esté replanificada y desplegada sobre la plataforma): contrato por la URL del gateway; el endpoint de Express, el ALB y las tareas no son alcanzables desde internet; `POST` interno sin firma → 403 y con el rol de Reportes (o uno de prueba) → 201; `buscar-listener-express.sh` devuelve el listener correcto; Deprovision confirmado con geoespacial desplegado → lista los dependientes y no elimina nada — archivos: (ninguno; evidencia en el journal y en verify.md) — cubre: RF-006, RF-012, RF-019, HU-2, HU-3, HU-5 criterio 3, MS-003, RNF-001 — depende: T017, T020

## Fase 5: Pulido

- [ ] T024 [P] Actualizar el README: piezas y diagrama, tabla de parámetros SSM (contrato P9), workflows y cómo lanzar Deprovision (orden: consumidores primero), tabla de costes de research R-5 (incluida la nota del ALB de Express), arranque (enlace a `infra/bootstrap/`), validación local con Podman — archivos: README.md — cubre: RNF-004, HU-6, MS-005 — verifica: contiene las secciones citadas, la estimación mensual desglosada y el enlace a `docs/integracion.md`
- [ ] T025 [P] Actualizar CLAUDE.md con el stack, los scripts, los workflows y los comandos de validación — archivos: CLAUDE.md — cubre: (pulido) — verifica: los comandos coinciden con los de la cabecera de este archivo
- [ ] T026 (Opcional, con autorización expresa del usuario) Ciclo completo: con los consumidores desaprovisionados, ejecutar Deprovision confirmado → todo eliminado y el rol sigue funcionando → relanzar Deprovision → «nada que eliminar» → push a `main` recrea la plataforma (los IDs cambian y los consumidores los toman de SSM) — archivos: (ninguno) — cubre: HU-5 criterios 1, 4 y 5, HU-4 criterio 2 — verifica: runs en verde y la evidencia queda en el journal — depende: T023

## Correcciones de verificación

<!-- /sdd-verify añade aquí tareas si detecta fallos -->

## Cobertura

| Requisito | Tareas |
|---|---|
| RF-001 | T003, T006, T020 |
| RF-002 | T003, T006 |
| RF-003 | T003, T007, T020, T023 |
| RF-004 | T004, T008, T020 |
| RF-005 | T004, T008 |
| RF-006 | T014, T015, T016, T023 |
| RF-007 | T004, T008, T013, T020 |
| RF-008 | T004, T009, T013, T020 |
| RF-009 | T002, T020 |
| RF-010 | T010, T018, T020 |
| RF-011 | T016, T017 |
| RF-012 | T005, T012, T019, T022, T023 |
| RF-013 | T005, T011, T018 |
| RF-014 | T001, T018, T019 |
| RF-015 | T004, T008, T020 |
| RF-016 | T001, T019 |
| RF-017 | T004, T008 |
| RF-018 | T015, T016, T017 |
| RF-019 | T015, T016, T017, T023 |
| RNF-001 | T003, T006, T023 |
| RNF-002 | T018, T021 |
| RNF-003 | T020, T021 |
| RNF-004 | T007, T024 |
| RNF-005 | T004, T008 |
| RNF-006 | T002, T004, T008 |
| RNF-007 | T003, T006 |
| MS-001 | T020 |
| MS-002 | T021 |
| MS-003 | T023 |
| MS-004 | T017 |
| MS-005 | T024 |
