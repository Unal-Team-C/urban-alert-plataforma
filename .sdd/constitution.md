# Constitución del proyecto

- **Versión**: 1.0.1
- **Última modificación**: 2026-10-11

> Principios no negociables. Todo `plan.md` se verifica contra ellos (§3 del plan).
> Una excepción exige justificación escrita en el plan. Cada principio debe ser concreto y verificable.

## Principios

### P1. Infraestructura solo como código, aplicada solo desde GitHub Actions
Todo recurso de AWS de la plataforma está definido en Terraform en este repositorio y solo lo crean, cambian o eliminan los workflows de `.github/workflows/` ejecutados en `main`. En local solo se ejecuta `init -backend=false`, `fmt`, `validate` y `test`; nunca `plan`/`apply`/`destroy` contra el estado real ni cambios en la consola (salvo los recursos de arranque, P2).
**Por qué**: un único camino de cambio hace el entorno repetible, revisable y reconstruible, y evita derivas entre el estado y AWS.

### P2. Recursos de arranque fuera de Terraform
El proveedor OIDC de GitHub, el rol de los workflows (y sus políticas) y el bucket `urban-alert-tfstate-348364742283` se crean a mano una vez, están documentados (con sus JSON versionados en `urban-alert-geoespacial/infra/bootstrap/`) y nunca aparecen en el estado de este repo ni en bloques `import`.
**Por qué**: si Terraform los gestionara, un desaprovisionamiento dejaría a los workflows sin credenciales ni estado.

### P3. Sin secretos ni credenciales de larga duración
Los workflows se autentican en AWS solo con OIDC (`aws-actions/configure-aws-credentials` + `role-to-assume`); no hay claves de acceso en GitHub. Ningún secreto aparece en el repositorio, en variables de GitHub, en salidas de Terraform ni en logs de los workflows; los valores sensibles van a Secrets Manager y en Terraform se marcan `sensitive`.
**Por qué**: el repositorio y los logs de Actions los ve todo el equipo; una credencial filtrada da acceso a la cuenta.

### P4. Cambios destructivos solo explícitos
Solo el workflow manual de desaprovisionamiento, con confirmación escrita, puede eliminar la plataforma. El workflow de aprovisionamiento falla antes de aplicar si el plan elimina o reemplaza un recurso del que dependen los consumidores (red, subredes, gateway, VPC Link), salvo que un cambio commiteado lo habilite explícitamente. Antes de destruir se comprueba que no hay dependientes.
**Por qué**: la plataforma es compartida; un reemplazo silencioso rompe a todos los microservicios a la vez.

### P5. Coste mínimo y documentado
Se elige la opción más barata que cumpla la spec (proyecto académico, un solo entorno). Todo recurso con coste por hora o por unidad figura en la tabla de costes del README con su estimación mensual; añadir uno nuevo exige justificarlo en `plan.md §Decisiones` con su coste.
**Por qué**: la cuenta la paga el equipo y los recursos de red (NAT, endpoints, balanceadores) cobran aunque no haya tráfico.

### P6. Validación antes de cada commit y antes de cada apply
Antes de cada commit de tarea y como primer job del workflow de aprovisionamiento pasan: `terraform fmt -check -recursive`, `terraform validate` y `terraform test` de cada stack (con `-lockfile=readonly`), `actionlint` sobre los workflows y `shellcheck` sobre los scripts. En local se ejecutan con Podman, sin instalar nada (comandos en *Calidad y pruebas*).
**Por qué**: los errores de sintaxis, de formato o de lógica se detectan sin tocar AWS ni gastar ejecuciones de Actions.

### P7. Pruebas de Terraform para lo que protege
Cada requisito de seguridad, aislamiento o protección (sin IP pública, reglas de grupos de seguridad, guardas contra destrucción, rutas solo HTTPS, salidas publicadas) tiene al menos un `run` en un `.tftest.hcl` con `mock_provider` que falla si se rompe.
**Por qué**: `validate` no comprueba intención; los tests documentan y protegen las garantías que consumen los microservicios.

### P8. Versiones fijadas y reproducibles
Terraform `>= 1.10, < 2.0` (CI y local con `hashicorp/terraform:1.16.5`), proveedor `hashicorp/aws ~> 6.0`, `.terraform.lock.hcl` versionado con hashes para `linux_amd64`, `linux_arm64` y `darwin_arm64`. Las imágenes de herramientas (`actionlint`, `shellcheck`) y las actions de GitHub se referencian con versión fijada.
**Por qué**: el mismo commit debe producir el mismo resultado en local y en CI, hoy y dentro de un mes.

### P9. Las salidas son un contrato con los consumidores
Las salidas que leen los microservicios (RF-008 de la spec 001) tienen nombre estable, están documentadas en el README con su significado y no se renombran ni eliminan sin una entrada en el journal y la actualización coordinada de los consumidores. Todo recurso usa el prefijo `urban-alert-` y las etiquetas por defecto `Project=urban-alert`, `ManagedBy=terraform`, `Stack=<stack>`.
**Por qué**: los microservicios despliegan contra estas salidas sin intervención manual; un cambio no coordinado rompe sus pipelines.

### P10. Ejecuciones serializadas e idempotentes
Los workflows de aprovisionamiento y desaprovisionamiento comparten un grupo de `concurrency` sin cancelación; dos aprovisionamientos seguidos sobre el mismo commit dan 0 cambios en el segundo.
**Por qué**: dos `apply` simultáneos o un plan que nunca converge corrompen el estado o generan cambios fantasma.

## Stack y restricciones técnicas

- AWS, cuenta `348364742283`, región `us-east-2`, un único entorno.
- Terraform (ver P8) con estado remoto en `s3://urban-alert-tfstate-348364742283/` bajo una clave propia de este repo, `encrypt = true` y `use_lockfile = true`.
- GitHub Actions en `Unal-Team-C/urban-alert-plataforma`; el rol OIDC confía en el subject inmutable `repo:Unal-Team-C@335834608/*:ref:refs/heads/main`.
- Consumidores: microservicios en ECS Express Mode (Fargate) desde sus propios repos.

## Calidad y pruebas

Requiere `podman machine start`. Desde la raíz del repo:

- Terraform: `podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5 -chdir=infra/<stack> init -backend=false`, luego `validate` y `test`; `... fmt -check -recursive infra`
- Workflows: `podman run --rm -v "$PWD":/repo -w /repo docker.io/rhysd/actionlint:1.7.7`
- Scripts: `podman run --rm -v "$PWD":/mnt -w /mnt docker.io/koalaman/shellcheck:v0.10.0 scripts/*.sh`

## Flujo de trabajo

- Desarrollo guiado por especificaciones según `.sdd/PROTOCOL.md`.
- Un commit local por tarea completada y verificada (P6); nunca `push` sin que el usuario lo pida.

## Historial

- 0.0.0 — plantilla inicial
- 1.0.0 — 2026-10-11 — P1–P10 a partir de la práctica de `urban-alert-geoespacial` (spec 002) y de la spec 001-red-api-gateway
- 1.0.1 — 2026-10-11 — shellcheck fijado a `v0.10.0` (antes `stable`) para cumplir P8
