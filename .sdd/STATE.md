# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: ninguna
fase: constitution
tarea_actual: -
estado_tarea: -

## Siguiente paso

Crear la primera feature con `/sdd-new`: red compartida (VPC con subredes privadas + salida a internet) y Amazon API Gateway compartido con VPC Link, consumidos por los microservicios (primero urban-alert-geoespacial, spec 002 de ese repo).

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Repo creado el 2026-10-11 a petición del usuario, a raíz del cambio de requisitos de urban-alert-geoespacial (exposición solo por Amazon API Gateway compartido; ver su .sdd/journal.md).
- ECS Express con subredes privadas crea un ALB interno y no asigna IP pública: las tareas necesitan NAT o endpoints de VPC.

## Bloqueos / preguntas abiertas

- ninguno
