# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: en_progreso | en_progreso | hecha | bloqueada -->

feature_activa: 001-red-api-gateway
fase: implement
tarea_actual: T020
estado_tarea: bloqueada

## Siguiente paso

T020 bloqueada: esperar a que el usuario complete los 4 pasos de infra/bootstrap/README.md (política, confianza OIDC, secreto/variable, autorizar push). Al desbloquear: push a main → seguir el run Provision (gh run watch) → T021 re-run → T022 Deprovision sin confirmación → T023 cuando geoespacial esté integrado.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Hallazgo: las políticas del rol de GitHub (geoespacial infra/bootstrap/github-*-policy.json) NO permiten crear VPC/subredes/NAT/EIP/rutas/endpoints, API Gateway, VPC Link ni SSM: hará falta una política nueva de arranque.
- Push: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main` (el keychain no tiene credencial HTTPS).
- Terraform local: wrapper `<scratchpad>/tf` (podman, hashicorp/terraform:1.16.5, caché de plugins en ~/.cache/tf-plugins), ejecutar desde la raíz del repo.
- Indicaciones técnicas y contexto heredado en specs/001-red-api-gateway/notes.md.

## Bloqueos / preguntas abiertas

- T020 (primer Provision real): el usuario debe (1) crear y adjuntar github-actions-urban-alert-platform (infra/bootstrap/github-platform-policy.json), (2) corregir la confianza OIDC con el subject inmutable, (3) crear secreto AWS_ROLE_ARN y variable AWS_REGION en urban-alert-plataforma, (4) autorizar el push a main. T021–T023 y T026 dependen de T020.
- Confianza OIDC del rol pendiente de actualizar por el usuario (subject inmutable); sin ella el primer aprovisionamiento falla en la autenticación.
