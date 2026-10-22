# Plan: Email de tarjeta Visa Infinite se asigna a la cuenta de ahorros

## Causa raíz (confirmada reproduciendo el match en BD)

Email real del 21/oct ("DiDi CO Food", $35.000) → `SourceRecognition::Matcher` devolvió **"Cuenta de Ahorros"** en vez de la tarjeta:

```
scores=[["Tarjeta Visa Infinite", 4], ["Cuenta de Ahorros", 7], ["Lifemiles", 1]]
```

- El remitente `davibankinforma@davibank.com` y el dominio `davibank.com` son identificadores **del seed del grupo Davibank (la cuenta)** → sender=3 + domain=3 + keyword "davibank"=1 = 7.
- La tarjeta Visa Infinite solo tiene keywords de producto ("infinite", "tarjeta Visa Infinite", "davibank") = 4.
- El zeroing de señales de banco (`institution_ambiguous?`) solo se activa cuando **≥2 grupos de bancos distintos** matchean a nivel de institución; aquí 3 productos del MISMO banco están configurados y el seed concentra las señales de banco, por lo que nunca se detecta la ambigüedad y el boilerplate del banco decide por la cuenta.
- Contradice el diseño documentado en `app/services/source_recognition/matcher.rb:19-24` ("Institution signals identify the BANK, not the product").

Defecto menor adicional: el keyword "davibank" que el usuario **dismissed** en Lifemiles aún puntúa (el matcher descarta `suggested?` pero no `dismissed`).

## Cambios

### 1. `app/services/source_recognition/matcher.rb`

**`institution_ambiguous?`** — las señales de banco (sender/domain/subject/header) no deciden qué producto pagó cuando:
- ≥2 grupos de bancos distintos matchean a nivel de banco (regla actual, intacta), o
- el grupo matcheado tiene **≥2 miembros configurados** (cuenta + tarjetas del mismo banco): la evidencia de banco es compartida y solo la evidencia de producto (keywords, last-four anclado) elige al ganador; sin evidencia de producto el resultado queda ambiguo (Array → va a revisión/candidatos), según la semántia ya documentada.

Implementación:
```ruby
matched_groups = bank_groups.values.select do |group|
  group[:members].select(&:recognition_configured?).any? { |s| institution_match?(s) }
end
@institution_ambiguous = matched_groups.size >= 2 ||
  matched_groups.any? { |g| g[:members].count(&:recognition_configured?) >= 2 }
```

**`per_source_score` / `institution_match?` / `shared_bank_evidence`** — excluir también `dismissed?` además de `suggested?`.

### 2. Efecto esperado con los datos del usuario

- Email de tarjeta: cuenta=1 (kw davibank), Visa=3-4 → **Visa** gana.
- Email de débito/cuenta: la cuenta gana igual por sus keywords de producto ("tarjeta clasica", 7273) o keywords propias; si el body no tiene evidencia de producto → ambiguo → revisión (más seguro que asignar mal).
- Grupos con un solo miembro configurado: comportamiento intacto (el seed sigue ganando con su sender).

### 3. Los dos gastos mal asignados (35.000 y 36.500 del 21/oct)

- Se reasignan a mano desde la UI (o edición del gasto); el fix evita futuros casos. No hay tarea de reescritura automática.

## TDD

1. `test/services/source_recognition/matcher_test.rb` — tests nuevos (rojo primero):
   - seed con sender/domain del banco + hermana tarjeta con keywords de producto → gana la tarjeta (caso DiDi).
   - identificador `dismissed` no puntúa (consulta single winner vs empate por dismissed).
   - la cuenta sigue asignándose cuando el body no evidencia tarjeta (sin regresión).
2. Ejecutar: `bin/rails test test/services/source_recognition`.
3. Implementar y volver a ejecutar.
4. Regresión: `test/services/expenses/money_source_detection_test.rb`, `test/services/gmail/*`, suite completa `bin/rails test`, rubocop.
5. Playwright no aplica (lógica server-side).
6. `graphify update .` al final.

## Riesgos / decisiones

- Con ≥2 productos configurados en un banco, un email sin ninguna keyword de producto ya no se auto-asigna al seed: queda ambiguo → candidato a revisión. Trade-off aceptado por el diseño documentado (asignar mal es peor que pedir revisión).
- Los emails cuyo body dice "tarjeta Clásica"/últimos dígitos siguen resolviendo por producto.
