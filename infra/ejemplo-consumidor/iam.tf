# Lets the calling microservice (e.g. Reportes) sign requests (SigV4) to the internal routes with its task role.
# Belongs in the caller's stack, which owns its task role; shown here to keep the pattern in one place.
resource "aws_iam_role_policy" "invocar_rutas_internas" {
  name = "invocar-rutas-internas-geoespacial"
  role = var.rol_llamante

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "execute-api:Invoke"
      Resource = [
        for k, r in local.rutas : "${data.aws_ssm_parameter.api_execution_arn.value}/$default/${r.metodo}${split(" ", r.route_key)[1]}"
        if r.auth == "AWS_IAM"
      ]
    }]
  })
}
