# frozen_string_literal: true

# Initial content for the Maglev-backed help center. The seeder creates each
# page once and never overwrites editor changes.
module HelpCenterSeed
  module_function

  def category(path:, name:, description:, icon:, position:)
    {
      path: path,
      name: name,
      description: description,
      icon: icon,
      position: position
    }
  end

  def article(path:, title:, summary:, blocks:, icon: "▤", position: 1,
              popular: false, featured: false, related_paths: [], publish: true)
    {
      path: path,
      title: title,
      summary: summary,
      icon: icon,
      position: position,
      popular: popular,
      featured: featured,
      related_paths: related_paths,
      blocks: blocks,
      publish: publish
    }
  end

  def paragraph(html)
    { type: "paragraph", text: html }
  end

  def heading(text, level: "2")
    { type: "heading", level: level, text: text }
  end

  def callout(title, text, variant = "tip")
    { type: "callout", title: title, text: text, variant: variant }
  end

  CATEGORIES = [
    category(
      path: "ayuda/primeros-pasos",
      name: "Primeros pasos",
      description: "Crea tu cuenta, configura tu perfil y registra tu primer movimiento.",
      icon: "①",
      position: 1
    ),
    category(
      path: "ayuda/gastos-e-ingresos",
      name: "Gastos e ingresos",
      description: "Aprende a registrar, editar y organizar tus movimientos.",
      icon: "↕",
      position: 2
    ),
    category(
      path: "ayuda/cuentas-y-medios-de-dinero",
      name: "Cuentas y medios de dinero",
      description: "Organiza cuentas, efectivo, tarjetas, bolsillos y deudas.",
      icon: "◇",
      position: 3
    ),
    category(
      path: "ayuda/membresia-y-pagos",
      name: "Membresía y pagos",
      description: "Conoce los planes y cómo funciona el pago de tu membresía.",
      icon: "✦",
      position: 4
    ),
    category(
      path: "ayuda/herramientas-inteligentes",
      name: "Herramientas inteligentes",
      description: "Usa la IA, Gmail, WhatsApp y el Chat Financiero a tu favor.",
      icon: "✧",
      position: 5
    )
  ].freeze

  ARTICLES = [
    article(
      path: "ayuda/primeros-pasos/que-es-yogasto",
      title: "¿Qué es Yogasto y cómo te ayuda?",
      summary: "Conoce qué puedes organizar en Yogasto y cómo empezar con buen pie.",
      icon: "✦",
      position: 1,
      popular: true,
      featured: true,
      related_paths: [
        "ayuda/primeros-pasos/crear-cuenta",
        "ayuda/primeros-pasos/registrar-tu-primer-gasto",
        "ayuda/gastos-e-ingresos/registrar-un-gasto"
      ],
      blocks: [
        paragraph("<p>Yogasto es una aplicación para organizar tus finanzas personales: tus gastos, ingresos, cuentas, tarjetas, presupuestos, metas y reportes en un mismo lugar.</p>"),
        heading("Qué puedes hacer"),
        paragraph("<ul><li>Registrar gastos e ingresos y saber en qué se va tu dinero.</li><li>Organizar cuentas, efectivo, tarjetas y deudas.</li><li>Consultar reportes, presupuestos y metas.</li><li>Usar herramientas de IA para registrar movimientos y entender mejor tus finanzas.</li></ul>"),
        heading("Cómo empezar"),
        paragraph("<ol><li>Crea tu cuenta y confirma tu correo.</li><li>Agrega al menos una cuenta o medio de dinero.</li><li>Registra tu primer gasto o ingreso.</li><li>Revisa tus reportes y ajusta lo que necesites.</li></ol>"),
        callout("Empieza simple", "No necesitas configurarlo todo el primer día. Empieza por registrar los movimientos que ya tienes y ve completando tu espacio poco a poco.")
      ]
    ),
    article(
      path: "ayuda/primeros-pasos/crear-cuenta",
      title: "Cómo crear tu cuenta en Yogasto",
      summary: "Regístrate, confirma tu correo y empieza a organizar tus finanzas.",
      icon: "✎",
      position: 2,
      popular: true,
      related_paths: [
        "ayuda/primeros-pasos/que-es-yogasto",
        "ayuda/primeros-pasos/configurar-tu-perfil",
        "ayuda/primeros-pasos/registrar-tu-primer-gasto"
      ],
      blocks: [
        paragraph("<p>Para crear tu cuenta entra a <a href='/users/sign_up'>Crear cuenta</a> y completa el formulario con tu nombre, correo electrónico y contraseña.</p>"),
        heading("Paso a paso"),
        paragraph("<ol><li>Abre la página de registro.</li><li>Escribe tu nombre y un correo al que tengas acceso.</li><li>Crea una contraseña y confírmala.</li><li>Envía el formulario y revisa tu correo para confirmar la cuenta.</li><li>Inicia sesión con tu correo y contraseña.</li></ol>"),
        callout("Revisa tu correo", "Si no encuentras el mensaje de confirmación, revisa la carpeta de spam o promociones antes de volver a intentarlo.", "note"),
        callout("Tu contraseña es personal", "No compartas tu contraseña con nadie. Si necesitas recuperarla, usa la opción de recuperación de contraseña.", "warning")
      ]
    ),
    article(
      path: "ayuda/primeros-pasos/configurar-tu-perfil",
      title: "Cómo configurar tu perfil",
      summary: "Revisa tus datos y mantén actualizada la información de tu cuenta.",
      icon: "◯",
      position: 3,
      related_paths: [
        "ayuda/primeros-pasos/crear-cuenta",
        "ayuda/membresia-y-pagos/plan-gratis"
      ],
      blocks: [
        paragraph("<p>En <a href='/profile'>Perfil</a> puedes revisar la información de tu cuenta y acceder a las opciones de configuración.</p>"),
        heading("Qué puedes revisar"),
        paragraph("<ul><li>Tu nombre y correo electrónico.</li><li>El estado de tu contraseña.</li><li>Los accesos a la configuración de tu cuenta y de tus herramientas.</li></ul>"),
        callout("Si cambias tu correo", "Revisa el mensaje de confirmación que enviamos a la nueva dirección antes de cerrar la sesión.", "note")
      ]
    ),
    article(
      path: "ayuda/primeros-pasos/registrar-tu-primer-gasto",
      title: "Cómo registrar tu primer gasto",
      summary: "Aprende a crear un gasto y a asociarlo con una cuenta o medio de dinero.",
      icon: "▤",
      position: 4,
      popular: true,
      related_paths: [
        "ayuda/gastos-e-ingresos/registrar-un-gasto",
        "ayuda/cuentas-y-medios-de-dinero/agregar-una-cuenta",
        "ayuda/primeros-pasos/que-es-yogasto"
      ],
      blocks: [
        paragraph("<p>Para registrar un gasto entra a <a href='/expenses/new'>Nuevo gasto</a>. Antes de guardarlo necesitas tener al menos una cuenta o medio de dinero creado.</p>"),
        heading("Completa el gasto"),
        paragraph("<ul><li><strong>Valor:</strong> el monto que pagaste.</li><li><strong>Fecha:</strong> cuándo ocurrió el movimiento.</li><li><strong>Descripción:</strong> una frase que te ayude a recordarlo.</li><li><strong>Categoría:</strong> el grupo al que pertenece.</li><li><strong>Medio de pago:</strong> la cuenta, efectivo o tarjeta con la que pagaste.</li></ul>"),
        callout("Si aún no tienes un medio de pago", "Crea primero una cuenta, efectivo o tarjeta en <a href='/money_sources'>Cuentas y tarjetas</a> y vuelve al formulario.", "tip")
      ]
    ),

    article(
      path: "ayuda/gastos-e-ingresos/registrar-un-gasto",
      title: "Cómo registrar un gasto",
      summary: "Registra un gasto con su valor, fecha, categoría y medio de pago.",
      icon: "↘",
      position: 1,
      popular: true,
      related_paths: [
        "ayuda/gastos-e-ingresos/registrar-un-ingreso",
        "ayuda/gastos-e-ingresos/editar-o-eliminar-un-movimiento",
        "ayuda/gastos-e-ingresos/como-funcionan-las-categorias"
      ],
      blocks: [
        paragraph("<p>Entra a <a href='/expenses/new'>Nuevo gasto</a> y completa la información del movimiento. El formulario te pide el valor, la fecha, una descripción, la categoría y el medio de pago.</p>"),
        heading("Buenas prácticas"),
        paragraph("<ul><li>Usa descripciones claras y cortas.</li><li>Selecciona siempre el medio de pago correcto.</li><li>Asigna una categoría para que tus reportes sean más útiles.</li></ul>"),
        callout("El medio de pago es obligatorio", "Si el formulario no te deja guardar, revisa que hayas elegido una cuenta, efectivo o tarjeta.", "warning")
      ]
    ),
    article(
      path: "ayuda/gastos-e-ingresos/registrar-un-ingreso",
      title: "Cómo registrar un ingreso",
      summary: "Añade el dinero que entra y asígnalo a la cuenta correcta.",
      icon: "↗",
      position: 2,
      popular: true,
      related_paths: [
        "ayuda/gastos-e-ingresos/registrar-un-gasto",
        "ayuda/gastos-e-ingresos/editar-o-eliminar-un-movimiento",
        "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta"
      ],
      blocks: [
        paragraph("<p>Para registrar un ingreso entra a <a href='/incomes/new'>Nuevo ingreso</a>. Completa el valor, la fecha, la descripción, la categoría y el medio de dinero al que entró.</p>"),
        heading("Para qué sirve"),
        paragraph("<p>Registrar tus ingresos te ayuda a entender cuánto dinero entra, compararlo con tus gastos y calcular tu capacidad de ahorro.</p>"),
        callout("Revisa el medio de dinero", "Selecciona la cuenta o medio donde realmente entró el dinero. Así los saldos y reportes se mantienen consistentes.", "tip")
      ]
    ),
    article(
      path: "ayuda/gastos-e-ingresos/editar-o-eliminar-un-movimiento",
      title: "Cómo editar o eliminar un gasto o ingreso",
      summary: "Corrige un movimiento o elimínalo cuando ya no corresponda.",
      icon: "✎",
      position: 3,
      related_paths: [
        "ayuda/gastos-e-ingresos/registrar-un-gasto",
        "ayuda/gastos-e-ingresos/registrar-un-ingreso"
      ],
      blocks: [
        paragraph("<p>Puedes editar o eliminar un movimiento desde las páginas de <a href='/expenses'>Gastos</a> e <a href='/incomes'>Ingresos</a>. Abre el movimiento y elige la acción correspondiente.</p>"),
        heading("Antes de eliminar"),
        paragraph("<ul><li>Revisa que no sea un movimiento que quieras conservar para tus reportes.</li><li>Ten en cuenta que eliminar un movimiento también revierte su efecto sobre el saldo de la cuenta asociada.</li></ul>"),
        callout("Los cambios afectan tus saldos", "Si editas el valor o el medio de pago, los saldos y reportes se actualizan con la nueva información.", "warning")
      ]
    ),
    article(
      path: "ayuda/gastos-e-ingresos/como-funcionan-las-categorias",
      title: "Cómo funcionan las categorías",
      summary: "Usa categorías para agrupar tus movimientos y leer mejor tus reportes.",
      icon: "◫",
      position: 4,
      related_paths: [
        "ayuda/gastos-e-ingresos/registrar-un-gasto",
        "ayuda/gastos-e-ingresos/registrar-un-ingreso"
      ],
      blocks: [
        paragraph("<p>Las categorías agrupan tus gastos e ingresos por tipo. Por ejemplo, puedes separar alimentación, transporte, vivienda o salario.</p>"),
        heading("Cómo aprovecharlas"),
        paragraph("<ul><li>Asigna una categoría a cada movimiento.</li><li>Revisa tus reportes por categoría para detectar en qué gastas más.</li><li>Ajusta tus presupuestos con esa información.</li></ul>"),
        callout("Menos categorías, más claridad", "Al principio es mejor tener pocas categorías bien definidas que muchas categorías difíciles de distinguir.", "tip")
      ]
    ),
    article(
      path: "ayuda/gastos-e-ingresos/como-funcionan-los-recurrentes",
      title: "Cómo funcionan los gastos e ingresos recurrentes",
      summary: "Organiza los movimientos que se repiten y revísalos cuando ocurran.",
      icon: "↻",
      position: 5,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/dia-de-balance",
        "ayuda/gastos-e-ingresos/registrar-un-gasto"
      ],
      blocks: [
        paragraph("<p>Los recurrentes te ayudan a recordar y organizar movimientos que se repiten, como servicios, suscripciones o ingresos fijos. Puedes gestionarlos desde <a href='/recurring_templates'>Recurrentes</a>.</p>"),
        heading("Cómo usarlos"),
        paragraph("<ol><li>Crea una plantilla con la información del movimiento.</li><li>Revisa los pagos pendientes del periodo.</li><li>Asigna el movimiento real cuando ocurra.</li></ol>"),
        callout("No es un cobro automático", "La plantilla organiza tu seguimiento; no mueve dinero ni realiza pagos por ti.", "warning")
      ]
    ),

    article(
      path: "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta",
      title: "¿Qué es una cuenta en Yogasto?",
      summary: "Conoce los tipos de cuentas y medios de dinero que puedes organizar.",
      icon: "◇",
      position: 1,
      popular: true,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/agregar-una-cuenta",
        "ayuda/cuentas-y-medios-de-dinero/diferencia-entre-cuenta-y-tarjeta",
        "ayuda/cuentas-y-medios-de-dinero/dia-de-balance"
      ],
      blocks: [
        paragraph("<p>En Yogasto una cuenta o medio de dinero representa dónde está tu dinero o de dónde sale cuando pagas. Puedes organizar cuentas bancarias, efectivo, billeteras, tarjetas, bolsillos y préstamos.</p>"),
        heading("Tipos disponibles"),
        paragraph("<ul><li><strong>Cuenta:</strong> dinero disponible en una entidad financiera.</li><li><strong>Efectivo:</strong> dinero que tienes físicamente.</li><li><strong>Billetera:</strong> saldo en una billetera digital.</li><li><strong>Tarjeta de crédito:</strong> cupo disponible y deuda asociada.</li><li><strong>Préstamo:</strong> obligación que vas pagando con el tiempo.</li><li><strong>Bolsillo:</strong> dinero apartado dentro de tus cuentas para un objetivo.</li></ul>"),
        callout("Un lugar para cada cosa", "Separar tus cuentas te ayuda a entender mejor tus saldos y a tomar decisiones con información más clara.", "tip")
      ]
    ),
    article(
      path: "ayuda/cuentas-y-medios-de-dinero/agregar-una-cuenta",
      title: "Cómo agregar una cuenta o medio de dinero",
      summary: "Crea una cuenta, efectivo, billetera o tarjeta para asociar tus movimientos.",
      icon: "＋",
      position: 2,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta",
        "ayuda/cuentas-y-medios-de-dinero/agregar-una-tarjeta-de-credito",
        "ayuda/primeros-pasos/registrar-tu-primer-gasto"
      ],
      blocks: [
        paragraph("<p>Entra a <a href='/money_sources'>Cuentas y tarjetas</a> y elige el tipo de medio de dinero que quieres agregar. Completa su nombre y los datos que te pida el formulario.</p>"),
        heading("Para tener en cuenta"),
        paragraph("<ul><li>Usa un nombre que reconozcas fácilmente.</li><li>Registra el saldo inicial si ya tienes dinero en ese medio.</li><li>Puedes crear cuentas, efectivo, billeteras, tarjetas, préstamos y bolsillos.</li></ul>"),
        callout("Los movimientos se asocian al medio", "Cuando registres un gasto o ingreso, elige el medio correcto para que los saldos sean coherentes.", "tip")
      ]
    ),
    article(
      path: "ayuda/cuentas-y-medios-de-dinero/agregar-una-tarjeta-de-credito",
      title: "Cómo agregar una tarjeta de crédito",
      summary: "Registra tu tarjeta y su cupo para seguir tus compras y tu deuda.",
      icon: "▣",
      position: 3,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/diferencia-entre-cuenta-y-tarjeta",
        "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta"
      ],
      blocks: [
        paragraph("<p>En <a href='/money_sources/new?kind=credit_card'>Cuentas y tarjetas</a> elige la opción de tarjeta de crédito y completa la información que te pida el formulario, como el nombre, el cupo y las fechas de corte y pago cuando correspondan.</p>"),
        heading("Qué puedes controlar"),
        paragraph("<ul><li>El cupo total de la tarjeta.</li><li>El cupo utilizado y el disponible.</li><li>Las compras y los pagos asociados.</li></ul>"),
        callout("Yogasto no mueve tu tarjeta", "La aplicación organiza y registra la información; no realiza pagos ni modifica tu tarjeta real.", "warning")
      ]
    ),
    article(
      path: "ayuda/cuentas-y-medios-de-dinero/diferencia-entre-cuenta-y-tarjeta",
      title: "Diferencia entre una cuenta y una tarjeta de crédito",
      summary: "Entiende cómo se comportan los saldos de una cuenta y de una tarjeta.",
      icon: "⇄",
      position: 4,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta",
        "ayuda/cuentas-y-medios-de-dinero/agregar-una-tarjeta-de-credito"
      ],
      blocks: [
        paragraph("<p>Una cuenta o un medio de dinero disponible representa dinero que tienes. Una tarjeta de crédito representa un cupo que puedes usar y una deuda que debes pagar.</p>"),
        heading("En la práctica"),
        paragraph("<ul><li>Cuando pagas con una cuenta, el saldo disponible disminuye.</li><li>Cuando compras con una tarjeta de crédito, aumenta el cupo utilizado.</li><li>Cuando pagas la tarjeta, reduces la deuda asociada.</li></ul>"),
        callout("Revisa el tipo correcto", "Si registras una compra con la tarjeta como si fuera una cuenta, tus reportes de deuda y disponibilidad pueden quedar confusos.", "warning")
      ]
    ),
    article(
      path: "ayuda/cuentas-y-medios-de-dinero/dia-de-balance",
      title: "Qué es el Día de Balance",
      summary: "Compara tus saldos con la realidad y revisa los pagos pendientes del periodo.",
      icon: "◷",
      position: 5,
      related_paths: [
        "ayuda/cuentas-y-medios-de-dinero/que-es-una-cuenta",
        "ayuda/gastos-e-ingresos/como-funcionan-los-recurrentes",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro"
      ],
      blocks: [
        paragraph("<p>El <a href='/reconciliation'>Día de Balance</a> es un espacio para revisar que lo que tienes registrado coincida con la realidad: saldos de cuentas, deudas y pagos pendientes del periodo.</p>"),
        heading("Para qué sirve"),
        paragraph("<ol><li>Ver el saldo que Yogasto calcula para cada cuenta o deuda.</li><li>Compararlo con el saldo real que consultas en tu banco o tarjeta.</li><li>Asignar pagos pendientes a los movimientos que ya registraste.</li><li>Marcar como revisado lo que ya está cuadrado.</li></ol>"),
        callout("Herramienta Pro", "El Día de Balance hace parte de las funciones Pro. Si tu plan no la incluye, puedes conocer las opciones en <a href='/precios'>Precios y planes</a>.", "note")
      ]
    ),

    article(
      path: "ayuda/membresia-y-pagos/plan-gratis",
      title: "Qué incluye el plan Gratis",
      summary: "Empieza a organizar tus finanzas sin pagar y conoce sus funciones esenciales.",
      icon: "○",
      position: 1,
      popular: true,
      related_paths: [
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
        "ayuda/membresia-y-pagos/como-adquirir-una-membresia",
        "ayuda/primeros-pasos/que-es-yogasto"
      ],
      blocks: [
        paragraph("<p>El plan Gratis te permite empezar a organizar tu dinero sin pagar. Incluye las herramientas esenciales para registrar y revisar tus movimientos.</p>"),
        heading("Incluye"),
        paragraph("<ul><li>Registro y organización de gastos e ingresos.</li><li>Administración de cuentas, efectivo y tarjetas.</li><li>Categorías para organizar tus movimientos.</li><li>Consulta de reportes y movimientos.</li><li>Gestión de gastos e ingresos recurrentes.</li></ul>"),
        callout("Sin fecha de vencimiento", "Puedes usar el plan Gratis y cambiarte a Pro cuando quieras acceder a más herramientas.", "tip")
      ]
    ),
    article(
      path: "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
      title: "Qué beneficios tiene Yogasto Pro",
      summary: "Descubre las funciones avanzadas que puedes activar con una membresía.",
      icon: "✦",
      position: 2,
      popular: true,
      related_paths: [
        "ayuda/membresia-y-pagos/como-adquirir-una-membresia",
        "ayuda/herramientas-inteligentes/chat-financiero",
        "ayuda/herramientas-inteligentes/conectar-gmail"
      ],
      blocks: [
        paragraph("<p>Yogasto Pro amplía las herramientas para entender y automatizar tus finanzas. Incluye todo lo del plan Gratis y funciones adicionales.</p>"),
        heading("Funciones Pro"),
        paragraph("<ul><li>Chat financiero con IA para consultar tus finanzas.</li><li>Análisis y oportunidades de ahorro.</li><li>Registro de gastos a partir de correos de tus bancos.</li><li>Registro por WhatsApp con texto, notas de voz o imágenes.</li><li>Herramientas avanzadas de planificación.</li></ul>"),
        callout("Las funciones pueden variar", "La disponibilidad de cada herramienta depende de tu plan y de la configuración de tu cuenta. Revisa la página de <a href='/precios'>Precios y planes</a> para ver las opciones vigentes.", "note")
      ]
    ),
    article(
      path: "ayuda/membresia-y-pagos/como-adquirir-una-membresia",
      title: "Cómo adquirir una membresía",
      summary: "Elige un plan y completa el pago desde el checkout seguro.",
      icon: "▣",
      position: 3,
      related_paths: [
        "ayuda/membresia-y-pagos/plan-gratis",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
        "ayuda/membresia-y-pagos/que-pasa-cuando-termina-mi-membresia"
      ],
      blocks: [
        paragraph("<p>Para adquirir una membresía entra a <a href='/precios'>Precios y planes</a>, elige el plan que quieras y continúa con el pago.</p>"),
        heading("Paso a paso"),
        paragraph("<ol><li>Revisa las opciones de plan y sus beneficios.</li><li>Selecciona la membresía que prefieras.</li><li>Completa el checkout con el proveedor de pagos.</li><li>Espera la confirmación del pago.</li><li>Tu acceso Pro se activa cuando el pago queda confirmado.</li></ol>"),
        callout("Paga solo desde el checkout", "No compartas datos de pago por mensajes, correos o enlaces que no provengan del proceso oficial de compra.", "warning")
      ]
    ),
    article(
      path: "ayuda/membresia-y-pagos/que-pasa-cuando-termina-mi-membresia",
      title: "Qué pasa cuando termina mi membresía",
      summary: "Entiende qué funciones cambian y cómo seguir usando tu cuenta.",
      icon: "◷",
      position: 4,
      related_paths: [
        "ayuda/membresia-y-pagos/plan-gratis",
        "ayuda/membresia-y-pagos/como-adquirir-una-membresia"
      ],
      blocks: [
        paragraph("<p>Cuando termina una prueba o una membresía de pago, tu cuenta y tus datos se conservan. Puedes seguir usando Yogasto con las funciones del plan Gratis.</p>"),
        heading("Qué cambia"),
        paragraph("<p>Las funciones Pro dejan de estar disponibles hasta que actives o renueves una membresía. Las funciones esenciales para registrar y consultar tus movimientos siguen disponibles.</p>"),
        callout("Tus datos no desaparecen", "Puedes volver a activar Pro más adelante y encontrar tu información en la misma cuenta.", "note")
      ]
    ),
    article(
      path: "ayuda/membresia-y-pagos/pagar-con-pse",
      title: "Cómo pagar mediante PSE",
      summary: "Paga tu membresía con débito bancario PSE desde el checkout.",
      icon: "⌁",
      position: 5,
      related_paths: [
        "ayuda/membresia-y-pagos/como-adquirir-una-membresia",
        "ayuda/membresia-y-pagos/que-pasa-cuando-termina-mi-membresia"
      ],
      blocks: [
        paragraph("<p>PSE (Pagos Seguros en Línea) es una opción de pago con débito bancario. En Yogasto puedes elegirla al pagar tu membresía desde el checkout.</p>"),
        heading("Paso a paso"),
        paragraph("<ol><li>Entra a <a href='/precios'>Precios y planes</a> y elige la membresía.</li><li>Continúa al checkout y selecciona <strong>PSE</strong> como medio de pago.</li><li>Serás dirigido al portal de tu banco para autorizar el débito.</li><li>Completa la autorización y vuelve al proceso de compra.</li><li>Tu acceso Pro se activa cuando el pago queda confirmado.</li></ol>"),
        callout("Pago manual", "PSE debita el valor desde tu banco en el momento. No crea una suscripción automática: para el siguiente periodo debes realizar un nuevo pago.", "note"),
        callout("No compartas tus claves", "La autorización se completa en el portal del banco. Yogasto no solicita tu clave de internet banking por chat, correo o WhatsApp.", "warning")
      ]
    ),

    article(
      path: "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
      title: "Cómo funciona el registro de gastos con IA",
      summary: "Conoce cómo Yogasto interpreta la información y crea movimientos para revisar.",
      icon: "✧",
      position: 1,
      popular: true,
      related_paths: [
        "ayuda/herramientas-inteligentes/registrar-gastos-con-lenguaje-natural",
        "ayuda/herramientas-inteligentes/conectar-gmail",
        "ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp"
      ],
      blocks: [
        paragraph("<p>Yogasto usa inteligencia artificial para interpretar información como correos de bancos, mensajes de WhatsApp, textos, imágenes o archivos, y convertirla en movimientos organizados.</p>"),
        heading("Cómo fluye"),
        paragraph("<ol><li>Recibes o envías la información de un movimiento.</li><li>Yogasto identifica datos como el valor, el comercio, la fecha y la categoría.</li><li>El movimiento queda listo para revisar y guardar.</li></ol>"),
        callout("Revisa antes de guardar", "La IA ayuda a reducir el trabajo manual, pero siempre conviene revisar los datos identificados antes de confirmarlos.", "warning")
      ]
    ),
    article(
      path: "ayuda/herramientas-inteligentes/registrar-gastos-con-lenguaje-natural",
      title: "Cómo registrar gastos con lenguaje natural",
      summary: "Describe tus gastos como se los contarías a alguien y deja que Yogasto los organice.",
      icon: "✎",
      position: 2,
      popular: true,
      related_paths: [
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
        "ayuda/gastos-e-ingresos/registrar-un-gasto",
        "ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp"
      ],
      blocks: [
        paragraph("<p>Puedes escribir una descripción natural con uno o varios gastos y Yogasto identifica cada movimiento, sus valores, fechas, categorías y medios de pago cuando los mencionas.</p>"),
        heading("Ejemplo"),
        paragraph("<p>“Hoy pagué 18.000 de un café, 42.000 de almuerzo y 65.000 de gasolina con mi tarjeta débito”.</p>"),
        paragraph("<p>La aplicación separa la información en movimientos individuales para que los revises y los guardes.</p>"),
        callout("Incluye el medio de pago", "Si mencionas la cuenta o la tarjeta, Yogasto puede asociar mejor cada gasto.", "tip")
      ]
    ),
    article(
      path: "ayuda/herramientas-inteligentes/conectar-gmail",
      title: "Cómo conectar Gmail para importar movimientos",
      summary: "Conecta tu correo y revisa los movimientos que Yogasto identifica.",
      icon: "✉",
      position: 3,
      featured: true,
      related_paths: [
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro"
      ],
      blocks: [
        paragraph("<p>En <a href='/settings/gmail'>Configuración de Gmail</a> puedes conectar tu cuenta para que Yogasto identifique notificaciones de movimientos y te ayude a registrarlos.</p>"),
        heading("Cómo empezar"),
        paragraph("<ol><li>Entra a la configuración de Gmail.</li><li>Conecta tu cuenta de Google.</li><li>Revisa los movimientos o candidatos que Yogasto identifique.</li><li>Confirma los que correspondan y descarta los que no.</li></ol>"),
        callout("Función Pro", "La importación desde Gmail hace parte de las funciones Pro. Revisa tu plan en <a href='/precios'>Precios y planes</a>.", "note")
      ]
    ),
    article(
      path: "ayuda/herramientas-inteligentes/chat-financiero",
      title: "Cómo usar el Chat Financiero",
      summary: "Haz preguntas sobre tus finanzas y recibe orientación basada en tus datos.",
      icon: "◌",
      position: 4,
      popular: true,
      related_paths: [
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro",
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia"
      ],
      blocks: [
        paragraph("<p>El <a href='/financial_chat'>Chat Financiero</a> te permite hacer preguntas sobre tus finanzas y recibir respuestas basadas en la información registrada en tu cuenta.</p>"),
        heading("Ideas para usarlo"),
        paragraph("<ul><li>Preguntar en qué categorías estás gastando más.</li><li>Revisar cómo van tus ingresos frente a tus gastos.</li><li>Explorar oportunidades para organizar mejor tu dinero.</li></ul>"),
        callout("Es una herramienta de apoyo", "El chat no reemplaza asesoría financiera profesional ni toma decisiones por ti; úsalo para entender mejor tu información.", "note")
      ]
    ),
    article(
      path: "ayuda/herramientas-inteligentes/registrar-gastos-por-whatsapp",
      title: "Cómo registrar gastos por WhatsApp",
      summary: "Vincula WhatsApp y envía texto, notas de voz o imágenes de tus gastos.",
      icon: "◍",
      position: 5,
      related_paths: [
        "ayuda/herramientas-inteligentes/como-funciona-el-registro-con-ia",
        "ayuda/herramientas-inteligentes/registrar-gastos-con-lenguaje-natural",
        "ayuda/membresia-y-pagos/beneficios-de-yogasto-pro"
      ],
      blocks: [
        paragraph("<p>En <a href='/settings/whatsapp'>Configuración de WhatsApp</a> puedes vincular tu cuenta para enviar información de tus gastos por mensaje.</p>"),
        heading("Puedes enviar"),
        paragraph("<ul><li>Un texto describiendo el gasto.</li><li>Una nota de voz.</li><li>Una imagen de un recibo.</li></ul>"),
        callout("Revisa lo que se registra", "Después de enviar el mensaje, revisa en Yogasto los datos identificados y confirma que correspondan.", "warning")
      ]
    )
  ].freeze
end
