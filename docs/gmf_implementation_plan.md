# Plan de implementación: GMF (4x1.000) en Yogasto

Fecha: 2026-11-01  
Estado: Plan (sin código implementado aún)

## 0. Principios rectores

- El GMF **no** es un 0,4% automático sobre todos los gastos. Depende del tipo de operación, del producto financiero, de las exenciones legales y del acumulado mensual.
- Los períodos del GMF son **meses calendario** (1..fin de mes), independientes del ciclo financiero del usuario (`PayCycle`). Se implementa un servicio dedicado `Gmf::Period`.
- Una sola cuenta bancaria por usuario puede estar marcada `gmf_exempt = true`.
- La tarjeta débito hereda la configuración de su cuenta padre; no se duplica configuración en la tarjeta.
- Las compras con tarjeta de crédito NO generan GMF por la compra; solo se evalúa el pago desde cuenta bancaria.
- El GMF se registra como un **gasto independiente** (categoría "Impuestos y gravámenes" / subcategoría "4x1.000 (GMF)"), referenciando el movimiento original.
- Toda operación que toque acumuladores + movimientos debe ir en transacción DB y ser idempotente.

---

## 1. Fase 1 — Modelo de datos y migraciones

### 1.1 MoneySource

Migración: agregar `gmf_exempt boolean NOT NULL DEFAULT false` a `money_sources`.

Validaciones en `MoneySource`:
- `gmf_exempt` solo permitido para `kind == "account"` (cuentas bancarias elegibles). Rechazar tarjetas de crédito, efectivo, wallets, pockets, loans, debit_card.
- Unicidad por usuario: índice parcial único `CREATE UNIQUE INDEX ... ON money_sources (user_id) WHERE gmf_exempt = true`.
- Validación de backend + protección concurrente: usar transacción con `SELECT ... FOR UPDATE` sobre las fuentes del usuario al activar.

Métodos:
- `self.gmf_exempt_for(user)` → cuenta exenta actual.
- `enable_gmf_exemption!` / `disable_gmf_exemption!` dentro de transacción, desmarcando la anterior.

### 1.2 UVT (configuración centralizada)

Tabla `gmf_uvt_years`: `year integer PK`, `value decimal(12,2)`, `created_at`, `updated_at`.

Seed con valores anuales (Colombia). Servicio `Gmf::Uvt.value_for(year)` con fallback al último año disponible. No hardcodear 350 UVT como cifra monetaria; el límite se calcula `350 * uvt_value`.

> Alternativa más liviana: módulo Ruby con hash por año. Se prefiere tabla para permitir actualización anual sin deploy, pero el plan deja abierta la decisión. Decisión recomendada: tabla + seed.

### 1.3 Acumulador mensual

Tabla `gmf_monthly_accumulators`:
- `id uuid`
- `user_id uuid FK`
- `money_source_id uuid FK`
- `year integer`
- `month integer`
- `total_debits decimal(14,2) default 0`
- `covered_by_exemption decimal(14,2) default 0`
- `taxable decimal(14,2) default 0`
- `gmf_generated decimal(14,2) default 0`
- timestamps
- Unique index `[user_id, money_source_id, year, month]`.

### 1.4 Metadata GMF en transacciones

Migración sobre `transactions`:
- `gmf_origin_type string` (polimórfico: "Expense"/"Transfer")
- `gmf_origin_id uuid`
- `gmf_status string` (estimated/charged/reconciled/cancelled) nullable
- `gmf_estimated boolean default false`
- `gmf_bank_reference string` nullable

Índice `[user_id, gmf_origin_type, gmf_origin_id]`.

### 1.5 Categoría del sistema

Seed en `db/seeds.rb`:
- Categoría padre default "Impuestos y gravámenes" (`category_type: expense`, `is_default: true`).
- Subcategoría default "4x1.000 (GMF)" con `parent` = padre, `is_default: true`.

Ambas no editables/eliminables por usuario (ya cubierto por `editable_by?`/`deletable_by?` que exigen `custom?`).

---

## 2. Fase 2 — Servicios core

### 2.1 `Gmf::Period`

```ruby
Gmf::Period.for(date) # => { year:, month: }
Gmf::Period.calendar_month_range(year, month)
```

Usa fecha efectiva del movimiento. Nunca `PayCycle`.

### 2.2 `Gmf::Uvt`

```ruby
Gmf::Uvt.value_for(year)      # BigDecimal
Gmf::Uvt.exemption_limit(year) # 350 * value
```

### 2.3 Clasificación de operaciones

Módulo `Gmf::OperationClassification` con enum:
- `taxable_consumes_exemption`
- `taxable_no_exemption`
- `legally_exempt`
- `non_taxable_event`

