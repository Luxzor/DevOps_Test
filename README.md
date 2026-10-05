# Tasks API: CI/CD con GitHub Actions y AWS

Pipeline de CI/CD completo, como el de un equipo de producto, que lleva una API REST
contenedorizada desde un Pull Request hasta producción en AWS (ECS Fargate) de forma
automática, segura y reversible. Todo se puede practicar **sin cuenta de AWS**: tres
instancias del emulador [Floci](https://github.com/floci-io/floci) hacen de las cuentas dev,
staging y prod, y migrar a AWS real es cambiar un archivo de variables.

| Documento | Contenido |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Diagramas, seguridad y decisiones de diseño |
| [docs/runbook.md](docs/runbook.md) | Puesta en marcha, releases, rollback, incidentes, migración a AWS |
| [docs/simulation.md](docs/simulation.md) | Spike del emulador, ajustes y qué no se aprende en simulación |
| [infra/targets/README.md](infra/targets/README.md) | Archivos de destino `local` y `aws` |

## Cómo llega un cambio a producción

1. Rama corta y Pull Request con título en formato Conventional Commits (`feat: ...`).
2. **CI** (runners de GitHub): lint, tipos, pruebas con cobertura mínima de 80 %, CodeQL,
   Trivy, Gitleaks, Checkov, build de la imagen y escaneo. En paralelo, el workflow **Infra**
   comenta el `terraform plan` de los tres ambientes si el PR toca `infra/`.
3. Con `ci-ok` en verde y una aprobación, squash merge a `main`.
4. **CD**: la imagen construida en CI (una sola vez) se publica en el ECR de dev, se despliega,
   se verifica con un smoke test, se promueve tal cual a staging y pasa pruebas end to end.
5. **release-please** mantiene un PR de release con el CHANGELOG. Al fusionarlo se crea el tag
   `vX.Y.Z` y el despliegue a **prod** espera la aprobación de un revisor. Después de desplegar,
   el pipeline vigila las alarmas 10 minutos y revierte solo si algo falla.

## Estructura

```
app/                  API FastAPI, pruebas y Dockerfile multi etapa
infra/
  bootstrap/          estado remoto (S3 + DynamoDB), proveedor OIDC y roles del pipeline
  modules/            network, ecr, alb, ecs-service, observability
  environments/       dev, staging, prod: consumen los módulos con variables distintas
  targets/            local.json (simulación) y aws.json (cuentas reales)
scripts/              lógica de despliegue compartida por workflows y personas
simulation/           docker-compose con las tres cuentas simuladas y el runner autohospedado
.github/workflows/    ci, codeql, pr-title, infra, cd, deploy (reutilizable), rollback
docs/                 arquitectura, runbook y guía de simulación
```

## La aplicación

API REST en Python 3.12 con FastAPI. Configuración solo por variables de entorno (12 factor).

| Endpoint | Descripción |
| --- | --- |
| `GET /health` | Health check del balanceador y de ECS |
| `GET /version` | Versión, **hash del commit** y ambiente: comprueba qué corre en cada lugar |
| `GET /tasks`, `GET /tasks/{id}` | Lectura (pública) |
| `POST /tasks`, `PATCH /tasks/{id}`, `DELETE /tasks/{id}` | Escritura; exige `X-API-Key` (token en Secrets Manager) |

| Variable | Default | Uso |
| --- | --- | --- |
| `APP_ENV` | `local` | Nombre del ambiente |
| `APP_GIT_SHA`, `APP_VERSION` | fijadas en la imagen | Identidad de la build |
| `APP_API_TOKEN` | sin definir (escritura abierta) | Inyectada por ECS desde Secrets Manager |
| `APP_STORAGE` | `memory` | `dynamodb` en los ambientes desplegados |
| `APP_DYNAMODB_TABLE` | | Tabla de tareas |
| `APP_LOG_LEVEL` | `INFO` | Logs JSON en stdout, hacia CloudWatch |

```bash
make install test          # pruebas unitarias e integración con cobertura
make run                   # http://localhost:8000/docs
```

## Inicio rápido (simulación)

Requisitos: Docker con Compose, Terraform 1.11+, AWS CLI v2, `jq`, Git y `gh`.

```bash
make sim-up                # tres cuentas: API en :4566/:4567/:4568, app en :8081/:8082/:8083
make bootstrap             # único paso manual: estado remoto, OIDC y roles en cada cuenta
make infra                 # terraform apply de dev, staging y prod
make deploy-local          # build, publicar, desplegar y promover hasta prod con los mismos scripts del CD
make versions              # qué commit corre en cada ambiente
```

Para el flujo completo con GitHub Actions (repositorio privado, runner autohospedado,
Environments y protección de `main`), seguir [docs/runbook.md](docs/runbook.md#1-puesta-en-marcha-desde-cero-simulación).
`scripts/github-setup.sh` deja el repositorio configurado con un solo comando.

## Workflows

| Workflow | Disparador | Runner | Qué hace |
| --- | --- | --- | --- |
| `ci.yml` | PR y push a `main` | GitHub | Calidad, pruebas, seguridad, build; guarda la imagen de `main` |
| `codeql.yml` | PR, push a `main`, semanal | GitHub | SAST de Python y de los workflows |
| `pr-title.yml` | PR | GitHub | Título en formato Conventional Commits |
| `infra.yml` | PR y push a `main` en `infra/`, manual | autohospedado | Plan comentado en el PR; apply dev, staging, prod; destroy manual |
| `cd.yml` | CI de `main` en verde | autohospedado | dev, staging (E2E), release-please, prod (aprobación) |
| `deploy.yml` | reutilizable | autohospedado | Publicar o promover, desplegar, verificar, vigilar, revertir |
| `rollback.yml` | manual | autohospedado | Redesplegar una versión anterior indicando solo su tag o commit |

Buenas prácticas aplicadas: permisos mínimos declarados en cada workflow, acciones fijadas
por hash de commit, `concurrency` para cancelar ejecuciones obsoletas de PR y encolar
despliegues, caché de pip y de capas de Docker, jobs en paralelo y un único check obligatorio
(`ci-ok`).

## Criterios de aceptación

| Criterio | Cómo se cumple |
| --- | --- |
| Un PR con una prueba fallida no puede fusionarse | `app-test` falla, `ci-ok` queda en rojo y el ruleset de `main` lo exige (`scripts/github-setup.sh`) |
| Un merge a `main` despliega solo a dev y staging | `cd.yml`: dev y staging no tienen aprobación; prod solo corre si release-please creó un release |
| Producción solo con tag de release y aprobación | Job `prod` condicionado a `release_created` y Environment `prod` con revisor obligatorio |
| La misma imagen en los tres ambientes | Build única en CI; `promote-image.sh` copia entre ECR y falla si el digest cambia |
| Sin llaves de AWS de larga duración | OIDC con `configure-aws-credentials`; no hay secretos de AWS en el repositorio ni en GitHub |
| Infraestructura creada y destruida con Terraform | `infra.yml` (apply y destroy) y `make infra`; probado destroy y apply completo de dev (54 recursos) |
| Un despliegue defectuoso se revierte | `deploy.sh` revierte si falla la estabilidad o el smoke test; `deploy.yml` si fallan E2E o alarmas; `rollback.yml` manual. Probado con una imagen rota |
| README, diagrama y runbook | Este archivo, `docs/architecture.md` y `docs/runbook.md` |

## Fases del proyecto

| Fase | Entregable | Estado |
| --- | --- | --- |
| 1. Base | App, pruebas, Dockerfile, CI, plantillas y protección de rama | Listo; la protección se aplica con `scripts/github-setup.sh` |
| 2. Infraestructura | Bootstrap, módulos y ambientes; apply por pipeline | Listo y probado en simulación |
| 3. CD | OIDC, despliegue automático a dev y staging con workflow reutilizable | Listo; scripts probados en simulación |
| 4. Producción | Environments con aprobación, release por tag, rollback | Listo; rollback automático probado |
| 5. Endurecimiento | Escaneos, alarmas, tablero, documentación | Listo |

Lo probado en este repositorio sin GitHub: scripts de despliegue, promoción, rollback,
E2E y vigilancia contra los tres emuladores; Terraform completo; Checkov, Trivy, Gitleaks,
actionlint y shellcheck. Los workflows se validaron con actionlint, pero su primera ejecución
real ocurre al configurar el repositorio y el runner.

## Seguridad en un repositorio privado

El runner autohospedado exige un repositorio privado. En repositorios privados, CodeQL con
panel de Code Scanning, el escaneo de secretos y el push protection de GitHub requieren los
planes pagos GitHub Code Security y Secret Protection. Por eso:

- CodeQL corre igual y **falla el job** si encuentra problemas; con el plan, definir la
  variable `CODEQL_UPLOAD=always` para ver los resultados en la pestaña Security.
- Gitleaks (historial completo) y Trivy (secretos) cubren la detección de secretos en el CI.
- Las alertas y actualizaciones de seguridad de Dependabot sí son gratuitas y
  `scripts/github-setup.sh` las activa.

## Costos

En simulación: cero. En AWS real, con Fargate mínimo, un ALB por ambiente y NAT Gateway,
entre 60 y 120 dólares al mes si todo queda encendido (cifra aproximada, a validar con la
calculadora de precios de AWS). Para controlarlo: un solo NAT en dev y staging (ya
configurado), destruir dev y staging fuera de horario (workflow Infra con `destroy`) y un
presupuesto de AWS Budgets con alerta antes de crear recursos.

## Pasos de crecimiento (fuera del alcance)

Kubernetes (EKS), varios microservicios, multi región, cumplimiento formal (SOC 2, ISO) y
optimización avanzada de costos. Mejoras directas sobre este proyecto: blue green con
CodeDeploy, replicación nativa de ECR entre cuentas, llaves KMS propias, WAF, access logs del
ALB, RDS PostgreSQL con migraciones en el pipeline y rotación automática del token.
