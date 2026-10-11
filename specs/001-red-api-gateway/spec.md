# Especificación: Red y API Gateway compartidos de UrbanAlert

- **ID**: 001-red-api-gateway
- **Estado**: aprobada <!-- borrador | aclarada | aprobada | implementada -->
- **Creada**: 2026-10-11
- **Entrada original**: "Plataforma compartida de UrbanAlert en AWS (us-east-2, cuenta 348364742283) con Terraform aplicado desde GitHub Actions (rol OIDC existente, estado en el bucket urban-alert-tfstate-348364742283 con clave propia). Alcance: (1) VPC con subredes privadas en al menos 2 zonas y salida a internet para las tareas de ECS (decidir NAT Gateway vs endpoints de VPC); (2) Amazon API Gateway compartido, único punto de entrada de todos los microservicios, con VPC Link hacia los balanceadores internos de ECS Express Mode; (3) salidas que consumen los microservicios (VPC, subredes privadas, IDs del API Gateway y del VPC Link); (4) workflow de aprovisionamiento en push a main y de desaprovisionamiento manual con confirmación. Primer consumidor: urban-alert-geoespacial (spec 002 de ese repo), que debe quedar accesible solo a través del gateway. Riesgo a investigar: el ALB de ECS Express enruta por cabecera Host."

## 1. Resumen

Crear la infraestructura común sobre la que se despliegan todos los microservicios de UrbanAlert en AWS: una red privada propia, repartida en al menos dos zonas de disponibilidad, desde la que los servicios pueden salir a lo que necesitan pero a la que no se llega desde internet, y un Amazon API Gateway compartido que es la única puerta de entrada pública a los microservicios. La plataforma publica los identificadores que cada microservicio necesita para desplegarse en esa red y registrar sus rutas en el gateway, y se aprovisiona y desaprovisiona con flujos de GitHub Actions, igual que los microservicios.

## 2. Problema y contexto

- El requisito de exposición cambió (ver journal de `urban-alert-geoespacial`, 2026-10-11): los microservicios deben exponerse **solo** a través de un Amazon API Gateway **compartido**, sin URL pública propia.
- Para que un servicio de ECS Express no sea público hay que desplegarlo en subredes privadas; entonces Express crea un balanceador **interno** y no asigna IP pública a las tareas, que necesitan otra vía para descargar su imagen, leer secretos y escribir logs. La VPC predeterminada de la cuenta solo tiene subredes públicas, así que no sirve.
- La red y el gateway no pertenecen a ningún microservicio: si cada repo creara los suyos, habría varias puertas de entrada y redes aisladas entre sí. Por eso viven en este repo (`Unal-Team-C/urban-alert-plataforma`) y los microservicios los consumen.
- Ya existen, creados a mano: el proveedor OIDC de GitHub y el rol de los flujos, y el bucket del estado de Terraform `urban-alert-tfstate-348364742283` (documentados en `urban-alert-geoespacial/infra/bootstrap/`).
- Riesgo conocido: el balanceador que crea ECS Express se comparte entre servicios y decide a qué servicio enviar cada petición según la cabecera `Host`; una petición que llega desde el gateway con otro `Host` puede no llegar a ningún servicio o llegar al equivocado.

## 3. Usuarios y actores

- **Equipo de plataforma (integrantes del equipo)**: aprovisionar y cambiar la red y el gateway con un commit a `main`, y eliminarlos a mano cuando no se usan.
- **Microservicios de UrbanAlert y sus flujos de despliegue** (primero `urban-alert-geoespacial`): obtener sin pasos manuales la red y el gateway donde desplegarse y registrar sus rutas.
- **Clientes de la API (frontend, servicio de Reportes, otros servicios)**: llamar a todos los microservicios a través de una única URL HTTPS estable.
- **Revisor / docente**: entender desde el repositorio qué infraestructura compartida existe, cuánto cuesta y cómo se integra un microservicio.

## 4. Historias de usuario

