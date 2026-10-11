# UrbanAlert — Plataforma compartida en AWS

Infraestructura común a todos los microservicios de UrbanAlert, gestionada con Terraform desde GitHub Actions:

- **Red**: VPC con subredes privadas para los servicios y su salida a internet.
- **Amazon API Gateway**: punto de entrada único; cada microservicio registra sus rutas y queda accesible solo a través de él.

Cuenta `348364742283`, región `us-east-2`. Los recursos de arranque (proveedor OIDC de GitHub, rol de los workflows y bucket del estado de Terraform) se crearon a mano y están documentados en [urban-alert-geoespacial/infra/bootstrap](https://github.com/Unal-Team-C/urban-alert-geoespacial/tree/main/infra/bootstrap).

## Desarrollo con SDD

Se desarrolla con **desarrollo guiado por especificaciones (SDD)** usando Claude Code y un arnés con persistencia en disco. Las features van en `specs/NNN-nombre/`.

- Guía de uso: [.sdd/GUIA.md](.sdd/GUIA.md) · Referencia: [.sdd/README.md](.sdd/README.md) · Protocolo: [.sdd/PROTOCOL.md](.sdd/PROTOCOL.md)