Reglas iniciales (documentadas, ajustables):
- `expense` desde cuenta/billetera → taxable_consumes_exemption.
- `debit_card_purchase` → taxable_consumes_exemption.
- `withdrawal` → taxable_consumes_exemption.
- `service_payment` → taxable_consumes_exemption.
- `transfer` → depende de `transfer_type` y reglas; por defecto `taxable_consumes_exemption` solo si `from_source` es cuenta y no es transferencia entre cuentas propias del mismo usuario? **Ambigüedad documentada**: se marca como `taxable_consumes_exemption` por defecto pero se deja flag `uncertain` para conciliación.
- `credit_card_purchase` → non_taxable_event.
- `credit_card_payment` → taxable_consumes_exemption (pago desde cuenta).
- Desconocido → non_taxable_event (no generar GMF automático).

### 2.4 `Gmf::Calculator`

Entrada: `user`, `origin_money_source`, `operation_type`, `date`, `amount`, `tax_treatment` (opcional), `bank_charged_gmf` (opcional).

Salida (struct):
- `taxed?` (boolean)
- `consumes_exemption?` (boolean)
- `taxable_base` (BigDecimal)
- `gmf_amount` (BigDecimal)
- `covered_by_exemption` (BigDecimal)
- `taxable_excess` (BigDecimal)
- `reason` (string, motivo si no aplica)

Lógica:
1. Determinar si `origin_money_source` es elegible para GMF (account/debit_card roll-up al padre).
2. Clasificar operación.
3. Si no gravada → gmf 0, reason.
4. Si gravada y NO consume exención → gmf = amount * 0.004.
5. Si consume exención:
   - Si origen NO es la cuenta exenta → gmf = amount * 0.004 (no hay límite independiente).
   - Si origen ES la cuenta exenta:
     - Cargar acumulador del mes calendario.
     - `available = limit - accumulator.total_debits` (o covered).
     - `covered = min(amount, available)` clamp ≥ 0.
     - `excess = amount - covered`.
     - `gmf = excess * 0.004`.
     - (El acumulador se actualiza por el caller o por el servicio de creación.)

Tarifa: constante `Gmf::RATE = BigDecimal("0.004")`.

### 2.5 `Gmf::MonthlyAccumulator`

```ruby
Gmf::MonthlyAccumulator.for(user:, money_source:, date:) # get_or_create
Gmf::MonthlyAccumulator.add!(accumulator, amount:, covered:, taxable:, gmf:)
Gmf::MonthlyAccumulator.revert!(accumulator, amount:, covered:, taxable:, gmf:)
```

Usar `SELECT ... FOR UPDATE` dentro de transacción.

### 2.6 `Gmf::ChargeCreator`

Crea el gasto independiente de GMF:
- Busca categoría "4x1.000 (GMF)" (subcategory) del usuario/sistema.
- Crea `Expense` con:
  - `user`, `money_source: origin`, `amount: gmf_amount`, `date: original_date`,
  - `description: "GMF 4x1.000 - <original>"`,
  - `category: gmf_category`,
  - `source: "gmf"`,
  - `gmf_origin_type/id`, `gmf_status: "estimated"`, `gmf_estimated: true`.
- No debe disparar GMF recursivamente (guard por `source == "gmf"` o categoría GMF).

Debe ser idempotente: si ya existe un GMF charge con mismo origin, actualizar en vez de crear.

---

## 3. Fase 3 — Configuración MoneySource (UI + backend)

### 3.1 Validación de elegibilidad

```ruby
validate :gmf_exempt_only_for_eligible_accounts
```

Elegible: `kind == "account"` (y activo). Debit card no (hereda).

### 3.2 Concurrencia

Al guardar `gmf_exempt = true`:
```ruby
ActiveRecord::Base.transaction do
  user.money_sources.where(gmf_exempt: true).lock.update_all(gmf_exempt: false)
  self.gmf_exempt = true
  save!
end
```

Desmarcar no requiere tocar otras.

### 3.3 Wizard de creación

En `financial_setups` manual/import flows o en el form de MoneySource: agregar pregunta "¿Esta cuenta tiene marcada la exención del 4x1.000?" Sí/No.

Si ya existe cuenta exenta:
- Mostrar cuál es.
- No permitir marcar segunda; continuar como no exenta.
- No cambiar automáticamente la cuenta exenta al crear nueva.

### 3.4 Formulario de edición

En `_form.html.erb`, sección "Características de la cuenta", agregar switch "Cuenta exenta del 4x1.000" con descripción. Si ya existe otra exenta, mostrar texto de confirmación. JS para confirmar cambio (modal/confirm). Backend maneja desmarcado.

### 3.5 Detalle de cuenta