### HU-1: Aprovisionar la plataforma con un commit a `main` (Prioridad: P1)

Como integrante del equipo quiero que un commit a `main` cree o actualice la red y el gateway compartidos, para no depender de pasos manuales en la consola.

**Criterios de aceptación**
1. Dada una cuenta con solo los recursos de arranque, cuando se hace un commit a `main`, entonces al terminar el flujo existen la red privada en al menos dos zonas, la salida de las subredes privadas y el gateway con su URL HTTPS, y el resumen del flujo muestra los identificadores publicados (RF-008).
2. Dado un commit a `main` cuya validación de la infraestructura falla, cuando se ejecuta el flujo, entonces no se modifica nada en AWS y el flujo queda en rojo.
3. Dado un commit a `main` sin cambios de infraestructura, cuando se ejecuta el flujo, entonces informa de que no hay cambios.
4. Dados dos commits seguidos a `main`, cuando sus flujos coinciden en el tiempo, entonces se ejecutan uno detrás de otro, nunca a la vez.

### HU-2: Exponer un microservicio solo a través del gateway (Prioridad: P1)

Como microservicio quiero desplegarme en las subredes privadas y registrar mis rutas en el gateway compartido, para que los clientes me llamen por la URL del gateway y nadie pueda llamarme directamente desde internet.

**Criterios de aceptación**
1. Dado un microservicio desplegado en las subredes privadas con sus rutas registradas siguiendo la guía de integración (RF-011), cuando un cliente llama a una de esas rutas en la URL del gateway, entonces recibe la respuesta de ese microservicio.
2. Dados dos microservicios integrados que comparten el mismo balanceador interno, cuando un cliente llama a la ruta de cada uno, entonces cada petición la atiende el microservicio que corresponde a su ruta, nunca el otro.
3. Dado un microservicio integrado, cuando se intenta llegar a él desde internet por cualquier vía distinta del gateway (su URL generada por la plataforma de contenedores, la dirección del balanceador o la IP de una tarea), entonces la conexión no es posible.
4. Dada una ruta que no pertenece a ningún microservicio, cuando un cliente la llama, entonces el gateway responde «no encontrado» sin reenviarla a ningún servicio.
5. Dado el gateway, cuando se llama por HTTP sin cifrar, entonces no se atiende la petición (solo HTTPS).
6. Dada una ruta registrada como interna (RF-019), cuando la llama un cliente sin firma de AWS o con una identidad no autorizada, entonces el gateway la rechaza con «prohibido» sin reenviarla al servicio; cuando la llama un microservicio autorizado con su rol de tarea, entonces llega al servicio.

### HU-3: Salida de los servicios desde la red privada (Prioridad: P1)

Como microservicio desplegado en subredes privadas quiero poder descargar mi imagen, leer mis secretos, escribir mis logs, usar los servicios de AWS que necesito y llamar a otros microservicios a través del gateway, para arrancar y funcionar sin tener IP pública.

**Criterios de aceptación**
1. Dada una tarea en una subred privada sin IP pública, cuando arranca, entonces descarga su imagen del registro de la cuenta, lee sus secretos y sus logs aparecen en la consola de AWS.
2. Dada una tarea en una subred privada, cuando un equipo intenta abrirle una conexión entrante desde internet, entonces no es posible.
3. Dada una tarea en una subred privada, cuando llama a la ruta de otro microservicio en la URL del gateway, entonces recibe su respuesta.
4. Dada una tarea en una subred privada, cuando intenta llegar a un destino de internet que no es de AWS ni el gateway, entonces el resultado coincide con lo documentado en el README (no se garantiza esa salida).

### HU-4: Consumir la plataforma desde el repo de un microservicio (Prioridad: P1)

Como flujo de despliegue de un microservicio quiero leer de forma automática los identificadores de la red y del gateway, para desplegarme sin copiar valores a mano ni depender de cambios en este repo.

