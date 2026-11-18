# frozen_string_literal: true

# SEO/GEO content catalog for the Maglev public site.
#
# ARTICLES refresh the five existing help center pages without changing their
# URLs. LANDING_PAGES describe the commercial pages created from scratch.
# CmsPage::SeoContentSeeder applies both and adds the internal links.
module SeoContentSeed
  module_function

  def paragraph(html)
    { type: "paragraph", text: html }
  end

  def heading(text, level: "2")
    { type: "heading", level: level, text: text }
  end

  def callout(title, text, variant = "tip")
    { type: "callout", title: title, text: text, variant: variant }
  end

  def example(label, text, note)
    { type: "example", label: label, text: text, note: note }
  end

  def unordered(items)
    "<ul>#{items.map { |item| "<li>#{item}</li>" }.join}</ul>"
  end

  def ordered(items)
    "<ol>#{items.map { |item| "<li>#{item}</li>" }.join}</ol>"
  end

  ARTICLES = [
    {
      path: "ayuda/primeros-pasos/que-es-yogasto",
      title: "¿Qué es Yogasto y cómo te ayuda?",
      summary: "Yogasto reúne gastos, ingresos, cuentas, tarjetas, presupuestos y metas. Conoce cómo funciona y cómo empezar.",
      seo_title: "Qué es Yogasto y cómo organiza tu dinero",
      meta_description: "Yogasto es una app para organizar gastos e ingresos, cuentas, tarjetas, presupuestos y metas. Conoce cómo funciona y cómo empezar paso a paso.",
      og_title: "Qué es Yogasto: finanzas personales en orden",
      og_description: "Descubre qué puedes organizar en Yogasto, cómo registrar movimientos manualmente o con IA y cómo empezar a usar tu cuenta.",
      canonical_url: "https://yogasto.co/ayuda/primeros-pasos/que-es-yogasto",
      icon: "✦",
      position: 1,
      popular: true,
      featured: true,
      related_paths: [
        "ayuda/primeros-pasos/crear-cuenta",
        "ayuda/primeros-pasos/registrar-tu-primer-gasto",
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia"
      ],
      blocks: [
        paragraph("<p>Yogasto es una aplicación para organizar tus finanzas personales. Reúne tus gastos, ingresos, cuentas, tarjetas, presupuestos, metas y reportes en un solo lugar para que puedas entender en qué se va tu dinero y tomar decisiones con más claridad.</p>"),
        paragraph("<p>No es un banco ni una herramienta de inversión. Es un espacio personal para registrar y ordenar la información financiera que tú decides administrar, con la ayuda de la automatización y la inteligencia artificial cuando quieras usarlas.</p>"),
        heading("¿Para quién es Yogasto?"),
        paragraph(unordered([
          "Personas que quieren saber cuánto dinero entra y sale cada mes.",
          "Quienes usan varias cuentas, billeteras, efectivo y tarjetas y necesitan una visión conjunta.",
          "Personas con ingresos variables que necesitan presupuestar y priorizar gastos.",
          "Quienes tienen tarjetas de crédito, créditos o metas de ahorro y quieren seguir su avance.",
          "Usuarios que prefieren registrar un gasto con una frase, una nota de voz o una foto, en lugar de llenar formularios largos."
        ])),
        heading("Cómo te ayuda a organizar tus finanzas"),
        paragraph(unordered([
          "Separa gastos e ingresos para conocer tu flujo de dinero real.",
          "Agrupa los movimientos por categorías y consulta reportes por periodo.",
          "Organiza cuentas, efectivo, billeteras, tarjetas de crédito y préstamos.",
          "Define presupuestos y metas de ahorro y revisa su progreso.",
          "Automatiza parte del registro con WhatsApp, Gmail y herramientas de IA."
        ])),
        heading("Registra gastos e ingresos manualmente"),
        paragraph("<p>Puedes crear un movimiento desde <a href='/expenses/new'>Nuevo gasto</a> o <a href='/incomes/new'>Nuevo ingreso</a>. El formulario te pide el valor, la fecha, una descripción, la categoría y el medio de dinero. Si quieres ver el detalle del formulario, consulta <a href='/ayuda/gastos-e-ingresos/registrar-un-gasto'>cómo registrar un gasto</a> y <a href='/ayuda/gastos-e-ingresos/registrar-un-ingreso'>cómo registrar un ingreso</a>.</p>"),
        paragraph("<p>Antes de registrar tu primer movimiento necesitas al menos una cuenta o medio de dinero. Puedes crearla en <a href='/money_sources'>Cuentas y tarjetas</a>; la guía <a href='/ayuda/cuentas-y-medios-de-dinero/agregar-una-cuenta'>cómo agregar una cuenta</a> explica los tipos disponibles.</p>"),
        heading("Automatiza el registro con WhatsApp y Gmail"),
        paragraph("<p>Yogasto puede interpretar información que tú le envías o autorizas y convertirla en movimientos organizados. La automatización no elimina la revisión: siempre puedes comprobar, corregir o descartar lo que se propone.</p>"),
        heading("Registrar gastos por WhatsApp", level: "3"),
        paragraph("<p>Después de asociar tu número, puedes escribir o enviar una nota de voz o una foto de un recibo. Yogasto identifica el valor, la fecha, el comercio y la categoría cuando la información es suficiente. La guía <a href='/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp'>cómo registrar gastos por WhatsApp</a> muestra el paso a paso y ejemplos; también puedes conocer la función en <a href='/funciones/registrar-gastos-por-whatsapp'>registro de gastos por WhatsApp</a>.</p>"),
        heading("Procesar notificaciones bancarias de Gmail", level: "3"),
        paragraph("<p>Si conectas Gmail, Yogasto revisa únicamente los correos que coinciden con las notificaciones que configuras, extrae los datos del movimiento y te muestra candidatos para confirmar o descartar. No se conecta automáticamente a tu banco. Consulta <a href='/ayuda/herramientas-inteligentes/conectar-gmail'>cómo conectar Gmail</a> y la página <a href='/funciones/importar-gastos-desde-gmail'>importar gastos desde Gmail</a>.</p>"),
        heading("Analiza tus finanzas con inteligencia artificial"),
        paragraph("<p>El <a href='/financial_chat'>Chat Financiero</a> responde preguntas sobre los datos que ya registraste: gastos por categoría, comparación de ingresos y gastos, deudas, presupuestos y metas. Es una conversación de solo lectura: analiza y sugiere, pero no crea ni modifica movimientos. Puedes ver ejemplos en <a href='/ayuda/herramientas-inteligentes/chat-financiero'>cómo usar el Chat Financiero</a> y en <a href='/funciones/asistente-financiero-con-ia'>asistente financiero con IA</a>.</p>"),
        heading("Presupuestos, cuentas, tarjetas y reportes"),
        paragraph(unordered([
          "Presupuestos por categoría para limitar y seguir tus gastos.",
          "Cuentas, efectivo y billeteras con sus saldos disponibles.",
          "Tarjetas de crédito con cupo, deuda y pagos asociados.",
          "Metas de ahorro y bolsillos para separar dinero con un propósito.",
          "Reportes y resúmenes para comparar periodos y detectar hábitos."
        ])),
        heading("Cómo empezar en Yogasto"),
        paragraph(ordered([
          "Crea tu cuenta desde <a href='/users/sign_up'>Crear cuenta</a> y confirma tu correo.",
          "Agrega tu primera cuenta, efectivo o tarjeta en <a href='/money_sources'>Cuentas y tarjetas</a>.",
          "Registra un gasto en <a href='/expenses/new'>Nuevo gasto</a> y un ingreso en <a href='/incomes/new'>Nuevo ingreso</a>.",
          "Revisa tus categorías y tu primer reporte.",
          "Si quieres automatizar, activa Pro y conecta WhatsApp o Gmail desde la configuración."
        ])),
        callout("Empieza con lo que ya tienes", "No necesitas configurar todo el primer día. Registra los movimientos de esta semana y ve completando cuentas, presupuestos y metas a medida que los necesites."),
        heading("Cuándo tiene sentido pasar a Pro"),
        paragraph("<p>El plan Gratis te permite registrar y organizar lo esencial. Las funciones de automatización y análisis, como WhatsApp, Gmail, el Chat Financiero y las oportunidades de ahorro, forman parte de Yogasto Pro. Puedes comparar las opciones vigentes en <a href='/precios'>Precios y planes</a> y revisar el detalle en <a href='/ayuda/membresia-y-pagos/beneficios-de-yogasto-pro'>beneficios de Yogasto Pro</a>.</p>"),
        paragraph("<p>Si quieres una visión general de la aplicación, visita <a href='/funciones/app-para-controlar-gastos'>la app para controlar gastos personales</a>. Si te interesa el contexto local, consulta <a href='/finanzas-personales-colombia'>finanzas personales en Colombia</a>.</p>")
      ]
    },
    {
      path: "ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp",
      title: "Cómo registrar gastos por WhatsApp",
      summary: "Vincula tu número y envía texto, notas de voz o imágenes. Yogasto interpreta el gasto y te permite revisarlo.",
      seo_title: "Registrar gastos por WhatsApp con IA",
      meta_description: "Vincula tu WhatsApp y registra gastos con texto, notas de voz o fotos. Mira ejemplos, cómo interpreta la IA y cómo revisar cada movimiento.",
      og_title: "Registra gastos por WhatsApp con Yogasto",
      og_description: "Envía “Pagué 35.000 en gasolina” y Yogasto organiza el gasto. Conoce el paso a paso, los ejemplos y la privacidad del canal.",
      canonical_url: "https://yogasto.co/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp",
      icon: "◍",
      position: 5,
      popular: true,
      featured: true,
      related_paths: [
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
        "ayuda/herramientas-inteligentes/registrar-gastos-con-lenguaje-natural",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro"
      ],
      blocks: [
        paragraph("<p>WhatsApp es uno de los canales más rápidos para registrar un gasto: escribes una frase, envías una nota de voz o una foto del recibo y Yogasto se encarga de interpretar la información. Esta guía explica cómo asociar tu número, qué puedes enviar y cómo revisar lo que se registra.</p>"),
        heading("Qué necesitas antes de empezar"),
        paragraph(unordered([
          "Una cuenta de Yogasto activa.",
          "Una membresía con acceso a las funciones Pro. Puedes revisar las opciones en <a href='/precios'>Precios y planes</a>.",
          "Al menos una cuenta, efectivo o tarjeta creada en <a href='/money_sources'>Cuentas y tarjetas</a> para asociar el gasto.",
          "El número de WhatsApp que quieres vincular. Puedes desconectarlo y asociar otro cuando lo necesites."
        ])),
        heading("Cómo asociar tu número de WhatsApp"),
        paragraph(ordered([
          "Entra a <a href='/settings/whatsapp'>Configuración → WhatsApp</a>.",
          "Pulsa <strong>Enviar mensaje a Yogasto</strong>. Se abrirá WhatsApp con un mensaje inicial que incluye un código de conexión.",
          "Envía ese mensaje desde el número que quieres asociar.",
          "Espera la confirmación de Yogasto en el mismo chat. La página se actualiza automáticamente cuando la conexión se completa.",
          "Desde ese momento puedes enviar tus gastos a ese chat sin comandos adicionales."
        ])),
        callout("Solo se hace una vez", "El mensaje inicial solo es necesario la primera vez. Después basta con enviar el gasto como se lo contarías a otra persona."),
        heading("Cómo iniciar la conversación"),
        paragraph("<p>Una vez asociado el número, abre el chat de Yogasto y envía el primer gasto. No necesitas recordar comandos ni iniciar sesión desde WhatsApp. Si cambias de número, desconecta el anterior desde la configuración y repite la asociación con el nuevo.</p>"),
        heading("Qué puedes enviar"),
        paragraph(unordered([
          "<strong>Texto:</strong> una frase con el gasto, el valor y el contexto que recuerdes.",
          "<strong>Nota de voz:</strong> describe el gasto hablando con naturalidad.",
          "<strong>Imagen:</strong> una foto de un recibo, factura o comprobante.",
          "<strong>Imagen con texto:</strong> la foto y una descripción breve en el mismo mensaje."
        ])),
        heading("Ejemplos de gastos en lenguaje natural"),
        example("EJEMPLO · GASOLINA", "Pagué 35.000 en gasolina", "Yogasto identifica el valor, la fecha del mensaje y una categoría compatible con transporte."),
        example("EJEMPLO · ALMUERZO", "Almorcé por 28.000", "El valor y la descripción se convierten en un gasto de alimentación listo para revisar."),
        example("EJEMPLO · MERCADO", "Compré mercado por 150.000", "Yogasto reconoce el comercio o la descripción y propone una categoría de supermercado o alimentación."),
        example("EJEMPLO · VARIOS GASTOS", "Hoy pagué 18.000 de un café, 42.000 de almuerzo y 65.000 de gasolina con mi tarjeta débito", "El mensaje se separa en gastos individuales. Si mencionas el medio de pago, se usa para asociar cada movimiento."),
        heading("Cómo interpreta Yogasto el valor, la fecha, el comercio y la categoría"),
        paragraph(unordered([
          "<strong>Valor:</strong> reconoce formatos como 35.000, 35 mil o $35.000 y los interpreta en pesos colombianos.",
          "<strong>Fecha:</strong> usa la fecha del mensaje cuando no indicas otra; también entiende expresiones como “ayer” o “el sábado”.",
          "<strong>Comercio o descripción:</strong> conserva el nombre del negocio o la frase que describe el gasto.",
          "<strong>Categoría:</strong> propone una categoría según el contexto y tus categorías existentes.",
          "<strong>Medio de pago:</strong> si mencionas efectivo, una cuenta o una tarjeta, intenta asociar el gasto a ese medio."
        ])),
        callout("Incluye el medio de pago cuando puedas", "Una frase como “con mi tarjeta débito” ayuda a que el gasto quede asociado a la cuenta correcta desde el principio.", "tip"),
        heading("Qué pasa cuando la información no se puede interpretar"),
        paragraph("<p>Si falta un dato importante, Yogasto puede hacer una pregunta de aclaración en el mismo chat. Si el mensaje no parece un gasto, te lo indica para que lo reformules. Cuando la información no alcanza para crear el movimiento con seguridad, el gasto queda pendiente en la bandeja de <a href='/expense_candidates'>candidatos a gasto</a> para que lo revises.</p>"),
        heading("Cómo revisar y corregir los movimientos registrados"),
        paragraph(ordered([
          "Cuando Yogasto identifica un gasto con información suficiente, te confirma en el chat el valor y la descripción.",
          "Si el gasto queda para revisión, ábrelo desde <a href='/expense_candidates'>candidatos a gasto</a>.",
          "Completa o corrige el valor, la fecha, la categoría y el medio de pago.",
          "Confirma el movimiento para convertirlo en un gasto definitivo o descártalo si no corresponde.",
          "Después puedes editarlo o eliminarlo como cualquier otro movimiento desde <a href='/expenses'>Gastos</a>."
        ])),
        heading("Privacidad: solo los mensajes que envías a Yogasto"),
        paragraph("<p>Yogasto solo procesa los mensajes que tú decides enviar directamente a su número de WhatsApp. No lee tus conversaciones personales, no accede a los chats con otras personas y no utiliza tu cuenta de WhatsApp para obtener mensajes que no le hayas enviado. Para evitar duplicados, conserva identificadores técnicos de los mensajes procesados durante un periodo limitado.</p>"),
        callout("Tu privacidad no cambia por usar el canal", "Las reglas de tratamiento de datos son las mismas que en la aplicación. Puedes consultar el detalle en la <a href='/privacidad'>política de privacidad</a>.", "note"),
        heading("Situaciones frecuentes"),
        paragraph(unordered([
          "<strong>No recibo la confirmación:</strong> revisa que el número asociado sea el mismo desde el que escribes y vuelve a abrir la página de configuración.",
          "<strong>El número ya está vinculado a otra cuenta:</strong> Yogasto no transfiere números entre cuentas. Usa el número asociado a tu cuenta o desconéctalo primero.",
          "<strong>La nota de voz no se entiende:</strong> intenta grabarla de nuevo en un lugar con menos ruido o escribe el gasto.",
          "<strong>Mi membresía no está activa:</strong> las funciones de WhatsApp requieren acceso Pro. Revisa tu estado en <a href='/plans'>tu plan</a>."
        ])),
        paragraph("<p>Para conocer la función completa, visita <a href='/funciones/registrar-gastos-por-whatsapp'>registro de gastos por WhatsApp</a>. También puedes comparar las herramientas disponibles en <a href='/precios'>Precios y planes</a>.</p>")
      ]
    },
    {
      path: "ayuda/herramientas-inteligentes/conectar-gmail",
      title: "Cómo conectar Gmail para importar movimientos",
      summary: "Conecta Gmail y revisa los candidatos a gasto que Yogasto identifica en las notificaciones bancarias que autorizas.",
      seo_title: "Cómo conectar Gmail y detectar gastos",
      meta_description: "Conecta Gmail a Yogasto para identificar notificaciones bancarias, revisar candidatos, confirmarlos o descartarlos y desconectar cuando quieras.",
      og_title: "Conecta Gmail y automatiza el registro de gastos",
      og_description: "Yogasto revisa las notificaciones bancarias que autorizas, extrae el movimiento y te pide confirmar antes de guardar. Conoce permisos y privacidad.",
      canonical_url: "https://yogasto.co/ayuda/herramientas-inteligentes/conectar-gmail",
      icon: "✉",
      position: 3,
      featured: true,
      related_paths: [
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
        "ayuda/herramientas-inteligentes/chat-financiero"
      ],
      blocks: [
        paragraph("<p>Conectar Gmail permite que Yogasto identifique notificaciones de compras y cargos enviadas por tus bancos o emisores de tarjeta. En lugar de registrar cada movimiento a mano, revisas los candidatos que la aplicación encuentra y decides cuáles se convierten en gastos.</p>"),
        heading("Antes de conectar Gmail"),
        paragraph(unordered([
          "Una cuenta de Yogasto con acceso a las funciones Pro. Revisa las opciones en <a href='/precios'>Precios y planes</a>.",
          "Al menos una cuenta, efectivo o tarjeta creada en <a href='/money_sources'>Cuentas y tarjetas</a>.",
          "La cuenta de Google donde recibes las notificaciones del banco o de la tarjeta.",
          "La configuración de reconocimiento de tus fuentes de dinero. Si aún no la tienes, Yogasto te guía antes de conectar."
        ])),
        heading("Cómo conectar tu cuenta de Gmail"),
        paragraph(ordered([
          "Entra a <a href='/settings/gmail'>Configuración → Gmail</a>.",
          "Pulsa <strong>Conectar Gmail</strong>.",
          "Elige la cuenta de Google que recibe las notificaciones.",
          "Revisa los permisos solicitados y autoriza el acceso de lectura.",
          "Vuelve a Yogasto. La cuenta queda conectada y el primer análisis busca notificaciones para proponerte fuentes y movimientos."
        ])),
        heading("Qué permisos solicita Google"),
        paragraph("<p>Yogasto solicita permiso para leer mensajes de Gmail y conocer el correo de la cuenta que autorizas. No solicita permisos para enviar, modificar o eliminar correos. La conexión se realiza mediante OAuth de Google y los tokens se almacenan cifrados; puedes revocar el acceso desde tu cuenta de Google en cualquier momento.</p>"),
        heading("Qué notificaciones bancarias puede identificar"),
        paragraph("<p>Yogasto analiza los correos que coinciden con las fuentes que has configurado: remitentes, asuntos o palabras clave de tus bancos y tarjetas. Su objetivo son las notificaciones de compras, cargos y consumos. Los correos promocionales, los resúmenes que no describen una transacción y los mensajes de otras fuentes se ignoran.</p>"),
        heading("Qué información extrae"),
        paragraph(unordered([
          "El valor y la moneda del movimiento.",
          "La fecha de la compra o del cargo.",
          "El comercio o la descripción disponible en el correo.",
          "El banco o la tarjeta cuando el mensaje lo indica.",
          "Los últimos cuatro dígitos de la tarjeta, si aparecen, para asociar el medio de pago correcto.",
          "Una categoría sugerida según el comercio y tus categorías."
        ])),
        heading("Cómo revisar los candidatos a gasto"),
        paragraph("<p>Cuando la información es clara, Yogasto crea el gasto y lo deja disponible en <a href='/expenses'>Gastos</a>. Cuando falta un dato o la interpretación no es concluyente, el movimiento queda como candidato pendiente en <a href='/expense_candidates'>candidatos a gasto</a>. Allí puedes completar el valor, la fecha, la categoría o el medio de pago; luego lo confirmas o lo descartas.</p>"),
        paragraph("<p>La confirmación es importante: un candidato no se convierte en gasto definitivo hasta que la información está completa y revisada. Así evitas duplicados y movimientos asociados a la cuenta equivocada.</p>"),
        heading("Qué pasa cuando un correo no se puede procesar"),
        paragraph(unordered([
          "<strong>No parece una transacción:</strong> se marca como ignorado y no genera candidatos.",
          "<strong>Falta un dato:</strong> queda pendiente para revisión con la información disponible.",
          "<strong>El procesamiento falla:</strong> el correo queda marcado para reintento y no se duplica en la siguiente sincronización.",
          "<strong>Ya fue procesado:</strong> Yogasto recuerda el identificador del mensaje para no volver a importarlo."
        ])),
        heading("Cómo desconectar Gmail"),
        paragraph(ordered([
          "Entra a <a href='/settings/gmail'>Configuración → Gmail</a>.",
          "Pulsa <strong>Desconectar</strong> y confirma la acción.",
          "Yogasto elimina los tokens de acceso guardados y deja de revisar la cuenta.",
          "Los gastos que ya confirmaste se conservan; puedes eliminarlos desde la aplicación si lo necesitas."
        ])),
        heading("Privacidad y retención de datos"),
        paragraph("<p>Yogasto accede a Gmail en modo de solo lectura y únicamente para buscar las notificaciones que coinciden con tus fuentes configuradas. No envía correos en tu nombre, no modifica tu bandeja de entrada y no elimina mensajes. No guarda el cuerpo completo de tus correos: el contenido se procesa de forma temporal para extraer los datos del movimiento y no se conserva como copia permanente. La aplicación mantiene el asunto, los datos del movimiento y un identificador técnico para evitar procesar dos veces el mismo correo.</p>"),
        callout("Revisa antes de confirmar", "La automatización reduce el trabajo manual, pero no reemplaza tu revisión. Comprueba los candidatos antes de confirmarlos, sobre todo si usas varias tarjetas o cuentas.", "warning"),
        paragraph("<p>Para conocer la función completa, visita <a href='/funciones/importar-gastos-desde-gmail'>importar gastos desde Gmail</a>. También puedes comparar las herramientas disponibles en <a href='/precios'>Precios y planes</a>.</p>")
      ]
    },
    {
      path: "ayuda/herramientas-inteligentes/chat-financiero",
      title: "Cómo usar el Chat Financiero",
      summary: "Haz preguntas sobre tus finanzas y recibe respuestas basadas en la información registrada en tu cuenta.",
      seo_title: "Chat Financiero con IA",
      meta_description: "Consulta tus gastos, ingresos, categorías, deudas y metas con el Chat Financiero de Yogasto. Análisis con IA y oportunidades de ahorro.",
      og_title: "Chat Financiero: analiza tus finanzas con IA",
      og_description: "Haz preguntas en lenguaje natural y recibe respuestas basadas en los datos que registras en Yogasto, con ejemplos en pesos colombianos.",
      canonical_url: "https://yogasto.co/ayuda/herramientas-inteligentes/chat-financiero",
      icon: "◌",
      position: 4,
      popular: true,
      featured: true,
      related_paths: [
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
        "ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp"
      ],
      blocks: [
        paragraph("<p>El <a href='/financial_chat'>Chat Financiero</a> es una conversación con inteligencia artificial que responde preguntas sobre tus finanzas usando la información que ya registraste en Yogasto. Sirve para entender tus hábitos, comparar periodos y detectar oportunidades de organización.</p>"),
        heading("Qué hace el Chat Financiero"),
        paragraph("<p>El chat analiza tus datos y redacta una respuesta en lenguaje natural. Es una herramienta de solo lectura: no crea, edita ni elimina gastos, ingresos, presupuestos, metas o pagos. Tampoco mueve dinero. Su función es ayudarte a interpretar lo que ya está registrado y sugerir próximos pasos que tú decides ejecutar.</p>"),
        heading("Qué información puede analizar"),
        paragraph(unordered([
          "Gastos e ingresos del periodo, por categoría y por medio de dinero.",
          "Comparaciones entre meses o ciclos financieros.",
          "Presupuestos activos y su nivel de avance.",
          "Tarjetas de crédito, créditos y préstamos registrados.",
          "Metas de ahorro y bolsillos.",
          "Patrones de gasto y cambios frente al periodo anterior."
        ])),
        heading("Ejemplos de preguntas"),
        example("EJEMPLO · CATEGORÍAS", "¿En qué categorías gasté más este mes?", "El chat ordena las categorías por valor y muestra los montos en pesos colombianos, por ejemplo: Alimentación $ 620.000, Vivienda $ 1.200.000."),
        example("EJEMPLO · COMPARACIÓN", "¿Cuánto gasté en alimentación entre septiembre y octubre?", "Compara ambos periodos y señala la diferencia absoluta y porcentual, si los datos están disponibles."),
        example("EJEMPLO · INGRESOS Y GASTOS", "¿Mis ingresos de este mes cubren mis gastos fijos?", "Usa tus ingresos registrados y tus gastos recurrentes para mostrar el margen disponible."),
        example("EJEMPLO · TARJETAS", "¿Cuánto debo en mis tarjetas y cuánto cupo tengo disponible?", "Resume la deuda y el cupo disponible de cada tarjeta registrada."),
        example("EJEMPLO · AHORRO", "¿Dónde puedo ahorrar $200.000 al mes?", "Identifica categorías con mayor peso y propone ajustes concretos, sin crear presupuestos ni metas por ti."),
        heading("Análisis de categorías y patrones de gasto"),
        paragraph("<p>Puedes preguntar por una categoría concreta, por el cambio frente al mes anterior o por los gastos que más crecieron. El chat también puede señalar concentraciones: por ejemplo, si una categoría representa una parte alta de tu gasto total o si un comercio aparece varias veces en el periodo.</p>"),
        heading("Comparación de ingresos y gastos"),
        paragraph("<p>El chat puede contrastar lo que entra con lo que sale y explicar si tu flujo del periodo deja margen para ahorrar, invertir en una meta o cubrir una obligación. La respuesta se basa en los movimientos registrados; si falta información, lo indica en lugar de inventar cifras.</p>"),
        heading("Oportunidades de ahorro y organización"),
        paragraph("<p>Además de responder preguntas, el chat puede sugerir ajustes y prioridades. Las sugerencias son orientativas y tú decides qué hacer. Para llevarlas a la práctica puedes crear un presupuesto en <a href='/budgets'>Presupuestos</a>, una meta en <a href='/goals'>Metas</a>, revisar tus hábitos en <a href='/financial_habits'>Hábitos financieros</a> o explorar <a href='/savings_opportunities'>oportunidades de ahorro</a>.</p>"),
        heading("Limitaciones de las respuestas con IA"),
        paragraph(unordered([
          "El chat solo conoce los datos registrados en tu cuenta. Si un gasto o una deuda no está registrada, no puede considerarla.",
          "Puede cometer errores de interpretación o redacción. Verifica las cifras importantes antes de tomar una decisión.",
          "No garantiza resultados futuros ni predice con certeza cuánto vas a ahorrar.",
          "No reemplaza asesoría financiera, contable, tributaria o legal profesional.",
          "No ejecuta acciones sobre tus finanzas: las decisiones y los cambios los haces tú en la aplicación."
        ])),
        heading("Diferencia entre el Chat Financiero y el registro con IA"),
        paragraph("<p>El Chat Financiero analiza información existente y responde preguntas. El registro con IA, en cambio, convierte un mensaje, una nota de voz, una imagen o una notificación bancaria en un movimiento para revisar. Puedes conocer ese flujo en <a href='/ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia'>cómo funciona el registro de gastos con IA</a>, en <a href='/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp'>registro por WhatsApp</a> o en la página <a href='/funciones/registrar-gastos-por-whatsapp'>registro de gastos por WhatsApp</a>.</p>"),
        callout("Función Pro", "El Chat Financiero forma parte de las funciones Pro. Puedes revisar tu plan y las condiciones vigentes en <a href='/precios'>Precios y planes</a>.", "note"),
        paragraph("<p>Para una visión general, visita <a href='/funciones/asistente-financiero-con-ia'>asistente financiero con IA</a>.</p>")
      ]
    },
    {
      path: "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
      title: "Qué beneficios tiene Yogasto Pro",
      summary: "Conoce las funciones Pro verificadas y en qué se diferencian del plan Gratis.",
      seo_title: "Beneficios de Yogasto Pro",
      meta_description: "Conoce qué incluye Yogasto Pro: WhatsApp, Gmail, IA, Chat Financiero, análisis de gastos y oportunidades de ahorro. Compara Gratis y Pro.",
      og_title: "Yogasto Pro: automatización y análisis con IA",
      og_description: "Descubre las funciones Pro verificadas, cómo se diferencian del plan Gratis y dónde consultar precios y condiciones vigentes.",
      canonical_url: "https://yogasto.co/ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
      icon: "✦",
      position: 2,
      popular: true,
      featured: true,
      related_paths: [
        "ayuda/membresia-y-pagos/plan-gratis",
        "ayuda/membresia-y-pagos/como-adquirir-una-membresia",
        "ayuda/herramientas-inteligentes/chat-financiero"
      ],
      blocks: [
        paragraph("<p>Yogasto Pro amplía las herramientas para automatizar el registro y entender mejor tus finanzas. Incluye todo lo del plan Gratis y suma funciones de inteligencia artificial, integraciones y análisis avanzado. Los precios y las condiciones vigentes están siempre en <a href='/precios'>Precios y planes</a>.</p>"),
        heading("Qué incluye el plan Gratis"),
        paragraph(unordered([
          "Registro y organización de gastos e ingresos.",
          "Cuentas, efectivo, billeteras y tarjetas.",
          "Categorías y reportes básicos.",
          "Presupuestos y metas de ahorro.",
          "Gastos e ingresos recurrentes."
        ])),
        heading("Qué agrega Yogasto Pro"),
        heading("Automatización con WhatsApp", level: "3"),
        paragraph("<p>Puedes asociar tu número y registrar gastos con texto, notas de voz o imágenes. Yogasto interpreta el valor, la fecha, el comercio y la categoría, y te permite revisar lo que registra. Guía completa: <a href='/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp'>registrar gastos por WhatsApp</a>.</p>"),
        heading("Integración con Gmail", level: "3"),
        paragraph("<p>Yogasto revisa las notificaciones bancarias que autorizas, extrae los datos del movimiento y te muestra candidatos para confirmar o descartar. No se conecta automáticamente a tu banco. Guía completa: <a href='/ayuda/herramientas-inteligentes/conectar-gmail'>cómo conectar Gmail</a>.</p>"),
        heading("Procesamiento con inteligencia artificial", level: "3"),
        paragraph("<p>La IA convierte texto, notas de voz, imágenes, comprobantes y extractos en movimientos organizados. También sugiere categorías y completa datos cuando la información es suficiente. El resultado siempre pasa por tu revisión antes de convertirse en un movimiento definitivo cuando falta información.</p>"),
        heading("Chat Financiero", level: "3"),
        paragraph("<p>Una conversación de solo lectura para preguntar por tus gastos, ingresos, categorías, deudas, presupuestos y metas. El chat analiza los datos registrados y responde con cifras y sugerencias. Guía completa: <a href='/ayuda/herramientas-inteligentes/chat-financiero'>cómo usar el Chat Financiero</a>.</p>"),
        heading("Análisis de gastos y oportunidades de ahorro", level: "3"),
        paragraph("<p>Las herramientas Pro ayudan a detectar patrones, revisar categorías con mayor peso y encontrar oportunidades de ajuste. Puedes explorar <a href='/savings_opportunities'>oportunidades de ahorro</a>, revisar <a href='/financial_habits'>hábitos financieros</a> y consultar análisis por categoría en <a href='/category_insights'>categorías</a>.</p>"),
        heading("Otras herramientas Pro verificadas", level: "3"),
        paragraph(unordered([
          "Importación de extractos y archivos para registrar varios movimientos.",
          "Capacidad de deuda y escenarios de pago para entender el costo de tus obligaciones.",
          "Reglas de transacciones para clasificar movimientos de forma consistente.",
          "Reconocimiento de fuentes de dinero y configuración de notificaciones bancarias."
        ])),
        heading("Gratis y Pro: diferencias principales"),
        paragraph("<table><thead><tr><th>Necesidad</th><th>Gratis</th><th>Pro</th></tr></thead><tbody><tr><td>Registrar gastos e ingresos</td><td>Sí</td><td>Sí</td></tr><tr><td>Cuentas, tarjetas, presupuestos y metas</td><td>Sí</td><td>Sí</td></tr><tr><td>Registro por WhatsApp</td><td>No</td><td>Sí</td></tr><tr><td>Detección de gastos desde Gmail</td><td>No</td><td>Sí</td></tr><tr><td>Chat Financiero y análisis con IA</td><td>No</td><td>Sí</td></tr><tr><td>Oportunidades de ahorro y hábitos financieros</td><td>No</td><td>Sí</td></tr></tbody></table>"),
        heading("Cómo consultar tu plan y los precios"),
        paragraph("<p>Puedes revisar el estado de tu membresía en <a href='/plans'>tu plan</a> y consultar las opciones, precios y medios de pago vigentes en <a href='/precios'>Precios y planes</a>. Los valores y la disponibilidad pueden cambiar; la página de precios es la fuente de verdad. Para el paso a paso de una compra, consulta <a href='/ayuda/membresia-y-pagos/como-adquirir-una-membresia'>cómo adquirir una membresía</a>.</p>"),
        callout("Las funciones pueden variar", "La disponibilidad de cada herramienta depende de tu plan y de la configuración de tu cuenta. Revisa la página de precios para ver las condiciones vigentes.", "note"),
        callout("Paga solo desde el checkout oficial", "No compartas datos de pago por mensajes, correos o enlaces que no provengan del proceso oficial de compra.", "warning"),
        paragraph("<p>Si quieres ver la aplicación en contexto, visita <a href='/funciones/app-para-controlar-gastos'>la app para controlar gastos personales</a> y <a href='/funciones/asistente-financiero-con-ia'>el asistente financiero con IA</a>.</p>")
      ]
    }
  ].freeze

  # Articles outside the five SEO priorities that still need a factual
  # correction kept in version control.
  SUPPORTING_ARTICLES = [
    {
      path: "ayuda/cuentas-y-medios-de-dinero/dia-de-balance",
      title: "Qué es el Día de Balance",
      summary: "Compara tus saldos con la realidad y revisa los pagos pendientes del periodo.",
      seo_title: "Qué es el Día de Balance",
      meta_description: "Compara tus saldos con la realidad y revisa los pagos pendientes del periodo.",
      og_title: "Día de Balance: revisa tus saldos y pagos del periodo",
      og_description: "Aprende a usar el Día de Balance para comparar saldos, revisar deudas y asignar pagos pendientes.",
      canonical_url: "https://yogasto.co/ayuda/cuentas-y-medios-de-dinero/dia-de-balance",
      icon: "◷",
      position: 5,
      popular: false,
      featured: false,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta",
        "ayuda/gastos-e-ingresos/como-funcionan-los-recurrentes",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro"
      ],
      blocks: [
        paragraph("<p>El <a href='/reconciliation'>Día de Balance</a> es un espacio para revisar que lo que tienes registrado coincida con la realidad: saldos de cuentas, deudas y pagos pendientes del periodo.</p>"),
        heading("Para qué sirve"),
        paragraph("<ol><li>Ver el saldo que Yogasto calcula para cada cuenta o deuda.</li><li>Compararlo con el saldo real que consultas en tu banco o tarjeta.</li><li>Asignar pagos pendientes a los movimientos que ya registraste.</li><li>Marcar como revisado lo que ya está cuadrado.</li></ol>"),
        heading("Qué no hace"),
        paragraph("<p>El Día de Balance no mueve dinero, no realiza pagos y no modifica tu banco ni tu tarjeta. Tampoco cambia el saldo real de tus productos financieros.</p>"),
        callout("Disponible en tu cuenta", "El Día de Balance no requiere una membresía Pro. Puedes abrirlo desde <a href='/reconciliation'>Día de Balance</a> cuando quieras comparar tus saldos con la realidad y revisar los pagos pendientes del periodo.")
      ]
    }
  ].freeze

  LANDING_PAGES = [
    {
      path: "funciones/app-para-controlar-gastos",
      title: "Una app para controlar tus gastos personales",
      h1: "Una app para controlar tus gastos personales",
      seo_title: "App para controlar gastos personales",
      meta_description: "Organiza gastos e ingresos, presupuestos, cuentas y tarjetas en una sola app. Yogasto te ayuda a entender en qué se va tu dinero y a decidir mejor.",
      og_title: "App para controlar tus gastos personales",
      og_description: "Yogasto reúne tus gastos, ingresos, cuentas, tarjetas, presupuestos y metas para que tengas una visión clara de tu dinero.",
      canonical_url: "https://yogasto.co/funciones/app-para-controlar-gastos",
      hero: {
        eyebrow: "CONTROL DE GASTOS",
        description: "Yogasto reúne tus gastos, ingresos, cuentas, tarjetas, presupuestos y metas en un solo lugar. Menos hojas de cálculo y más claridad sobre en qué se va tu dinero.",
        note: "Registro manual o automatizado con IA. Tú mantienes el control de tu información.",
        note_icon: "✦",
        variant: "lavender",
        show_art: true,
        art_style: "chat",
        art_greeting: "¿Cómo van tus gastos este mes?",
        art_message: "Tengo tus movimientos organizados.",
        art_reply: "Revisemos tus categorías.",
        art_badge: "Todo en un lugar"
      },
      features: {
        kicker: "UNA VISIÓN COMPLETA",
        title: "Lo esencial para ordenar tu dinero, ",
        gradient_text: "sin complicarte.",
        description: "Cada función está pensada para que registrar, revisar y decidir sea parte de tu rutina, no una tarea pesada.",
        items: [
          { icon: "▥", color: "blue", title: "Gastos e ingresos", description: "Registra cada movimiento y entiende cuánto entra, cuánto sale y en qué se va tu dinero." },
          { icon: "▣", color: "orange", title: "Cuentas y tarjetas", description: "Organiza cuentas, efectivo, billeteras, tarjetas de crédito y préstamos." },
          { icon: "◎", color: "green", title: "Presupuestos", description: "Define límites por categoría y revisa tu avance antes de que el mes termine." },
          { icon: "◇", color: "purple", title: "Metas de ahorro", description: "Separa dinero con un propósito y sigue el progreso de cada meta." },
          { icon: "▤", color: "pink", title: "Reportes claros", description: "Consulta resúmenes por periodo y detecta los cambios en tus hábitos." },
          { icon: "✧", color: "cyan", title: "Automatización con IA", description: "Convierte mensajes, correos y archivos en movimientos organizados." }
        ]
      },
      content: {
        kicker: "CÓMO TE AYUDA",
        title: "Del registro suelto a una ",
        gradient_text: "visión que sí entiendes.",
        description: "Controlar tus gastos no significa anotarlo todo de forma perfecta. Significa tener información suficiente para saber dónde estás y qué puedes ajustar.",
        blocks: [
          heading("Qué significa controlar tus gastos"),
          paragraph("<p>Controlar tus gastos es saber qué movimientos ocurrieron, en qué categorías se concentran y cómo se comparan con tus ingresos. Yogasto organiza esa información para que puedas responder preguntas concretas: cuánto gastaste este mes, qué cambió frente al anterior, cuánto te queda disponible y qué compromisos vienen.</p>"),
          heading("Organiza tu mes en una sola vista"),
          { type: "list", style: "unordered", items: "Gastos e ingresos del periodo.\nPresupuestos por categoría y su avance.\nCuentas, efectivo y billeteras disponibles.\nTarjetas de crédito, cupo y deuda.\nMetas de ahorro y dinero separado." },
          heading("Registra sin fricción"),
          paragraph("<p>Puedes registrar manualmente desde <a href='/expenses/new'>Nuevo gasto</a> o <a href='/incomes/new'>Nuevo ingreso</a>, o usar las herramientas de automatización. Con <a href='/funciones/registrar-gastos-por-whatsapp'>el registro por WhatsApp</a> basta una frase o una nota de voz; con <a href='/funciones/importar-gastos-desde-gmail'>la importación desde Gmail</a>, Yogasto identifica notificaciones bancarias y te muestra candidatos para revisar.</p>"),
          heading("Decide con reportes y presupuestos"),
          paragraph("<p>Los reportes te ayudan a leer tus hábitos y los presupuestos convierten esa lectura en un límite concreto. También puedes crear metas y separar dinero en bolsillos. Si quieres profundizar, consulta <a href='/ayuda/gastos-e-ingresos/como-funcionan-las-categorias'>cómo funcionan las categorías</a> y <a href='/ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta'>qué es una cuenta en Yogasto</a>.</p>"),
          callout("No necesitas registrar todo el primer día", "Empieza por una cuenta y los movimientos de la semana. La claridad aparece cuando el registro se vuelve parte de tu rutina."),
          heading("Empieza en tres pasos"),
          paragraph("<p>Crea tu cuenta en <a href='/users/sign_up'>Crear cuenta</a>, agrega un medio de dinero en <a href='/money_sources'>Cuentas y tarjetas</a> y registra tu primer gasto. Si quieres una introducción completa, lee <a href='/ayuda/primeros-pasos/que-es-yogasto'>qué es Yogasto</a>.</p>")
        ]
      },
      steps: {
        kicker: "EMPIEZA EN MINUTOS",
        title: "Tu dinero más claro, ",
        gradient_text: "paso a paso.",
        description: "No necesitas ser experto en finanzas. Solo empieza por organizar lo que ya tienes.",
        items: [
          { title: "Configura tu espacio", description: "Agrega tus cuentas, tarjetas, ingresos y categorías para tener todo a la mano." },
          { title: "Registra tus movimientos", description: "Hazlo manualmente o aprovecha las herramientas de automatización con IA." },
          { title: "Decide con claridad", description: "Consulta tus reportes, ajusta tus presupuestos y avanza hacia tus metas." }
        ]
      },
      links: {
        kicker: "SIGUE APRENDIENDO",
        title: "Guías para empezar con buen pie",
        description: "Estas lecturas complementan la visión general de la aplicación.",
        cards: [
          { icon: "✦", title: "Qué es Yogasto", description: "Conoce qué puedes organizar y cómo empezar.", href: "/ayuda/primeros-pasos/que-es-yogasto" },
          { icon: "▤", title: "Registra tu primer gasto", description: "El paso a paso del formulario y el medio de pago.", href: "/ayuda/primeros-pasos/registrar-tu-primer-gasto" },
          { icon: "○", title: "Qué incluye el plan Gratis", description: "Empieza sin pagar y conoce las funciones esenciales.", href: "/ayuda/membresia-y-pagos/plan-gratis" },
          { icon: "✦", title: "Precios y planes", description: "Compara las opciones vigentes de Yogasto.", href: "/precios" }
        ]
      },
      cta: {
        kicker: "TU DINERO, MÁS CLARO",
        title: "Empieza a organizar tus gastos hoy.",
        description: "Crea tu cuenta, registra tus primeros movimientos y descubre lo fácil que puede ser tener todo en orden.",
        link_text: "Empieza gratis",
        href: "/users/sign_up"
      }
    },
    {
      path: "funciones/registrar-gastos-por-whatsapp",
      title: "Registra tus gastos por WhatsApp",
      h1: "Registra tus gastos por WhatsApp",
      seo_title: "Gastos por WhatsApp: registro automático",
      meta_description: "Registra gastos por WhatsApp con lenguaje natural, notas de voz o fotos. Yogasto interpreta valor, fecha y categoría y te deja revisar cada movimiento.",
      og_title: "Registrar gastos por WhatsApp",
      og_description: "Envía un mensaje como “Pagué 35.000 en gasolina” y Yogasto lo convierte en un gasto listo para revisar.",
      canonical_url: "https://yogasto.co/funciones/registrar-gastos-por-whatsapp",
      hero: {
        eyebrow: "REGISTRO POR WHATSAPP",
        description: "Escribe como le contarías a un amigo, envía una nota de voz o una foto del recibo. Yogasto interpreta el gasto y te deja revisarlo antes de guardarlo.",
        note: "Disponible con Yogasto Pro. Solo procesa los mensajes que envías a su número.",
        note_icon: "💬",
        variant: "lavender",
        show_art: true,
        art_style: "chat",
        art_greeting: "Pagué 35.000 en gasolina",
        art_message: "Registré tu gasto en Transporte.",
        art_reply: "¿Quieres revisarlo?",
        art_badge: "Sin formularios"
      },
      features: {
        kicker: "MENOS FRICCIÓN, MÁS REGISTRO",
        title: "Tu gasto favorito es ",
        gradient_text: "el que sí registras.",
        description: "El canal que ya usas todos los días se convierte en una forma rápida de mantener tus finanzas al día.",
        items: [
          { icon: "✎", color: "green", title: "Texto natural", description: "Describe el gasto con tus propias palabras, sin formatos ni comandos." },
          { icon: "🎙", color: "purple", title: "Notas de voz", description: "Habla con naturalidad y deja que Yogasto transcriba e interprete el gasto." },
          { icon: "📷", color: "blue", title: "Fotos de recibos", description: "Envía una imagen de un comprobante para extraer la información del movimiento." },
          { icon: "≡", color: "orange", title: "Varios gastos por mensaje", description: "Un solo mensaje puede separarse en movimientos individuales para revisar." }
        ]
      },
      content: {
        kicker: "ASÍ FUNCIONA",
        title: "De un mensaje a un gasto ",
        gradient_text: "organizado.",
        description: "El flujo está pensado para que registrar sea tan rápido como escribir, y para que tú conserves la última palabra.",
        blocks: [
          heading("Cómo funciona"),
          { type: "list", style: "ordered", items: "Entra a Configuración → WhatsApp y pulsa “Enviar mensaje a Yogasto”.\nEnvía el mensaje inicial desde el número que quieres asociar.\nEspera la confirmación de la conexión en el mismo chat.\nEscribe, graba una nota de voz o envía una foto con tu gasto.\nRevisa la confirmación o el candidato pendiente en la aplicación." },
          heading("Ejemplos prácticos"),
          example("EJEMPLO · GASOLINA", "Pagué 35.000 en gasolina", "Yogasto identifica el valor, la fecha y una categoría de transporte."),
          example("EJEMPLO · ALMUERZO", "Almorcé por 28.000", "El gasto queda asociado a alimentación y listo para revisar."),
          example("EJEMPLO · MERCADO", "Compré mercado por 150.000", "La descripción y el valor se convierten en un gasto de supermercado."),
          heading("Qué interpreta Yogasto"),
          paragraph("<p>Yogasto reconoce valores en pesos colombianos, fechas relativas como “hoy” o “ayer”, el comercio o la descripción del gasto y una categoría sugerida. Si mencionas el medio de pago, intenta asociarlo a la cuenta o tarjeta correspondiente. Cuando falta un dato, puede preguntarte en el chat o dejar el movimiento pendiente de revisión.</p>"),
          heading("Revisa y corrige"),
          paragraph("<p>Los gastos que la aplicación identifica con suficiente información se confirman y aparecen en <a href='/expenses'>Gastos</a>. Los que necesitan un dato adicional quedan en <a href='/expense_candidates'>candidatos a gasto</a>, donde puedes completar el valor, la fecha, la categoría o el medio de pago antes de confirmarlos o descartarlos. También puedes editarlos después como cualquier otro movimiento.</p>"),
          heading("Privacidad del canal"),
          paragraph("<p>Yogasto solo procesa los mensajes que tú decides enviar directamente a su cuenta de WhatsApp. No lee tus conversaciones personales ni accede a los chats con otras personas. Para evitar duplicados, conserva identificadores técnicos de los mensajes procesados durante un periodo limitado. Puedes ampliar esta información en la <a href='/privacidad'>política de privacidad</a>.</p>"),
          callout("El tutorial completo está en el Centro de ayuda", "Consulta <a href='/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp'>cómo registrar gastos por WhatsApp</a> para ver los pasos, los ejemplos y las situaciones frecuentes.", "note"),
          heading("Ideal si registras sobre la marcha"),
          paragraph("<p>Este canal es útil si pagas con frecuencia fuera de casa, si prefieres hablar en lugar de escribir o si quieres registrar el gasto en el momento para no olvidarlo. Si además recibes notificaciones bancarias, combínalo con <a href='/funciones/importar-gastos-desde-gmail'>la importación desde Gmail</a>.</p>")
        ]
      },
      links: {
        kicker: "APRENDE MÁS",
        title: "Todo sobre WhatsApp y la IA",
        description: "Guías relacionadas para aprovechar el canal y entender el procesamiento.",
        cards: [
          { icon: "◍", title: "Tutorial de WhatsApp", description: "Pasos, ejemplos, privacidad y solución de problemas.", href: "/ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp" },
          { icon: "✧", title: "Cómo funciona la IA", description: "Qué datos interpreta y cómo revisar los movimientos.", href: "/ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia" },
          { icon: "✎", title: "Lenguaje natural", description: "Registra varios gastos en una sola frase.", href: "/ayuda/herramientas-inteligentes/registrar-gastos-con-lenguaje-natural" },
          { icon: "✦", title: "Beneficios de Pro", description: "Conoce las funciones que incluye tu membresía.", href: "/ayuda/membresia-y-pagos/beneficios-de-yogasto-pro" }
        ]
      },
      cta: {
        kicker: "REGISTRA EN SEGUNDOS",
        title: "Convierte un mensaje en un gasto.",
        description: "Activa Yogasto Pro, asocia tu WhatsApp y empieza a registrar sin formularios.",
        link_text: "Empieza gratis",
        href: "/users/sign_up"
      }
    },
    {
      path: "funciones/importar-gastos-desde-gmail",
      title: "Importa gastos desde Gmail sin trabajo manual",
      h1: "Importa gastos desde Gmail sin trabajo manual",
      seo_title: "Importar gastos desde Gmail automáticamente",
      meta_description: "Yogasto identifica notificaciones bancarias en Gmail, extrae los datos del movimiento y te muestra candidatos para confirmar o descartar antes de guardar.",
      og_title: "Importar gastos desde Gmail",
      og_description: "Conecta tu correo, revisa los candidatos que Yogasto encuentra y confirma solo los movimientos que correspondan.",
      canonical_url: "https://yogasto.co/funciones/importar-gastos-desde-gmail",
      hero: {
        eyebrow: "AUTOMATIZACIÓN CON GMAIL",
        description: "Tus bancos ya envían notificaciones. Yogasto las convierte en candidatos a gasto para que solo tengas que revisar y confirmar.",
        note: "Acceso de solo lectura. Yogasto no guarda el cuerpo completo de tus correos.",
        note_icon: "✉",
        variant: "lavender",
        show_art: true,
        art_style: "chat",
        art_greeting: "Compra aprobada por $86.500",
        art_message: "Identifiqué el valor y el comercio.",
        art_reply: "Quedó listo para revisar.",
        art_badge: "Menos registro manual"
      },
      features: {
        kicker: "DEL CORREO AL MOVIMIENTO",
        title: "La notificación llega. ",
        gradient_text: "Yogasto la organiza.",
        description: "La automatización reduce el trabajo repetitivo, pero mantiene tu revisión en el centro del proceso.",
        items: [
          { icon: "✉", color: "blue", title: "Notificaciones bancarias", description: "Identifica compras y cargos en los correos que coinciden con tus fuentes." },
          { icon: "✧", color: "purple", title: "Extracción con IA", description: "Reconoce valor, fecha, comercio y datos de la tarjeta cuando están disponibles." },
          { icon: "✓", color: "green", title: "Candidatos revisables", description: "Los movimientos incompletos quedan pendientes para que los confirmes o descartes." },
          { icon: "🔒", color: "orange", title: "Control y privacidad", description: "Acceso de solo lectura, tokens cifrados y desconexión cuando quieras." }
        ]
      },
      content: {
        kicker: "CÓMO FUNCIONA",
        title: "Un flujo claro, ",
        gradient_text: "sin sorpresas.",
        description: "Yogasto no se conecta automáticamente a tu banco ni mueve dinero. Trabaja con los correos que autorizas y te devuelve el control antes de guardar.",
        blocks: [
          heading("El flujo completo"),
          { type: "list", style: "ordered", items: "Configuras tus fuentes de dinero y los remitentes o asuntos que identifican a tu banco.\nConectas Gmail con OAuth y autorizas el acceso de lectura.\nYogasto busca las notificaciones que coinciden con tus fuentes.\nExtrae los datos del movimiento y crea el gasto o un candidato pendiente.\nRevisas, completas si falta algo y confirmas o descartas." },
          heading("Qué correos puede identificar"),
          paragraph("<p>Yogasto se enfoca en notificaciones de compras, cargos y consumos enviadas por bancos y emisores de tarjeta. Los correos promocionales, los resúmenes sin una transacción concreta y los mensajes de fuentes no configuradas se ignoran. También puedes configurar remitentes, asuntos y palabras clave para afinar la búsqueda.</p>"),
          heading("Qué información extrae"),
          { type: "list", style: "unordered", items: "Valor y moneda del movimiento.\nFecha de la compra o del cargo.\nComercio o descripción.\nBanco o tarjeta cuando el correo lo indica.\nÚltimos cuatro dígitos de la tarjeta, si aparecen.\nCategoría sugerida." },
          heading("Confirmación de candidatos"),
          paragraph("<p>Cuando la información es suficiente, el gasto se crea y queda disponible en <a href='/expenses'>Gastos</a>. Si falta un dato o la interpretación no es concluyente, el movimiento queda en <a href='/expense_candidates'>candidatos a gasto</a> para que lo revises. Un candidato no se convierte en gasto definitivo hasta que lo confirmas.</p>"),
          heading("Privacidad y retención"),
          paragraph("<p>La conexión usa permisos de solo lectura: Yogasto no envía correos en tu nombre, no modifica tu bandeja y no elimina mensajes. No guarda el cuerpo completo de tus correos; el contenido se procesa de forma temporal para extraer los datos del movimiento. Conserva el asunto, los datos del gasto y un identificador técnico para evitar duplicados. Al desconectar, se eliminan los tokens de acceso.</p>"),
          callout("El tutorial completo está en el Centro de ayuda", "Consulta <a href='/ayuda/herramientas-inteligentes/conectar-gmail'>cómo conectar Gmail</a> para ver los permisos, el paso a paso y qué ocurre cuando un correo no se puede procesar.", "note"),
          heading("Ideal si recibes muchas notificaciones"),
          paragraph("<p>Este flujo es útil si tu banco envía un correo por cada compra, si usas varias tarjetas o si quieres reducir el registro manual sin perder la revisión. Si además quieres registrar gastos en el momento, combínalo con <a href='/funciones/registrar-gastos-por-whatsapp'>el registro por WhatsApp</a>.</p>")
        ]
      },
      links: {
        kicker: "SIGUE APRENDIENDO",
        title: "Guías de Gmail y automatización",
        description: "Encuentra el detalle técnico y las respuestas a las situaciones frecuentes.",
        cards: [
          { icon: "✉", title: "Tutorial de Gmail", description: "Conexión, permisos, candidatos y desconexión.", href: "/ayuda/herramientas-inteligentes/conectar-gmail" },
          { icon: "✧", title: "Registro con IA", description: "Cómo Yogasto interpreta correos, textos e imágenes.", href: "/ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia" },
          { icon: "💬", title: "Registro por WhatsApp", description: "Otra forma de automatizar el registro diario.", href: "/funciones/registrar-gastos-por-whatsapp" },
          { icon: "✦", title: "Precios y planes", description: "Consulta las opciones vigentes de membresía.", href: "/precios" }
        ]
      },
      cta: {
        kicker: "AUTOMATIZA TU REGISTRO",
        title: "Deja que tus notificaciones trabajen por ti.",
        description: "Conecta Gmail, revisa los candidatos y confirma solo los movimientos que correspondan.",
        link_text: "Empieza gratis",
        href: "/users/sign_up"
      }
    },
    {
      path: "funciones/asistente-financiero-con-ia",
      title: "Tu asistente financiero con inteligencia artificial",
      h1: "Tu asistente financiero con inteligencia artificial",
      seo_title: "Asistente financiero con IA para tus gastos",
      meta_description: "Pregunta por tus gastos, ingresos, categorías y deudas. El asistente financiero con IA de Yogasto analiza tus datos registrados y sugiere dónde ajustar.",
      og_title: "Asistente financiero con IA",
      og_description: "Analiza tus gastos, compara periodos y descubre oportunidades de ahorro conversando con el Chat Financiero de Yogasto.",
      canonical_url: "https://yogasto.co/funciones/asistente-financiero-con-ia",
      hero: {
        eyebrow: "ANÁLISIS CON IA",
        description: "Haz preguntas sobre tus gastos, ingresos, categorías, deudas y metas. El asistente analiza la información que registras y te ayuda a convertirla en decisiones concretas.",
        note: "Conversación de solo lectura. Tú decides qué cambios hacer.",
        note_icon: "✧",
        variant: "lavender",
        show_art: true,
        art_style: "chat",
        art_greeting: "¿En qué gasté más este mes?",
        art_message: "Alimentación concentra $620.000.",
        art_reply: "Puedes ajustar $80.000.",
        art_badge: "Análisis en segundos"
      },
      features: {
        kicker: "PREGUNTA, ENTIENDE, DECIDE",
        title: "Tus datos financieros, ",
        gradient_text: "en una conversación.",
        description: "El asistente no adivina: trabaja con los movimientos, presupuestos y deudas que ya están en tu cuenta.",
        items: [
          { icon: "◫", color: "pink", title: "Análisis por categoría", description: "Descubre qué categorías concentran tu gasto y cómo cambian en el tiempo." },
          { icon: "⇄", color: "blue", title: "Ingresos vs. gastos", description: "Compara lo que entra y lo que sale para entender tu margen del periodo." },
          { icon: "⌁", color: "green", title: "Patrones de gasto", description: "Identifica concentraciones, aumentos y hábitos que se repiten." },
          { icon: "✦", color: "purple", title: "Oportunidades de ahorro", description: "Recibe sugerencias concretas para ajustar sin perder de vista lo importante." }
        ]
      },
      content: {
        kicker: "EJEMPLOS DE USO",
        title: "Preguntas que puedes hacerle ",
        gradient_text: "a tus finanzas.",
        description: "El Chat Financiero responde en lenguaje natural y usa pesos colombianos en sus ejemplos y cálculos.",
        blocks: [
          heading("Qué puedes preguntar"),
          example("CATEGORÍAS", "¿En qué categorías gasté más este mes?", "Ordena las categorías por valor y muestra el peso de cada una en tu gasto total."),
          example("COMPARACIÓN", "¿Cuánto gasté en alimentación entre septiembre y octubre?", "Compara ambos periodos y explica la diferencia en pesos y porcentaje."),
          example("FLUJO", "¿Mis ingresos cubren mis gastos fijos?", "Contrasta ingresos y gastos recurrentes para mostrar el margen disponible."),
          example("DEUDAS", "¿Cuánto debo en mis tarjetas y cuánto cupo tengo?", "Resume deuda, cupo utilizado y cupo disponible por tarjeta."),
          example("AHORRO", "¿Dónde puedo ahorrar $200.000 al mes?", "Señala categorías con mayor peso y propone ajustes concretos para evaluar."),
          heading("Cómo se conecta con tus datos"),
          paragraph("<p>El asistente usa los movimientos, presupuestos, cuentas, tarjetas, créditos y metas que has registrado. Si un dato no existe, lo indica en lugar de inventarlo. Cuando detecta que una respuesta anterior quedó desactualizada, puede corregirla con la información vigente.</p>"),
          heading("Qué no hace el asistente"),
          { type: "list", style: "unordered", items: "No crea, edita ni elimina gastos, ingresos, presupuestos, metas o pagos.\nNo mueve dinero ni ejecuta transferencias.\nNo garantiza resultados futuros ni reemplaza asesoría financiera profesional.\nNo conoce información que no hayas registrado en Yogasto." },
          heading("Del análisis a la acción"),
          paragraph("<p>Las respuestas son un punto de partida. Si el chat sugiere un ajuste, puedes crear un presupuesto en <a href='/budgets'>Presupuestos</a>, una meta en <a href='/goals'>Metas</a> o revisar tus <a href='/savings_opportunities'>oportunidades de ahorro</a>. También puedes consultar tus <a href='/financial_habits'>hábitos financieros</a> para entender qué se repite cada mes.</p>"),
          callout("El tutorial completo está en el Centro de ayuda", "Consulta <a href='/ayuda/herramientas-inteligentes/chat-financiero'>cómo usar el Chat Financiero</a> para ver más ejemplos, limitaciones y la diferencia con el registro automático de gastos.", "note"),
          heading("Asistente y registro automático: dos herramientas distintas"),
          paragraph("<p>El asistente analiza y conversa; el registro con IA crea movimientos a partir de mensajes, correos, imágenes o archivos. Si tu objetivo es dejar de registrar a mano, empieza por <a href='/funciones/registrar-gastos-por-whatsapp'>WhatsApp</a> o por <a href='/funciones/importar-gastos-desde-gmail'>Gmail</a>. Si tu objetivo es entender lo que ya registraste, usa el Chat Financiero.</p>")
        ]
      },
      links: {
        kicker: "EXPLORA EL ANÁLISIS",
        title: "Guías para sacar más provecho",
        description: "Aprende a interpretar tus datos y a convertir las sugerencias en acciones.",
        cards: [
          { icon: "◌", title: "Tutorial del Chat Financiero", description: "Ejemplos, alcance y limitaciones de la IA.", href: "/ayuda/herramientas-inteligentes/chat-financiero" },
          { icon: "✦", title: "Beneficios de Pro", description: "Conoce las funciones de análisis y automatización.", href: "/ayuda/membresia-y-pagos/beneficios-de-yogasto-pro" },
          { icon: "▤", title: "Cómo funcionan las categorías", description: "Organiza mejor tus movimientos y reportes.", href: "/ayuda/gastos-e-ingresos/como-funcionan-las-categorias" },
          { icon: "✦", title: "Precios y planes", description: "Consulta las opciones vigentes de membresía.", href: "/precios" }
        ]
      },
      cta: {
        kicker: "CONVERSA CON TUS FINANZAS",
        title: "Hazle una pregunta a tus datos.",
        description: "Activa Yogasto Pro y usa el Chat Financiero para entender tus hábitos y encontrar oportunidades de ajuste.",
        link_text: "Empieza gratis",
        href: "/users/sign_up"
      }
    },
    {
      path: "finanzas-personales-colombia",
      title: "Finanzas personales en Colombia: ordena tu dinero en pesos",
      h1: "Finanzas personales en Colombia: ordena tu dinero en pesos",
      seo_title: "Finanzas personales en Colombia",
      meta_description: "Guía práctica para organizar tus finanzas personales en Colombia: gastos en pesos, presupuestos, cuentas, tarjetas de crédito y hábitos de ahorro.",
      og_title: "Finanzas personales en Colombia",
      og_description: "Organiza tus gastos en pesos, tus cuentas y tarjetas, y construye una rutina financiera adaptada al día a día colombiano.",
      canonical_url: "https://yogasto.co/finanzas-personales-colombia",
      hero: {
        eyebrow: "FINANZAS EN COLOMBIA",
        description: "Organizar tus finanzas en Colombia empieza por entender tus pesos, tus cuentas y tus compromisos. Yogasto te ayuda a registrar y leer esa información sin depender de una conexión bancaria automática.",
        note: "Pesos colombianos, cuentas, tarjetas y presupuestos en un solo lugar.",
        note_icon: "▣",
        variant: "lavender",
        show_art: true,
        art_style: "chat",
        art_greeting: "¿Cuánto gasté en mercado?",
        art_message: "$ 480.000 en Alimentación.",
        art_reply: "Vas dentro del presupuesto.",
        art_badge: "Todo en pesos"
      },
      features: {
        kicker: "UN CONTEXTO COTIDIANO",
        title: "Tu día a día financiero, ",
        gradient_text: "en pesos y en orden.",
        description: "Varias cuentas, efectivo, billeteras digitales y tarjetas pueden convivir en una misma visión.",
        items: [
          { icon: "$", color: "green", title: "Montos en COP", description: "Registra y consulta tus movimientos en pesos colombianos." },
          { icon: "◇", color: "blue", title: "Varias cuentas", description: "Bancos, efectivo y billeteras digitales en un mismo espacio." },
          { icon: "▣", color: "orange", title: "Tarjetas de crédito", description: "Cupo, deuda y pagos para seguir tus obligaciones." },
          { icon: "◎", color: "purple", title: "Presupuestos", description: "Límites por categoría para organizar el mes." },
          { icon: "◇", color: "green", title: "Metas de ahorro", description: "Separa dinero y sigue el avance de tus objetivos." },
          { icon: "▤", color: "pink", title: "Reportes", description: "Entiende tus hábitos y compara periodos." }
        ]
      },
      content: {
        kicker: "ORGANIZACIÓN LOCAL",
        title: "Una rutina financiera que ",
        gradient_text: "se adapta a tu realidad.",
        description: "No existe una sola forma de manejar el dinero. Yogasto te ayuda a construir la tuya con información clara y sin promesas de rendimientos.",
        blocks: [
          heading("Por qué organizar tus finanzas en pesos"),
          paragraph("<p>La mayoría de tus gastos, ingresos y obligaciones están en pesos colombianos. Verlos juntos y en la misma unidad te ayuda a comparar, presupuestar y detectar desbalances. También evita que una compra con tarjeta, un retiro en efectivo o una transferencia entre cuentas se pierdan en registros separados.</p>"),
          heading("Situaciones comunes en Colombia"),
          { type: "list", style: "unordered", items: "Recibir ingresos en una cuenta y pagar desde otra.\nUsar efectivo para compras pequeñas y tarjeta para compras grandes.\nTener varias tarjetas de crédito con fechas de corte y pago distintas.\nCombinar billeteras digitales, cuentas bancarias y efectivo.\nEnfrentar meses con ingresos variables o gastos extraordinarios.\nPagar servicios y suscripciones que se repiten cada mes." },
          heading("Cómo Yogasto se adapta a ese contexto"),
          { type: "list", style: "unordered", items: "Registra cuentas, efectivo, billeteras y tarjetas con sus saldos.\nOrganiza gastos e ingresos por categorías y periodos.\nDistingue una compra con tarjeta de un pago de la tarjeta.\nPermite presupuestar y comparar el avance del mes.\nAutomatiza el registro con WhatsApp, Gmail e IA cuando tienes Pro." },
          heading("Un punto de partida en tres pasos"),
          { type: "list", style: "ordered", items: "Crea tu cuenta y agrega los medios de dinero que usas hoy.\nRegistra los movimientos de una semana para tener una base real.\nRevisa tus categorías, define un presupuesto y ajusta lo que necesites." },
          heading("Lo que Yogasto no hace"),
          paragraph("<p>Yogasto no se conecta automáticamente a tu banco, no realiza pagos, no mueve dinero y no solicita tus claves de banca en línea. Tampoco promete rendimientos ni reemplaza asesoría financiera profesional. La información se registra manualmente o se procesa a partir de los mensajes y correos que tú autorizas.</p>"),
          callout("Empieza con lo que ya tienes", "No necesitas cambiar de banco ni reunir todos tus datos históricos. Empieza por una cuenta y los movimientos de esta semana.", "tip"),
          heading("Sigue aprendiendo"),
          paragraph("<p>Consulta <a href='/ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta'>qué es una cuenta en Yogasto</a>, <a href='/ayuda/cuentas-y-medios-de-dinero/diferencia-entre-cuenta-y-tarjeta'>la diferencia entre una cuenta y una tarjeta</a> y <a href='/ayuda/cuentas-y-medios-de-dinero/dia-de-balance'>qué es el Día de Balance</a>. Si quieres una visión general de la aplicación, visita <a href='/funciones/app-para-controlar-gastos'>la app para controlar gastos personales</a>.</p>")
        ]
      },
      links: {
        kicker: "MÁS GUÍAS",
        title: "Aprende a organizar cada pieza",
        description: "Contenido relacionado para cuentas, tarjetas y registro de movimientos.",
        cards: [
          { icon: "◇", title: "¿Qué es una cuenta?", description: "Tipos de cuentas y medios de dinero que puedes organizar.", href: "/ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta" },
          { icon: "▣", title: "Agrega una tarjeta de crédito", description: "Registra cupo, deuda y pagos de tu tarjeta.", href: "/ayuda/cuentas-y-medios-de-dinero/agregar-una-tarjeta-de-credito" },
          { icon: "▤", title: "Registra un gasto", description: "El paso a paso para crear un movimiento.", href: "/ayuda/gastos-e-ingresos/registrar-un-gasto" },
          { icon: "✦", title: "Precios y planes", description: "Compara las opciones vigentes de Yogasto.", href: "/precios" }
        ]
      },
      cta: {
        kicker: "TU DINERO, EN PESOS Y EN ORDEN",
        title: "Empieza a organizar tus finanzas hoy.",
        description: "Crea tu cuenta, registra tus primeros movimientos y construye una rutina financiera que puedas sostener.",
        link_text: "Empieza gratis",
        href: "/users/sign_up"
      }
    }
  ].freeze

  HOME_LINKS = {
    kicker: "EXPLORA YOGASTO",
    title: "Encuentra la herramienta que necesitas",
    description: "Conoce las formas de registrar y entender tu dinero, y elige por dónde empezar.",
    cards: [
      { icon: "▥", title: "Controla tus gastos", description: "Una visión completa de tus gastos, cuentas, tarjetas y presupuestos.", href: "/funciones/app-para-controlar-gastos" },
      { icon: "💬", title: "Registra por WhatsApp", description: "Convierte un mensaje, una nota de voz o una foto en un gasto.", href: "/funciones/registrar-gastos-por-whatsapp" },
      { icon: "✉", title: "Importa desde Gmail", description: "Identifica notificaciones bancarias y revisa los candidatos.", href: "/funciones/importar-gastos-desde-gmail" },
      { icon: "✧", title: "Asistente con IA", description: "Pregunta por tus hábitos y descubre oportunidades de ajuste.", href: "/funciones/asistente-financiero-con-ia" },
      { icon: "▣", title: "Finanzas en Colombia", description: "Organiza tus pesos, cuentas y compromisos del día a día.", href: "/finanzas-personales-colombia" }
    ]
  }.freeze

  FOOTER_LINKS = [
    { label: "Controla tus gastos", href: "/funciones/app-para-controlar-gastos" },
    { label: "Gastos por WhatsApp", href: "/funciones/registrar-gastos-por-whatsapp" },
    { label: "Importar desde Gmail", href: "/funciones/importar-gastos-desde-gmail" },
    { label: "Asistente financiero con IA", href: "/funciones/asistente-financiero-con-ia" },
    { label: "Finanzas personales en Colombia", href: "/finanzas-personales-colombia" }
  ].freeze
end
