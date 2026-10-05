# Runbook

Procedimientos para poner en marcha, operar y recuperar el sistema. Los comandos asumen que
estás en la raíz del repositorio. En simulación (`TARGET=local`, valor por defecto) no hace
falta configurar credenciales: los scripts usan las del emulador.

## 1. Puesta en marcha desde cero (simulación)

Requisitos: Docker con Docker Compose, Terraform 1.11 o superior, AWS CLI v2, `jq`, Git y
GitHub CLI (`gh`). Repositorio **privado** en GitHub.

1. **Emuladores** (las tres cuentas):

   ```bash
   docker compose -f simulation/docker-compose.yml up -d
   docker compose -f simulation/docker-compose.yml ps   # los tres en (healthy)
   ```

2. **Bootstrap** de cada cuenta. Es el único paso manual: crea el bucket del estado, la tabla
   de bloqueo, el proveedor OIDC de GitHub y los roles del pipeline.

   ```bash
   for env in dev staging prod; do AUTO_APPROVE=1 scripts/bootstrap.sh "$env"; done
   ```

3. **Configuración del repositorio** (Environments, protección de `main`, variables):

   ```bash
   gh auth login
   scripts/github-setup.sh Luxzor/DevOps_Test
   ```

4. **Runner autohospedado**. En GitHub: Settings, Actions, Runners, New self-hosted runner;
   copiar solo el token. Luego:

   ```bash
   RUNNER_REPO_URL=https://github.com/Luxzor/DevOps_Test RUNNER_TOKEN=<token> \
     docker compose -f simulation/docker-compose.yml --profile runner up -d --build
   ```

   El runner aparece como `sim-runner` con la etiqueta `sim`. El token de registro se usa una
   sola vez; si se recrea el contenedor, hace falta uno nuevo.

5. **Infraestructura**: Actions, Infra, Run workflow, `apply` en dev, luego staging y prod
   (prod pide aprobación). También se aplica sola al fusionar cambios en `infra/`.

6. **Primer despliegue**: fusionar cualquier Pull Request a `main`. El CD publica la imagen y
   despliega en dev y staging.

> Hasta el primer despliegue, el servicio de cada ambiente apunta a la imagen `bootstrap`, que
> no existe: ECS reintenta arrancar la tarea sin éxito. Es esperado y se corrige solo con el
> primer despliegue.

Atajo para practicar sin GitHub (mismo código que usa el pipeline):

```bash
make sim-up bootstrap infra             # emuladores, bootstrap y apply de los 3 ambientes
make deploy-local                       # build, publicar, dev, staging (con E2E) y prod
```

## 2. Qué versión corre en cada ambiente

- Desde la terminal: `scripts/versions.sh` (o `make versions`).
- En el resumen de cada ejecución del workflow **CD** (tabla de versiones).
- En la app: `curl http://localhost:8081/version` (8082 staging, 8083 prod).
- En el parámetro SSM que escribe cada despliegue:

  ```bash
  source scripts/lib.sh && use_env prod
  aws ssm get-parameter --name /tasks-api/prod/image-tag --query Parameter.Value --output text
  ```

## 3. Release a producción

1. Cada merge a `main` actualiza un Pull Request llamado `chore(main): release X.Y.Z` con el
   CHANGELOG. La versión sale de los títulos de los PR: `fix:` sube el patch, `feat:` el
   minor y `!` o `BREAKING CHANGE` el major.
2. Fusionar ese PR cuando se quiera publicar. El CD despliega el commit en dev y staging, crea
   el tag `vX.Y.Z` y el release de GitHub, y deja el job **prod** esperando aprobación.
3. El revisor de prod aprueba en la ejecución del workflow (Review deployments).
4. El pipeline promueve la imagen desde staging, despliega, corre el smoke test y vigila las
   alarmas durante 10 minutos. Si algo falla, vuelve solo a la versión anterior.

> Con el `GITHUB_TOKEN`, el PR de release no dispara el CI y no se puede fusionar con la regla
> de checks obligatorios. Solución: crear una GitHub App o un token fine-grained con permisos
> `contents` y `pull-requests` de escritura sobre este repositorio y guardarlo como secreto
> `RELEASE_PLEASE_TOKEN`.

## 4. Rollback

**Automático.** Ocurre sin intervención si después de desplegar:

- el servicio no queda estable en 10 minutos,
- ECS revierte el despliegue (circuit breaker, en AWS),
- falla el smoke test (`/health` o `/version` con otro commit),
- fallan las pruebas end to end (staging), o
- se dispara una alarma durante la vigilancia (prod).

**Manual.** Actions, **Rollback**, Run workflow: elegir el ambiente e indicar la versión como
tag de release (`v1.2.0`) o hash de commit. La imagen ya está en el ECR del ambiente, así que
no se reconstruye nada. En prod exige la misma aprobación que un despliegue.

Sin GitHub (por ejemplo, si GitHub está caído), desde una máquina con acceso a la cuenta:

```bash
scripts/deploy.sh prod <hash-del-commit>
```

**Probar el rollback** (criterio de aceptación). Se hizo así en la simulación:

