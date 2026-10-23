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
| Fase 2 | 1 High nuevo + medios de integridad/autorización | Completada (SEC-003 a SEC-009; SEC-007 parcial: falta login) | CI en verde (ver registro) |
| Fase 3 | Endurecimiento (bajos/informativos) | Hecha salvo SEC-015 (requiere decisión) | CI en verde (ver registro) |

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
- Evidencia: commit `151ae95`; CI run `39988051388` en verde (MiniTest, Playwright,
  Brakeman).

### SEC-005 — Referencias ajenas en registros secundarios (Media)

- [x] Implementado y verificado.
- Archivos: `app/models/recurring_template.rb`, `app/models/transaction_rule.rb`,
  `app/models/category.rb`, `config/locales/es.yml` (llave
  `validation.category_parent_owner`), tests de modelo y controlador de los 3 recursos.
- Riesgo: plantillas recurrentes, reglas de transacción y padre de categoría podían
  referenciar `category_id`/`money_source_id` de otro usuario. La Fase 1 ya impedía la
  mutación de saldo, pero los registros aceptaban y mostraban referencias ajenas.
- Solución: validaciones de propiedad al nivel de modelo (mismo patrón que
  `Payment#target_belongs_to_user`); compartidas (sin dueño) permitidas para todos,
  personales solo del mismo dueño; categoría compartida solo con padre compartido.
- Pruebas: 18 escenarios (8 controlador, 10 modelo), rojo confirmado antes de
  implementar y verificados en verde; suite completa en CI.
- Evidencia: commits `7491a45`, `5852123` (grafo); CI run `39992390240` en verde.

### SEC-006 — CSV injection en la exportación de gastos (Media)

- [x] Implementado y verificado.
- Archivo: `app/services/expenses/csv_exporter.rb` + pruebas.
- Riesgo: descripción/categoría/fuente se escribían sin neutralizar; una celda que
  empieza con `=`, `+`, `-`, `@`, tab o CR se ejecuta como fórmula al abrir el CSV.
- Solución: `safe_text` antepone `'` a las celdas de texto con esos prefixes; el importe
  y la fecha no se tocan.

### SEC-007 — Sin rate limiting en autenticación, webhooks y endpoints de IA (Media)

- [x] Implementado y verificado (parcial: sin login de Devise).
- Archivos: `lib/rate_limit_proxy.rb`, `app/controllers/webhooks/whatsapp_controller.rb`,
  `app/controllers/financial_chats/messages_controller.rb`,
  `app/controllers/users/passwords_controller.rb`,
  `app/controllers/expense_evaluations_controller.rb`,
  `app/controllers/expense_playground_controller.rb`,
  `app/controllers/gmail_connections_controller.rb` + sus pruebas.
- Riesgo: fuerza bruta de credenciales, abuso de costo de IA y saturación de jobs.
- Solución: `rate_limit` nativo de Rails 8 (sin dependencias nuevas) con
  `RateLimitProxy` que resuelve `Rails.cache` en tiempo de ejecución (Solid Cache en
  producción; no-op con el `null_store` de testing). Límites: webhook 30/min,
  chat 20/min, reset 5/min, evaluaciones 10/min, playground 30/min, Gmail sync 5/min.
- Pendiente: rate limit del login de Devise requiere un `SessionsController` propio
  (riesgo de romper los flujos e2e con límites por IP); sugerir al usuario si lo aplica.
- Pruebas: webhook 31 requests -> 429, chat 21 -> 429, reset 6 -> 429.
- Evidencia: commit `02b3b0e`; CI run `39997726167` y `39999729133` en verde.

### SEC-008 — Subida de extractos sin límite explícito de tamaño (Media)

- [x] Implementado y verificado.
- Archivos: `app/controllers/statement_imports_controller.rb`,
  `app/services/statements/parser.rb`,
  `app/services/expenses/file_import/pipeline.rb`, locales `wizard.upload.file_too_large`.
- Riesgo: el archivo completo se leía y base64-codificaba en memoria sin límite.
- Solución: `oversize_upload?` en el controlador con `request.content_length` (barato y
  pre-lectura) + guardas equivalentes en `Statements::Parser` y en el pipeline del
  playground después de decodificar; máximo alineado con `FILE_MAX_BYTES` (20 MB).
- Nota de prueba: la guarda del controlador no es comprobable en el stack de
  integración (el compositor multipart de Rack deforma el part); la cobertura real
  vive en `Statements::ParserTest` y `FileProcessorTest`.

### SEC-009 — Descarga de media de WhatsApp sin allowlist de host (Media/Baja)

