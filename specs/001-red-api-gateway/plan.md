# Plan técnico: Red y API Gateway compartidos de UrbanAlert

- **Spec**: ./spec.md
- **Estado**: aprobado <!-- borrador | aprobado -->
- **Fecha**: 2026-10-11
- **Investigación**: ./research.md

## 1. Resumen técnico

Un único stack de Terraform (`infra/plataforma`) crea una VPC `10.20.0.0/16` con subredes privadas `/20` y públicas `/24` en 2 zonas (configurable), un NAT Gateway gestionado (uno, o uno por zona con una variable), el endpoint de gateway de S3, una **HTTP API** de Amazon API Gateway con stage `$default` (límite de tasa, logs de acceso, CORS) y un **VPC Link v2** con su grupo de seguridad. Las salidas se publican como **parámetros SSM** bajo `/urban-alert/plataforma/`, que es el contrato con los microservicios. Cada microservicio registra en su repo sus integraciones y rutas, que apuntan al listener HTTPS del ALB interno de Express y **sobrescriben `Host`** con el endpoint del servicio (así se resuelve el enrutamiento por cabecera `Host`). La plataforma aporta un ejemplo validado y una guía para hacerlo. Dos workflows de GitHub Actions: aprovisionamiento en push a `main`, con una guarda que impide reemplazar los recursos compartidos, y desaprovisionamiento manual con confirmación y comprobación de dependientes.

## 2. Contexto técnico

| Aspecto | Valor |
|---|---|
| Lenguaje / versión | Terraform `>= 1.10, < 2.0` (CI y local: `hashicorp/terraform:1.16.5`); Bash para scripts; YAML de GitHub Actions |
| Dependencias principales | Proveedor `hashicorp/aws ~> 6.0` (con `aws_apigatewayv2_*`, `aws_nat_gateway`, `aws_ssm_parameter`); `jq` (incluido en los runners de GitHub) en los scripts; AWS CLI v2 (incluido en los runners) |
| Almacenamiento | Estado en `s3://urban-alert-tfstate-348364742283/plataforma/terraform.tfstate` (`encrypt`, `use_lockfile`); salidas en SSM Parameter Store (estándar) |
| Pruebas | `terraform test` con `mock_provider`; pruebas de scripts con fixtures JSON (`scripts/tests/run.sh`); `actionlint`, `shellcheck`; humo tras el `apply` (`scripts/smoke-gateway.sh`) |
| Plataforma objetivo | AWS `us-east-2`, cuenta `348364742283`; consumidores en ECS Express Mode (Fargate) |
| Restricciones | Constitución P1–P10; coste mínimo; rol OIDC compartido con el subject inmutable `repo:Unal-Team-C@335834608/*`; los recursos de arranque se crean a mano |

## 3. Verificación contra la constitución

| Principio | ¿Cumple? | Nota / justificación de excepción |
|---|---|---|
| P1 IaC solo desde Actions | Sí | Todo en `infra/plataforma`; `apply`/`destroy` solo en los workflows sobre `main`. En local, solo `init -backend=false`, `fmt`, `validate` y `test`. |
| P2 Arranque fuera | Sí, con nota | La política nueva del rol (`infra/bootstrap/github-platform-policy.json`) se versiona **en este repo** (es específica de la plataforma) y la adjunta el usuario a mano; el README de `infra/bootstrap/` enlaza las de geoespacial. No entra en el estado. |
| P3 Sin secretos | Sí | OIDC con `secrets.AWS_ROLE_ARN`; la plataforma no maneja secretos. La cabecera secreta de Auditoria es asunto del consumidor (fuera de alcance). |
| P4 Destrucción explícita | Sí | `scripts/guard-plan.sh` (D-008) y `scripts/check-dependents.sh` (D-009); `deprovision.yml` exige confirmación. |
| P5 Coste mínimo | Sí | 1 NAT, sin endpoints de interfaz, HTTP API (no REST), logs con 30 días; tabla de costes en el README (research R-5: ~36,6 USD/mes). |
| P6 Validación | Sí | Job `validate` antes de `provision`; mismos comandos en local con Podman. |
| P7 Pruebas que protegen | Sí | `infra/plataforma/tests/plataforma.tftest.hcl` (§9). |
| P8 Versiones fijadas | Sí | Terraform 1.16.5, aws `~> 6.0`, lockfile con 3 plataformas, actions con versión mayor fijada (`@v4`/`@v3`, igual que geoespacial), contenedores de herramientas con versión. |
| P9 Salidas como contrato | Sí | Parámetros SSM con nombres fijos (§7), documentados; prefijo `urban-alert-` y etiquetas por defecto `Stack=plataforma`. |
| P10 Serialización | Sí | `concurrency: urban-alert-plataforma` en ambos workflows, `cancel-in-progress: false`; MS-002 se comprueba relanzando el workflow. |

