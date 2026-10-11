# Recursos de arranque de la plataforma

Terraform no gestiona estos recursos: los necesita para poder ejecutarse, y el workflow de desaprovisionamiento no debe borrarlos (spec 001, RF-016; constitución P2).

El proveedor OIDC de GitHub, el rol que asumen los workflows y el bucket del estado ya existen y se comparten con los microservicios. Cómo se crearon, y la copia versionada de su configuración, está en [urban-alert-geoespacial/infra/bootstrap](https://github.com/Unal-Team-C/urban-alert-geoespacial/tree/main/infra/bootstrap). Aquí solo se documenta lo que la plataforma necesita **además**.

Cuenta `348364742283`, región `us-east-2`. Los JSON de esta carpeta son la copia versionada de lo configurado en AWS: si se cambia una política en la consola, hay que actualizar aquí el JSON, y al revés.

## Pasos manuales (una sola vez, antes del primer Provision)

### 1. Política de la plataforma en el rol de GitHub

Crear la política gestionada `github-actions-urban-alert-platform` con [github-platform-policy.json](github-platform-policy.json) y adjuntarla al rol de los workflows (el mismo que usan los microservicios).

```bash
aws iam create-policy --policy-name github-actions-urban-alert-platform \
  --policy-document file://infra/bootstrap/github-platform-policy.json
aws iam attach-role-policy --role-name <rol-de-github> \
  --policy-arn arn:aws:iam::348364742283:policy/github-actions-urban-alert-platform
```

Para actualizarla tras un cambio del JSON (se conservan hasta 5 versiones; borra la más antigua si hace falta):

```bash
aws iam create-policy-version --set-as-default \
  --policy-arn arn:aws:iam::348364742283:policy/github-actions-urban-alert-platform \
  --policy-document file://infra/bootstrap/github-platform-policy.json
```

Qué permite y por qué:

| Bloque | Para qué |
|---|---|
| `NetworkManage` | VPC, subredes, IGW, IP elástica, NAT Gateway, tablas de rutas, endpoint de S3, grupos de seguridad y ENI del VPC Link. La mayoría de las acciones de creación de EC2 no admiten restringir el recurso. |
| `ApiGatewayManage` | HTTP API, stage, VPC Link y etiquetas, con `apigateway:*` limitado a `/apis*`, `/vpclinks*` y `/tags/*`. Al crear stages y VPC Links con etiquetas, API Gateway exige `apigateway:TagResource`, pero esa acción no figura en la referencia de IAM y el editor de políticas la rechaza. El comodín la cubre sin dar más alcance que los verbos `GET`/`POST`/`PUT`/`PATCH`/`DELETE` sobre esos mismos recursos. También lo usan los microservicios para registrar sus rutas e integraciones. |
| `ApiGatewayServiceLinkedRole` | Rol vinculado `ops.apigateway.amazonaws.com`, que crea API Gateway la primera vez que se crea un VPC Link. |
| `ApiGatewayLogGroups`, `ApiGatewayAccessLogDelivery` | Grupo de logs `/aws/apigateway/urban-alert-*` y entrega de los logs de acceso. |
| `PlatformParameters`, `ParametersDescribe` | Parámetros SSM `/urban-alert/*`: la plataforma los escribe y los microservicios los leen. |
| `LoadBalancersDescribe` | Comprobar dependientes antes de desaprovisionar y localizar el listener del ALB de Express (`scripts/buscar-listener-express.sh`). |

### 2. Confianza OIDC del rol con el subject inmutable

Los repos de `Unal-Team-C` usan el subject inmutable de GitHub (`repo:Unal-Team-C@335834608/<repo>@<id>:ref:refs/heads/main`). La relación de confianza del rol debe ser la de [github-oidc-trust.json](https://github.com/Unal-Team-C/urban-alert-geoespacial/blob/main/infra/bootstrap/github-oidc-trust.json), que admite `repo:Unal-Team-C@335834608/*:ref:refs/heads/main`. Con eso queda cubierto también este repo.

```bash
aws iam update-assume-role-policy --role-name <rol-de-github> --policy-document file://github-oidc-trust.json
```

### 3. Secreto y variable de GitHub en este repo

Settings → Secrets and variables → Actions de `Unal-Team-C/urban-alert-plataforma`:

| Tipo | Nombre | Valor |
|---|---|---|
| Secreto | `AWS_ROLE_ARN` | ARN del rol de los workflows (`arn:aws:iam::348364742283:role/<rol-de-github>`) |
| Variable | `AWS_REGION` | `us-east-2` |

### 4. Comprobar

Lanzar Provision con un push a `main`. Si falla en `configure-aws-credentials`, falta el paso 2 (o el 3). Si falla con `AccessDenied` durante el `apply`, falta el paso 1: el mensaje indica la acción, y el siguiente push retoma desde el estado.

## Estado de Terraform

Clave `plataforma/terraform.tfstate` en el bucket `urban-alert-tfstate-348364742283`, con cifrado y bloqueo por `.tflock` (`use_lockfile`).
