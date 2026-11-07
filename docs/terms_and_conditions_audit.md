# Auditoría de los Términos y condiciones

Fecha de revisión: 7 de noviembre de 2026.

Este informe es interno. Recoge la evidencia usada para reescribir los términos
públicos, las contradicciones encontradas frente al documento anterior y los
puntos que requieren validación legal o una decisión del responsable. No debe
publicarse en `/terminos-y-condiciones` ni sustituye una revisión jurídica.

## Alcance y método

- Se revisó la semilla `db/seeds/terms_and_conditions.rb`, el contenido de
  Maglev y la página pública.
- Se contrastaron precios, periodo de prueba, planes, cierre de cuenta y pagos
  con el código de `PaymentEngine`, `PlansController`, `ProfilesController` y
  `Users::RegistrationsController`.
- Se revisaron los enlaces a la Política de privacidad y al formulario de
  contacto.
- No se inventaron datos empresariales, plazos, reembolsos ni garantías.

## 1. Coincidencias verificadas con las reglas del prompt

| Regla | Evidencia | Resultado |
| --- | --- | --- |
| Plan mensual $14.900 COP | `db/seeds.rb` crea la opción “Mensual” con `price = 14900` | Coincide |
| Plan anual $149.900 COP | `db/seeds.rb` crea la opción “Anual” con `price = 149900` | Coincide |
| Prueba de 60 días | `PaymentEngine::Configuration.free_trial_duration_days` y `Setting` usan 60 | Coincide |
| Prueba sin tarjeta | `free_trial_requires_card = false` | Coincide |
| Prueba sin cobro automático | `Memberships::StartFreeTrial` no crea pagos | Coincide |
| Una prueba por cuenta | `free_trial_once_per_user = true` | Coincide |
| Sin renovación automática | Cada compra se inicia manualmente; `FulfillPurchase` otorga o extiende acceso, no cobra | Coincide |
| Vencimiento pasa a Gratis | `ExpireMembershipsJob` y `UserAccess` desactivan el acceso Pro al vencer | Coincide |
| Cierre desde Perfil | `app/views/profiles/show.html.erb` muestra el botón de cierre y `Users::RegistrationsController#destroy` elimina la cuenta | Coincide |
| Cierre sin condición de plan o soporte | El botón no exige plan ni contacto previo | Coincide |
| Datos eliminados en cascada | `app/models/user.rb` define `dependent: :destroy` para los registros principales | Coincide |
| Backups no inmediatos | No existe promesa de eliminación instantánea; la política de privacidad lo explica | Coincide |
| Medios de pago actuales | `app/views/plans/checkout.html.erb` permite tarjeta y PSE; el flujo usa ePayco | Coincide |
| Comunicaciones comerciales separadas | `ProfilesController` y el consentimiento de marketing son independientes | Coincide |
| Enlace de privacidad | `/privacidad` existe y está publicado | Coincide |
| Contacto | `/contactanos` redirige a `/contact` y `hola@yogasto.co` está configurado | Coincide |

## 2. Contradicciones y cambios frente al documento anterior

- El documento anterior describía los planes como una posibilidad (“puede
  ofrecer”) y dejaba condiciones pendientes. La nueva versión define Gratis y
  Pro como reglas comerciales concretas.
- Se incorporaron el periodo de prueba de 60 días y los precios de $14.900 COP
  mensual y $149.900 COP anual.
- Se eliminó la idea de que el plan Gratis podía estar limitado a quienes nunca
  tuvieron una membresía. El prompt define el plan Gratis como permanente.
- Se eliminó la cláusula de “renovación no automática por defecto” y se
  reemplazó por una regla clara: no existe renovación automática.
- Se eliminó la referencia a “modo recurrente” del plan mensual como si
  implicara cobro automático. La compra sigue siendo manual.
- Se reorganizó el documento en 18 secciones y se añadieron retracto,
  reversión, responsabilidades, privacidad, reclamaciones y legislación
  aplicable.
- Se retiraron todas las advertencias internas y textos pendientes de la
  versión pública.
- Se añadió identificación del responsable con los datos ya publicados en la
  Política de privacidad: José Uribe, Soledad, Atlántico, Colombia y
  `hola@yogasto.co`.

## 3. Puntos que requieren decisión o validación legal

### 3.1. Identificación del proveedor en comercio electrónico

Los términos identifican a José Uribe como persona natural, con domicilio en
Soledad, Atlántico, Colombia, y correo `hola@yogasto.co`. No se publicó NIT ni
número de cédula.

Pendiente:

- Confirmar si la normativa de comercio electrónico exige publicar NIT,
  identificación tributaria, dirección física o algún otro dato del proveedor.
- Si se requiere, definir el dato exacto y el canal para publicarlo sin exponer
  información personal innecesaria.

