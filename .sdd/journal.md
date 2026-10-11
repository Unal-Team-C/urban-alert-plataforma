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