**Criterios de aceptación**
1. Dada la plataforma aprovisionada, cuando el flujo de un microservicio necesita la red, las subredes privadas, el gateway y el enlace privado del gateway, entonces los obtiene de las salidas publicadas sin intervención manual.
2. Dado que la plataforma se recrea (desaprovisionar y aprovisionar), cuando el microservicio vuelve a desplegarse, entonces toma los identificadores nuevos sin cambios en su repo.
3. Dado que la plataforma no está aprovisionada, cuando el flujo de un microservicio intenta leer las salidas, entonces falla con un mensaje que indica que falta la plataforma.

### HU-5: Desaprovisionar la plataforma a mano (Prioridad: P2)

Como integrante del equipo quiero lanzar a mano un flujo que elimine la red y el gateway, para no generar costes cuando no se usan y poder recrearlos con un commit a `main`.

**Criterios de aceptación**
1. Dado el repositorio en GitHub, cuando un integrante lanza el flujo de desaprovisionamiento y escribe la confirmación exigida, entonces se eliminan todos los recursos de la plataforma y el resultado queda en la ejecución del flujo.
2. Dado que se lanza sin la confirmación exacta, cuando se ejecuta, entonces no elimina nada y termina indicando que falta la confirmación.
3. Dado que algún microservicio sigue desplegado en la red o tiene rutas en el gateway, cuando se lanza el desaprovisionamiento confirmado, entonces no elimina nada y lista los recursos de otros stacks que lo impiden.
4. Dada la plataforma ya eliminada, cuando se lanza de nuevo, entonces termina sin error indicando que no hay nada que eliminar.
5. Dada la plataforma eliminada, cuando se lanza cualquier flujo de nuevo, entonces sigue pudiendo autenticarse en AWS (los recursos de arranque no se tocan).
6. El flujo nunca se ejecuta por un commit; solo bajo demanda.

### HU-6: Entender y reproducir la plataforma (Prioridad: P2)

Como revisor o nuevo integrante quiero encontrar en el repositorio qué crea la plataforma, cuánto cuesta y cómo se integra un microservicio, para reproducirla o añadir un servicio nuevo.

**Criterios de aceptación**
1. Dado el README, cuando se busca cómo integrar un microservicio, entonces hay una guía paso a paso que incluye cómo resolver el enrutamiento por cabecera `Host` del balanceador de Express (RF-011).
2. Dado el README, cuando se busca el coste, entonces aparece una estimación mensual de los recursos de la plataforma con la plataforma encendida y sin tráfico.

### Casos borde

- La confianza del rol OIDC aún no admite este repo (subject inmutable `repo:Unal-Team-C@335834608/...`) → el flujo falla en la autenticación sin crear nada; el siguiente commit, con la confianza corregida, aprovisiona desde cero.
- El rol de los flujos no tiene permisos sobre algún tipo de recurso de la plataforma → el flujo falla indicando la acción denegada; el siguiente intento retoma desde el estado sin duplicar recursos.
- El aprovisionamiento falla a mitad → el siguiente commit a `main` retoma desde el estado registrado sin duplicar recursos.
- Alguien cambia a mano un recurso de la plataforma → el siguiente aprovisionamiento muestra la diferencia y lo devuelve a lo definido en el repositorio.
- Un cambio de la plataforma obligaría a reemplazar la red o el gateway mientras hay microservicios desplegados (cambio de identificadores, nueva URL) → el aprovisionamiento no lo aplica sin que quede visible en el plan del flujo; ver RF-013.
- Un microservicio registra en el gateway una ruta que ya usa otro → el registro falla en el flujo de ese microservicio; la ruta existente no cambia.
- Un microservicio llama a una ruta interna de otro sin tener concedido el permiso → el gateway responde «prohibido» y el servicio destino no recibe la petición.
- Un microservicio integrado no tiene ninguna tarea sana → el gateway responde con un error de servicio no disponible para sus rutas; las rutas de los demás no se ven afectadas.
- Cae una zona de disponibilidad → los microservicios con tareas en la otra zona siguen recibiendo tráfico por el gateway (salvo la limitación de salida asumida en Supuestos).
- Se lanza el desaprovisionamiento mientras corre un aprovisionamiento → espera a que termine (RF-010).
- El flujo se lanza desde otra rama o desde un fork → no obtiene credenciales de AWS.