## 4. Arquitectura y componentes

```text
 Internet ──HTTPS──► API Gateway (HTTP API, stage $default)   ◄── logs de acceso → CloudWatch /aws/apigateway/urban-alert-gateway
                       │  rutas e integraciones: las registra cada microservicio
                       │  (HTTP_PROXY, VPC_LINK, overwrite:header.host = endpoint Express, overwrite:path)
                       ▼
                 VPC Link v2 (ENI en ambas subredes privadas, SG: salida 443 hacia la VPC)
 ┌──────────── VPC 10.20.0.0/16 ─────────────────────────────────────────────────────────┐
 │  privada-a 10.20.0.0/20                 privada-b 10.20.16.0/20                        │
 │   ALB interno de Express (compartido, HTTPS:443, reglas por host-header)  ◄─ consumidor │
 │   tareas Fargate (sin IP pública)                                         ◄─ consumidor │
 │        │ 0.0.0.0/0                              │ 0.0.0.0/0                             │
 │        ▼                                        ▼                                       │
 │  pública-a 10.20.240.0/24: NAT Gateway + EIP ◄──┘ (o un NAT por zona si nat_por_zona) │
 │  pública-b 10.20.241.0/24 (sin NAT por defecto)                                       │
 │  endpoint de gateway S3 en las tablas privadas (capas de ECR sin pasar por el NAT)    │
 └──────────────────────────────── IGW ───────────────────────────────────────────────────┘
 SSM /urban-alert/plataforma/* ──► flujos de los microservicios (data "aws_ssm_parameter")
```

| Componente | Responsabilidad | Requisitos |
|---|---|---|
| Red (`network.tf`) | VPC con DNS, subredes privadas y públicas por zona, IGW, tablas de rutas, SG por defecto vacío | RF-001, RF-002, RNF-001, RNF-007 |
| Salida (`egress.tf`) | NAT Gateway(s) + EIP, rutas `0.0.0.0/0` de las tablas privadas, endpoint de gateway S3 | RF-003, RNF-004 |
| Gateway (`gateway.tf`) | HTTP API, stage `$default` con throttling, logs de acceso, CORS; sin rutas propias (sin `$default` → 404) | RF-004, RF-007, RF-015, RF-017, RF-018, RF-019, RNF-005, RNF-006 |
| Enlace (`gateway.tf`) | VPC Link v2 en las subredes privadas + SG (solo salida 443 a la VPC) | RF-005, RF-006, RNF-007 |
| Logs (`logs.tf`) | Grupo `/aws/apigateway/urban-alert-gateway`, 30 días | RF-015, RNF-006 |
| Contrato (`ssm.tf`, `outputs.tf`) | Parámetros SSM y salidas de Terraform | RF-008, HU-4 |
| Guarda (`scripts/guard-plan.sh`) | Falla si el plan elimina o reemplaza un recurso protegido, salvo `permitir_reemplazo_compartido = true` | RF-013 |
| Dependientes (`scripts/check-dependents.sh`) | Antes de `destroy`, lista los SG, ALB y ENI ajenos dentro de la VPC y las rutas e integraciones del gateway | RF-012 |
| Humo (`scripts/smoke-gateway.sh`) | Tras el `apply`: ruta inexistente → 404, HTTP sin cifrar no atendido, 9 parámetros SSM presentes | RF-007, RF-008, HU-1 |
| Listener Express (`scripts/buscar-listener-express.sh`) | Para los consumidores: obtiene el ARN del listener 443 del ALB de un servicio Express | RF-006, RF-011 |
| Ejemplo de consumidor (`infra/ejemplo-consumidor`) | Integraciones y rutas de referencia (pública, con reescritura, interna IAM) validadas con `terraform test` | RF-006, RF-011, RF-018, RF-019, MS-004 |
| Workflows | `provision.yml` (push a `main`), `deprovision.yml` (manual) | RF-009, RF-010, RF-012, RF-014 |
| Documentación | README (piezas, salidas, costes, workflows, arranque), `docs/integracion.md`, `infra/bootstrap/README.md` | RF-011, RNF-004, HU-6 |

