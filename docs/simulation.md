# Modo simulación con Floci

Todo el proyecto corre sin cuenta de AWS. Tres instancias del emulador
[Floci](https://github.com/floci-io/floci) (licencia MIT, sin cuenta ni token) hacen de las
tres cuentas. Terraform, los scripts y los workflows son los mismos que en AWS real: solo
cambian los endpoints y las credenciales, que salen del archivo `infra/targets/local.json`.

## Cómo está armado

| Pieza real | En la simulación |
| --- | --- |
| Cuentas dev, staging y prod | `floci-dev`, `floci-staging` y `floci-prod` en `simulation/docker-compose.yml`, con IDs de cuenta 111111111111, 222222222222 y 333333333333 |
| API de AWS | `http://localhost:4566`, `4567` y `4568` |
| URL pública de la app (ALB) | `http://localhost:8081`, `8082` y `8083` |
| Tareas de ECS | Contenedores reales de Docker, uno por tarea, en la red `sim-<env>` |
| Registro ECR | Un `registry:2` por emulador, con URIs `localhost:<puerto>/<cuenta>/<región>/tasks-api` |
| CI | Runners de GitHub (repositorio privado) |
| CD y Terraform | Runner autohospedado (`simulation/runner`), con red del host para ver `localhost` |
| OIDC | Token real de GitHub; Floci acepta la asunción del rol sin validar firma ni condiciones |
| Estado de Terraform | Bucket S3 y tabla DynamoDB dentro de cada emulador (persistentes en un volumen) |

## Prueba de factibilidad (spike)

Primera tarea del proyecto: confirmar que el emulador soporta las piezas críticas. Se probó
con Floci 2.1.0 (imagen `floci/floci:2.1.0`), primero a mano con la AWS CLI y después con el
Terraform y los scripts definitivos.

| Pieza | Resultado |
| --- | --- |
| ECR: crear repositorio, `docker login`, push y pull | Funciona (con URIs estilo ruta) |
| ECR: tags inmutables y digest estable al copiar entre cuentas | Funciona: el digest es idéntico en los tres ambientes |
| ECS: clúster, definición de tarea Fargate con `awsvpc`, servicio | Funciona: cada tarea es un contenedor real |
| ECS: rolling update y `wait services-stable` | Funciona: el reemplazo arranca antes de apagar la tarea vieja |
| ECS: circuit breaker con rollback | **No funciona en 2.1.0**: la configuración no se guarda y una tarea rota se reinicia sin fin. Mitigado con verificación y rollback en el pipeline. |
| ALB: listener, target group `ip`, health checks y enrutamiento | Funciona |
| Secrets Manager inyectado en la tarea, rol de tarea, DynamoDB desde la app | Funciona: Floci inyecta endpoint y credenciales del rol, igual que AWS |
| CloudWatch Logs (driver `awslogs`) y alarmas (`SetAlarmState`) | Funciona |
| Métricas a partir de logs (`PutMetricFilter`) | **No disponible en 2.1.0** (sí en las versiones nightly). Desactivado con `log_metric_filters: false`. |
| STS `AssumeRoleWithWebIdentity` con token de GitHub | Funciona; no valida firma ni condiciones de confianza |
| Backend S3 con bloqueo DynamoDB | Funciona |
| `terraform apply` y `destroy` completos de un ambiente (54 recursos) | Funciona, en poco más de un minuto |

Ninguna pieza tuvo que reemplazarse por Docker Compose: lo que falta se compensa en el
pipeline o se documenta abajo.

## Ajustes necesarios para el emulador

Cada uno está comentado en el código donde se aplica.

1. **Un ID de cuenta por defecto por instancia** (`FLOCI_DEFAULT_ACCOUNT_ID`). El plano de
   datos del ALB busca los target groups en la cuenta por defecto; si no coincide con la de
   los recursos, responde 502.
2. **Puerto propio por instancia** (`FLOCI_PORT`). Floci arma las URIs de ECR con el puerto
   en el que escucha, que debe coincidir con el publicado en el host.
3. **URIs de ECR estilo ruta** (`FLOCI_SERVICES_ECR_URI_STYLE=path`). El estilo
   `<cuenta>.dkr.ecr.<región>.localhost` necesita que el sistema resuelva `*.localhost`.
4. **Espacio de nombres de Docker por instancia** (`FLOCI_DOCKER_RESOURCE_NAMESPACE`), para
   que los tres registros y las tareas no choquen en el mismo Docker.
5. **Endpoint de S3 Control con `localhost.floci.io`**. El proveedor de AWS antepone el ID de
   cuenta al host (`111111111111.localhost`); `*.localhost.floci.io` es un DNS público que
   apunta a 127.0.0.1. Requiere conexión a Internet para resolver el nombre.
6. **`readonlyRootFilesystem` solo en AWS**. Floci 2.1.0 descarta el atributo y Terraform vería
   un cambio en cada plan.
7. **Filtro de alarmas en la consulta**. `DescribeAlarms` ignora `--state-value`; el script de
   vigilancia filtra con JMESPath, que funciona igual en AWS.

## Diferencias conocidas en el plan

Floci 2.1.0 no devuelve algunos atributos, así que `terraform plan` muestra siempre unos pocos
cambios en el sitio (sin reemplazos) aunque no haya nada que cambiar:

- etiquetas de flow logs y de la definición de tarea,
- `treat_missing_data` de las alarmas,
- `health_check_grace_period_seconds` y `enable_ecs_managed_tags` del servicio.

En AWS real el plan queda vacío. Al revisar un plan en simulación, estos cambios se pueden
ignorar; cualquier otro, no.

## Qué no se aprende en simulación

- **Costos.** Nada cuesta. En AWS, el NAT Gateway y los ALB son lo más caro (ver el README).
- **Redes reales.** Los security groups, las tablas de rutas y el NAT existen como recursos,
  pero no filtran ni enrutan tráfico. Un error de red que en AWS deja la app incomunicada aquí
  pasa desapercibido.
- **IAM real.** Las políticas no se evalúan: un rol con permisos de menos funciona igual. El
  mínimo privilegio se diseña aquí, pero se valida en AWS (IAM Access Analyzer ayuda).
- **OIDC real.** No se verifica la firma del token ni la condición `sub`; en AWS un Environment
  equivocado recibe `AccessDenied`.
- **Límites y cuotas** de servicio, **latencias** reales, fallas de zona de disponibilidad y
  tiempos reales de un rolling update (en AWS tarda varios minutos).
- **Métricas nativas** del ALB y de Container Insights: las alarmas que dependen de ellas
  quedan en `INSUFFICIENT_DATA`. Para practicar la respuesta a incidentes se fuerza una alarma:

  ```bash
  AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url http://localhost:4568 \
    cloudwatch set-alarm-state --alarm-name tasks-api-prod-5xx-errors \
    --state-value ALARM --state-reason "simulacro"
  ```

## Persistencia y reinicios

- El estado de cada emulador (incluido el bucket del estado de Terraform) vive en un volumen
  (`floci-<env>-data`). `docker compose down` lo conserva; `down -v` lo borra todo.
- Las tareas de ECS no sobreviven a un reinicio del emulador, pero el servicio las vuelve a
  crear solo en pocos segundos.
- Si se borran los volúmenes, hay que repetir el bootstrap y el `apply` (ver el runbook).

## Actualizar Floci

La imagen está fijada por versión y digest; Dependabot propone las actualizaciones. Al
actualizar, revisar el CHANGELOG de Floci: si una versión nueva trae `PutMetricFilter` o el
circuit breaker, se puede activar `log_metric_filters` en `local.json` y ajustar esta guía.