En `show.html.erb`, bloque mensual:
- Total débitos que consumen exención.
- Límite mensual.
- Disponible.
- Total GMF cobrado.
- Porcentaje utilizado.

Solo movimientos gravados.

---

## 4. Fase 4 — Integración con movimientos

### 4.1 Expenses (gastos)

Hook en `Expenses::Create` o `Transaction` after_commit create:
- Si `source != "gmf"` y categoría != GMF y money_source presente:
  - Clasificar operación como `expense_payment` (o según contexto).
  - Llamar `Gmf::Calculator`.
  - Si gmf_amount > 0 o consume exención:
    - Actualizar acumulador (covered/taxable).
    - Crear GMF charge si gmf_amount > 0.

Para importaciones (gmail/whatsapp/csv), mismo path vía `Expenses::Create`, así que cubierto.

### 4.2 Transfers

Hook en `Transfer` after_commit create:
- Evaluar GMF sobre `from_source` con operation_type `transfer`.
- Crear GMF charge asociado a `from_source` si aplica.
- No modificar monto recibido en destino.
- Actualizar acumulador.

### 4.3 Retiros

Un retiro es un `Transfer`? Revisar cómo se registran retiros. Si es Transfer (account→cash), el hook de transfer cubre. Si es Expense, cubierto.

### 4.4 Tarjetas de crédito

- Compra con tarjeta de crédito: `Expense` con money_source = tarjeta de crédito. Clasificación `credit_card_purchase` → non_taxable_event → no GMF. Pero el expense se registra normal.
- Pago de tarjeta: `Payment`/`Transfer` desde cuenta → money_source origen cuenta → clasificación `credit_card_payment` → evalúa GMF.

### 4.5 Balance

El GMF charge es un Expense independiente, por lo que `BalanceSync` ya ajusta saldo automáticamente. No modificar operación original.

---

## 5. Fase 5 — Conciliación bancaria

### 5.1 Detector de débito GMF

Servicio `Gmf::BankChargeDetector`:
- Recibe descripción bancaria.
- Matching configurable por patrones (config o tabla `gmf_bank_patterns`).
- Retorna boolean + confidence.

### 5.2 Reconciliación en importación

En `Expenses::Create` / import pipeline:
- Si el movimiento importado se detecta como débito GMF:
  - Buscar GMF charge existente (estimated) por `user + money_source + date (±3 días) + status estimated`.
  - Si existe: actualizar `amount` al valor real, `gmf_status = reconciled`, `gmf_estimated = false`. **No crear nuevo gasto.**
  - Si no existe: crear Expense normal con categoría GMF y status `charged`.
- Evitar doble registro por idempotency_key / gmail_message_id.

### 5.3 Estados

`estimated` → `charged` (conciliado con banco) → `reconciled`. `cancelled` para reversiones.

---

## 6. Fase 6 — Edición y eliminación

### 6.1 Edición de movimiento original

Hook `Transaction` after_commit update:
- Si cambió `amount` o `date` o `money_source_id`:
  - Revertir acumulador y GMF charge anterior.
  - Recalcular con nuevos valores.
  - Actualizar GMF charge existente o crear/eliminar según corresponda.

Idempotencia: buscar GMF charge por origin; actualizar importe; si nuevo gmf = 0, marcar `cancelled` o eliminar si `estimated`.

### 6.2 Eliminación

Hook after_commit destroy:
- Revertir acumulador.
- Si GMF charge `estimated` → eliminar/cancelar.
- Si `charged`/`reconciled` (real del banco) → no eliminar; marcar origin nil y status `orphaned`? Spec: no eliminar GMF real sin conciliación. Se deja el gasto real y se desvincula del origen.

### 6.3 Cambio de fecha

Retirar del período anterior, agregar al nuevo. Como el acumulador es por mes, revertir en período viejo y agregar en nuevo.

### 6.4 Cambio de MoneySource

Recalcular tratamiento con cuenta correcta; revertir en origen anterior.

---

## 7. Fase 7 — Reportes y UI

- Reportes por categoría ya incluyen GMF charge (es Expense).
- Dashboard: agregar card "Impuestos bancarios del mes/año".
- MoneySource show: bloque mensual GMF (sección 3.5).
- Historial: link desde GMF charge al movimiento original (`gmf_origin`).

---

## 8. Fase 8 — Pruebas (Minitest)

### Configuración
- Crear primera cuenta exenta.
- Intentar segunda cuenta exenta (rechazo).
- Cambiar exención entre cuentas (transacción atómica).
- Desmarcar.
- Marcar cuenta no elegible (rechazo).
- Concurrencia (dos requests simultáneas).