## 5. Requisitos funcionales

- **RF-001**: La plataforma DEBE crear una red propia (no la predeterminada) con subredes privadas en al menos dos zonas de disponibilidad de `us-east-2`, sin acceso entrante directo desde internet, con espacio de direcciones suficiente para los balanceadores y las tareas de todos los microservicios previstos.
- **RF-002**: La red DEBE incluir subredes públicas solo si la salida elegida o el gateway las necesitan; ningún microservicio se despliega en ellas.
- **RF-003**: Las tareas en las subredes privadas, sin IP pública, DEBEN poder: descargar imágenes del registro de la cuenta, leer secretos, escribir logs, obtener credenciales de AWS, usar los servicios de AWS que declaren los microservicios, y llamar a la URL del gateway (los microservicios se comunican entre sí solo a través de él). No necesitan llegar a destinos de internet ajenos a AWS: las imágenes ya contienen todo lo necesario. La alternativa de salida (NAT Gateway, endpoints de VPC o combinación) se decide en el plan con su coste y queda justificada allí.
- **RF-004**: La plataforma DEBE crear un único Amazon API Gateway, compartido por todos los microservicios, con una URL HTTPS estable mientras no se desaprovisione; es la única entrada pública a los microservicios.
- **RF-005**: La plataforma DEBE crear el enlace privado (VPC Link) que permite al gateway llegar a los balanceadores internos que ECS Express crea en las subredes privadas, y un grupo de seguridad para ese enlace, publicado para que los microservicios puedan referenciarlo en sus propias reglas. Los balanceadores de los microservicios son internos (no alcanzables desde internet); no se exige que acepten tráfico solo del enlace, porque su grupo de seguridad lo gestiona ECS Express (ver Clarificaciones).
- **RF-006**: Una petición a una ruta registrada por un microservicio DEBE llegar a ese microservicio aunque varios compartan el mismo balanceador interno, que distingue servicios por la cabecera `Host`. La forma de conseguirlo se investiga y decide en el plan y se valida con al menos un servicio real (`urban-alert-geoespacial`).
- **RF-007**: El gateway DEBE responder «no encontrado» a las rutas no registradas y aceptar solo HTTPS.
- **RF-008**: La plataforma DEBE publicar como salidas, legibles automáticamente por los flujos de los microservicios con su rol de AWS: identificador de la red, identificadores de las subredes privadas, identificador del gateway, su URL, su ARN de ejecución (para conceder permisos sobre rutas internas, RF-019), identificador del enlace privado y su grupo de seguridad, y la región.
- **RF-009**: El estado de la infraestructura DEBE guardarse en el bucket `urban-alert-tfstate-348364742283` con una clave propia de este repo, distinta de la de cualquier microservicio, cifrado y con bloqueo.
- **RF-010**: El flujo de aprovisionamiento DEBE ejecutarse en cada push a `main` y, en este orden: validar la definición de la infraestructura (formato, validez y pruebas); calcular el plan; aplicarlo; mostrar en el resumen las salidas publicadas. Cualquier paso fallido DEBE detener los siguientes. Los flujos de aprovisionamiento y desaprovisionamiento DEBEN impedir ejecuciones simultáneas sobre la plataforma.
- **RF-011**: El repositorio DEBE incluir una guía de integración para microservicios: qué salidas leer y cómo, cómo desplegar en las subredes privadas, cómo registrar las rutas en el gateway (incluida la cabecera `Host` que espera el balanceador de Express), por qué el balanceador queda aislado de internet (y qué tráfico interno puede llegarle), la convención de rutas (RF-018) con ejemplos de reescritura de ruta, restricción de métodos y cabecera fija, y cómo llama un microservicio a otro a través del gateway, incluidas las rutas internas con firma IAM (RF-019).
- **RF-012**: Debe existir un flujo de desaprovisionamiento que solo se ejecute bajo demanda y exija escribir una confirmación explícita (p. ej. el nombre de la plataforma). Antes de eliminar, DEBE comprobar que ningún otro stack usa la red ni tiene rutas en el gateway; si los hay, no elimina nada y los lista. Si no, elimina todos los recursos de la plataforma, salvo los de arranque.
- **RF-013**: El aprovisionamiento NO DEBE reemplazar ni eliminar la red, las subredes, el gateway ni el enlace privado de forma silenciosa: si el plan los reemplaza o elimina, el flujo DEBE fallar antes de aplicar, salvo que el cambio se haya habilitado de forma explícita en el repositorio.
- **RF-014**: Los flujos DEBEN autenticarse en AWS con credenciales temporales mediante el rol OIDC existente, sin claves de larga duración en GitHub, y solo desde `main`.
- **RF-015**: El gateway DEBE registrar un log de acceso por petición (fecha, ruta, método, código de respuesta, latencia, identificador de petición) en los logs de la cuenta.
- **RF-016**: Los recursos de arranque (proveedor OIDC, rol de los flujos, bucket del estado) DEBEN quedar fuera de lo que gestiona y elimina esta plataforma.
- **RF-017**: En esta feature el gateway NO autentica a los clientes: solo enruta. Una petición a una ruta registrada llega al microservicio sin que el gateway exija credenciales; la autenticación que necesite cada servicio la hace el propio servicio.
- **RF-019**: El gateway DEBE permitir que un microservicio registre rutas **internas**, solo para otros microservicios (p. ej. la asignación de coordenadas de Geoespacial que llama Reportes), protegidas con firma IAM: solo se reenvían si la petición va firmada con una identidad de AWS a la que se ha concedido invocar esa ruta (el rol de tarea del microservicio que llama). No es autenticación de clientes finales (RF-017) y no usa secretos compartidos. La guía (RF-011) DEBE explicar cómo registrar una ruta interna y cómo conceder a otro microservicio permiso para llamarla.
- **RF-018**: Las rutas públicas DEBEN seguir la convención de la infraestructura local (`UrbanAlert/infrastructure/README.md`, copia en `fuentes/`): prefijo `/api/v1/<servicio>/` con el nombre del servicio en español (`reportes`, `geoespacial`, `usuarios`, `auditoria`); cada ruta se reenvía a la ruta propia del servicio, que puede ser distinta (p. ej. `/api/v1/geoespacial/reports` → `/api/v1/geospatial/reports` del servicio); cada ruta publica solo los métodos indicados (p. ej. Geoespacial, solo `GET`); y una ruta puede añadir cabeceras fijas hacia el servicio (p. ej. `X-Urban-Gateway-Key` hacia Auditoria). Cualquier otra ruta bajo `/api/` responde «no encontrado». La plataforma no registra estas rutas (las registra cada microservicio), pero el gateway y la guía (RF-011) DEBEN permitir todo lo anterior.