## 5. Estructura de archivos

```text
.github/workflows/
  provision.yml               # push a main: validate → plan → guarda → apply → humo → resumen
  deprovision.yml             # workflow_dispatch(confirm): dependientes → destroy
infra/
  bootstrap/
    README.md                 # qué crear a mano (enlaza geoespacial/infra/bootstrap), secretos y variables de GitHub
    github-platform-policy.json  # política nueva para el rol de GitHub (R-4)
  plataforma/
    versions.tf backend.tf providers.tf variables.tf terraform.tfvars
    network.tf egress.tf gateway.tf logs.tf ssm.tf outputs.tf
    .terraform.lock.hcl
    tests/plataforma.tftest.hcl
  ejemplo-consumidor/         # referencia para los microservicios; nunca se aplica desde aquí
    versions.tf variables.tf main.tf iam.tf
    .terraform.lock.hcl
    tests/ejemplo.tftest.hcl
scripts/
  guard-plan.sh check-dependents.sh smoke-gateway.sh buscar-listener-express.sh
  tests/run.sh
  tests/fixtures/{plan-*.json, deps-*/...}
docs/integracion.md           # guía de integración (RF-011)
README.md CLAUDE.md           # actualizados
```

## 6. Modelo de datos

No hay datos de dominio. Variables de `infra/plataforma`, con su validación:

| Variable | Defecto | Validación |
|---|---|---|
| `region` | `us-east-2` | — |
| `nombre` | `urban-alert` | empieza por `urban-alert` |
| `vpc_cidr` | `10.20.0.0/16` | CIDR válido con prefijo ≤ /16 |
| `numero_zonas` | `2` | `>= 2` (exigido por ALB y por los grupos de subredes de RDS) |
| `nat_por_zona` | `false` | — |
| `cors_origenes` | `["*"]` | lista no vacía |
| `limite_tasa` / `limite_rafaga` | `50` / `100` | `> 0`; ráfaga ≥ tasa |
| `retencion_logs_dias` | `30` | `>= 30` (RNF-006) y valor admitido por CloudWatch |
| `permitir_reemplazo_compartido` | `false` | — (lo lee la guarda desde el plan JSON) |

Subredes: privada `i` = `cidrsubnet(vpc_cidr, 4, i)` (/20), pública `i` = `cidrsubnet(vpc_cidr, 8, 240 + i)` (/24), con zonas tomadas de `data "aws_availability_zones"` (state `available`).

## 7. Contratos / interfaces

**Parámetros SSM (contrato P9, tipo `String` salvo indicación):**

| Parámetro | Valor |
|---|---|
| `/urban-alert/plataforma/region` | `us-east-2` |
| `/urban-alert/plataforma/vpc-id` | ID de la VPC |
| `/urban-alert/plataforma/vpc-cidr` | `10.20.0.0/16` |
| `/urban-alert/plataforma/subredes-privadas` | `StringList`, IDs separados por comas, en orden de zona |
| `/urban-alert/plataforma/api-id` | ID de la HTTP API |
| `/urban-alert/plataforma/api-endpoint` | `https://<api-id>.execute-api.us-east-2.amazonaws.com` |
| `/urban-alert/plataforma/api-execution-arn` | `arn:aws:execute-api:us-east-2:348364742283:<api-id>` |
| `/urban-alert/plataforma/vpc-link-id` | ID del VPC Link v2 |
| `/urban-alert/plataforma/vpc-link-sg-id` | SG del VPC Link |

