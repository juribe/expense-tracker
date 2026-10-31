# MCP server

Servidor MCP (Model Context Protocol) que permite a agentes externos consultar
y operar las finanzas de un usuario de Yogasto. El LLM interpreta el lenguaje
natural y construye argumentos estructurados; Rails valida y aplica las reglas
financieras existentes. El servidor no hace NLP ni llama a modelos de IA.

## Arquitectura

```text
Cliente MCP (Claude, ChatGPT, Inspector…)
        │  POST /mcp  (JSON-RPC, Bearer token)
        ▼
Mcp::EndpointController
  ├─ Mcp::Authentication        token → usuario + scopes
  ├─ Mcp::Current               identidad del request
  └─ Mcp::ServerFactory         servidor fast-mcp por request
        │
        ▼
app/lib/mcp/tools/...           argumentos + respuesta JSON
        │
        ▼
Servicios y modelos existentes
  Expenses::Create · Payments::CreateManual · Transfer · Budget · Goal · GoalAllocation
```

El endpoint es **stateless**: no usa sesiones, SSE ni estado en memoria, por lo
que funciona con varios workers de Puma. Cada request construye su propio
servidor y devuelve la respuesta JSON-RPC en el cuerpo HTTP.

## Instalación

```sh
bundle install
bin/rails db:migrate
```

Dependencia añadida: `fast-mcp ~> 1.6`. Se carga explícitamente en
`config/initializers/fast_mcp.rb` porque el gem publica `lib/fast_mcp.rb`.

## Endpoint

| Método | Ruta | Respuesta |
|---|---|---|
| `POST` | `/mcp` | JSON-RPC 2.0 |
| `GET` / `DELETE` | `/mcp` | `405` con error JSON-RPC `-32601` |

Cabeceras requeridas:

```http
Authorization: Bearer ygm_...
Content-Type: application/json
```

Ejemplo de handshake:

```sh
curl -s http://localhost:3000/mcp \
  -H "Authorization: Bearer $YOGASTO_MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```

Llamada a una tool:

```sh
curl -s http://localhost:3000/mcp \
  -H "Authorization: Bearer $YOGASTO_MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_financial_context","arguments":{"sections":["categories","money_sources"]}}}'
```

## Autenticación

Cada token pertenece a un usuario y tiene scopes `read` y `write`.

1. Inicia sesión en Yogasto.
2. Ve a **Configuración → Agentes de IA (MCP)** (`/settings/mcp`).
3. Crea un token y cópialo: se muestra una sola vez.
4. Revócalo desde la misma página cuando ya no lo necesites.

Reglas:

- El token se guarda como digest SHA-256; nunca en claro.
- Un token revocado o expirado deja de autenticar de inmediato.
- Los scopes determinan qué tools se registran: un token de lectura no ve ni
  puede invocar tools de escritura.
- El usuario **nunca** se toma de un argumento. No existe `user_id` en ninguna
  tool; el token decide a qué datos se accede.
- No se aceptan sesiones web ni cookies como credencial externa.

## Formato de respuesta

Éxito:

```json
{
  "success": true,
  "data": {
    "id": "expense_123",
    "amount": "85000.0",
    "date": "2026-10-30",
    "description": "Gasolina"
  }
}
```

Error:

```json
{
  "success": false,
  "error": {
    "code": "INVALID_MONEY_SOURCE",
    "message": "The selected money source is not available."
  }
}
```

Los montos se serializan como **strings decimales exactos** (`"85000.0"`) para
no perder precisión entre `BigDecimal` y el agente.

### Códigos de error estables

`UNAUTHENTICATED`, `FORBIDDEN_SCOPE`, `INVALID_ARGUMENT`, `INVALID_DATE_RANGE`,
`NOT_FOUND`, `INVALID_CATEGORY`, `INVALID_MONEY_SOURCE`, `INVALID_ACCOUNT`,
`INVALID_CREDIT_CARD`, `INVALID_DEBT`, `INVALID_POCKET`, `INVALID_BUDGET`,
`INVALID_GOAL`, `INSUFFICIENT_FUNDS`, `OPERATION_NOT_ALLOWED`,
`CONFLICT_DUPLICATE`, `INTERNAL_ERROR`.