## 6. Requisitos no funcionales

- **RNF-001 (seguridad)**: Ninguna tarea ni balanceador de microservicio tiene IP pública ni es alcanzable desde internet salvo a través del gateway; no hay secretos en el repositorio, las variables de GitHub ni los logs de los flujos; el estado remoto está cifrado y no es público.
- **RNF-002 (idempotencia)**: Dos aprovisionamientos seguidos sobre el mismo commit producen cero cambios en el segundo.
- **RNF-003 (duración)**: Un aprovisionamiento sin cambios termina en menos de 10 minutos; uno desde cero, en menos de 20.
- **RNF-004 (coste)**: Se eligen las opciones de menor coste compatibles con los requisitos para un proyecto académico; el coste mensual estimado de la plataforma encendida y sin tráfico queda documentado en el README con el detalle por recurso.
- **RNF-005 (protección del gateway)**: El gateway limita la tasa de peticiones con un valor por defecto documentado, de modo que un cliente no puede enviar a los microservicios más peticiones por segundo que ese límite.
- **RNF-006 (observabilidad)**: Los logs de acceso del gateway se conservan al menos 30 días.
- **RNF-007 (disponibilidad)**: La caída de una zona de disponibilidad no deja sin entrada a los microservicios que tengan tareas en la otra zona.