Si la plataforma no existe, `data "aws_ssm_parameter"` falla con `ParameterNotFound` sobre `/urban-alert/plataforma/...`, lo que deja claro que falta la plataforma (HU-4 criterio 3).

**Integración de un microservicio (lo que documenta la guía y prueba el ejemplo):**

```hcl
resource "aws_apigatewayv2_integration" "reports" {
  api_id                 = data.aws_ssm_parameter.api_id.value
  integration_type       = "HTTP_PROXY"
  integration_method     = "GET"
  integration_uri        = var.express_listener_arn     # listener 443 del ALB de Express
  connection_type        = "VPC_LINK"
  connection_id          = data.aws_ssm_parameter.vpc_link_id.value
  payload_format_version = "1.0"
  tls_config { server_name_to_verify = var.express_endpoint }
  request_parameters = {
    "overwrite:header.host" = var.express_endpoint       # sin esto, el ALB responde 404
    "overwrite:path"        = "/api/v1/geospatial/reports"
  }
}
resource "aws_apigatewayv2_route" "reports" {
  api_id    = data.aws_ssm_parameter.api_id.value
  route_key = "GET /api/v1/geoespacial/reports"
  target    = "integrations/${aws_apigatewayv2_integration.reports.id}"
}
# Ruta interna (RF-019): POST /api/v1/geoespacial/coordinates con authorization_type = "AWS_IAM";
# el rol de tarea de Reportes recibe execute-api:Invoke sobre
# "${api_execution_arn}/$default/POST/api/v1/geoespacial/coordinates".
# Ruta con parámetro: overwrite:path = "/api/v1/geospatial/coordinates/$request.path.id".
```

**Scripts:**

| Script | Entrada | Salida / código |
|---|---|---|
| `guard-plan.sh <plan.json>` | `terraform show -json tfplan` | 0 si no hay `delete` sobre direcciones protegidas (`aws_vpc.this`, `aws_subnet.privada[*]`, `aws_apigatewayv2_api.this`, `aws_apigatewayv2_stage.default`, `aws_apigatewayv2_vpc_link.this`, `aws_security_group.vpc_link`, `aws_ssm_parameter.*`) o si `permitir_reemplazo_compartido = true`; si no, 1 y la lista |
| `check-dependents.sh <vpc_id> <api_id>` (o `--desde-dir <dir>` en las pruebas) | AWS CLI: SG, ALB y ENI de la VPC; rutas e integraciones de la API | 0 si no hay recursos ajenos; si no, 1 con la lista. Se excluyen el SG por defecto y los etiquetados `Stack=plataforma`, y las ENI del NAT y del VPC Link |
| `smoke-gateway.sh <api_endpoint>` | URL del gateway | 0 si `/api/v1/__humo__` → 404, `http://` no responde 2xx/3xx y existen los 9 parámetros SSM |
| `buscar-listener-express.sh <cluster> <servicio>` | AWS CLI | ARN del listener 443 por la cadena de research R-1; 1 si algún paso no devuelve nada |

**Workflows:** `secrets.AWS_ROLE_ARN` y `vars.AWS_REGION` en el repo de la plataforma. Para desaprovisionar hay que escribir `urban-alert-plataforma` en la confirmación.

## 8. Decisiones

### D-001: Un solo stack de Terraform
- **Decisión**: `infra/plataforma`, con estado `plataforma/terraform.tfstate`.
- **Alternativas consideradas**: separar red y gateway en dos stacks, como platform/service en geoespacial.
- **Motivo**: tienen el mismo ciclo de vida y se despliegan juntos; con dos stacks habría que orquestar el orden y la destrucción sin ganar nada (P5/simplicidad).

### D-002: Direccionamiento
- **Decisión**: VPC `10.20.0.0/16`; privadas `/20` (unas 4.000 IP por zona, para tareas, ALB y ENI del VPC Link); públicas `/24` (solo NAT); `numero_zonas = 2`, configurable.
- **Alternativas consideradas**: `/24` privadas (se quedarían cortas con Express, que exige al menos 8 IP libres por subred y una IP por tarea); 3 zonas (nada lo exige).
- **Motivo**: hay margen para todos los microservicios previstos; el rango no se solapa con la VPC predeterminada (`172.31.0.0/16`).

