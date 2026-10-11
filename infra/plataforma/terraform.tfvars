# Values are documented in variables.tf; change them here, in a commit, never by hand in AWS.
numero_zonas                  = 2
nat_por_zona                  = false
cors_origenes                 = ["*"]
limite_tasa                   = 50
limite_rafaga                 = 100
retencion_logs_dias           = 30
permitir_reemplazo_compartido = false