## 7. Entidades clave

No hay datos de dominio. Recursos relevantes para la spec:

- **Red compartida**: red privada, subredes privadas por zona y su vía de salida.
- **Gateway compartido**: URL pública única, rutas registradas por los microservicios, límite de tasa y logs de acceso.
- **Enlace privado del gateway**: conexión del gateway a los balanceadores internos, con su grupo de seguridad.
- **Salidas publicadas**: identificadores que consumen los microservicios (RF-008).
- **Recursos de arranque**: OIDC, rol de los flujos y bucket del estado, creados a mano y fuera de la gestión de la plataforma.

## 8. Fuera de alcance

- Cambiar `urban-alert-geoespacial` para consumir la plataforma: se hace actualizando su spec 002 en su repo. Aquí solo se valida la integración con él (RF-006, MS-003).
- Dominio propio y certificado propio para el gateway: se usa la URL HTTPS que asigna AWS.
- Autenticación en el gateway (p. ej. *authorizer* de Cognito, como anticipa el README de la infraestructura local): feature posterior. Mientras tanto la API queda abierta salvo lo que proteja cada servicio, igual que en local.
- Servir el frontend: el gateway solo atiende `/api/v1/*`; el frontend se publica en otra feature con su propia URL y llama al gateway (CORS, ver Supuestos).
- `/health` propio del gateway: la salud se comprueba con las rutas de salud de cada microservicio.
- Documentación de las APIs bajo `/docs/<servicio>` (en local, Nginx reescribe las URLs absolutas de Scalar/Swagger; el gateway no lo hace).
- WAF, caché del gateway, planes de uso y claves de API por cliente.
- Varios entornos (staging/producción): hay uno solo.
- Comunicación directa entre microservicios dentro de la red (descubrimiento de servicios, malla) más allá de que la red lo permita.
- Bases de datos, colas u otros recursos de los microservicios: cada uno los crea en su repo.
- Validación del pipeline en pull requests.
- Conectividad híbrida (VPN, Direct Connect) y acceso de administración a la red (bastiones).

## 9. Supuestos

- Región `us-east-2`, cuenta `348364742283`, un único entorno.
- Tecnologías fijadas por el usuario (restricciones, no decisiones de diseño): AWS, Terraform aplicado solo desde GitHub Actions, Amazon API Gateway con VPC Link, microservicios en ECS Express Mode (Fargate).
- El usuario actualiza la confianza del rol OIDC con el subject inmutable (`repo:Unal-Team-C@335834608/*:ref:refs/heads/main`, ver `urban-alert-geoespacial/infra/bootstrap/github-oidc-trust.json`); eso cubre también este repo.
- El rol de los flujos tiene o recibirá permisos para crear red, gateway y logs; si falta alguno, el plan lo lista para que el usuario lo añada a mano (el rol es de arranque).
- Los microservicios registran sus propias rutas e integraciones en el gateway desde sus repos; la plataforma solo crea el gateway, el enlace y sus valores por defecto.
- Las salidas se leen desde los flujos de los microservicios con el mismo rol de GitHub (misma cuenta).
- Para reducir coste se acepta que, si la salida necesita recursos por zona, haya uno solo compartido por las dos zonas; la caída de esa zona deja sin salida a las tareas de la otra hasta que se recupere (aceptado para un proyecto académico; el plan lo detalla).
- CORS: como el frontend tendrá otro origen, el gateway acepta peticiones de navegador desde cualquier origen sin credenciales, configurable en el repositorio, hasta que se conozca la URL del frontend.
- Límite de tasa por defecto y retención de logs: valores modestos (p. ej. decenas de peticiones por segundo; 30 días), ajustables en el repositorio.