### D-003: Salida = un NAT Gateway gestionado + endpoint de gateway S3
- **Decisión**: un NAT en la pública-a (`nat_por_zona = false`); todas las tablas privadas salen por él. Con `true` se crea un NAT por zona. Endpoint de gateway S3 en las tablas privadas. Sin endpoints de interfaz.
- **Alternativas consideradas**: instancia NAT, gateway Nginx propio, API REST privada + `execute-api`, solo endpoints de interfaz (research R-3; decisión del usuario en la spec §11).
- **Motivo**: los servicios llaman a la URL pública del gateway, así que hace falta salida a internet. El NAT gestionado escala solo y no requiere mantenimiento. El endpoint S3 es gratis y quita del NAT el tráfico de las capas de ECR.

### D-004: HTTP API en lugar de REST API
- **Decisión**: `aws_apigatewayv2_api` con `protocol_type = "HTTP"`, stage `$default` con `auto_deploy = true`.
- **Alternativas consideradas**: REST API (research R-2).
- **Motivo**: es 3,5 veces más barata; cubre VPC Link v2 a ALB, IAM por ruta, reescritura de ruta y cabeceras, CORS y throttling. Lo que solo da REST (WAF, caché, planes de uso) está fuera de alcance. Responde solo por HTTPS, sin configurar nada más.

### D-005: Resolver el enrutamiento por `Host` en la integración de cada ruta
- **Decisión**: cada integración apunta al **ARN del listener 443** del ALB interno de Express con `tls_config.server_name_to_verify` y `overwrite:header.host` iguales al endpoint del servicio, `payload_format_version = "1.0"` y `overwrite:path` para traducir la ruta pública a la del servicio.
- **Alternativas consideradas**: añadir reglas propias al listener de Express (Express gestiona sus reglas y puede sobrescribirlas); poner un NLB o un ALB propio delante (más coste y piezas, y Express no deja controlar su ALB); usar HTTP al puerto 80 (Express solo crea el listener 443).
- **Motivo**: es la vía verificada en la práctica (research R-1); `Host` no es una cabecera reservada en HTTP API. Contrapartida: el servicio ve su dominio `.on.aws` como `Host`, y `X-Forwarded-Host` no se puede fijar porque es reservada.

### D-006: Salidas en SSM Parameter Store
- **Decisión**: un parámetro por salida bajo `/urban-alert/plataforma/` (§7); las salidas de Terraform se mantienen para el resumen del workflow.
- **Alternativas consideradas**: `terraform_remote_state` sobre el bucket, como entre los stacks de geoespacial.
- **Motivo**: el contrato queda explícito y versionable (P9). El consumidor no depende del formato del estado ni de la versión de Terraform, puede leer los valores con la CLI en sus workflows y obtiene un error claro si falta la plataforma. Los parámetros estándar son gratis.

### D-007: Valores por defecto del stage
- **Decisión**: throttling por defecto de 50 rps con ráfaga de 100; logs de acceso en JSON (`requestId`, `ip`, `requestTime`, `httpMethod`, `routeKey`, `path`, `status`, `responseLatency`, `integrationLatency`, `integrationErrorMessage`) en `/aws/apigateway/urban-alert-gateway` durante 30 días; CORS con `allow_origins = var.cors_origenes`, métodos `GET, POST, PUT, PATCH, DELETE, OPTIONS`, cabeceras `content-type, authorization, x-amz-date, x-amz-security-token`, `allow_credentials = false` y `max_age = 3600`.
- **Alternativas consideradas**: sin throttling (incumple RNF-005); logs sin estructura.
- **Motivo**: valores modestos y ajustables (spec §9); los logs en JSON se pueden consultar con Logs Insights.