No se devuelven stack traces ni rutas internas.

## Tools de consulta

| Tool | Argumentos principales |
|---|---|
| `get_financial_context` | `sections` (array o lista separada por comas) |
| `get_categories` | `category_type` (expense/income) |
| `get_money_sources` | `kind`, `active_only` |
| `get_expenses` | `start_date`, `end_date`, `category_id`, `money_source_id`, `limit`, `offset` |
| `get_expense` | `expense_id` |
| `get_incomes` | mismos filtros que `get_expenses` |
| `get_income` | `income_id` |
| `get_accounts` | `kind` |
| `get_account_balances` | — |
| `get_credit_cards` | — |
| `get_credit_card_details` | `credit_card_id` |
| `get_debts` | — |
| `get_debt_details` | `debt_id` |
| `get_pockets` | — |
| `get_pocket_details` | `pocket_id` |
| `get_budgets` | `month`, `start_date`, `end_date` |
| `get_budget_details` | `budget_id`, período |
| `get_budget_progress` | `budget_id`, período |
| `get_savings_goals` | `status` (active/archived/all) |
| `get_savings_goal_details` | `goal_id` |
| `get_monthly_report` | `month` o `start_date`/`end_date` |
| `get_expenses_by_category` | período |
| `get_income_vs_expenses` | período |

Las listas de movimientos usan por defecto el mes o ciclo financiero actual,
`limit` 25 (máximo 100) y `offset`. Nunca devuelven el historial completo.

## Tools de escritura

Todas requieren scope `write` y aceptan `idempotency_key` (UUID) cuando crean
registros.

| Tool | Argumentos |
|---|---|
| `create_expense` | `amount`, `date`, `category_id`, `money_source_id`, `description` |
| `update_expense` | `expense_id` + campos |
| `delete_expense` | `expense_id`, `confirm: true` |
| `create_income` | `amount`, `date`, `category_id`, `money_source_id`, `description` |
| `update_income` | `income_id` + campos |
| `create_transfer` | `amount`, `date`, `source_id`, `destination_id`, `description` |
| `create_credit_card_payment` | `amount`, `date`, `account_id`, `credit_card_id`, `description`, `category_id?`, componentes |
| `create_debt_payment` | `amount`, `date`, `debt_id`, `source_id`, `description`, `category_id?`, componentes |
| `create_pocket` | `name` |
| `update_pocket` | `pocket_id`, `name`, `active` |
| `allocate_to_pocket` | `pocket_id`, `amount`, `source_id`, `date` |
| `withdraw_from_pocket` | `pocket_id`, `amount`, `destination_id`, `date` |
| `create_budget` | `category_id`, `amount`, `period` |
| `update_budget` | `budget_id`, `amount`, `period`, `active` |
| `create_savings_goal` | `name`, `target_amount`, `pocket_id`, `target_date`, `category`, `priority` |
| `update_savings_goal` | `goal_id` + campos |
| `contribute_to_savings_goal` | `goal_id`, `amount`, `date`, `source_id?` |
| `withdraw_from_savings_goal` | `goal_id`, `amount`, `date` |

### Semántica financiera

- **Gastos**: usan `Expenses::Create` con `source: "manual"`, por lo que se
  mantiene la regla de saldo suficiente y el control de categorías. El origen
  MCP queda en la auditoría, no en el modelo financiero.
- **Transferencias**: usan el modelo `Transfer`; respetan deudas, bolsillos y
  reservas de metas.
- **Pagos**: usan `Payments::CreateManual`. El abono crea el gasto de la fuente
  de fondos y lo aplica a la deuda en una sola transacción. Si no se envían
  componentes, todo el pago reduce capital (mismo default del formulario web).
  La categoría por defecto es la de pagos de deuda (`categories.debt_payments`).
