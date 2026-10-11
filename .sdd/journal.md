# Journal SDD

<!-- Bitácora append-only: añade entradas AL FINAL, no reescribas las anteriores.
     Formato:
     ## AAAA-MM-DD · <feature o "general"> · <evento>
     - detalle (qué, por qué, archivos, verificación)
     Las horas exactas de cada edición/checkpoint quedan en .sdd/activity.log. -->

## 2026-10-11 · general · Repo creado con el arnés SDD
- github.com/Unal-Team-C/urban-alert-plataforma (privado). Arnés copiado de urban-alert-geoespacial (estado, journal y constitución en blanco).
- Propósito: red compartida y Amazon API Gateway para todos los microservicios de UrbanAlert.

## 2026-10-11 · 001-red-api-gateway · Creada spec desde descripción
- spec.md: red propia con subredes privadas en ≥2 zonas y salida, API Gateway compartido con VPC Link a los ALB internos de ECS Express, salidas para microservicios, flujos de aprovisionamiento (push a main) y desaprovisionamiento (manual, confirmación, comprobación de dependientes). 6 HU, RF-001–017, RNF-001–007, MS-001–005.
- 3 [NEEDS CLARIFICATION]: Q1 salida a internet general vs solo AWS (NAT vs endpoints); Q2 autenticación en el gateway; Q3 convención de rutas (prefijo por servicio).
- notes.md: indicaciones técnicas para el plan (riesgo Host del ALB de Express, endpoints mínimos, salidas) y contexto heredado de STATE.md.

## 2026-10-11 · 001-red-api-gateway · Clarificación (spec aclarada)
- Q1: sin salida a internet fuera de AWS; los servicios se hablan solo por el gateway → las tareas deben llegar a la URL pública del gateway (RF-003). Implica salida a internet (NAT) en el plan: el endpoint execute-api no sirve para APIs públicas (notes.md).
- Q2: el gateway solo enruta; autenticación de clientes fuera de alcance (RF-017).
- Q3: convención de UrbanAlert/infrastructure/README.md (copiado a fuentes/): /api/v1/<servicio>/ con reescritura, métodos por ruta, cabecera fija; resto de /api/ → 404 (RF-018).
- Rutas internas entre servicios → firma IAM por ruta con el rol de tarea del llamante (RF-019); salida añadida: ARN de ejecución del gateway.
- Gateway solo para APIs: frontend y /health propio fuera de alcance; CORS abierto hasta conocer la URL del frontend.

## 2026-10-11 · 001-red-api-gateway · Decisión: salida por NAT Gateway gestionado
- Evaluadas alternativas (API REST privada + endpoint execute-api, gateway Nginx propio con IP elástica, instancia NAT). El usuario elige mantener API Gateway administrado + NAT Gateway gestionado. Registrado en spec §11 y notes.md; detalle (uno compartido vs uno por zona, endpoint S3) para /sdd-plan.

## 2026-10-11 · 001-red-api-gateway · Spec aprobada
- El usuario aprueba specs/001-red-api-gateway/spec.md (Estado: aprobada). Siguiente: /sdd-plan (recomendado /sdd-constitution antes; la constitución sigue en blanco).

## 2026-10-11 · general · Constitución 1.0.0
- P1 IaC solo desde Actions en main · P2 arranque fuera de Terraform · P3 OIDC y sin secretos · P4 destrucción solo explícita (guarda anti-reemplazo y comprobación de dependientes) · P5 coste mínimo documentado · P6 fmt/validate/test/actionlint/shellcheck antes de commit y apply · P7 terraform test para garantías de seguridad · P8 versiones fijadas (TF 1.16.5, aws ~>6.0, lockfile multiplataforma) · P9 salidas como contrato, prefijo y etiquetas · P10 concurrency e idempotencia.
- Inferidos de urban-alert-geoespacial (CLAUDE.md, tasks.md, infra/platform). No hay plan.md previos que revisar.