## 10. Métricas de éxito

- **MS-001**: Desde una cuenta con solo los recursos de arranque, un commit a `main` deja la plataforma aprovisionada en menos de 20 minutos sin ninguna acción manual.
- **MS-002**: Una segunda ejecución del aprovisionamiento sin cambios reporta 0 recursos modificados.
- **MS-003**: Con `urban-alert-geoespacial` integrado, sus pruebas de contrato (spec 001: asignar, consultar cercanos, resolver por id, salud) pasan contra la URL del gateway, y fallan al conectar contra su URL de Express, su balanceador y sus tareas desde internet.
- **MS-004**: Un microservicio nuevo se integra siguiendo solo la guía (RF-011) y las salidas publicadas, sin cambios en este repo.
- **MS-005**: El coste mensual estimado de la plataforma encendida y sin tráfico está documentado y desglosado por recurso.

## 11. Clarificaciones

### Sesión 2026-10-11
- P: (Q1) ¿Algún microservicio necesita salir a internet fuera de AWS? → R: **No**: los microservicios solo se hablan entre sí a través del API Gateway y las imágenes ya contienen todo lo necesario. Consecuencia: las tareas sí necesitan llegar a la URL pública del gateway y a los servicios de AWS que usen (RF-003, HU-3).
- P: (Q2) ¿El gateway autentica a los clientes? → R: **De momento solo enruta** (RF-017; autenticación fuera de alcance).
- P: (Q3) ¿Convención de rutas? → R: **La de `UrbanAlert/infrastructure/README.md`** (copiado en `fuentes/`): `/api/v1/<servicio>/...` con reescritura a la ruta propia del servicio, métodos por ruta y cabecera fija hacia Auditoria; resto de `/api/` → 404 (RF-018). `/docs/<servicio>` queda fuera de alcance.
- P: Las rutas internas entre servicios (p. ej. POST de asignación de Geoespacial, que en local Nginx no publica), ¿cómo se protegen si el gateway es público? → R: **Firma IAM** por ruta con el rol de tarea del servicio que llama (RF-019, HU-2 criterio 6).
- P: ¿El gateway sirve también el frontend en `/` y un `/health` propio, como Nginx en local? → R: **Solo APIs** (`/api/v1/*`). El frontend irá en otra feature con su URL y CORS; sin `/health` propio (Fuera de alcance).
- P: ¿Alternativas al API Gateway con IP pública y patas privadas en la VPC, o abaratar la salida con una instancia NAT? → R: Se mantiene el API Gateway administrado y la salida será **NAT Gateway gestionado** (se descartan instancia NAT, gateway propio con Nginx y API REST privada adicional). Decisión técnica para el plan; la spec no cambia (RF-003 sigue sin fijar el cómo).
- P: (plan D-013) El SG del ALB de Express lo gestiona Express y no puede restringirse al VPC Link, ¿se ajusta RF-005? → R: **Sí**: se elimina «único origen permitido en sus balanceadores» de RF-005 y RF-011. El aislamiento frente a internet (HU-2 criterio 3, RNF-001) lo da el ALB interno en subredes privadas; dentro de la VPC el ALB es alcanzable por otras tareas (aceptado).

---

### Checklist de calidad (autorrevisión antes de entregar)

- [x] Sin detalles de implementación (lenguajes, frameworks, APIs, estructura de código) — AWS, Terraform, GitHub Actions, API Gateway, VPC Link y ECS Express son restricciones fijadas por el usuario; NAT vs endpoints y la solución al enrutamiento por `Host` se dejan al plan
- [x] Cada requisito es testeable y no ambiguo
- [x] Criterios de aceptación con resultado observable
- [x] Casos borde identificados
- [x] Alcance acotado (fuera de alcance explícito)
- [x] Como máximo 3 `[NEEDS CLARIFICATION]` pendientes (0 tras la sesión del 2026-10-11)
- [x] Coherente con `.sdd/constitution.md` (plantilla sin principios definidos)
