# Investigación: 001-red-api-gateway

Fecha: 2026-10-11. Fuentes al final de cada apartado.

## R-1. Cómo enruta el ALB de ECS Express y cómo llegar a él desde API Gateway

**Hechos (documentación de AWS):**
- Con subredes privadas (sin ruta a un IGW en su tabla), Express crea un ALB **interno**, sin IP pública en las tareas; la salida a internet es responsabilidad nuestra (NAT).
- El primer servicio Express de una VPC fija las subredes/zonas del ALB; los siguientes deben usar subredes de esas mismas zonas → los consumidores deben pasar **todas** las subredes privadas publicadas.
- Hasta 25 servicios Express de la misma VPC comparten un ALB; Express crea más ALB si hacen falta y elimina los que quedan sin uso.
- Listener HTTPS:443 con certificado ACM gestionado por Express; reglas por `host-header` con el dominio generado de cada servicio (`ingressPaths[].endpoint`). Grupos objetivo HTTP al puerto del contenedor.
- Express crea y gestiona el SG del ALB (entrada HTTPS) y el del servicio; un SG que pasemos en `network_configuration` es una vía de entrada **adicional a las tareas**, no al ALB. **No podemos restringir el SG del ALB al VPC Link**: lo gestiona Express.

**Hechos (práctica verificada por terceros, classmethod 2026):** API Gateway HTTP API + VPC Link v2 → listener HTTPS del ALB interno de Express funciona sin NLB ni certificado propio con:
- integración `HTTP_PROXY`, `connection_type = VPC_LINK`, `integration_uri` = **ARN del listener 443**;
- `tls_config.server_name_to_verify` = endpoint del servicio;
- `request_parameters` con `overwrite:header.host` = endpoint del servicio (sin él → 404 del ALB);
- `payload_format_version = "1.0"`.

**Parameter mapping de HTTP API (docs):** `overwrite:path`, `append|overwrite|remove:header.*`; `Host` **no** está en la lista de cabeceras reservadas (sí lo están `X-Forwarded-*`, `Forwarded`, `Authorization`, `Origin`…). Consecuencia: el servicio ve como `Host` su dominio `.on.aws`, no el del gateway.

**Cómo obtiene un consumidor el ARN del listener:** `aws_ecs_express_gateway_service` (Terraform) solo exporta `ingress_paths[].endpoint`, y `DescribeExpressGatewayService` no devuelve ARNs del ALB (CloudFormation sí, vía `ECSManagedResourceArns.IngressPath.ListenerArn`). Cadena determinista: `ecs describe-services` → `loadBalancers[0].targetGroupArn` → `elbv2 describe-target-groups` → `LoadBalancerArns[0]` → `elbv2 describe-listeners` → puerto 443. Se verifica con el primer despliegue real de geoespacial (riesgo en plan §10).

Fuentes: [Resources created by ECS Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html) · [classmethod: ECS Express + API Gateway VPC Link v2](https://dev.classmethod.jp/en/articles/ecs-express-mode-api-gateway-vpc-link-v2/) · [HTTP API parameter mapping](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-parameter-mapping.html) · [DescribeExpressGatewayService](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DescribeExpressGatewayService.html) · [AWS::ECS::ExpressGatewayService](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ecs-expressgatewayservice.html) · [Terraform aws_ecs_express_gateway_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_express_gateway_service)

## R-2. HTTP API frente a REST API

| | HTTP API | REST API |
|---|---|---|
| Precio | ~1 USD / millón | ~3,5 USD / millón |
| VPC Link a ALB | sí (VPC Link v2, por ARN de listener) | sí (VPC Link v2 desde 2025; v1 solo NLB) |
| Autorización IAM por ruta | sí (`AWS_IAM`) | sí |
| Reescritura de ruta/cabeceras | parameter mapping | mapping templates |
| CORS | integrado | manual |
| Límite de tasa | por stage/ruta | por stage/método + planes de uso |
| WAF, caché, claves de API | no | sí (fuera de alcance) |

Elegida **HTTP API** (D-004). Ruta no registrada sin ruta `$default` → 404 nativo. Ruta duplicada → `ConflictException` nativa (caso borde de la spec).

Fuentes: [Private integrations for REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/private-integration.html) · [Choose between REST APIs and HTTP APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html)

## R-3. Salida de las subredes privadas

- Los servicios se llaman por la URL **pública** del gateway (Q1): requiere salida a internet. El endpoint de interfaz `execute-api` solo da acceso a APIs REST **privadas**, y con DNS privado activado rompe la resolución de APIs públicas desde la VPC.
- Decisión del usuario: **NAT Gateway gestionado** (descartadas instancia NAT, gateway Nginx propio y API REST privada adicional).
- Endpoint de gateway de S3: gratis; las capas de ECR se descargan de S3 → no pasan por el NAT (ahorra 0,045 USD/GB).

Fuentes: [Introducing API Gateway private endpoints](https://aws.amazon.com/blogs/compute/introducing-amazon-api-gateway-private-endpoints) · [DoiT: private and public APIs from a VPC](https://www.doit.com/es/blog/accessing-private-and-public-apis-from-within-a-vpc-via-api-gateway)

## R-4. Permisos del rol de GitHub

Las políticas actuales (`urban-alert-geoespacial/infra/bootstrap/github-deploy-policy.json` y `github-terraform-policy.json`) permiten SG, `ec2:Describe*` y etiquetas, pero **no**: VPC, subredes, IGW, EIP, NAT, tablas de rutas, endpoints de VPC, API Gateway (`apigateway:*` sobre `/apis/*`, `/vpclinks/*`, `/tags/*`), rol vinculado de API Gateway, entregas de logs de API Gateway, grupos de logs fuera de `/ecs/urban-alert-*`, SSM Parameter Store, ni `elasticloadbalancing:Describe*`. Hace falta una política nueva de arranque (D-011).

## R-5. Costes de referencia (us-east-2, plataforma encendida sin tráfico)

| Recurso | Precio | Mes (730 h) |
|---|---|---|
| NAT Gateway (1) | 0,045 USD/h + 0,045 USD/GB | ~32,9 USD |
| IPv4 pública (EIP del NAT) | 0,005 USD/h | ~3,7 USD |
| HTTP API | 1 USD / millón de peticiones | ~0 |
| VPC Link v2 | sin cargo | 0 |
| Endpoint de gateway S3 | sin cargo | 0 |
| Parámetros SSM estándar | sin cargo | 0 |
| CloudWatch Logs | 0,50 USD/GB ingesta + 0,03 USD/GB-mes | ~0 |
| **Total** | | **~36,6 USD** |

No incluye el ALB interno que crea Express (~16–20 USD/mes, compartido por hasta 25 servicios): lo paga el primer consumidor.