- **Bolsillos**: `allocate_to_pocket` y `withdraw_from_pocket` son `Transfer`.
  No son gastos ni ingresos.
- **Metas**: `contribute_to_savings_goal` crea un `GoalAllocation`. Con
  `source_id`, primero transfiere el dinero al bolsillo y luego lo reserva.
  `withdraw_from_savings_goal` libera la reserva; no saca dinero del bolsillo.
  Para sacar dinero real usa `withdraw_from_pocket`.
- **Presupuestos**: solo período `monthly`; la categoría debe ser de gasto y
  estar disponible para el usuario.

## Idempotencia y auditoría

- `McpIdempotencyRecord` guarda el resultado por usuario y `idempotency_key`.
  Reintentar con la misma clave devuelve el resultado original; usarla con
  argumentos distintos responde `CONFLICT_DUPLICATE`.
- El registro y la operación comparten transacción, de modo que dos reintentos
  concurrentes no crean dos movimientos.
- `McpToolInvocation` audita las tools de escritura: tool, usuario, token,
  estado, código de error, recurso afectado y **solo las claves** de los
  argumentos. Nunca guarda montos ni descripciones.

## Pruebas

```sh
bin/rails test test/models/mcp_access_token_test.rb \
               test/services/mcp \
               test/integration/mcp_endpoint_test.rb \
               test/integration/mcp_settings_test.rb \
               test/mcp
```

Cubren tokens, autenticación, protocolo, aislamiento entre usuarios, scopes,
todas las tools de lectura y escritura, idempotencia, rollback y auditoría.

## Limitaciones conocidas

1. **Protocolo**: fast-mcp 1.6.0 implementa MCP `2024-11-05` y su transporte
   nativo es HTTP+SSE con estado en memoria. Este proyecto usa un adaptador
   stateless (`POST /mcp`) para soportar varios workers. Clientes que exigen
   Streamable HTTP `2025-06-18` o superior pueden no conectar; para esos casos
   sería necesario migrar al SDK oficial `mcp` o esperar soporte upstream.
2. **OAuth 2.1**: no está implementado. La autenticación es por token personal
   revocable. El resolver está aislado para admitir más adelante un proveedor
   OAuth.
3. **Resources y Prompts**: fast-mcp 1.6.0 no implementa MCP Prompts y sus
   Resources no reciben headers ni contexto de request. Se posponen para no
   exponer datos entre usuarios.
4. **Rate limiting**: no hay throttling por token. Se recomienda añadirlo antes
   de una exposición pública.
5. **Moneda y zona horaria**: la aplicación usa `COP` y `America/Bogota` de forma
   global; no existe moneda ni zona horaria por usuario.
6. **Fechas de pago**: se derivan de `payment_due_day`; no se persiste una
   próxima fecha exacta.
7. El endpoint no sirve SSE ni notificaciones servidor→cliente.
8. **Retención**: `mcp_tool_invocations` y `mcp_idempotency_records` crecen sin
   limpieza automática; conviene programar una purga por antigüedad antes de un
   uso intensivo.
9. **CORS**: no se habilitó para clientes MCP que corren en el navegador; los
   clientes nativos y de servidor no lo necesitan.

## Archivos principales

```text
app/controllers/mcp/endpoint_controller.rb
app/controllers/mcp/settings_controller.rb
app/views/mcp/settings/show.html.erb
app/lib/mcp/
  application_tool.rb  authentication.rb  current.rb  http_transport.rb
  server_factory.rb    idempotency.rb     audit.rb    error.rb
  presenters/*.rb
  tools/{context,expenses,incomes,transfers,accounts,credit_cards,debts,pockets,budgets,savings_goals,reports}/*.rb
app/models/mcp_access_token.rb
app/models/mcp_idempotency_record.rb
app/models/mcp_tool_invocation.rb
config/initializers/fast_mcp.rb
db/migrate/*_create_mcp_*.rb
```