- [x] Implementado y verificado.
- Archivos: `app/services/whatsapp/media_fetcher.rb` + pruebas.
- Riesgo: se descargaba cualquier URL devuelta por Graph API (SSRF acotado).
- Solución: `safe_media_url?` público exige HTTPS y hosts de Meta
  (`lookaside.fbsbx.com`/`.fbsbx.com`/`.fbcdn.net`); `download` rechaza lo demás y lo
  registra sin hacer la petición.

## Fase 3 — Endurecimiento (bajos/informativos)

### SEC-010 — CSP deshabilitada

- [x] Implementado (parcialmente estricto).
- Archivo: `config/initializers/content_security_policy.rb` + `SecurityHeadersTest`.
- Solución: CSP activa con base conservadora (`default-src 'self'`, `object-src 'none'`,
  `frame-ancestors 'self'`, `form-action 'self'`, `base-uri 'self'`), y los orígenes
  externos reales del layout (jsdelivr para el bundle de Bootstrap, Google Fonts).
- Pendiente: `script-src`/`style-src` aún llevan `unsafe-inline` porque las plantillas
  ERB tienen scripts inline; se retira cuando el JS se moduleice (regla del proyecto).

### SEC-011 — Endurecer webhook de WhatsApp

- [x] Implementado y verificado.
- Archivo: `app/controllers/webhooks/whatsapp_controller.rb` + pruebas.
- Acciones: comparación del verify token en tiempo constante (`secure_compare`), `403`
  claro cuando el token no está configurado (antes se filtraba por igualdad), `401`
  cuando `FB_APP_SECRET` no está configurado (antes 500 por HMAC con clave nula), y
  `413 antes de leer para payloads > 1 MB + rate limit 30/min sobre el POST.

### SEC-012 — `config.hosts` sin definir en producción

- [x] Implementado (condicional).
- Archivo: `config/environments/production.rb`.
- Solución: si `RAILS_PUBLIC_HOSTS` está definido (lista separada por comas), la app
  activa la protección de hosts y añade los orígenes https permitidos de Action Cable;
  si no está definido, registra una advertencia y deja la protección abierta.
- Necesita de ti: el dominio real de producción para fijar `RAILS_PUBLIC_HOSTS` en el
  entorno; sin ese valor el ítem queda cerrado solo en código, no en operación.

### SEC-013 — Logging de datos financieros en el playground

- [x] Implementado y verificado.
- Archivo: `app/controllers/expense_playground_controller.rb`.
- Acción: el `puts` de candidatos completos (montos/descripciones) quedó reemplazado
  por una línea de métricas sin datos financieros ni payloads.

### SEC-014 — Orígenes de Action Cable no configurados

- [x] Implementado (condicional).
- Archivos: `config/environments/production.rb`.
- Solución: los orígenes `https://<RAILS_PUBLIC_HOSTS>` se añaden a
  `config.action_cable.allowed_request_origins` cuando la variable existe; el stream
  ya sigue autenticado por usuario y no cambió.

### SEC-015 — Prompts y salidas de IA en claro en base de datos (Informativo/Bajo)

- [ ] Pendiente — requiere decisión tuya.
- Archivo: `db/schema.rb:47-48` (`ai_requests.prompt`, `ai_requests.output`).
- Acción propuesta: cifrar en reposo (Active Record Encryption) o acotar la retención
  /redacción de estos campos. No se aplicó en esta fase porque los datos viejos en
  claro harían fallar su lectura si se activa el cifrado sin una estrategia de
  transición (o una limpieza de datos), y eso es una decisión de datos, no de código.
- Lo que necesito de ti: confirmar si el historial de prompts/salidas se conserva útil
  (¿se consulta `expense-evaluations`/`ai_summary` al depurar?) y si aceptas limpiar
  registros viejos o cifrar los nuevos y borrar el histórico.

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
| 2026-10-23 | SEC-004 | `set_category` de show con `Category.for_user` | `151ae95`, `d624924` (grafo) | CI run `39988051388` en verde |
| 2026-10-23 | SEC-005 | Validaciones de propiedad en template/rule/category parent | `7491a45`, `5852123` (grafo) | CI run `39992390240` en verde |
| 2026-10-23 | SEC-006, SEC-008, SEC-009, SEC-011, SEC-013 | Endurecimiento webhook/media/CSV/uploads; métricas sin datos | `d9e4446`, `0f14061` (grafo) | CI run `39995194991` en verde |
| 2026-10-23 | SEC-007 | Rate limits nativos + `RateLimitProxy` | `02b3b0e`, `d77fb95` (grafo) | CI runs `39997726167` y `39999729133` en verde |
| 2026-10-23 | Registro | Cierre del tracker tras CPI/hosts y pendientes marcados | commit del cierre | CI del push en verde |
| 2026-10-23 | SEC-010, SEC-012, SEC-014 | CSP activa; hosts/cable origen condicionales | `51e2d7b`, `da49731` (grafo) | CI run `39999729133` en verde |

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