### 3.2. Retracto, reversión y devoluciones

Los términos mencionan el artículo 47 y el artículo 51 de la Ley 1480 de 2011,
distinguen retracto, reversión y devolución, y no prometen reembolsos
automáticos.

Pendiente:

- Validación jurídica del texto de retracto y reversión.
- Definir el procedimiento interno para recibir, verificar y responder
  solicitudes.
- Confirmar plazos, documentos exigibles y trazabilidad de cada solicitud.
- Revisar la cláusula sobre aceptación expresa del inicio inmediato del
  servicio.

### 3.3. Aceptación en el checkout

El checkout actual permite elegir tarjeta o PSE y continuar con el pago, pero no
incluye una aceptación expresa e independiente para el inicio inmediato del
servicio.

Pendiente:

- Decidir si se implementará esa aceptación en el checkout.
- Si se implementa, validar su redacción y su independencia frente a los
  términos generales.
- No presentarla como renuncia general al retracto.

### 3.4. Medios de pago y facturación

El checkout permite tarjeta y PSE. El flujo de pago usa ePayco.

Pendiente:

- Confirmar los medios realmente habilitados en producción.
- Confirmar si los precios incluyen impuestos y cómo se emite la factura o
  comprobante.
- Definir el procedimiento para pagos pendientes, rechazados, duplicados o
  verificados manualmente.

### 3.5. Plan Gratis y control de acceso

El prompt define el plan Gratis como permanente. En el código,
`paid_access_required` está activo y `need_membership?` redirige a planes cuando
el usuario no tiene ninguna membresía. Además, `free_plan_available?` solo
muestra la tarjeta Gratis a usuarios que nunca han tenido una membresía.

Riesgo:

- Un usuario nuevo podría quedar atrapado en el ciclo de selección de plan si
  intenta continuar con el plan Gratis sin tener una membresía.
- Debe revisarse la regla comercial y el control de acceso para que el plan
  Gratis permanente funcione como se describe en los términos.

Este punto no se corrigió porque el prompt prohíbe cambiar el funcionamiento de
la aplicación.

### 3.6. Funcionalidades Pro y gating técnico

Los términos describen como Pro la importación de extractos, Gmail, WhatsApp,
MCP, chat financiero, hábitos, oportunidades de ahorro, análisis por categoría,
reglas y candidatos.

En el código, `require_premium` solo está declarado en
`ReconciliationsController` y `SavingsOpportunitiesController`. Otras
funcionalidades Pro no tienen una compuerta técnica equivalente.

Riesgo:

- Usuarios sin plan Pro podrían acceder a funcionalidades que los términos
  describen como exclusivas de Pro.
- Debe revisarse si se añadirán compuertas técnicas o si los términos deben
  ajustarse.

Este punto no se corrigió porque el prompt prohíbe cambiar el funcionamiento de
la aplicación.

### 3.7. Etiqueta de cierre de cuenta

La interfaz muestra “Cancelar mi cuenta” dentro de la sección Perfil. El prompt
habla de “Cerrar cuenta”. Los términos usan una descripción funcional para no
depender de la etiqueta exacta.

Pendiente:

- Decidir si se unifica la etiqueta de la interfaz a “Cerrar cuenta” o se
  mantiene “Cancelar mi cuenta”.

### 3.8. Conservación y backups

Los términos indican que el cierre es definitivo para el usuario, pero que las
copias de seguridad pueden seguir ciclos técnicos y no desaparecer
instantáneamente. No se publicó un plazo de retención.

Pendiente:

- Confirmar el periodo real de backups de OVHcloud.
- Validar el texto con la Política de privacidad y la revisión legal.

### 3.9. Comunicaciones comerciales

El perfil permite gestionar el consentimiento de comunicaciones comerciales de
forma separada. Los términos aclaran que las autorizaciones comerciales son
opcionales.

Pendiente:

- Validar que el flujo de registro y el checkout mantengan esa separación.
- Confirmar que no se envía publicidad sin autorización.

### 3.10. Declaración de edad en el registro

Los términos indican que, al registrarse, el usuario declara ser mayor de 18
años. El formulario de registro acepta términos y privacidad, pero no incluye un
campo específico de declaración de edad.

Pendiente:

- Decidir si se requiere un checkbox o declaración expresa de edad en el
  registro.
- Si se implementa, validar su redacción y su registro.

## 4. Pruebas ejecutadas

```sh
bin/rails test test/integration/public_cms_terms_and_conditions_test.rb
bin/rails test test/system/terms_and_conditions_test.rb
```

Las pruebas de la página validan que abra, que el índice tenga las 18 secciones,
que los metadatos sean indexables y que planes y pagos conserven las reglas
principales. No se añadieron pruebas detalladas para cada texto informativo.