## 2026-10-11 · 001-red-api-gateway · Plan redactado (borrador)
- research.md: R-1 ALB de Express (interno con subredes privadas, compartido hasta 25 servicios, HTTPS:443 con reglas host-header; SG del ALB gestionado por Express); HTTP API + VPC Link v2 → listener 443 con overwrite:header.host + tls server_name_to_verify + payload 1.0 (verificado por terceros; Host no es reservada). Listener ARN: no lo exporta Terraform ni DescribeExpressGatewayService → cadena describe-services → target group → LB → listener 443. R-4: al rol de GitHub le faltan permisos de VPC/NAT/API Gateway/SSM.
- Decisiones: D-001 un stack · D-002 10.20.0.0/16, /20 privadas · D-003 1 NAT (+ variable por zona) + endpoint S3 · D-004 HTTP API · D-005 Host por integración · D-006 salidas en SSM /urban-alert/plataforma/* · D-007 throttling 50/100, logs JSON 30 d, CORS · D-008 guarda sobre plan JSON · D-009 dependientes (SG/ALB/ENI/rutas) · D-010 ejemplo de consumidor validado en vez de módulo git · D-011 política de arranque nueva · D-012 SG por defecto vacío · D-013 no se puede restringir el SG del ALB de Express al VPC Link (ajuste a RF-005, pendiente de aceptar).

## 2026-10-11 · 001-red-api-gateway · Plan aprobado
- Usuario aprueba el plan y el ajuste D-013: RF-005 y RF-011 ya no exigen restringir el ALB de Express al VPC Link (registrado en spec §11). Siguiente: /sdd-tasks.

## 2026-10-11 · 001-red-api-gateway · tasks.md generado: 26 tareas
- Preparación 2 (política de arranque, esqueleto del stack) · Pruebas 3 (tftest red/salida, gateway/contrato, scripts con fixtures) · Núcleo 9 (red, salida, gateway, contrato, lockfile, 4 scripts) · Integración 9 (ejemplo de consumidor + pruebas, guía, provision, deprovision, primer apply real, idempotencia, deprovision sin confirmación, verificación conjunta con geoespacial) · Pulido 3 (README, CLAUDE.md, ciclo completo opcional).
- Pruebas de Terraform divididas por área para ejecutarlas con -filter durante la implementación. T020+ dependen de pasos manuales del usuario (política, OIDC, secreto/variable, push).

## 2026-10-11 · 001-red-api-gateway · tasks.md aprobado
- Usuario aprueba las 26 tareas. Siguiente: /sdd-implement desde T001.

## 2026-10-11 · 001-red-api-gateway · T001 hecha
- infra/bootstrap/github-platform-policy.json (red/NAT/endpoints/SG/ENI, apigateway /apis /vpclinks /tags, rol vinculado ops.apigateway, logs /aws/apigateway/urban-alert-* y entregas, SSM /urban-alert/*, elasticloadbalancing:Describe*; 2,9 KB < 6 KB del límite) e infra/bootstrap/README.md (4 pasos: política, confianza OIDC inmutable, secreto/variable, comprobar). Verificado: json.tool OK; grep encuentra las 8 acciones; 4 pasos.

## 2026-10-11 · 001-red-api-gateway · T002 hecha
- infra/plataforma: versions (TF >=1.10 <2, aws ~>6.0), backend (plataforma/terraform.tfstate, encrypt, use_lockfile), providers (default_tags Project/ManagedBy/Stack=plataforma), variables con validaciones (prefijo, CIDR <=/16, 2–4 zonas, tasa/ráfaga, retención CloudWatch >=30), terraform.tfvars. El lockfile generado por init se descarta hasta T010 (multiplataforma). Verificado: init -backend=false + validate «Success»; fmt -check limpio.

## 2026-10-11 · 001-red-api-gateway · T003 hecha
- tests/red.tftest.hcl (2 privadas /20 en zonas distintas de la VPC 10.20.0.0/16 con DNS; ninguna subred con IP pública automática; solo la tabla pública va al IGW y las privadas salen por NAT; asociaciones; SG por defecto sin reglas; numero_zonas=1 rechazado) y tests/salida.tftest.hcl (1 NAT compartido en publica[0] con su EIP; nat_por_zona → 2 NAT, cada tabla con el de su zona; endpoint S3 Gateway en las tablas privadas). Verificado: test -filter de cada archivo falla solo con «Reference to undeclared resource».

## 2026-10-11 · general · Push a main (petición del usuario)
- origin/main → af8ce62 (spec/plan/tareas, T001–T003). Sin workflows todavía: no se ejecuta nada en AWS. El push por HTTPS necesita `git -c credential.helper= -c credential.helper='!gh auth git-credential' push` (osxkeychain sin credencial).

## 2026-10-11 · 001-red-api-gateway · T004 hecha
- tests/gateway.tftest.hcl (HTTP API urban-alert-gateway sin target/route_key → sin ruta por defecto; execute-api activo; CORS sin credenciales; stage $default auto_deploy, 50/100, logs JSON con requestId/requestTime/httpMethod/routeKey/path/status/latencias al grupo /aws/apigateway/urban-alert-gateway de 30 d; retención 7 rechazada; VPC Link en las privadas con su SG, sin entrada y salida solo tcp/443 al CIDR de la VPC) y tests/contrato.tftest.hcl (9 nombres SSM exactos, valores = ids de los recursos, subredes StringList en orden, resto String; salidas ssm_prefix, vpc_id, api_endpoint, subredes_privadas, vpc_link_id). Verificado: test -filter de cada archivo falla solo con «Reference to undeclared resource».

## 2026-10-11 · 001-red-api-gateway · T005 hecha
- scripts/tests/run.sh (función expect: código de salida + texto) y fixtures: 4 planes (sin cambios con reemplazo no protegido → 0; VPC+subred reemplazadas → 1; mismo con permiso → 0; borrado de parámetro SSM → 1) y 5 directorios deps-* (vacío con SG default/plataforma y ENI de NAT/VPC Link → 0; SG ajeno, ALB en la VPC, ruta+integración, ENI de tarea → 1). Verificado: run.sh falla los 11 casos solo porque no existen guard-plan.sh ni check-dependents.sh (exit 127).

## 2026-10-11 · 001-red-api-gateway · T006 hecha
- network.tf: zonas = primeras numero_zonas de aws_availability_zones (ordenadas) con precondición; VPC 10.20.0.0/16 con DNS; privadas cidrsubnet(/4) y públicas cidrsubnet(/8, 240+i) sin IP pública; IGW; tabla pública + aws_route.publica_internet + asociaciones; aws_default_security_group sin reglas. Ajuste de pruebas: las aserciones de rutas/asociaciones privadas pasan de red.tftest.hcl a salida.tftest.hcl (run private_subnets_reach_the_internet_only_through_nat) para que cada archivo dependa solo de su área. Verificado: test -filter=tests/red.tftest.hcl → 4 passed.

## 2026-10-11 · 001-red-api-gateway · T007 hecha
- egress.tf: EIP + NAT (1, o uno por zona con nat_por_zona) en las públicas con depends_on IGW; una tabla privada por zona con 0.0.0.0/0 → NAT propio o el compartido; asociaciones; endpoint de gateway S3 en las tablas privadas. Verificado: test -filter=tests/salida.tftest.hcl → 4 passed; fmt -check limpio.

## 2026-10-11 · 001-red-api-gateway · T008 hecha
- logs.tf (grupo /aws/apigateway/urban-alert-gateway, retención var) y gateway.tf (HTTP API urban-alert-gateway con CORS y disable_execute_api_endpoint=false explícito; stage $default auto_deploy, throttling por variables, logs de acceso JSON; SG del VPC Link sin entrada + regla de salida tcp/443 al CIDR de la VPC; VPC Link v2 en las privadas). Hallazgo: con mock_provider el proveedor valida formato de ARN → mock_resource aws_cloudwatch_log_group con ARN realista en los 4 archivos de prueba. Verificado: gateway 5 passed; red 4 y salida 4 siguen pasando.

## 2026-10-11 · 001-red-api-gateway · T009 hecha
- ssm.tf: local contrato (9 claves) → aws_ssm_parameter.contrato for_each bajo /urban-alert/plataforma/, subredes-privadas StringList; outputs.tf: ssm_prefix, region, vpc_id, vpc_cidr, subredes_privadas, api_id, api_endpoint, api_execution_arn, vpc_link_id, vpc_link_sg_id. Verificado: terraform test completo 16 passed (red 4, salida 4, gateway 5, contrato 3); validate «Success».

## 2026-10-11 · 001-red-api-gateway · T010 hecha
- .terraform.lock.hcl de infra/plataforma: hashicorp/aws 6.68.0 (~> 6.0) con hashes h1 para linux_amd64, linux_arm64 y darwin_arm64. Verificado: init -backend=false -lockfile=readonly limpio tras borrar .terraform; 3 hashes h1.

## 2026-10-11 · 001-red-api-gateway · T011 hecha
- scripts/guard-plan.sh: jq sobre resource_changes, bloquea actions con delete (eliminar o reemplazar) en aws_vpc.this, aws_subnet.privada[n], aws_apigatewayv2_api.this, aws_apigatewayv2_stage.default, aws_apigatewayv2_vpc_link.this, aws_security_group.vpc_link y aws_ssm_parameter.contrato[*]; excepción con permitir_reemplazo_compartido=true; lista en stderr. Hallazgo: macOS trae bash 3.2 (sin mapfile) → scripts sin arrays de bash 4. run.sh: printf en lugar de sed (SC2001). Verificado: 5 casos guard ok; shellcheck sin avisos.

## 2026-10-11 · 001-red-api-gateway · T012 hecha
- scripts/check-dependents.sh [--desde-dir DIR] <vpc_id> <api_id>: sin --desde-dir consulta AWS (describe-security-groups/network-interfaces filtrados por VPC, elbv2 describe-load-balancers, apigatewayv2 get-routes/get-integrations; api vacío → sin rutas) a un temporal; jq lista SG ajenos (excluye default y Stack=plataforma), ALB de la VPC, ENI salvo nat_gateway/api_gateway_managed, rutas e integraciones; exit 1 con la lista y la indicación de desaprovisionar antes los microservicios. Verificado: run.sh 11/11 ok; shellcheck sin avisos.

## 2026-10-11 · 001-red-api-gateway · T013 hecha
- scripts/smoke-gateway.sh <https endpoint>: (1) /api/v1/__humo__ → 404 con hasta 10 reintentos de 6 s; (2) http://host sin 2xx/3xx (timeout 10 s); (3) ssm get-parameters-by-path /urban-alert/plataforma/ = 9; exit 1 si falla alguno, 2 si el uso es incorrecto. Verificado: bash -n y shellcheck sin avisos; con http:// sale 2 con el uso (ejecución real en T020).

## 2026-10-11 · 001-red-api-gateway · T014 hecha
- scripts/buscar-listener-express.sh <cluster> <servicio|ARN>: ecs describe-services → loadBalancers[0].targetGroupArn → elbv2 describe-target-groups → LoadBalancerArns[0] → describe-listeners Port 443; error explícito en cada paso vacío/None. Verificado: bash -n y shellcheck de todos los scripts sin avisos (SC2016 desactivado en la consulta JMESPath con backticks). Ejecución real pendiente de T023.

## 2026-10-11 · 001-red-api-gateway · T015 hecha
- infra/ejemplo-consumidor: versions.tf (proveedor + aviso de que nunca se aplica aquí), variables.tf (express_endpoint host sin esquema, express_listener_arn de listener ALB, rol_llamante, cabeceras_fijas sensible) y tests/ejemplo.tftest.hcl (6 runs: integraciones HTTP_PROXY/VPC_LINK al listener con payload 1.0; Host y SNI = endpoint; reescritura de reports y coordinates/$request.path.id; exactamente 3 rutas con su integración; POST interno AWS_IAM, públicas NONE, política execute-api:Invoke solo sobre $default/POST/api/v1/geoespacial/coordinates; cabecera fija; endpoint con https:// rechazado). Verificado: test falla solo por «Reference to undeclared resource».

## 2026-10-11 · 001-red-api-gateway · T016 hecha
- ejemplo-consumidor: main.tf (3 data SSM; local rutas reports/coordinate/assign; integraciones HTTP_PROXY VPC_LINK al listener, payload 1.0, tls server_name, request_parameters = cabeceras fijas + overwrite:header.host + overwrite:path; rutas for_each con authorization_type), iam.tf (execute-api:Invoke sobre <exec-arn>/$default/<MÉTODO><ruta> de las rutas AWS_IAM, en el rol del llamante) y lockfile multiplataforma (aws 6.68.0, 3 hashes). Nota: al ser cabeceras_fijas sensible, request_parameters sale oculto en los planes del consumidor. Verificado: test 6 passed; validate «Success»; init -lockfile=readonly OK; fmt limpio.

## 2026-10-11 · 001-red-api-gateway · T017 hecha
- docs/integracion.md: requisitos; contrato SSM (tabla, HCL y CLI, ParameterNotFound); Express en todas las subredes privadas (ALB por VPC fijado por el primer servicio, run-task sin IP pública); endpoint + listener tras desplegar (rutas en paso posterior); convención de rutas con tabla de atributos de la integración (Host, SNI, payload 1.0, overwrite:path, cabeceras fijas desde Secrets Manager), sin $default, ConflictException; rutas internas AWS_IAM + execute-api:Invoke + firma SigV4; aislamiento D-013; Host/Location/30 s/throttling/CORS/ENI 60 días; permisos; orden de desaprovisionamiento; lista de comprobación RF-011. Verificado: los 6 puntos de RF-011 están en la lista de comprobación; enlaza infra/ejemplo-consumidor (6 referencias).

## 2026-10-11 · 001-red-api-gateway · T018 hecha
- .github/workflows/provision.yml: push a main; concurrency urban-alert-plataforma sin cancelar; shell bash (pipefail); job validate (fmt, init -lockfile=readonly + validate + test de plataforma y ejemplo-consumidor, run.sh, actionlint 1.7.7, shellcheck v0.10.0); job provision (id-token, configure-aws-credentials con secrets.AWS_ROLE_ARN/vars.AWS_REGION, plan -out con plan.txt, show -json, guard-plan.sh, apply tfplan, salidas, smoke-gateway.sh, resumen con línea del plan y salidas aunque falle). Constitución 1.0.1: shellcheck stable → v0.10.0 (P8), también en la cabecera de tasks.md. Verificado: actionlint sin errores; 0 aws-access-key-id; orden plan→guarda→apply = D-008.

## 2026-10-11 · 001-red-api-gateway · T019 hecha
- .github/workflows/deprovision.yml: solo workflow_dispatch con confirm; primer paso corta (exit 1, nada eliminado) si confirm != urban-alert-plataforma o la rama no es main, antes de checkout y credenciales; misma concurrency; init + state list vacío → «nothing to delete» y salta el resto; check-dependents.sh con vpc_id/api_id de las salidas; destroy -auto-approve; resumen según resultado. Verificado: actionlint sin errores; sin on: push; confirmación (línea 37) antes de configure-aws-credentials (53).

## 2026-10-11 · 001-red-api-gateway · T024 hecha
- README.md: arquitectura (diagrama + tabla de piezas), contrato SSM (9 parámetros), workflows (guarda y cómo habilitar reemplazos; Deprovision con orden y confirmación), costes R-5 desglosados (~36,6 USD/mes; nat_por_zona ~73; nota del ALB de Express), arranque (enlace a infra/bootstrap), validación local con Podman, SDD. Verificado: secciones Arquitectura/Contrato/Workflows/Costes/Arranque/Validación presentes; 3 enlaces a docs/integracion.md.

## 2026-10-11 · 001-red-api-gateway · T025 hecha
- CLAUDE.md: estado remoto, arranque, estructura (stack, ejemplo, scripts, workflows, contrato SSM), comandos de validación con Podman (terraform 1.16.5, run.sh, actionlint 1.7.7, shellcheck v0.10.0) y gotchas (bash 3.2, ARN en mocks, lockfile multiplataforma, push con gh). Verificado: los comandos coinciden con la cabecera de tasks.md.

## 2026-10-11 · 001-red-api-gateway · T020 desbloqueada
- El usuario confirma: política de la plataforma adjunta, confianza OIDC corregida, secreto AWS_ROLE_ARN y variable AWS_REGION creados. Autoriza el push a main.

## 2026-10-11 · 001-red-api-gateway · T020: primer Provision falla a medias
- Run 38107569124: validate OK (46 s); OIDC OK; plan + guarda OK; apply creó VPC, subredes, IGW, tablas, EIP, NAT (~1 min 55 s), endpoint S3, SG del VPC Link + regla, API y grupo de logs, asociaciones. Fallaron aws_apigatewayv2_stage.default y aws_apigatewayv2_vpc_link.this: AccessDenied apigateway:TagResource (API Gateway exige la acción de etiquetado además de POST cuando hay default_tags). Las rutas privadas y los parámetros SSM no llegaron a crearse (dependían de ellos).
- Corrección: añadidos apigateway:TagResource y apigateway:UntagResource a ApiGatewayManage; README de bootstrap con el comando create-policy-version. El siguiente push retoma desde el estado.
- README: nueva sección «UrbanAlert en AWS» (diagrama Mermaid validado con mermaid 11.4.1 + tabla local→AWS).
- Corrección de la corrección: el editor de IAM rechaza apigateway:TagResource/UntagResource («Action doesn't exist»); la referencia oficial (servicereference …/apigateway.json) no las lista, aunque el runtime las exige (AccessDenied del run 38107569124). Se sustituye la lista de verbos por `apigateway:*` sobre los mismos recursos (/apis*, /vpclinks*, /tags/*): mismo alcance efectivo y pasa la validación.
- El usuario publica la nueva versión de la política (apigateway:* acotado). Reintento de Provision con push a main.

## 2026-10-11 · 001-red-api-gateway · T020 hecha
- Run 38108135595 (3878f64) en verde en 3 min 53 s: plan 11 to add (stage, VPC Link, 2 rutas privadas, 7… + SSM), guarda OK, Apply complete 11 added; humo: ruta no registrada 404, HTTP plano no atendido (000), 9 parámetros SSM. Gateway: https://aotsp8k5ad.execute-api.us-east-2.amazonaws.com. Comprobado a mano: curl /api/v1/x → 404 {"message":"Not Found"}; http:// → 000. Entre los dos runs (3 min 13 s + 3 min 53 s) la plataforma quedó completa desde cero en < 20 min (MS-001, RNF-003).

## 2026-10-11 · 001-red-api-gateway · T021 hecha
- Re-run del run 38108135595 (intento 2, mismo commit 3878f64) en verde en 1 min 37 s: «No changes. Your infrastructure matches the configuration.», Apply 0/0/0, humo OK (MS-002, RNF-002, RNF-003 < 10 min).
