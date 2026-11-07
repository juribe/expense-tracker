# frozen_string_literal: true

# Initial content for the Maglev privacy policy. This is a preliminary draft:
# fields that need confirmation from the Yogasto owner are explicitly marked.
# The page is created without publishing by default.
module PrivacyPolicySeed
  module_function

  def text(html)
    { type: "privacy_text", text: html }
  end

  def list(items, ordered: false)
    { type: "privacy_list", ordered: ordered, items: items }
  end

  def cards(items, columns: "two")
    { type: "privacy_cards", columns: columns, items: items }
  end

  def card(icon:, title:, text:)
    { icon: icon, title: title, text: text }
  end

  def callout(title, text, variant = "note")
    { type: "privacy_callout", title: title, text: text, variant: variant }
  end

  def providers(items)
    { type: "privacy_providers", items: items }
  end

  def provider(name:, service_type:, purpose:, data:, policy_url: "")
    {
      name: name,
      service_type: service_type,
      purpose: purpose,
      data: data,
      policy_url: policy_url
    }
  end

  def section(anchor:, title:, nav_label: nil, intro: nil, children: [])
    {
      anchor: anchor,
      title: title,
      nav_label: nav_label,
      intro: intro,
      children: children
    }
  end

  PAGE = {
    title: "Política de privacidad",
    path: "privacidad",
    seo_title: "Política de privacidad",
    meta_description: "Conoce qué información utiliza Yogasto, para qué la usa y qué opciones tienes para controlar tus datos.",
    og_title: "Política de privacidad",
    og_description: "Transparencia sobre el tratamiento de tu información en Yogasto.",
    meta_robots: "noindex,follow"
  }.freeze

  DOCUMENT_SETTINGS = {
    eyebrow: "TRANSPARENCIA Y CONFIANZA",
    title: "Tu información es tuya.<br>Así la cuidamos.",
    description: "Queremos que tengas claridad sobre qué información utilizamos, para qué la usamos y qué opciones tienes para mantener el control de tus datos.",
    last_updated: "6 de noviembre de 2026",
    reading_time: "8 minutos",
    toc_label: "EN ESTA POLÍTICA",
    help_title: "¿Tienes preguntas sobre tus datos?",
    help_text: "Escríbenos y te ayudaremos a resolverlas.",
    help_link: { link_type: "url", href: "/contactanos", text: "Contactar a Yogasto", open_new_window: false },
    intro: "En Yogasto respetamos tu privacidad. Esta política explica cómo recopilamos, utilizamos, almacenamos y protegemos la información cuando visitas nuestro sitio web o utilizas nuestra aplicación y sus funcionalidades.",
    notice_title: "Una explicación clara, sin letra pequeña.",
    notice_text: "Yogasto te ayuda a organizar tus finanzas personales. Por eso, parte de la información que decides registrar puede ser especialmente privada. Queremos explicarte cómo la tratamos.",
    review_title: "Versión preliminar en revisión legal",
    review_text: "Estamos completando los datos de identificación del responsable y los plazos de conservación. No consideres esta versión como definitiva.",
    cta_title: "Tu tranquilidad también hace parte de tus finanzas.",
    cta_text: "Si tienes alguna inquietud sobre privacidad, estamos para ayudarte.",
    cta_link: { link_type: "url", href: "/contactanos", text: "Hablar con Yogasto", open_new_window: false }
  }.freeze

  SECTIONS = [
    section(
      anchor: "responsable",
      title: "¿Quién es responsable de tus datos?",
      nav_label: "Responsable",
      children: [
        text("<p>El responsable del tratamiento de los datos personales es el titular u operador de Yogasto. Para consultas relacionadas con privacidad puedes usar los canales de contacto indicados en esta política.</p>"),
        callout(
          "Datos pendientes de confirmar",
          "<p>Antes de publicar esta política deben completarse la razón social, el NIT, el domicilio y el correo o canal de privacidad del responsable. No inventes estos datos: deben ser confirmados por el responsable de Yogasto.</p>",
          "warning"
        ),
        text("<p>Esta política se interpreta conforme a la normativa aplicable en materia de protección de datos personales, incluyendo la Ley 1581 de 2012 y sus normas reglamentarias en Colombia, cuando corresponda.</p>")
      ]
    ),
    section(
      anchor: "datos",
      title: "¿Qué información recopilamos?",
      nav_label: "Información que recopilamos",
      intro: "Recopilamos la información que proporcionas al crear tu cuenta y al utilizar las herramientas de Yogasto. Según las funciones que decidas utilizar, puede incluir:",
      children: [
        cards([
          card(icon: "◎", title: "Datos de cuenta", text: "Nombre, correo electrónico y datos básicos del perfil. La contraseña se almacena mediante el mecanismo de autenticación de la aplicación."),
          card(icon: "▤", title: "Información financiera", text: "Gastos, ingresos, categorías, presupuestos, cuentas, tarjetas, deudas, movimientos, saldos y reportes que registres."),
          card(icon: "✎", title: "Contenido que compartes", text: "Textos, mensajes, archivos, documentos, imágenes y audios que envíes a las funciones que los procesan."),
          card(icon: "◌", title: "Datos de uso", text: "Interacciones con la aplicación, registros técnicos, información del dispositivo o navegador cuando se reciba y diagnósticos de errores."),
          card(icon: "⇄", title: "Integraciones", text: "Datos necesarios para activar funciones que conectes voluntariamente, como Gmail, correo de reenvío, WhatsApp o el servidor MCP."),
          card(icon: "▣", title: "Membresías y pagos", text: "Plan, estado de la membresía, historial de transacciones y referencias del proveedor de pagos. No almacenamos el número completo de las tarjetas; ePayco procesa los datos de pago.")
        ]),
        text("<p>No necesitas conectar servicios externos para utilizar las funciones básicas de Yogasto. Las integraciones opcionales se activan por decisión tuya.</p>")
      ]
    ),
    section(
      anchor: "uso",
      title: "¿Para qué utilizamos tu información?",
      nav_label: "Cómo usamos tus datos",
      intro: "Utilizamos los datos para prestar y mejorar el servicio, por ejemplo:",
      children: [
        list([
          "Crear y mantener tu cuenta.",
          "Registrar, organizar y mostrar tus gastos e ingresos.",
          "Calcular saldos, presupuestos, reportes y análisis que solicites.",
          "Procesar archivos, correos o mensajes cuando utilizas funciones de importación.",
          "Ejecutar funcionalidades inteligentes cuando decides usarlas.",
          "Administrar tu membresía y verificar tu acceso.",
          "Enviar comunicaciones relacionadas con tu cuenta o el servicio.",
          "Prevenir fraude, proteger la plataforma y resolver problemas técnicos.",
          "Diagnosticar errores y mejorar la experiencia de uso."
        ]),
        text("<p>No utilizamos tus datos financieros para vender perfiles personales a anunciantes.</p>")
      ]
    ),
    section(
      anchor: "ia",
      title: "Funciones inteligentes e inteligencia artificial",
      nav_label: "Funciones inteligentes",
      intro: "Algunas funciones de Yogasto pueden utilizar proveedores tecnológicos de inteligencia artificial para interpretar textos, clasificar movimientos, extraer información de archivos o responder consultas financieras.",
      children: [
        text("<p>La configuración actual permite usar Mistral como proveedor principal y, según el entorno, OpenRouter o Flex AI como proveedores alternativos o intermediarios. También se pueden procesar imágenes y audios para reconocimiento o transcripción cuando usas esas funciones.</p>"),
        text("<p>Cuando utilizas estas funciones, el contenido que envías y los datos necesarios para realizar la tarea pueden ser procesados por el proveedor correspondiente. El alcance depende de la función utilizada y de la configuración vigente.</p>"),
        callout(
          "Confirmar antes de publicar",
          "<p>Deben verificarse con cada proveedor: qué datos recibe, durante cuánto tiempo los conserva, en qué región se procesan, si los utiliza para entrenamiento y qué contrato o acuerdo de tratamiento aplica. No se debe afirmar que ningún proveedor almacena o entrena con los datos sin verificar sus condiciones y la configuración vigente.</p>",
          "warning"
        ),
        text("<p>Yogasto registra telemetría de las llamadas de IA, incluyendo el prompt y la respuesta, cifrada en reposo, para diagnóstico y métricas internas. Cuando esos registros están asociados a tu cuenta, se eliminan con ella conforme a las asociaciones configuradas.</p>"),
        text("<p>Si no deseas utilizar una función inteligente, puedes continuar utilizando las funciones manuales disponibles en la aplicación.</p>")
      ]
    ),
    section(
      anchor: "terceros",
      title: "¿Con quién compartimos información?",
      nav_label: "Cuándo compartimos datos",
      intro: "No vendemos tus datos personales. Podemos compartir información limitada con proveedores que nos ayudan a operar Yogasto, únicamente en la medida necesaria para prestar el servicio.",
      children: [
        providers([
          provider(
            name: "ePayco",
            service_type: "Procesamiento de pagos",
            purpose: "Procesar el pago de la membresía y validar las transacciones.",
            data: "Datos de pago y de la transacción. Yogasto almacena referencias, estado, valor y método de pago, no el número completo de la tarjeta."
          ),
          provider(
            name: "Mistral",
            service_type: "Inteligencia artificial",
            purpose: "Interpretar textos, imágenes y datos necesarios para las funciones inteligentes.",
            data: "Texto, montos, fechas, descripciones, categorías e imágenes enviadas a la función."
          ),
          provider(
            name: "OpenRouter / Flex AI",
            service_type: "Inteligencia artificial (según configuración)",
            purpose: "Proveedores alternativos o intermediarios para tareas de IA de menor costo.",
            data: "El mismo contenido necesario para ejecutar la tarea de IA configurada."
          ),
          provider(
            name: "Google / Gmail",
            service_type: "Integración de correo",
            purpose: "Leer correos que autorizas para identificar movimientos.",
            data: "Correos y metadatos necesarios para la importación cuando conectas Gmail."
          ),
          provider(
            name: "Meta / WhatsApp",
            service_type: "Mensajería",
            purpose: "Procesar los mensajes que envías al número de WhatsApp de Yogasto.",
            data: "Mensajes, imágenes o audios enviados voluntariamente a la aplicación."
          ),
          provider(
            name: "Cloudflare / Resend",
            service_type: "Procesamiento de correo entrante",
            purpose: "Recibir correos reenviados a la dirección de ingreso de Yogasto.",
            data: "Contenido y metadatos de los correos que reenvías, según el proveedor configurado."
          )
        ]),
        text("<p>También podremos comunicar información cuando exista una obligación legal válida o sea necesario para proteger derechos, usuarios o la seguridad del servicio.</p>"),
        callout(
          "Pendiente de confirmar",
          "<p>Antes de publicar deben confirmarse los nombres definitivos de los proveedores de infraestructura, alojamiento, monitoreo y respaldo, así como sus enlaces de privacidad, regiones y contratos. La lista anterior solo incluye servicios identificados en la implementación actual.</p>",
          "warning"
        )
      ]
    ),
    section(
      anchor: "seguridad",
      title: "¿Cómo protegemos tu información?",
      nav_label: "Cómo los protegemos",
      intro: "Aplicamos medidas técnicas y organizativas razonables para proteger la información frente al acceso, uso, modificación o divulgación no autorizados.",
      children: [
        list([
          "Autenticación de usuarios con Devise y contraseñas protegidas mediante bcrypt.",
          "HTTPS y cookies seguras en producción.",
          "Política de seguridad de contenido (CSP) y controles de acceso.",
          "Cifrado en reposo de tokens de Gmail, telemetría de IA y credenciales de proveedores.",
          "Límites de uso y medidas antispam en formularios públicos.",
          "Registros técnicos para diagnóstico y prevención de abuso."
        ]),
        text("<p>Ningún sistema conectado a Internet puede garantizar seguridad absoluta. No afirmamos certificaciones, auditorías independientes ni garantías de riesgo cero.</p>"),
        text("<p>Consulta también nuestra <a href='/security'>página de Seguridad</a> para conocer más sobre las prácticas disponibles.</p>")
      ]
    ),
    section(
      anchor: "retencion",
      title: "¿Durante cuánto tiempo conservamos tus datos?",
      nav_label: "Conservación y eliminación",
      intro: "Conservamos la información mientras sea necesaria para prestar el servicio, mantener tu cuenta, cumplir obligaciones legales, resolver disputas y hacer valer nuestros acuerdos.",
      children: [
        text("<p>Cuando eliminas tu cuenta desde tu perfil, la aplicación elimina el usuario y los registros asociados configurados con eliminación en cascada, incluyendo movimientos, cuentas, integraciones y telemetría de IA. La acción es permanente.</p>"),
        text("<p>Algunos registros pueden conservarse cuando exista una obligación legal, una disputa o una copia de respaldo pendiente de rotación. Los plazos concretos deben definirse antes de publicar esta política.</p>"),
        callout(
          "Plazos pendientes",
          "<p>No hay plazos de conservación, retención de respaldos ni periodos de registros técnicos documentados en el código actual. Deben establecerse y confirmarse antes de publicar esta sección.</p>",
          "warning"
        )
      ]
    ),
    section(
      anchor: "derechos",
      title: "¿Cuáles son tus derechos?",
      nav_label: "Tus derechos",
      intro: "De acuerdo con la normativa aplicable, puedes tener derecho a:",
      children: [
        list([
          "Conocer los datos personales que tenemos sobre ti.",
          "Actualizar y rectificar tu información.",
          "Solicitar prueba de la autorización cuando corresponda.",
          "Conocer cómo se ha utilizado tu información.",
          "Presentar consultas y reclamos relacionados con el tratamiento.",
          "Solicitar la supresión de datos cuando proceda legalmente.",
          "Revocar la autorización cuando sea legalmente posible."
        ]),
        text("<p>Para ejercer estos derechos puedes escribirnos desde <a href='/contactanos'>Contáctanos</a>. Incluye el correo asociado a tu cuenta y el motivo de tu solicitud. Podemos pedir información adicional para verificar tu identidad antes de atenderla.</p>"),
        text("<p>No envíes contraseñas ni datos completos de tarjetas por este canal.</p>"),
        callout(
          "Plazos legales",
          "<p>Las solicitudes se atenderán conforme a los términos legales aplicables. Esta versión no fija plazos distintos ni inventa términos de respuesta; deben validarse con el responsable legal antes de publicar.</p>",
          "note"
        )
      ]
    ),
    section(
      anchor: "cookies",
      title: "Cookies y tecnologías similares",
      nav_label: "Cookies",
      intro: "Yogasto utiliza cookies necesarias para mantener la sesión, proteger el acceso y recordar el aviso de membresía. También puede usar almacenamiento local o de sesión del navegador para preferencias de interfaz.",
      children: [
        text("<p>Las cookies estrictamente necesarias permiten que el servicio funcione. El almacenamiento local y de sesión se usa para preferencias como el tema visual, el estado del menú, avisos de onboarding y el estado de sincronización de Gmail.</p>"),
        callout(
          "Sin cookies publicitarias identificadas",
          "<p>En el código actual no identificamos cookies de analítica, publicidad ni píxeles de seguimiento. Antes de publicar esta política debe confirmarse que el entorno de producción, el CDN o servicios externos no añadan cookies adicionales.</p>",
          "note"
        )
      ]
    ),
    section(
      anchor: "menores",
      title: "Privacidad de menores de edad",
      nav_label: "Menores de edad",
      intro: "Yogasto no está dirigido a menores de edad. Si consideras que un menor nos ha proporcionado datos personales sin la autorización correspondiente, contáctanos para revisar la situación y tomar las medidas aplicables.",
      children: [
        text("<p>El registro actual no incluye un mecanismo de verificación de edad. La edad mínima, la autorización del representante legal y el procedimiento aplicable deben definirse antes de publicar esta política.</p>"),
        callout(
          "Pendiente de confirmar",
          "<p>No se debe inventar una edad mínima ni afirmar que existe verificación de edad. El responsable de Yogasto debe definir estos requisitos con revisión legal.</p>",
          "warning"
        )
      ]
    ),
    section(
      anchor: "cambios",
      title: "Cambios en esta política",
      nav_label: "Cambios",
      intro: "Podemos actualizar esta política para reflejar cambios en Yogasto, en nuestros proveedores o en las normas aplicables. Publicaremos la versión vigente en esta página e indicaremos la fecha de última actualización.",
      children: [
        text("<p>Cuando un cambio sea relevante, podremos comunicarlo mediante la aplicación o por correo electrónico, según corresponda. La fecha de actualización se administra desde Maglev.</p>"),
        text("<p>Maglev conserva la versión publicada de la página, pero no exponemos un historial de versiones separado en el sitio público.</p>")
      ]
    ),
    section(
      anchor: "contacto",
      title: "¿Cómo puedes contactarnos?",
      nav_label: "Contáctanos",
      intro: "Si tienes preguntas, solicitudes o reclamos sobre el tratamiento de tu información personal, puedes escribirnos desde nuestra página de contacto.",
      children: [
        text("<p>Incluye el correo asociado a tu cuenta, el motivo de tu solicitud y la información necesaria para ayudarnos a atenderla. No envíes contraseñas ni datos completos de tarjetas.</p>"),
        callout(
          "Canal de privacidad",
          "<p>Usa <a href='/contactanos'>Contáctanos</a> para iniciar una solicitud de privacidad. El correo específico de privacidad y el procedimiento interno de atención deben confirmarse antes de publicar.</p>",
          "tip"
        )
      ]
    )
  ].freeze
end