### Cálculo
- Exenta bajo límite (gmf 0).
- Exactamente en límite.
- Movimiento que supera parcialmente.
- Movimiento completamente por encima.
- Cuenta no exenta (gmf desde primer peso).
- Reinicio mensual calendario (independiente de pay cycle).
- Cambio de año y UVT.
- Movimiento no sujeto.
- Operación exenta legal.
- Operación que no consume límite.

### Integraciones
- Compra tarjeta débito.
- Transferencia.
- Retiro.
- Pago de servicios.
- Compra tarjeta de crédito (sin GMF).
- Pago tarjeta de crédito.

### Conciliación
- GMF estimado luego confirmado.
- GMF real sin estimación previa.
- Diferencia estimado vs real.
- Importación repetida.
- Evitar doble registro.

### Edición/eliminación
- Editar importe.
- Editar fecha.
- Cambiar MoneySource.
- Eliminar movimiento.
- Recalcular períodos.
- No modificar GMF real indebidamente.

### Período calendario
- Acumulado se reinicia el día 1 aunque el ciclo financiero empiece otro día.
- Operación retroactiva afecta período calendario de su fecha.

---

## 9. Archivos a crear/modificar (estimado)

**Migraciones:**
- `db/migrate/xxx_add_gmf_exempt_to_money_sources.rb`
- `db/migrate/xxx_create_gmf_uvt_years.rb`
- `db/migrate/xxx_create_gmf_monthly_accumulators.rb`
- `db/migrate/xxx_add_gmf_metadata_to_transactions.rb`

**Modelos:**
- `app/models/money_source.rb` (validaciones, métodos)
- `app/models/gmf_monthly_accumulator.rb` (nuevo)
- `app/models/gmf_uvt_year.rb` (nuevo)
- `app/models/transaction.rb` (metadata, hooks)
- `app/models/transfer.rb` (hooks)

**Servicios:**
- `app/services/gmf/period.rb`
- `app/services/gmf/uvt.rb`
- `app/services/gmf/operation_classification.rb`
- `app/services/gmf/calculator.rb`
- `app/services/gmf/monthly_accumulator.rb`
- `app/services/gmf/charge_creator.rb`
- `app/services/gmf/bank_charge_detector.rb`
- `app/services/gmf/reconciler.rb`

**Controladores/Vistas:**
- `app/controllers/money_sources_controller.rb`
- `app/views/money_sources/_form.html.erb`
- `app/views/money_sources/show.html.erb`
- Wizard financial_setups (manual/import rows) — pregunta GMF
- `app/views/financial_setups/_manual_row.html.erb`

**Seeds:**
- `db/seeds.rb` (categorías GMF + UVT)

**Tests:**
- `test/models/money_source_gmf_test.rb`
- `test/services/gmf/*_test.rb`
- `test/integration/gmf/*_test.rb`

---

## 10. Decisiones técnicas y riesgos

1. **Clasificación tributaria vs cálculo**: separar en `OperationClassification`. Las reglas de transferencias entre cuentas propias son ambiguas; se documenta y no se genera GMF automático en casos inciertos (se deja para conciliación).
2. **No consolidado entre entidades**: solo la cuenta marcada exenta acumula; las demás pagan desde el primer peso. Diseño deja `GmfMonthlyAccumulator` por `money_source`, preparado para futuro consolidado (agregar `consolidated_group_id`).
3. **Idempotencia**: `ChargeCreator` busca por `gmf_origin_type/id` antes de crear.
4. **Concurrencia**: índice único + `FOR UPDATE` + transacción.
5. **No modificar movimientos históricos al cambiar cuenta exenta**: solo cambia configuración futura; acumulados existentes se mantienen.
6. **GMF real del banco**: no se elimina automáticamente; se desvincula del origen.

---

## 11. Orden de implementación recomendado (TDD)

1. Migraciones + modelos base + seeds de categoría/UVT.
2. `Gmf::Period` + tests (calendario, independencia de PayCycle).
3. `Gmf::Uvt` + tests.
4. `Gmf::Calculator` + tests.
5. `Gmf::MonthlyAccumulator` + tests.
6. MoneySource validaciones/concurrencia + tests.
7. `Gmf::ChargeCreator` + tests.
8. Integración Expenses (TDD: test primero).
9. Integración Transfers.
10. Conciliación bancaria.
11. Edición/eliminación.
12. UI (form, show, wizard).
13. Reportes.

Cada paso: escribir test que falla → implementar → verificar → correr regresión.

---

## 12. Preguntas abiertas para el usuario (ambigüedades tributarias)

