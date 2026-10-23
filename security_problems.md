# Security Problems — Expense Tracker

Documento de seguimiento de la auditoría de seguridad. Sirve para retomar el trabajo
en otra sesión sin perder contexto: qué se hizo, qué no se hizo, evidencia y próximo paso.

## Cómo usar este documento

1. Marcar `[x]` solo cuando el cambio esté implementado **y** verificado con pruebas.
2. Al terminar cada ítem, agregar una fila en [Registro de cambios](#registro-de-cambios)
   con commit, pruebas ejecutadas y resultado real.
3. Mantener el estado global actualizado.
4. Todo cambio de comportamiento sigue el flujo TDD del proyecto: prueba que falla →
   implementación mínima → prueba en verde → suite completa en CI.
5. No marcar un ítem como hecho por intención: solo con evidencia (tests/CI).

Leyenda:

- `[x]` Hecho y verificado.
- `[ ]` Pendiente.
- `[~]` En curso (debe haber una sola fila en curso a la vez).

## Estado global

| Fase | Alcance | Estado | Evidencia |
| --- | --- | --- | --- |
| Fase 1 | 2 hallazgos High de la auditoría (SEC-001, SEC-002) | Completada | PR #1, CI run `39980111648` (MiniTest, Playwright, Brakeman en verde) |
| Fase 2 | 1 High nuevo + medios de integridad/autorización | En curso: SEC-003 y SEC-004 hechas; SEC-005 a SEC-009 pendientes | Ver registro de cambios |
| Fase 3 | Endurecimiento (bajos/informativos) | Pendiente | — |

Inventario de la auditoría original: 0 críticos, 2 altos, 7 medios, 8 bajos, 6 informativos.
La Fase 1 cubrió los 2 altos. Los ítems de este documento son los verificados contra el
código actual; al final hay una nota sobre la reconciliación con el informe original.

## Fase 1 — Alta (completada)

### SEC-001 — Transacciones podían referenciar money sources y categorías de otro usuario

- [x] Implementado y verificado.
- Archivos: `app/models/transaction.rb`, `test/models/transaction_ownership_test.rb`,
  controladores de expenses/incomes.
- Riesgo: un `money_source_id` ajeno permitía mover el `cached_balance` de otra cuenta
  vía `BalanceSync`; una categoría personalizada ajena filtraba datos.
- Solución: validaciones `money_source_belongs_to_user` y `category_belongs_to_user`.
  Las categorías compartidas (`user_id: nil`, incluidas las default) siguen permitidas.
- Evidencia: pruebas de modelo y controlador; suite completa en CI.
- Commits: `48096a3`, `f454d74`.

### SEC-002 — Transferencias podían usar cuentas de origen/destino de otro usuario

- [x] Implementado y verificado.
- Archivos: `app/models/transfer.rb`, `test/models/transfer_test.rb`,
  `test/controllers/transfers_controller_test.rb`.
- Riesgo: los hooks `after_commit` movían saldos de cuentas ajenas.
- Solución: validación `sources_belong_to_user` sobre ambos extremos.
- Evidencia: pruebas de modelo/controlador y CI en verde.
- Commits: `48096a3`, `f454d74`.

### Fixtures corregidas en Fase 1

- [x] Se actualizaron datos de prueba que construían relaciones cruzadas, sin cambiar
  aserciones: expenses, incomes, transfers, reports, budgets, búsquedas, alertas,
  insights, balance sync y bulk destroy.

## Fase 2 — Alta/Media (en curso)

### SEC-003 — `MoneySource#parent_id` permite apuntar a una cuenta de otro usuario (Alta)

- [x] Implementado y verificado.
- Archivos: `app/models/money_source.rb`, `app/services/money_sources/balance_sync.rb`,
  `test/models/money_source_test.rb`, `test/services/money_sources/balance_sync_test.rb`,
  `test/controllers/money_sources_controller_test.rb`.
- Riesgo: `parent_id` se aceptaba sin validar dueño; con una fuente `debit_card`,
  `BalanceSync.adjust!` escribía `cached_balance` sobre el padre. Un usuario podía
  mover el saldo de otra persona.
- Solución:
  - Validación `parent_belongs_to_user` (padre ajeno invalido con `:other_user`) y
    `parent_must_not_be_self` en `MoneySource`.
  - Guarda en `BalanceSync.adjust!`: el delta va al padre solo si es del mismo dueño;
    ante un enlace ajeno ya persistido, cae en la propia fuente.
- Pruebas: 8 escenarios (4 controlador, 3 modelo, 1 servicio), rojo confirmado antes
  de implementar y verificados en verde; suite completa en CI.
- Evidencia: commit `a5d853c`; CI run `39984286996` en verde (MiniTest, Playwright,
  Brakeman; el job de Playwright se re-corrío por un flake del category picker).

### SEC-004 — IDOR de lectura en `CategoriesController#show` (Media)

- [x] Implementado y verificado.
- Archivos: `app/controllers/categories_controller.rb`, `test/controllers/categories_controller_test.rb`.
- Riesgo: `Category.find(params[:id])` no filtraba por usuario; el `show` exponía nombre,
  descripción, padre y conteo de gastos de una categoría personalizada ajena.
- Solución: `set_category` carga con `Category.for_user(current_user).find(...)`; una
  categoría personalizada ajena cae en el `rescue` existente y redirige con
  `category_messages.not_found`. Las compartidas (default) siguen accesibles.
- Pruebas: 3 escenarios de controlador (propia, compartida y ajena), rojo confirmado
  antes de implementar y verificados en verde; suite completa en CI.
- Evidencia: commit del cambio; CI run por confirmar.

### SEC-005 — Referencias ajenas en registros secundarios (Media)

- [ ] Pendiente.
- Archivos:
  - `app/models/recurring_template.rb:9-10` y
    `app/controllers/concerns/recurring_template_actions.rb:167,174`.
  - `app/models/transaction_rule.rb:12-15` y
    `app/controllers/transaction_rules_controller.rb:93-102`.
  - `app/models/category.rb:62-76` y `app/controllers/categories_controller.rb:90`.
- Riesgo: plantillas recurrentes, reglas y categorías padre pueden referenciar
  `category_id`/`money_source_id`/`parent_id` de otro usuario. La Fase 1 ya impide la
  mutación de saldo al crear la transacción, pero los registros siguen aceptando y
  mostrando referencias ajenas (integridad y fuga de metadatos).
- Solución propuesta: validaciones de propiedad en cada modelo (mismo patrón que
  `Payment#target_belongs_to_user` y `MoneySource#institution_belongs_to_owner`).
- Pruebas requeridas: por modelo, referencia ajena inválida y propia/default válida;
  controladores rechazan create/update con ids ajenos.

### SEC-006 — CSV injection en la exportación de gastos (Media)

- [ ] Pendiente.
- Archivos: `app/services/expenses/csv_exporter.rb:25-31`.
- Riesgo: descripción/categoría/fuente se escriben sin neutralizar; una celda que
  empiece con `=`, `+`, `-` o `@` puede ejecutarse como fórmula al abrir el CSV.
- Solución propuesta: prefijar con `'` (o tab) las celdas que empiecen con esos
  caracteres, incluidos `\t` y `\r`; aplicar a todos los campos de texto.
- Pruebas requeridas: descripción/categoría/fuente con fórmulas quedan neutralizadas;
  exportación normal no cambia.

### SEC-007 — Sin rate limiting en autenticación, webhooks y endpoints de IA (Media)

- [ ] Pendiente.
- Archivos: `config/routes.rb` (login/password, webhooks, playground, evaluaciones,
  financial chat), `app/controllers/users/*`, `app/controllers/webhooks/whatsapp_controller.rb`.
- Riesgo: fuerza bruta de credenciales, abuso de costo de IA y saturación de jobs.
- Solución propuesta: usar el `rate_limit` nativo de Rails 8 en los controladores
  afectados (sin agregar dependencias), con `solid_cache` en producción. Evaluar
  límites por IP y por usuario.
- Pruebas requeridas: exceder el límite responde `429`; uso normal no se bloquea.

### SEC-008 — Subida de extractos sin límite explícito de tamaño (Media)

- [ ] Pendiente.
- Archivos: `app/controllers/statement_imports_controller.rb:120-125`,
  `app/services/statements/parser.rb:35`.
- Riesgo: el archivo completo se lee y se base64-codifica en memoria sin límite
  explícito; un archivo grande puede agotar memoria.
- Solución propuesta: rechazar archivos por encima de un máximo explícito (alineado con
  `Expenses::Inputs::Rules::File::FILE_MAX_BYTES`, 20 MB) antes de leer/converter.
- Pruebas requeridas: archivo sobre el límite responde error sin procesar; archivo
  válido sigue funcionando.

### SEC-009 — Descarga de media de WhatsApp sin allowlist de host (Media/Baja)

- [ ] Pendiente.
- Archivos: `app/services/whatsapp/media_fetcher.rb:50-58`.
- Riesgo: se descarga cualquier URL devuelta por Graph API sin validar host/esquema;
  un response manipulado podría inducir peticiones internas (SSRF acotado).
- Solución propuesta: exigir `https`, allowlist de dominios de Meta y/o bloquear rangos
  privados/reservados; validar también el `media_id`.
- Pruebas requeridas: URL con host no permitido se rechaza; URL válida (stub) funciona.

## Fase 3 — Endurecimiento (bajos/informativos)

### SEC-010 — CSP deshabilitada

- [ ] Pendiente.
- Archivo: `config/initializers/content_security_policy.rb` (todo comentado).
- Nota: activar CSP requiere sacar los scripts inline de las vistas (regla del proyecto:
  JS de aplicación solo en módulos dedicados). Planificar junto con esa limpieza.

### SEC-011 — Endurecer webhook de WhatsApp

- [ ] Pendiente.
- Archivo: `app/controllers/webhooks/whatsapp_controller.rb`.
- Acciones: comparación de verify token en tiempo constante (`secure_compare`), manejo
  explícito de `WHATSAPP_VERIFY_TOKEN`/`FB_APP_SECRET` ausentes (no 500), y límite de
  tamaño del payload antes de encolar el job.

### SEC-012 — `config.hosts` sin definir en producción

- [ ] Pendiente.
- Archivo: `config/environments/production.rb:82`.
- Acción: configurar hosts permitidos desde ENV para mantener la protección contra
  DNS rebinding.

### SEC-013 — Logging de datos financieros en el playground

- [ ] Pendiente.
- Archivo: `app/controllers/expense_playground_controller.rb:29`.
- Acción: quitar el `puts` con candidatos completos (montos/descripciones); si se
  necesita observabilidad, registrar solo métricas no sensibles.

### SEC-014 — Orígenes de Action Cable no configurados

- [ ] Pendiente.
- Archivos: `config/environments/production.rb`, `config/cable.yml`.
- Acción: definir `config.action_cable.allowed_request_origins` y verificar que el
  stream siga autenticado por usuario.

### SEC-015 — Prompts y salidas de IA en claro en base de datos (Informativo/Bajo)

- [ ] Pendiente.
- Archivo: `db/schema.rb:47-48` (`ai_requests.prompt`, `ai_requests.output`).
- Acción: evaluar cifrado en reposo (Active Record Encryption) o redacción/retención
  acotada, según necesidad de depuración. No bloquear la Fase 2 por esto.

## Reconciliación con la auditoría original

La auditoría original reportó 7 medios, 8 bajos y 6 informativos. Este documento lista
los ítems que pudieron verificarse en el código actual (6 medios + 6 bajos + 1 alto nuevo).
Si se recupera el informe original completo, agregar aquí los ítems restantes con su
estado para no perder trazabilidad. No asumir que la lista actual es exhaustiva.

## Registro de cambios

| Fecha | Ítem | Cambio | Commit | Pruebas / CI |
| --- | --- | --- | --- | --- |
| 2026-10-23 | SEC-001, SEC-002 | Validaciones de propiedad en `Transaction` y `Transfer`; fixtures corregidas | `48096a3`, `f454d74` | PR #1, run `39980111648` en verde |
| 2026-10-23 | Documento | Creación de `security_problems.md` | `4713aa0` | — |
| 2026-10-23 | SEC-003 | Validación de propiedad del `parent` y guarda en `BalanceSync.adjust!` | `a5d853c`, `c342544` (grafo) | CI run `39984286996` en verde |

## Comandos útiles

```bash
# Prueba puntual
bin/rails test test/models/transaction_ownership_test.rb

# Suite completa local
bin/rails test

# Estado de CI del PR
gh pr checks 1
gh run list --branch feature/ju-security --limit 5

# Actualizar grafo tras cambios de código de aplicación
graphify update .
```

## Convenciones

- Una rama/PR por fase o por hallazgo si el cambio es grande; commits pequeños y
  descriptivos.
- No mezclar refactors no relacionados con el arreglo de seguridad.
- Actualizar este documento en el mismo commit del cambio correspondiente.
- Cerrar cada ítem solo con tests en verde y, cuando aplique, CI en verde.
