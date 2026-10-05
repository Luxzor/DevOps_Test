# Destinos de despliegue (`target`)

Un destino describe **dónde** viven las tres cuentas (dev, staging, prod). Terraform, los
scripts y los workflows leen el mismo archivo, así que migrar de la simulación a AWS real es
cambiar de archivo, no de código.

| Archivo | Uso |
| --- | --- |
| `local.json` | Simulación con Floci (ver `simulation/docker-compose.yml`). Valor por defecto. |
| `aws.json` | Cuentas reales de AWS bajo AWS Organizations. Completar los IDs antes de usarlo. |

Campos generales: `region`, `github_repository` (para la confianza OIDC), `owner` (etiqueta
obligatoria `Owner`) y `log_metric_filters`, que activa las métricas derivadas de logs
(errores 5xx y latencia). Floci 2.1.0 todavía no implementa `PutMetricFilter`, por eso está
apagado en `local.json`; ver `docs/simulation.md`.

Campos por ambiente:

| Campo | Significado |
| --- | --- |
| `account_id` | ID de la cuenta. En la simulación, cada emulador usa un ID distinto. |
| `endpoint` | URL del API de AWS. `null` en AWS real (se usan los endpoints oficiales). |
| `app_url` | URL pública de la app. `null` en AWS real: se usa el DNS del balanceador. |
| `alb_listener_port` | Puerto del listener del ALB. 80 en AWS; 8080 dentro del emulador. |

El destino activo se elige con la variable de entorno `TARGET` (scripts locales) o con la
variable de repositorio `DEPLOY_TARGET` (workflows). Por defecto es `local`.