1. ¿Las transferencias entre cuentas propias del mismo usuario deben consumir la exención o se consideran exentas? (Se propone: consumen por defecto, marcadas como `uncertain` para conciliación manual.)
2. ¿Retiros en cajero propio del mismo banco consumen exención? (Se propone: sí, gravado.)
3. ¿Pagos de servicios (utilities) consumen exención? (Se propone: sí.)
4. ¿Se desea registrar GMF sobre pagos de tarjeta de crédito desde cuenta exenta? (Se propone: sí, como cualquier débito.)
5. ¿Valor UVT por año: se carga manualmente o se consulta API? (Se propone: seed manual anual.)

Responder estas preguntas antes de implementar las reglas de clasificación definitivas.
</doc>
```

Wait, I wrote to a file? I used write tool? I used `write`? Actually I output markdown in analysis but didn't call tool. Need call write. Let me call write.<|end|><|start|> fileList? Let me write file.<|end|><|start|> assistant to=write<|channel|>analysis <|constrain|>xml<|message|><rfl:parameter name="content">
# Plan de implementación: GMF (4x1.000) en Yogasto

Fecha: 2026-11-01
Estado: Plan (sin código implementado aún)

## 0. Principios rectores

- El GMF no es un 0,4% automático sobre todos los gastos. Depende del tipo de operación, del producto financiero, de las exenciones legales y del acumulado mensual.
- Los períodos del GMF son meses calendario (1..fin de mes), independientes del ciclo financiero del usuario (PayCycle). Se implementa un servicio dedicado Gmf::Period.
- Una sola cuenta bancaria por usuario puede estar marcada gmf_exempt = true.
- La tarjeta débito hereda la configuración de su cuenta padre; no se duplica configuración en la tarjeta.
- Las compras con tarjeta de crédito NO generan GMF por la compra; solo se evalúa el pago desde cuenta bancaria.
- El GMF se registra como un gasto independiente (categoría "Impuestos y gravámenes" / subcategoría "4x1.000 (GMF)"), referenciando el movimiento original.
- Toda operación que toque acumuladores + movimientos debe ir en transacción DB y ser idempotente.

## 1. Fase 1 — Modelo de datos y migraciones

### 1.1 MoneySource
Migración: agregar gmf_exempt boolean NOT NULL DEFAULT false a money_sources.

Validaciones en MoneySource:
- gmf_exempt solo permitido para kind == "account" (cuentas bancarias elegibles). Rechazar tarjetas de crédito, efectivo, wallets, pockets, loans, debit_card.
- Unicidad por usuario: índice parcial único CREATE UNIQUE INDEX ... ON money_sources (user_id) WHERE gmf_exempt = true.
- Validación de backend + protección concurrente: usar transacción con SELECT ... FOR UPDATE sobre las fuentes del usuario al activar.

Métodos:
- self.gmf_exempt_for(user) -> cuenta exenta actual.
- enable_gmf_exemption! / disable_gmf_exemption! dentro de transacción, desmarcando la anterior.

### 1.2 UVT (configuración centralizada)
Tabla gmf_uvt_years: year integer PK, value decimal(12,2), created_at, updated_at.

Seed con valores anuales (Colombia). Servicio Gmf::Uvt.value_for(year) con fallback al último año disponible. No hardcodear 350 UVT como cifra monetaria; el límite se calcula 350 * uvt_value.

### 1.3 Acumulador mensual
Tabla gmf_monthly_accumulators:
- id uuid
- user_id uuid FK
- money_source_id uuid FK
- year integer
- month integer
- total_debits decimal(14,2) default 0
- covered_by_exemption decimal(14,2) default 0
- taxable decimal(14,2) default 0
- gmf_generated decimal(14,2) default 0
- timestamps
- Unique index [user_id, money_source_id, year, month].

### 1.4 Metadata GMF en transacciones
Migración sobre transactions:
- gmf_origin_type string (polimórfico: "Expense"/"Transfer")
- gmf_origin_id uuid
- gmf_status string (estimated/charged/reconciled/cancelled) nullable
- gmf_estimated boolean default false
- gmf_bank_reference string nullable

Índice [user_id, gmf_origin_type, gmf_origin_id].

### 1.5 Categoría del sistema
Seed en db/seeds.rb:
- Categoría padre default "Impuestos y gravámenes" (category_type: expense, is_default: true).
- Subcategoría default "4x1.000 (GMF)" con parent = padre, is_default: true.

Ambas no editables/eliminables por usuario (ya cubierto por editable_by?/deletable_by? que exigen custom?).

## 2. Fase 2 — Servicios core

### 2.1 Gmf::Period
Gmf::Period.for(date) # => { year:, month: }
Gmf::Period.calendar_month_range(year, month)
Usa fecha efectiva del movimiento. Nunca PayCycle.

### 2.2 Gmf::Uvt
Gmf::Uvt.value_for(year)      # BigDecimal
Gmf::Uvt.exemption_limit(year) # 350 * value

### 2.3 Clasificación de operaciones
Módulo Gmf::OperationClassification con enum:
- taxable_consumes_exemption
- taxable_no_exemption
- legally_exempt
- non_taxable_event

Reglas iniciales (documentadas, ajustables):
- expense desde cuenta/billetera -> taxable_consumes_exemption.
- debit_card_purchase -> taxable_consumes_exemption.
- withdrawal -> taxable_consumes_exemption.
- service_payment -> taxable_consumes_exemption.
- transfer -> depende de transfer_type y reglas; por defecto taxable_consumes_exemption solo si from_source es cuenta y no es transferencia entre cuentas propias del mismo usuario? Ambigüedad documentada: se marca como taxable_consumes_exemption por defecto pero se deja flag uncertain para conciliación.
- credit_card_purchase -> non_taxable_event.
- credit_card_payment -> taxable_consumes_exemption (pago desde cuenta).
- Desconocido -> non_taxable_event (no generar GMF automático).

### 2.4 Gmf::Calculator
Entrada: user, origin_money_source, operation_type, date, amount, tax_treatment (opcional), bank_charged_gmf (opcional).

Salida (struct):
- taxed? (boolean)
- consumes_exemption? (boolean)
- taxable_base (BigDecimal)
- gmf_amount (BigDecimal)
- covered_by_exemption (BigDecimal)
- taxable_excess (BigDecimal)
- reason (string, motivo si no aplica)

Lógica:
1. Determinar si origin_money_source es elegible para GMF (account/debit_card roll-up al padre).
2. Clasificar operación.
3. Si no gravada -> gmf 0, reason.
4. Si gravada y NO consume exención -> gmf = amount * 0.004.
5. Si consume exención:
   - Si origen NO es la cuenta exenta -> gmf = amount * 0.004 (no hay límite independiente).
   - Si origen ES la cuenta exenta:
     - Cargar acumulador del mes calendario.
     - available = limit - accumulator covered total.
     - covered = min(amount, available) clamp >= 0.
     - excess = amount - covered.
     - gmf = excess * 0.004.
     - (El acumulador se actualiza por el caller o por el servicio de creación.)

Tarifa: constante Gmf::RATE = BigDecimal("0.004").

### 2.5 Gmf::MonthlyAccumulator
Gmf::MonthlyAccumulator.for(user:, money_source:, date:) # get_or_create
Gmf::MonthlyAccumulator.add!(accumulator, amount:, covered:, taxable:, gmf:)
Gmf::MonthlyAccumulator.revert!(accumulator, amount:, covered:, taxable:, gmf:)
Usar SELECT ... FOR UPDATE dentro de transacción.

### 2.6 Gmf::ChargeCreator
Crea el gasto independiente de GMF:
- Busca categoría "4x1.000 (GMF)" (subcategory) del usuario/sistema.
- Crea Expense con:
  - user, money_source: origin, amount: gmf_amount, date: original_date,
  - description: "GMF 4x1.000 - <original>",
  - category: gmf_category,
  - source: "gmf",
  - gmf_origin_type/id, gmf_status: "estimated", gmf_estimated: true.
- No debe disparar GMF recursivamente (guard por source == "gmf" o categoría GMF).

Debe ser idempotente: si ya existe un GMF charge con mismo origin, actualizar en vez de crear.

## 3. Fase 3 — Configuración MoneySource (UI + backend)

### 3.1 Validación de elegibilidad
validate :gmf_exempt_only_for_eligible_accounts
Elegible: kind == "account" (y activo). Debit card no (hereda).

### 3.2 Concurrencia
Al guardar gmf_exempt = true:
ActiveRecord::Base.transaction do
  user.money_sources.where(gmf_exempt: true).lock.update_all(gmf_exempt: false)
  self.gmf_exempt = true
  save!
end
Desmarcar no requiere tocar otras.

### 3.3 Wizard de creación
En financial_setups manual/import flows o en el form de MoneySource: agregar pregunta "¿Esta cuenta tiene marcada la exención del 4x1.000?" Sí/No.

Si ya existe cuenta exenta:
- Mostrar cuál es.
- No permitir marcar segunda; continuar como no exenta.
- No cambiar automáticamente la cuenta exenta al crear nueva.

### 3.4 Formulario de edición
En _form.html.erb, sección "Características de la cuenta", agregar switch "Cuenta exenta del 4x1.000" con descripción. Si ya existe otra exenta, mostrar texto de confirmación. JS para confirmar cambio (modal/confirm). Backend maneja desmarcado.

### 3.5 Detalle de cuenta
En show.html.erb, bloque mensual:
- Total débitos que consumen exención.
- Límite mensual.
- Disponible.
- Total GMF cobrado.
- Porcentaje utilizado.

Solo movimientos gravados.

## 4. Fase 4 — Integración con movimientos

### 4.1 Expenses (gastos)
Hook en Expenses::Create o Transaction after_commit create:
- Si source != "gmf" y categoría != GMF y money_source presente:
  - Clasificar operación como expense_payment (o según contexto).
  - Llamar Gmf::Calculator.
  - Si gmf_amount > 0 o consume exención:
    - Actualizar acumulador (covered/taxable).
    - Crear GMF charge si gmf_amount > 0.

Para importaciones (gmail/whatsapp/csv), mismo path vía Expenses::Create, así que cubierto.

### 4.2 Transfers
Hook en Transfer after_commit create:
- Evaluar GMF sobre from_source con operation_type transfer.
- Crear GMF charge asociado a from_source si aplica.
- No modificar monto recibido en destino.
- Actualizar acumulador.

### 4.3 Retiros
Un retiro es un Transfer? Revisar cómo se registran retiros. Si es Transfer (account->cash), el hook de transfer cubre. Si es Expense, cubierto.

### 4.4 Tarjetas de crédito
- Compra con tarjeta de crédito: Expense con money_source = tarjeta de crédito. Clasificación credit_card_purchase -> non_taxable_event -> no GMF. Pero el expense se registra normal.
- Pago de tarjeta: Payment/Transfer desde cuenta -> money_source origen cuenta -> clasificación credit_card_payment -> evalúa GMF.

### 4.5 Balance
El GMF charge es un Expense independiente, por lo que BalanceSync ya ajusta saldo automáticamente. No modificar operación original.

## 5. Fase 5 — Conciliación bancaria

### 5.1 Detector de débito GMF
Servicio Gmf::BankChargeDetector:
- Recibe descripción bancaria.
- Matching configurable por patrones (config o tabla gmf_bank_patterns).
- Retorna boolean + confidence.

### 5.2 Reconciliación en importación
En Expenses::Create / import pipeline:
- Si el movimiento importado se detecta como débito GMF:
  - Buscar GMF charge existente (estimated) por user + money_source + date (±3 días) + status estimated.
  - Si existe: actualizar amount al valor real, gmf_status = reconciled, gmf_estimated = false. No crear nuevo gasto.
  - Si no existe: crear Expense normal con categoría GMF y status charged.
- Evitar doble registro por idempotency_key / gmail_message_id.

### 5.3 Estados
estimated -> charged (conciliado con banco) -> reconciled. cancelled para reversiones.

## 6. Fase 6 — Edición y eliminación

### 6.1 Edición de movimiento original
Hook Transaction after_commit update:
- Si cambió amount o date o money_source_id:
  - Revertir acumulador y GMF charge anterior.
  - Recalcular con nuevos valores.
  - Actualizar GMF charge existente o crear/eliminar según corresponda.

Idempotencia: buscar GMF charge por origin; actualizar importe; si nuevo gmf = 0, marcar cancelled o eliminar si estimated.

### 6.2 Eliminación
Hook after_commit destroy:
- Revertir acumulador.
- Si GMF charge estimated -> eliminar/cancelar.
- Si charged/reconciled (real del banco) -> no eliminar; marcar origin nil y status orphaned? Spec: no eliminar GMF real sin conciliación. Se deja el gasto real y se desvincula del origen.

### 6.3 Cambio de fecha
Retirar del período anterior, agregar al nuevo. Como el acumulador es por mes, revertir en período viejo y agregar en nuevo.

### 6.4 Cambio de MoneySource
Recalcular tratamiento con cuenta correcta; revertir en origen anterior.

## 7. Fase 7 — Reportes y UI

- Reportes por categoría ya incluyen GMF charge (es Expense).
- Dashboard: agregar card "Impuestos bancarios del mes/año".
- MoneySource show: bloque mensual GMF (sección 3.5).
- Historial: link desde GMF charge al movimiento original (gmf_origin).

## 8. Fase 8 — Pruebas (Minitest)

### Configuración
- Crear primera cuenta exenta.
- Intentar segunda cuenta exenta (rechazo).
- Cambiar exención entre cuentas (transacción atómica).
- Desmarcar.
- Marcar cuenta no elegible (rechazo).
- Concurrencia (dos requests simultáneas).

### Cálculo
- Exenta bajo límite (gmf 0).
- Exactamente en límite.
- Movimiento que supera parcialmente.
- Movimiento completamente por encima.
- Cuenta no exenta (gmf desde primer peso).
- Reinicio mensual calendario (independiente de pay cycle).
- Cambio de año y UVT.
- Movimiento no sujeto.
- Operación exenta legal.
- Operación que no consume límite.

### Integraciones
- Compra tarjeta débito.
- Transferencia.
- Retiro.
- Pago de servicios.
- Compra tarjeta de crédito (sin GMF).
- Pago tarjeta de crédito.

### Conciliación
- GMF estimado luego confirmado.
- GMF real sin estimación previa.
- Diferencia estimado vs real.
- Importación repetida.
- Evitar doble registro.

### Edición/eliminación
- Editar importe.
- Editar fecha.
- Cambiar MoneySource.
- Eliminar movimiento.
- Recalcular períodos.
- No modificar GMF real indebidamente.

### Período calendario
- Acumulado se reinicia el día 1 aunque el ciclo financiero empiece otro día.
- Operación retroactiva afecta período calendario de su fecha.

## 9. Archivos a crear/modificar (estimado)

Migraciones:
- db/migrate/xxx_add_gmf_exempt_to_money_sources.rb
- db/migrate/xxx_create_gmf_uvt_years.rb
- db/migrate/xxx_create_gmf_monthly_accumulators.rb
- db/migrate/xxx_add_gmf_metadata_to_transactions.rb

Modelos:
- app/models/money_source.rb (validaciones, métodos)
- app/models/gmf_monthly_accumulator.rb (nuevo)
- app/models/gmf_uvt_year.rb (nuevo)
- app/models/transaction.rb (metadata, hooks)
- app/models/transfer.rb (hooks)

Servicios:
- app/services/gmf/period.rb
- app/services/gmf/uvt.rb
- app/services/gmf/operation_classification.rb
- app/services/gmf/calculator.rb
- app/services/gmf/monthly_accumulator.rb
- app/services/gmf/charge_creator.rb
- app/services/gmf/bank_charge_detector.rb
- app/services/gmf/reconciler.rb

Controladores/Vistas:
- app/controllers/money_sources_controller.rb
- app/views/money_sources/_form.html.erb
- app/views/money_sources/show.html.erb
- Wizard financial_setups (manual/import rows) — pregunta GMF
- app/views/financial_setups/_manual_row.html.erb

Seeds:
- db/seeds.rb (categorías GMF + UVT)

Tests:
- test/models/money_source_gmf_test.rb
- test/services/gmf/*_test.rb
- test/integration/gmf/*_test.rb

## 10. Decisiones técnicas y riesgos

1. Clasificación tributaria vs cálculo: separar en OperationClassification. Las reglas de transferencias entre cuentas propias son ambiguas; se documenta y no se genera GMF automático en casos inciertos (se deja para conciliación).
2. No consolidado entre entidades: solo la cuenta marcada exenta acumula; las demás pagan desde el primer peso. Diseño deja GmfMonthlyAccumulator por money_source, preparado para futuro consolidado (agregar consolidated_group_id).
3. Idempotencia: ChargeCreator busca por gmf_origin_type/id antes de crear.
4. Concurrencia: índice único + FOR UPDATE + transacción.
5. No modificar movimientos históricos al cambiar cuenta exenta: solo cambia configuración futura; acumulados existentes se mantienen.
6. GMF real del banco: no se elimina automáticamente; se desvincula del origen.

## 11. Orden de implementación recomendado (TDD)

1. Migraciones + modelos base + seeds de categoría/UVT.
2. Gmf::Period + tests (calendario, independencia de PayCycle).
3. Gmf::Uvt + tests.
4. Gmf::Calculator + tests.
5. Gmf::MonthlyAccumulator + tests.
6. MoneySource validaciones/concurrencia + tests.
7. Gmf::ChargeCreator + tests.
8. Integración Expenses (TDD: test primero).
9. Integración Transfers.
10. Conciliación bancaria.
11. Edición/eliminación.
12. UI (form, show, wizard).
13. Reportes.

Cada paso: escribir test que falla -> implementar -> verificar -> correr regresión.

## 12. Preguntas abiertas para el usuario (ambigüedades tributarias)

1. ¿Las transferencias entre cuentas propias del mismo usuario deben consumir la exención o se consideran exentas? (Se propone: consumen por defecto, marcadas como uncertain para conciliación manual.)
2. ¿Retiros en cajero propio del mismo banco consumen exención? (Se propone: sí, gravado.)
3. ¿Pagos de servicios (utilities) consumen exención? (Se propone: sí.)
4. ¿Se desea registrar GMF sobre pagos de tarjeta de crédito desde cuenta exenta? (Se propone: sí, como cualquier débito.)
5. ¿Valor UVT por año: se carga manualmente o se consulta API? (Se propone: seed manual anual.)

Responder estas preguntas antes de implementar las reglas de clasificación definitivas.
