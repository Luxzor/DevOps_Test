## Qué cambia y por qué

<!-- Una o dos frases. Enlaza el issue si existe. -->

## Tipo de cambio

<!-- El título del PR debe seguir Conventional Commits: feat:, fix:, docs:, ci:, chore:, ... -->

- [ ] `feat`: funcionalidad nueva (sube la versión minor)
- [ ] `fix`: corrección (sube la versión patch)
- [ ] Cambio incompatible (`!` en el título o `BREAKING CHANGE` en la descripción)
- [ ] Infraestructura, pipeline o documentación

## Lista de verificación

- [ ] Las pruebas cubren el cambio y el CI está en verde
- [ ] Si toca `infra/`, revisé el `terraform plan` comentado en este PR para los tres ambientes
- [ ] No agrego secretos, llaves ni credenciales al repositorio
- [ ] Las variables de configuración nuevas se leen del entorno y están documentadas
- [ ] Actualicé `README.md` o `docs/` si cambia cómo se usa o se opera el sistema
- [ ] El cambio se puede revertir (rollback) sin pasos manuales, o documenté cómo

## Cómo probarlo

<!-- Comandos o pasos para verificarlo localmente o en dev. -->
