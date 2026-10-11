# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: en_progreso | en_progreso | hecha | bloqueada -->

feature_activa: 001-red-api-gateway
fase: implement
tarea_actual: T007
estado_tarea: hecha

## Siguiente paso

T007: implementar infra/plataforma/egress.tf (aws_eip.nat, aws_nat_gateway.this con count 1 o numero_zonas, aws_route_table.privada, aws_route.privada_salida, aws_route_table_association.privada, aws_vpc_endpoint.s3); verificar test -filter=tests/salida.tftest.hcl.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Hallazgo: las políticas del rol de GitHub (geoespacial infra/bootstrap/github-*-policy.json) NO permiten crear VPC/subredes/NAT/EIP/rutas/endpoints, API Gateway, VPC Link ni SSM: hará falta una política nueva de arranque.
- Push: `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main` (el keychain no tiene credencial HTTPS).
- Terraform local: wrapper `<scratchpad>/tf` (podman, hashicorp/terraform:1.16.5, caché de plugins en ~/.cache/tf-plugins), ejecutar desde la raíz del repo.
- Indicaciones técnicas y contexto heredado en specs/001-red-api-gateway/notes.md.

## Bloqueos / preguntas abiertas

- Confianza OIDC del rol pendiente de actualizar por el usuario (subject inmutable); sin ella el primer aprovisionamiento falla en la autenticación.