### D-008: Guarda contra reemplazos sobre el plan JSON
- **Decisión**: `provision.yml` ejecuta `terraform plan -out=tfplan` → `terraform show -json tfplan > plan.json` → `guard-plan.sh plan.json` → `terraform apply tfplan`. La guarda busca `delete` en `resource_changes[].change.actions` (cubre eliminar y reemplazar) sobre la lista de direcciones protegidas, salvo que `.variables.permitir_reemplazo_compartido.value == true`.
- **Alternativas consideradas**: `lifecycle { prevent_destroy = true }`, que también bloquearía el desaprovisionamiento y no se puede condicionar con una variable.
- **Motivo**: cumple RF-013 y P4. La excepción es un cambio commiteado y visible en `terraform.tfvars`, y la guarda se puede probar con fixtures.

### D-009: Comprobación de dependientes antes de destruir
- **Decisión**: `check-dependents.sh` considera dependientes los SG de la VPC (salvo el por defecto y los etiquetados `Stack=plataforma`), los ALB de la VPC, las ENI de la VPC que no sean del NAT (`InterfaceType=nat_gateway`) ni del VPC Link (las de API Gateway), y cualquier ruta o integración de la API (la plataforma no crea ninguna).
- **Alternativas consideradas**: lanzar `destroy` y dejar que falle (deja la plataforma a medio destruir, por ejemplo el gateway borrado y la VPC no).
- **Motivo**: RF-012 / HU-5 criterio 3. Todo consumidor crea al menos un SG o un ALB en la VPC, o una ruta en el gateway, así que esas señales bastan.

### D-010: Ejemplo de consumidor validado en lugar de módulo compartido
- **Decisión**: `infra/ejemplo-consumidor/` con integraciones y rutas de ejemplo (geoespacial: `GET reports`, `GET coordinates/{id}` y `POST coordinates` interna con IAM, más la política de invocación para el rol que llama). Se valida con `terraform validate/test` en el CI, y cada consumidor copia lo que necesita (`docs/integracion.md`). `buscar-listener-express.sh` se copia igual.
- **Alternativas consideradas**: un módulo de Terraform referenciado por git (el repo es privado y los workflows de otros repos no pueden clonarlo sin una credencial adicional; P3).
- **Motivo**: no hace falta compartir credenciales entre repos, y el ejemplo no se queda desfasado porque el CI lo prueba.

### D-011: Permisos del rol de GitHub como recurso de arranque
- **Decisión**: `infra/bootstrap/github-platform-policy.json` con los permisos de R-4, limitados a `us-east-2`/cuenta y a recursos `urban-alert-*` donde la API lo permite (logs, SSM). Algunos no aceptan restricción por recurso (`ec2:Create*` de VPC, `apigateway` sobre `/apis/*` y `/vpclinks/*`). El usuario la crea y la adjunta al rol a mano.
- **Alternativas consideradas**: gestionarla con Terraform (incumple P2).
- **Motivo**: sin ella el primer `apply` falla con `AccessDenied`. Los consumidores necesitarán además `apigateway` sobre rutas e integraciones, y `ssm:GetParameter*` y `elasticloadbalancing:Describe*`; la misma política los incluye, porque el rol es compartido.

### D-012: SG por defecto vacío y sin IP pública automática
- **Decisión**: `aws_default_security_group` sin reglas; `map_public_ip_on_launch = false` también en las subredes públicas.
- **Motivo**: ningún recurso queda abierto por accidente (RNF-001); se prueba en P7.

### D-013: Aislamiento de los ALB de Express (ajuste a RF-005 y RF-011)
- **Decisión**: los microservicios **no** pueden restringir el SG del ALB de Express al VPC Link, porque ese SG lo crea y gestiona Express (research R-1). El aislamiento frente a internet lo da el esquema interno del ALB (subredes privadas). El SG del VPC Link se publica igualmente, para reglas de entrada adicionales del consumidor (por ejemplo, el SG de una base de datos) o para un cambio futuro de Express.
- **Alternativas consideradas**: modificar a mano el SG de Express (deriva no gestionada y Express puede revertirlo); poner un ALB propio delante (D-005).
- **Motivo**: la spec pide que el servicio no sea alcanzable **desde internet** salvo por el gateway (HU-2 criterio 3, RNF-001), y eso se cumple. Lo que no se cumple es la parte de RF-005 «único origen permitido en sus balanceadores»: dentro de la VPC, otras tareas pueden llegar al ALB. Ajuste aceptado por el usuario el 2026-10-11 y aplicado en la spec (RF-005, RF-011, §11).

