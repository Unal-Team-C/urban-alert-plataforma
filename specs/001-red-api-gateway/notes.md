# Notas: 001-red-api-gateway

## Indicaciones técnicas de la entrada (para /sdd-plan)

- Terraform desde GitHub Actions con el rol OIDC existente (subject inmutable `repo:Unal-Team-C@335834608/...`). Estado en `urban-alert-tfstate-348364742283`, clave propia (p. ej. `plataforma/terraform.tfstate`), `use_lockfile` + `encrypt`, como en geoespacial (`infra/platform/backend.tf`).
- Decidir NAT Gateway vs endpoints de VPC (RF-003). Endpoints mínimos para Fargate sin internet: ECR api + ECR dkr (interface), S3 (gateway, capas de ECR), CloudWatch Logs, Secrets Manager, STS si hace falta; cada endpoint de interfaz cobra por zona y hora. Comparar con un solo NAT Gateway (+ IP elástica, + datos procesados). Depende de Q1.
- Gateway: Amazon API Gateway (probablemente HTTP API, que admite VPC Link a ALB por listener ARN); confirmar en el plan frente a REST API (VPC Link de REST solo a NLB).
- **Riesgo Host**: ECS Express comparte un ALB entre servicios con la misma configuración de red y enruta por regla de `host-header` con el dominio generado del servicio (`*.ecs.us-east-2.on.aws`), en el listener HTTPS con su certificado. Investigar: si la integración HTTP API → VPC Link → listener puede fijar/reescribir `Host` (parameter mapping; posibles restricciones sobre cabeceras reservadas), `tlsConfig.serverNameToVerify`, o alternativas (regla de listener adicional por ruta/cabecera propia, NLB delante, etc.). Validar con geoespacial (MS-003).
- Salidas para los microservicios: vpc_id, private_subnet_ids, api_id, api_endpoint, vpc_link_id, vpc_link_security_group_id, region. Mecanismo (terraform_remote_state del bucket vs parámetros SSM) a decidir en el plan.
- Desaprovisionamiento: comprobar dependientes antes de destruir (ENIs ajenas en la VPC, rutas/integraciones del gateway no gestionadas por este estado).

## Contexto heredado (STATE.md al crear la feature)

- Repo creado el 2026-10-11 a raíz del cambio de requisitos de urban-alert-geoespacial (exposición solo por Amazon API Gateway compartido; ver su .sdd/journal.md).
- ECS Express con subredes privadas crea un ALB interno y no asigna IP pública: las tareas necesitan NAT o endpoints de VPC. Express crea sus propios SG de ALB y de servicio (los que se le pasan son adicionales).
- Geoespacial (spec 002) está bloqueada en T024 hasta que el usuario corrija la confianza OIDC; su supuesto «VPC predeterminada» (D-006) cambiará para consumir esta plataforma.

## Hallazgos de la clarificación (2026-10-11)

- Q1 → los servicios se llaman entre sí por el gateway. La URL del gateway es pública: desde subredes privadas sin IP pública solo se llega a ella con salida a internet (NAT). El endpoint de VPC `execute-api` sirve para APIs REST **privadas**, no para llamar a una API pública (y con DNS privado activado incluso rompe la resolución de las públicas): con endpoints solos no basta. Hipótesis para el plan: un NAT Gateway (uno, por coste) + endpoint de gateway de S3 (gratis, ahorra datos de ECR); endpoints de interfaz solo si compensan. Confirmar en el plan.
- Servicios de AWS que usarán los microservicios según la infra local y la spec 002: Secrets Manager, CloudWatch Logs, ECR; probablemente SQS (sustituto de RabbitMQ) y Cognito (Auditoria valida JWT y descarga el JWKS de cognito-idp). Con NAT todos quedan cubiertos.
- Q3 → convención de `UrbanAlert/infrastructure/README.md`: `/api/v1/<servicio>/...` reescrita a la ruta del servicio, métodos por ruta, cabecera fija `X-Urban-Gateway-Key` hacia Auditoria (secreto: ¿cómo lo inyecta la integración sin dejarlo en claro en el estado? → plan del consumidor). HTTP API: parameter mapping `overwrite:path` y `append:header.*` lo permiten; verificar.
- En local el gateway sirve también `/health` propio y el frontend en `/`; geoespacial asigna coordenadas por una ruta interna (no pública) que Reportes llama por HTTP.
- Rutas internas → firma IAM por ruta (HTTP API: autorización AWS_IAM; el rol de tarea del llamante necesita execute-api:Invoke sobre arn:aws:execute-api:<region>:<cuenta>:<api_id>/*/<MÉTODO>/<ruta>). Salida útil para consumidores: execution ARN del API.

## Decisión del usuario: salida (2026-10-11)

- **NAT Gateway gestionado** (no instancia NAT). Descartados: instancia NAT tipo fck-nat (punto único de fallo, escalado vertical con corte), gateway propio Nginx con IP elástica (exige dominio, pierde firma IAM), HTTP API pública + REST API privada vía execute-api (rutas duplicadas, sigue necesitando salida para ECR/logs/secretos).
- Por defecto, un solo NAT Gateway compartido por las 2 zonas (supuesto de coste de la spec; ~33 USD/mes + 0,045 USD/GB). Uno por zona duplicaría el coste: dejarlo como variable en el plan. Añadir endpoint de gateway de S3 (gratis) para no pasar las capas de ECR por el NAT.
