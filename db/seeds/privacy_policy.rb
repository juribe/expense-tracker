# frozen_string_literal: true

require_relative "legal_document_helpers"

# Public content for the Maglev privacy policy. Only verified, user-facing
# statements belong here: internal verification notes and pending decisions
# live in docs/privacy_policy_audit.md and must never be rendered on the page.
module PrivacyPolicySeed
  extend LegalDocumentHelpers

  PAGE = {
    title: "Política de privacidad",
    path: "privacidad",
    seo_title: "Política de privacidad",
    meta_description: "Conoce qué información utiliza Yogasto, para qué la usa y qué opciones tienes para controlar tus datos.",
    og_title: "Política de privacidad",
    og_description: "Transparencia sobre el tratamiento de tu información en Yogasto.",
    meta_robots: "index,follow"
  }.freeze

  DOCUMENT_SETTINGS = {
    eyebrow: "TRANSPARENCIA Y CONFIANZA",
    title: "Tu información es tuya.<br>Así la cuidamos.",
    description: "Queremos que tengas claridad sobre qué información utilizamos, para qué la usamos y qué opciones tienes para mantener el control de tus datos.",
    last_updated: "7 de noviembre de 2026",
    reading_time: "9 minutos",
    reading_label: "Lectura: ",
    updated_label: "Última actualización: ",
    meta_order: "updated_first",
    breadcrumb_parent_label: "Centro de ayuda",
    breadcrumb_parent_url: "/ayuda",
    breadcrumb_current_label: "Política de privacidad",
    toc_label: "EN ESTA POLÍTICA",
    help_title: "¿Tienes preguntas sobre tus datos?",
    help_text: "Escríbenos y te ayudaremos a resolverlas.",
    help_link: { link_type: "url", href: "/contactanos", text: "Contactar a Yogasto", open_new_window: false },
    intro: "En Yogasto respetamos tu privacidad. Esta política explica cómo recopilamos, utilizamos, almacenamos y protegemos la información cuando visitas nuestro sitio web o utilizas nuestra aplicación y sus funcionalidades.",
    notice_title: "Una explicación clara, sin letra pequeña.",
    notice_text: "Yogasto te ayuda a organizar tus finanzas personales. Por eso, parte de la información que decides registrar puede ser especialmente privada. Queremos explicarte cómo la tratamos.",
    review_title: "",
    review_text: "",
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
        text("<p>El responsable del tratamiento de los datos personales es <strong>José Uribe</strong>, titular de Yogasto. Para consultas, solicitudes o reclamos relacionados con privacidad puedes escribir a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>.</p>"),
        list([
          "Nombre o razón social: José Uribe",
          "Domicilio: Soledad, Atlántico, Colombia",
          "Correo electrónico y canal de privacidad: <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>"
        ]),
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
          card(icon: "⇄", title: "Integraciones", text: "Datos necesarios para activar funciones que conectes voluntariamente, como Gmail, correo de reenvío, WhatsApp o asistentes de inteligencia artificial."),
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
        text("<p>Yogasto puede usar Mistral como proveedor principal y OpenRouter como proveedor alternativo o intermediario para algunas tareas de inteligencia artificial. También se pueden procesar imágenes y audios para reconocimiento o transcripción cuando usas esas funciones.</p>"),
        text("<p>Cuando utilizas estas funciones, el contenido que envías y los datos necesarios para realizar la tarea pueden ser procesados por el proveedor correspondiente. El alcance depende de la función utilizada y de la configuración vigente. El tratamiento que cada proveedor realiza se rige por sus propias condiciones y por los acuerdos aplicables.</p>"),
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
            name: "OVHcloud",
            service_type: "Infraestructura y alojamiento",
            purpose: "Alojar la plataforma y almacenar la información de los usuarios.",
            data: "Información almacenada en la plataforma y las copias de seguridad automáticas necesarias para su disponibilidad."
          ),
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
            name: "OpenRouter",
            service_type: "Inteligencia artificial (según configuración)",
            purpose: "Proveer modelos alternativos o intermediarios para tareas de IA.",
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
            name: "Cloudflare",
            service_type: "Procesamiento de correo entrante",
            purpose: "Recibir correos reenviados a la dirección de ingreso de Yogasto.",
            data: "Contenido y metadatos de los correos que reenvías."
          )
        ]),
        text("<p>Yogasto utiliza proveedores externos de infraestructura tecnológica para alojar la plataforma y almacenar la información de sus usuarios. Actualmente, estos servicios son proporcionados por OVHcloud, cuya infraestructura se encuentra ubicada en Canadá.</p><p>Se realizan copias de seguridad automáticas para contribuir a la protección y disponibilidad de la información. Los proveedores tecnológicos pueden tratar datos personales en el marco de los servicios contratados y conforme a las condiciones y acuerdos de tratamiento aplicables.</p>"),
        text("<p>También podremos comunicar información cuando exista una obligación legal válida o sea necesario para proteger derechos, usuarios o la seguridad del servicio.</p>")
      ]
    ),
    section(
      anchor: "seguridad",
      title: "¿Cómo protegemos tu información?",
      nav_label: "Cómo los protegemos",
      intro: "Aplicamos medidas técnicas y organizativas razonables para proteger la información frente al acceso, uso, modificación o divulgación no autorizados.",
      children: [
        list([
          "Inicio de sesión con autenticación y contraseñas protegidas; no almacenamos contraseñas en texto plano.",
          "HTTPS y cookies seguras en producción.",
          "Controles de acceso y una política de seguridad de contenido para reducir riesgos en la interfaz.",
          "Cifrado en reposo de tokens de Gmail, telemetría de IA y credenciales de proveedores.",
          "Límites de uso y medidas antispam en formularios públicos.",
          "Registros técnicos para diagnóstico y prevención de abuso."
        ]),
        text("<p>Ningún sistema conectado a Internet puede garantizar seguridad absoluta. No afirmamos certificaciones, auditorías independientes ni garantías de riesgo cero.</p>"),
        text("<p>Consulta también nuestra <a href='/seguridad'>página de Seguridad</a> para conocer más sobre las prácticas disponibles.</p>")
      ]
    ),
    section(
      anchor: "retencion",
      title: "¿Durante cuánto tiempo conservamos tus datos?",
      nav_label: "Conservación y eliminación",
      intro: "Conservamos la información mientras sea necesaria para prestar el servicio, mantener tu cuenta, cumplir obligaciones legales, resolver disputas y hacer valer nuestros acuerdos.",
      children: [
        text("<p>Mientras tu cuenta esté activa, conservamos los datos que registras y los necesarios para operar el servicio. Cuando eliminas tu cuenta desde tu perfil, la aplicación elimina el usuario y los registros asociados configurados con eliminación en cascada, incluyendo movimientos, cuentas, integraciones y telemetría de IA. La eliminación de la cuenta es permanente en la aplicación.</p>"),
        text("<p>Las copias de seguridad automáticas pueden conservar versiones anteriores de la información durante el ciclo de respaldo configurado. Por eso, la eliminación de una cuenta no implica que todas las copias de respaldo se eliminen de inmediato; esas copias se van reemplazando conforme a la operación del servicio.</p>"),
        text("<p>Consulta la página de <a href='/eliminacion-de-datos'>Eliminación de datos</a> para conocer los pasos desde tu perfil y los canales disponibles si no puedes acceder a tu cuenta.</p>"),
        text("<p>El contenido de los correos procesados para importar movimientos se conserva solo mientras es necesario para completar el procesamiento y revisar el resultado. Una vez concluido el ciclo, ese contenido se elimina de las tablas de procesamiento; pueden permanecer metadatos y resultados asociados a tu cuenta. Los archivos, imágenes y audios que envías a las funciones de análisis se procesan para realizar la tarea solicitada.</p>"),
        text("<p>Los registros técnicos y la telemetría de IA se conservan para diagnóstico, seguridad y métricas internas. Cuando están asociados a tu cuenta, se eliminan con ella. Los registros técnicos no asociados a tu cuenta pueden conservarse por periodos limitados conforme a la operación de la infraestructura.</p>"),
        text("<p>Si existe una obligación legal, una disputa o un respaldo pendiente de rotación, podemos conservar la información necesaria durante el tiempo exigido o mientras la situación se resuelva.</p>")
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
        text("<p>Para ejercer estos derechos escribe a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>. Incluye el correo asociado a tu cuenta y el motivo de tu solicitud. Podemos pedir información adicional para verificar tu identidad antes de atenderla.</p>"),
        text("<p>No envíes contraseñas ni datos completos de tarjetas por este canal.</p>"),
        text("<p>De acuerdo con la Ley 1581 de 2012, las consultas se atenderán dentro de los diez (10) días hábiles siguientes a su recibo. Si no es posible responder en ese plazo, te informaremos los motivos y la fecha en que atenderemos la solicitud, que no podrá superar los cinco (5) días hábiles siguientes.</p>"),
        text("<p>Los reclamos se atenderán dentro de los quince (15) días hábiles siguientes a su recibo. Si no es posible responder en ese plazo, te informaremos los motivos y la fecha en que atenderemos el reclamo, que no podrá superar los ocho (8) días hábiles siguientes.</p>")
      ]
    ),
    section(
      anchor: "cookies",
      title: "Cookies y tecnologías similares",
      nav_label: "Cookies",
      intro: "Yogasto utiliza cookies necesarias para mantener la sesión, proteger el acceso y recordar el aviso de membresía. También puede usar almacenamiento local o de sesión del navegador para preferencias de interfaz.",
      children: [
        text("<p>Las cookies estrictamente necesarias permiten que el servicio funcione. El almacenamiento local y de sesión se usa para preferencias como el tema visual, el estado del menú, avisos de onboarding y el estado de sincronización de Gmail.</p>"),
        text("<p>La aplicación no incorpora cookies de analítica, publicidad ni píxeles de seguimiento. Si en el futuro incorporamos cookies no necesarias, actualizaremos esta política y, cuando corresponda, solicitaremos tu consentimiento.</p>")
      ]
    ),
    section(
      anchor: "menores",
      title: "Privacidad de menores de edad",
      nav_label: "Menores de edad",
      intro: "Yogasto no está dirigido a menores de edad. Si consideras que un menor nos ha proporcionado datos personales sin la autorización correspondiente, contáctanos para revisar la situación y tomar las medidas aplicables.",
      children: [
        text("<p>Si eres menor de edad, no debes crear una cuenta ni proporcionar datos personales sin la autorización de tu representante legal.</p>"),
        text("<p>La aplicación no cuenta actualmente con un mecanismo automático de verificación de edad. Si consideras que un menor nos ha proporcionado datos personales sin la autorización correspondiente, escríbenos a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a> para revisar la situación y adoptar las medidas aplicables.</p>")
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
      intro: "Si tienes preguntas, solicitudes o reclamos sobre el tratamiento de tu información personal, escríbenos a hola@yogasto.co.",
      children: [
        text("<p>Incluye el correo asociado a tu cuenta, el motivo de tu solicitud y la información necesaria para ayudarnos a atenderla. No envíes contraseñas ni datos completos de tarjetas.</p>"),
        text("<p>También puedes escribirnos a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a> o desde la página de <a href='/contactanos'>Contáctanos</a>.</p>")
      ]
    )
  ].freeze
end
