# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: en_progreso | en_progreso | hecha | bloqueada -->

feature_activa: 001-red-api-gateway
fase: implement
tarea_actual: T023
estado_tarea: bloqueada

## Siguiente paso

T023 bloqueada: depende de replanificar la spec 002 de urban-alert-geoespacial para consumir la plataforma (subredes privadas desde SSM, rutas en el gateway con Host = endpoint, POST interno con AWS_IAM, sin URL pública propia) y desplegarla. T026 (ciclo completo) solo con autorización expresa.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Plataforma aprovisionada (2026-10-11, runs 38108135595 intentos 1–2). NAT cobrando (~37 USD/mes).
- Hallazgo: las políticas del rol de GitHub (geoespacial infra/bootstrap/github-*-policy.json) NO permiten crear VPC/subredes/NAT/EIP/rutas/endpoints, API Gateway, VPC Link ni SSM: hará falta una política nueva de arranque.
- Push: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main` (el keychain no tiene credencial HTTPS).
- Terraform local: wrapper `<scratchpad>/tf` (podman, hashicorp/terraform:1.16.5, caché de plugins en ~/.cache/tf-plugins), ejecutar desde la raíz del repo.
- Indicaciones técnicas y contexto heredado en specs/001-red-api-gateway/notes.md.

## Bloqueos / preguntas abiertas

- T023: espera a geoespacial (replan de su spec 002 + despliegue sobre la plataforma). Gateway: https://aotsp8k5ad.execute-api.us-east-2.amazonaws.com. T026 opcional, requiere autorización.
- Confianza OIDC del rol pendiente de actualizar por el usuario (subject inmutable); sin ella el primer aprovisionamiento falla en la autenticación.