## 9. Estrategia de pruebas

| Nivel | Qué | Comando |
|---|---|---|
| Estático | Formato, validez y lockfile de ambos stacks | `$TF -chdir=infra/<stack> init -backend=false -lockfile=readonly && $TF -chdir=infra/<stack> validate`; `$TF fmt -check -recursive infra` |
| Unidad de Terraform (P7) | `plataforma.tftest.hcl` con `mock_provider "aws"` y `override_data` de zonas: (1) 2 privadas en zonas distintas, /20, sin IP pública y con ruta por defecto al NAT; (2) `numero_zonas = 1` → error de validación; (3) `nat_por_zona` false → 1 NAT, true → 2; (4) SG por defecto sin reglas; (5) SG del VPC Link sin entrada y con salida solo 443 a la VPC; (6) stage con throttling y logs de acceso; CORS sin credenciales; ninguna ruta `$default`; (7) los 9 parámetros SSM con sus nombres exactos (contrato P9); (8) `retencion_logs_dias = 7` → error; (9) endpoint S3 asociado a las tablas privadas | `$TF -chdir=infra/plataforma test` |
| Unidad de Terraform del ejemplo | Host sobrescrito = endpoint, `server_name_to_verify`, payload 1.0, `VPC_LINK`, reescritura de ruta, ruta interna `AWS_IAM`, política `execute-api:Invoke` limitada a esa ruta | `$TF -chdir=infra/ejemplo-consumidor test` |
| Scripts | `scripts/tests/run.sh`: guarda con fixtures (sin cambios → 0; reemplazo de VPC → 1; reemplazo con permiso → 0; borrado de un parámetro SSM → 1); dependientes con fixtures (vacío → 0; SG ajeno → 1 con el nombre; ruta en la API → 1); `shellcheck` | `bash scripts/tests/run.sh`; `podman run … shellcheck scripts/*.sh scripts/tests/*.sh` |
| Workflows | Sintaxis y shell embebido | `podman run … actionlint:1.7.7` |
| Humo (en AWS, dentro de `provision.yml`) | Ruta inexistente → 404 (RF-007), `http://` no atendido (HU-2 criterio 5), 9 parámetros SSM (RF-008) | `scripts/smoke-gateway.sh "$API_ENDPOINT"` |
| Idempotencia (en AWS) | Relanzar el workflow sobre el mismo commit da `No changes` (MS-002, RNF-002) | Re-run en Actions; el resumen muestra el plan |
| Integración con geoespacial (en su repo) | MS-003, HU-2 criterios 1–3 y 6, HU-3: contrato por el gateway; el endpoint de Express, el ALB y las tareas no son alcanzables desde internet; POST interno sin firma → 403 | Tarea de verificación conjunta (verify de esta feature + replan de la 002) |

`$TF` = `podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5` (constitución, Calidad y pruebas).

