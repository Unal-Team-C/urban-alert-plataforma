# CLAUDE.md

Plataforma compartida de UrbanAlert en AWS (cuenta 348364742283, us-east-2): la red (VPC con subredes privadas y
salida a internet) y el Amazon API Gateway por el que se exponen todos los microservicios. Los microservicios
(p. ej. `Unal-Team-C/urban-alert-geoespacial`) viven en sus propios repos y consumen las salidas de esta plataforma.

- Terraform se aplica solo desde GitHub Actions (rol OIDC compartido, subject inmutable `repo:Unal-Team-C@335834608/...`).
- Estado remoto: bucket `urban-alert-tfstate-348364742283` (clave propia de este repo).
- Recursos de arranque (OIDC, rol, bucket): documentados en `urban-alert-geoespacial/infra/bootstrap/`.

## Desarrollo guiado por especificaciones (SDD)

Este proyecto usa un arnés SDD con persistencia en disco para sobrevivir a interrupciones de sesión.
El protocolo es obligatorio en todas las sesiones:

@.sdd/PROTOCOL.md