```bash
# Imagen que arranca y se cae: el smoke test falla y deploy.sh vuelve a la revisión anterior
printf 'FROM tasks-api:%s\nCMD ["sh","-c","exit 1"]\n' "$SHA_BUENO" | docker build -t tasks-api:rota -
scripts/publish-image.sh dev tasks-api:rota "$(printf 'd%.0s' {1..40})"
DEPLOY_TIMEOUT=90 scripts/deploy.sh dev "$(printf 'd%.0s' {1..40})"   # termina con error y revierte
curl -s localhost:8081/version                                         # sigue el commit bueno
```

## 5. Respuesta a una alarma

1. Abrir el tablero `tasks-api-<env>` en CloudWatch y ver qué alarma está en `ALARM`.
2. Revisar los logs (JSON) del servicio:

   ```bash
   source scripts/lib.sh && use_env prod
   aws logs tail /ecs/tasks-api-prod --since 15m --format short
   ```

3. Si coincide con un despliegue reciente: **rollback primero, diagnóstico después**.
4. Si no: revisar tareas y eventos del servicio:

   ```bash
   aws ecs describe-services --cluster tasks-api-prod --services tasks-api \
     --query 'services[0].events[:10].[createdAt,message]' --output table
   ```

5. Registrar qué pasó y qué se cambió para que no se repita (postmortem sin culpas).

## 6. Cambios de infraestructura

- Todo cambio en `infra/` entra por Pull Request. El workflow **Infra** comenta el plan de los
  tres ambientes; revisarlo antes de aprobar (en simulación, ver `docs/simulation.md` para los
  cambios que siempre aparecen).
- Al fusionar, se aplica en dev, staging y prod en ese orden (prod con aprobación). Se aplica
  exactamente el plan mostrado en el job.
- Un cambio en la definición de tarea (CPU, memoria, variables) se activa en el siguiente
  despliegue de la app. Para activarlo ya: workflow **Rollback** con la versión actual.

### Destruir y recrear un ambiente

Actions, Infra, Run workflow con `action: destroy` y el nombre del ambiente en `confirm`. Para
recrearlo, el mismo workflow con `apply` y después un despliegue (Rollback con la última
versión, o un merge). Localmente:

```bash
scripts/tf.sh dev destroy
scripts/tf.sh dev apply
```

En AWS, producción tiene protecciones contra borrado (ALB, tabla DynamoDB, imágenes en ECR):
para destruirla hay que desactivarlas antes con un cambio revisado. Es intencional.

### Bloqueo de estado trabado

Si un job se canceló a mitad de un apply, el bloqueo puede quedar tomado:

```bash
scripts/tf.sh <env> force-unlock <LOCK_ID>   # el ID aparece en el mensaje de error
```

Antes, confirmar que ningún otro job de Terraform está corriendo.

## 7. Rotar el token de la API

Incrementar `secret_string_wo_version` en `aws_secretsmanager_secret_version.api_token`
(`infra/environments/<env>/main.tf`) y fusionar. Terraform genera un valor nuevo; las tareas lo
toman al reiniciarse, así que después hay que redesplegar (workflow Rollback con la versión
actual).

## 8. Respaldo del estado del bootstrap

El bootstrap guarda su estado localmente en `infra/bootstrap/terraform.tfstate.d/` (no se
versiona). Respaldarlo en un lugar seguro. Si se pierde, los recursos siguen funcionando; para
volver a administrarlos con Terraform se importan con `terraform import`.

## 9. Problemas frecuentes

| Síntoma | Causa probable | Solución |
| --- | --- | --- |
| Jobs de CD o Infra quedan en "Waiting for a runner" | Runner apagado o sin registrar | `docker compose -f simulation/docker-compose.yml --profile runner ps`; registrar con un token nuevo |
| `AccessDenied` al asumir el rol (AWS real) | El job no corre en el Environment esperado o desde otra rama | Revisar el `sub` del token y la política de confianza en `infra/bootstrap/main.tf` |
| `AWS account ID not allowed` | Credenciales de otra cuenta | Revisar el ambiente y el `account_id` del archivo de destino |
| `tag invalid: The image tag already exists` | ECR inmutable: esa etiqueta ya se publicó | Es esperado; `publish-image.sh` lo detecta y no vuelve a publicar |
| `no such host 111111111111.localhost.floci.io` | Sin DNS público | `localhost.floci.io` necesita Internet; ver `docs/simulation.md` |
| La app responde 502 en simulación | Tarea arrancando o emulador reiniciado | Esperar unos segundos; ver `docker ps` y los logs del emulador |
| El plan siempre muestra cambios en simulación | Atributos que Floci no devuelve | Ver la lista en `docs/simulation.md` |

## 10. Migrar a AWS real

1. Crear tres cuentas bajo AWS Organizations, con MFA en el usuario raíz y acceso por IAM
   Identity Center. Configurar AWS Budgets con alerta antes de crear recursos.
2. Completar los IDs de cuenta en `infra/targets/aws.json` (y opcionalmente un correo para las
   alarmas en `infra/environments/*/terraform.tfvars`).
3. Bootstrap de cada cuenta con credenciales de administrador (SSO):
   `TARGET=aws scripts/bootstrap.sh dev` (y staging, prod).
4. Cambiar la variable del repositorio `DEPLOY_TARGET` a `aws`. Los jobs pasan a correr en
   runners de GitHub y apagar el runner local ya no afecta.
5. Ejecutar el workflow Infra con `apply` en cada ambiente y fusionar un cambio para desplegar.
6. Para HTTPS: dominio en Route 53, certificado en ACM y `certificate_arn` en los tfvars.
