# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: en_progreso | en_progreso | hecha | bloqueada -->

feature_activa: 001-red-api-gateway
fase: implement
tarea_actual: T006
estado_tarea: hecha

## Siguiente paso

T006: implementar infra/plataforma/network.tf (data aws_availability_zones.available, aws_vpc.this, aws_subnet.privada/publica, aws_internet_gateway.this, aws_route_table.publica + aws_route.publica_internet + asociaciones, aws_default_security_group.this). Ojo: red.tftest.hcl también usa aws_route.privada_salida y aws_route_table_association.privada (de egress.tf, T007): esos runs pasarán al terminar T007.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Hallazgo: las políticas del rol de GitHub (geoespacial infra/bootstrap/github-*-policy.json) NO permiten crear VPC/subredes/NAT/EIP/rutas/endpoints, API Gateway, VPC Link ni SSM: hará falta una política nueva de arranque.
- Push: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main` (el keychain no tiene credencial HTTPS).
- Terraform local: wrapper `<scratchpad>/tf` (podman, hashicorp/terraform:1.16.5, caché de plugins en ~/.cache/tf-plugins), ejecutar desde la raíz del repo.
- Indicaciones técnicas y contexto heredado en specs/001-red-api-gateway/notes.md.

## Bloqueos / preguntas abiertas

- Confianza OIDC del rol pendiente de actualizar por el usuario (subject inmutable); sin ella el primer aprovisionamiento falla en la autenticación.