## 10. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| La confianza OIDC del rol sigue sin el subject inmutable | El primer workflow falla al autenticarse | Requisito previo en `infra/bootstrap/README.md`; no se crea nada en AWS hasta que funcione |
| Falta la política D-011 o le falta alguna acción | `apply` a medias con `AccessDenied` | Política completa desde el inicio; el siguiente `apply` retoma desde el estado; la acción que falta aparece en el log |
| La cadena para obtener el listener (R-1) no funciona igual en la realidad, o Express cambia sus reglas | Las rutas de geoespacial no llegan (404/503) | Se verifica en el primer despliegue de geoespacial; alternativa: buscar el listener por la regla con `host-header == endpoint` (`elbv2 describe-rules`) |
| Express reutiliza o comparte un ALB de forma inesperada (más de 25 servicios, o subredes de otras zonas) | Listener distinto por servicio | La guía exige pasar todas las subredes privadas; el script busca por servicio, no por VPC |
| `overwrite:header.host` deja de admitirse | El gateway no puede enrutar | Ya probado por terceros; humo de integración en geoespacial; plan B: ALB propio (D-005, alternativa) |
| El servicio construye URL absolutas con `Host` (por ejemplo, la cabecera `Location` de geoespacial devuelve la ruta interna) | Enlaces con dominio o ruta internos | Documentado en la guía; los clientes no deben depender de `Location` (geoespacial ya devuelve el id en el cuerpo) |
| Se elimina la plataforma con consumidores activos | Rotura general | D-009 + confirmación + documentación del orden: primero se desaprovisionan los consumidores |
| Un solo NAT: si cae su zona, la otra se queda sin salida | Llamadas entre servicios y despliegues fallan | Aceptado en la spec; `nat_por_zona = true` lo resuelve con un commit |
| Las ENI del VPC Link se eliminan tras 60 días sin tráfico | Primera petición lenta o con error tras mucho tiempo sin uso | Documentado; API Gateway las recrea al volver a usarse |
| Coste sostenido del NAT con la plataforma encendida sin uso | ~37 USD/mes | Tabla de costes y workflow de desaprovisionamiento |

## 11. Trazabilidad

| Requisito | Componentes | Pruebas |
|---|---|---|
| RF-001 | `network.tf` | tftest (1), (2) |
| RF-002 | `network.tf`, `egress.tf` | tftest (1): públicas solo con NAT/IGW y sin IP pública automática |
| RF-003 | `egress.tf` | tftest (1), (3), (9); integración geoespacial (HU-3) |
| RF-004 | `gateway.tf`, `ssm.tf` | tftest (6), (7); humo |
| RF-005 | `gateway.tf` (VPC Link + SG), D-013 | tftest (5) |
| RF-006 | D-005, `infra/ejemplo-consumidor`, `buscar-listener-express.sh` | test del ejemplo; integración geoespacial (HU-2 criterios 1–2) |
| RF-007 | `gateway.tf` (sin `$default`) | tftest (6); humo (404, http) |
| RF-008 | `ssm.tf`, `outputs.tf` | tftest (7); humo |
| RF-009 | `backend.tf` | revisión: clave `plataforma/terraform.tfstate`, `encrypt`, `use_lockfile` |
| RF-010 | `provision.yml` | actionlint; ejecución en `main` |
| RF-011 | `docs/integracion.md`, ejemplo | revisión contra la lista de RF-011; MS-004 |
| RF-012 | `deprovision.yml`, `check-dependents.sh` | `run.sh` (fixtures); actionlint |
| RF-013 | `guard-plan.sh`, `permitir_reemplazo_compartido` | `run.sh` (fixtures) |
| RF-014 | workflows (`id-token: write`, `configure-aws-credentials`) | actionlint; `grep` sin `aws-access-key-id` |
| RF-015 | `gateway.tf`, `logs.tf` | tftest (6) |
| RF-016 | `infra/bootstrap/` (fuera del estado) | `grep` sin recursos OIDC/IAM/bucket en `infra/plataforma` |
| RF-017 | `gateway.tf` (sin authorizer) | tftest (6) |
| RF-018 | guía + ejemplo (`overwrite:path`, métodos, cabecera fija) | test del ejemplo |
| RF-019 | ejemplo (`AWS_IAM` + `execute-api:Invoke`), salida `api-execution-arn` | test del ejemplo; integración geoespacial (HU-2 criterio 6) |
| RNF-001 | D-012, subredes privadas, SG del VPC Link | tftest (1), (4), (5) |
| RNF-002 | todo el stack | re-run sin cambios (MS-002) |
| RNF-003 | workflows | duración en Actions (< 10 min sin cambios, < 20 desde cero) |
| RNF-004 | D-003, D-004, README | tabla de costes (MS-005) |
| RNF-005 | `gateway.tf` (throttling) | tftest (6) |
| RNF-006 | `logs.tf` | tftest (6), (8) |
| RNF-007 | VPC Link y subredes en 2 zonas | tftest (1); revisión |
