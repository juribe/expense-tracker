# frozen_string_literal: true

require_relative "legal_document_helpers"

# Public content for the Maglev data deletion page. Only verified, user-facing
# statements belong here. Internal retention decisions live in
# docs/privacy_policy_audit.md and docs/data_deletion.md.
module DataDeletionSeed
  extend LegalDocumentHelpers

  PAGE = {
    title: "Eliminación de datos",
    path: "eliminacion-de-datos",
    seo_title: "Eliminación de datos",
    meta_description: "Conoce cómo eliminar tu cuenta de Yogasto, qué ocurre con tus datos y cómo solicitar la eliminación de tu información.",
    og_title: "Eliminación de datos",
    og_description: "Pasos y canales para eliminar tu cuenta y los datos asociados a Yogasto.",
    meta_robots: "index,follow"
  }.freeze

  DOCUMENT_SETTINGS = {
    eyebrow: "CONTROL Y TRANSPARENCIA",
    title: "Tú decides qué pasa con tus datos.",
    description: "Esta página explica cómo eliminar tu cuenta y la información asociada a Yogasto, qué ocurre con tus datos y cómo solicitar la eliminación si no puedes acceder a tu cuenta.",
    last_updated: "14 de noviembre de 2026",
    reading_time: "5 minutos",
    reading_label: "Lectura: ",
    updated_label: "Última actualización: ",
    meta_order: "updated_first",
    breadcrumb_parent_label: "Información legal",
    breadcrumb_parent_url: "",
    breadcrumb_current_label: "Eliminación de datos",
    toc_label: "EN ESTA PÁGINA",
    help_title: "¿Necesitas ayuda con tu solicitud?",
    help_text: "Escríbenos y revisamos tu caso.",
    help_link: { link_type: "url", href: "/contactanos", text: "Contactar a Yogasto", open_new_window: false },
    intro: "En Yogasto puedes eliminar tu cuenta cuando quieras. Aquí encuentras los pasos, lo que ocurre con tu información y los canales disponibles si no puedes hacerlo desde la aplicación.",
    notice_title: "Antes de continuar",
    notice_text: "La eliminación de la cuenta es permanente. Si solo quieres dejar de usar una integración o cambiar tus preferencias, revisa las opciones disponibles en tu perfil.",
    review_title: "",
    review_text: "",
    cta_title: "¿Tienes dudas sobre tus datos?",
    cta_text: "Escríbenos y te ayudamos a revisar tu solicitud.",
    cta_link: { link_type: "url", href: "/contactanos", text: "Contactar a Yogasto", open_new_window: false }
  }.freeze

  SECTIONS = [
    section(
      anchor: "perfil",
      title: "Elimina tu cuenta desde tu perfil",
      nav_label: "Desde tu perfil",
      intro: "Si puedes iniciar sesión, la forma más rápida de eliminar tu cuenta y los datos asociados es desde tu perfil.",
      children: [
        list([
          "Inicia sesión y abre <a href='/profile'>Mi perfil</a>.",
          "En la tarjeta <strong>¿Quieres dejar Yogasto?</strong>, escribe tu contraseña actual.",
          "Si activaste la verificación en dos pasos, ingresa el código de tu aplicación de autenticación o un código de recuperación.",
          "Escribe <strong>ELIMINAR</strong> para confirmar y pulsa <strong>Cancelar mi cuenta</strong>."
        ], ordered: true),
        callout(
          "La eliminación es permanente",
          "No es posible recuperar los movimientos, cuentas, presupuestos, metas ni configuraciones asociadas a la cuenta.",
          "warning"
        ),
        text("<p>Por seguridad pedimos una prueba adicional de identidad antes de eliminar la cuenta. Si no recuerdas tu contraseña, puedes restablecerla desde la pantalla de inicio de sesión.</p>")
      ]
    ),
    section(
      anchor: "que-se-elimina",
      title: "Qué información se elimina",
      nav_label: "Qué se elimina",
      intro: "Al eliminar tu cuenta, la aplicación elimina el usuario y los registros asociados configurados con eliminación en cascada, entre ellos:",
      children: [
        cards([
          card(icon: "◎", title: "Datos de la cuenta", text: "Nombre, correo, credenciales de acceso, passkeys, códigos de recuperación y preferencias."),
          card(icon: "▤", title: "Información financiera", text: "Gastos, ingresos, transferencias, cuentas, tarjetas, deudas, presupuestos y metas."),
          card(icon: "↻", title: "Automatizaciones", text: "Reglas de transacciones, correos procesados, importaciones y extractos asociados."),
          card(icon: "⇄", title: "Integraciones", text: "Conexiones de Gmail, correo de reenvío y WhatsApp vinculadas a tu cuenta."),
          card(icon: "✧", title: "Asistentes de IA", text: "Conversaciones, telemetría y resultados de las funciones de inteligencia artificial."),
          card(icon: "◌", title: "Alertas y actividad", text: "Notificaciones, consentimientos y progreso de configuración de tu cuenta.")
        ]),
        text("<p>La eliminación también retira el acceso a la cuenta. Algunos registros pueden conservarse cuando existe una obligación legal, una disputa o un respaldo pendiente de rotación; lo explicamos en la siguiente sección.</p>")
      ]
    ),
    section(
      anchor: "se-conserva",
      title: "Qué información puede conservarse",
      nav_label: "Conservación",
      intro: "La eliminación de la cuenta no siempre implica el borrado inmediato de todas las copias. Esto es lo que puede conservarse:",
      children: [
        cards([
          card(icon: "◷", title: "Copias de seguridad", text: "Pueden conservar versiones anteriores durante el ciclo de respaldo y se reemplazan conforme a la operación del servicio."),
          card(icon: "▣", title: "Obligaciones legales", text: "Información necesaria para cumplir deberes legales, contables o fiscales."),
          card(icon: "⚖", title: "Disputas y seguridad", text: "Información necesaria para atender reclamaciones, prevenir abusos o hacer valer acuerdos."),
          card(icon: "▥", title: "Registros técnicos", text: "Registros de infraestructura no asociados a tu cuenta, conservados por periodos limitados.")
        ]),
        callout(
          "Las copias no desaparecen de inmediato",
          "No prometemos que las copias de seguridad se eliminen de forma instantánea; se van reemplazando conforme a su rotación.",
          "note"
        ),
        text("<p>La <a href='/privacidad'>Política de privacidad</a> describe con más detalle el tratamiento, la conservación y tus derechos.</p>")
      ]
    ),
    section(
      anchor: "whatsapp",
      title: "Datos de WhatsApp y otros servicios conectados",
      nav_label: "WhatsApp e integraciones",
      intro: "Si vinculaste WhatsApp o conectaste otros servicios, tu información también está cubierta por esta página.",
      children: [
        list([
          "<strong>WhatsApp:</strong> se elimina la conexión y los movimientos creados a partir de tus mensajes. Si quieres eliminar el número y los datos asociados a una conversación, envía una solicitud por correo.",
          "<strong>Gmail y correo de reenvío:</strong> se eliminan la conexión y las credenciales asociadas. También puedes revocar el acceso desde tu cuenta de Google.",
          "<strong>ePayco:</strong> el proveedor de pagos conserva la información sujeta a sus propias políticas. Yogasto no almacena el número completo de tus tarjetas."
        ]),
        text("<p>Para prevenir abusos, algunos identificadores pueden conservarse sin la asociación con tu cuenta. Por ejemplo, el vínculo entre tu número de WhatsApp y tu cuenta se elimina, pero el número puede permanecer como identificador para evitar que se vincule a otra cuenta sin autorización. Puedes pedir la eliminación de ese identificador escribiendo a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>.</p>")
      ]
    ),
    section(
      anchor: "solicitud",
      title: "Solicita la eliminación sin acceder a tu cuenta",
      nav_label: "Solicitud por correo",
      intro: "Si no puedes iniciar sesión, perdiste el acceso al correo de tu cuenta o quieres eliminar datos asociados a una conversación de WhatsApp, puedes solicitar la eliminación por correo.",
      children: [
        text("<p>Escribe a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a> con el asunto <strong>Eliminación de datos</strong> e incluye:</p>"),
        list([
          "El correo asociado a tu cuenta o, si no la tienes, el número de WhatsApp desde el que escribiste.",
          "Qué información quieres eliminar: la cuenta completa o datos específicos.",
          "Cualquier dato que nos ayude a verificar que la solicitud es tuya."
        ]),
        text("<p>Podemos pedir información adicional para verificar tu identidad antes de atender la solicitud. Nunca te pediremos tu contraseña, códigos de verificación ni datos completos de tarjetas para atender esta solicitud.</p>"),
        text("<p>De acuerdo con la Ley 1581 de 2012, las consultas se atienden dentro de los diez (10) días hábiles siguientes a su recibo, prorrogables por cinco (5) días hábiles. Los reclamos se atienden dentro de los quince (15) días hábiles siguientes, prorrogables por ocho (8) días hábiles.</p>"),
        callout(
          "¿Solo quieres desconectar una integración?",
          "Puedes desconectar WhatsApp o Gmail desde los ajustes de tu cuenta sin eliminar tu información financiera.",
          "tip"
        )
      ]
    ),
    section(
      anchor: "derechos",
      title: "Otros derechos sobre tus datos",
      nav_label: "Tus derechos",
      intro: "Además de la eliminación, puedes ejercer los derechos que reconoce la normativa aplicable sobre tus datos personales:",
      children: [
        list([
          "Conocer los datos personales que tenemos sobre ti.",
          "Actualizar y rectificar tu información.",
          "Solicitar prueba de la autorización cuando corresponda.",
          "Solicitar la supresión de datos cuando proceda legalmente.",
          "Revocar la autorización cuando sea legalmente posible.",
          "Presentar consultas y reclamos relacionados con el tratamiento."
        ]),
        text("<p>La <a href='/privacidad'>Política de privacidad</a> explica el alcance de estos derechos, los canales y los plazos aplicables.</p>")
      ]
    ),
    section(
      anchor: "contacto",
      title: "Contacto",
      nav_label: "Contacto",
      intro: "Si tienes dudas sobre este proceso o sobre la información asociada a tu cuenta, escríbenos.",
      children: [
        text("<p>Correo: <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>. También puedes usar la página de <a href='/contactanos'>Contáctanos</a>.</p>"),
        text("<p>Incluye el correo asociado a tu cuenta y el motivo de tu solicitud. No envíes contraseñas ni datos completos de tarjetas por este canal.</p>")
      ]
    )
  ].freeze
end
