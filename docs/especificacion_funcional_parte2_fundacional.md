# Especificación funcional — Parte 2 (decisiones fundacionales)
> Complementa `especificacion_funcional_completa.md`. Extraída de una conversación anterior con Gemini (previa a la de 150.000 líneas), con foco en decisiones que no aparecían en el otro documento.

## 1. Identidad visual corporativa (definida desde el origen)
- Fondo azul oscuro institucional: **#1B365D** (autoridad/confianza).
- Acentos en dorado/ámbar: `Colors.amber` — también citado como **#E07A5F** en una revisión posterior para botones de acción.
- Fondo claro de tarjetas/pantallas: **#F5F7FA** / **#F8F9FA** (evita fatiga visual en obra).
- Textos: blanco sobre fondo oscuro, alto contraste.
- Tipografía: 18–20px títulos, 14px cuerpo/listas.
- Principio de metodología explícito: **"Desarrollo paso a paso. No se toca ni modifica ninguna sección o solapa previa una vez aprobada."**

## 2. Ciclo de vida del Certificado de Obra (5 estados) — Solapa 5

1. **Borrador (En Construcción/Revisión)**: carga de avances por Profesional/Empresa, con notificaciones de ida y vuelta.
2. **Emitido (Esperando Pago)**: aprobado por el Profesional; se notifica al Propietario con la fecha límite de pago (según días pactados en contrato).
3. **Leído por Propietario**: al abrir el certificado, se notifica automáticamente a la obra que fue visto.
4. **Pagado por Propietario**: el Propietario marca el pago, selecciona medio (transferencia/efectivo) y adjunta comprobante.
5. **Impactado y Cerrado**: la Empresa/Constructor verifica el cobro, tilda el impacto, adjunta factura/recibo final — cierra el ciclo.

### Reglas especiales
- **Plazo de pago**: se configura una sola vez antes del Certificado N°1 y aplica a todos los siguientes.
- **Impresión/firma física**: opción de descargar PDF en blanco (medición en campo) o completo (firma en papel). Si se opta por firma física, el sistema **bloquea la emisión del siguiente certificado** hasta subir el PDF/imagen firmado.

### Matriz de permisos por tipo de relación cliente-obra
- **Cliente Autoconstructor** (dueño y ejecutor): ve todo — costos directos, facturas, compras, precios reales de corralón. Carga directa habilitada.
- **Cliente con Profesional + Contratista**: visibilidad parcial/protegida — ve precio final de contrato y avance; oculto: salarios individuales, gastos generales, beneficio, imprevistos y precios negociados en bruto. Solo Profesional/Contratista cargan; Cliente aprueba certificaciones (solo lectura).
- **Cliente con Contratista Directo (sin Profesional)**: visibilidad restringida — ve avances y precio del rubro certificado; oculto: costos internos del contratista y márgenes. Cliente valida/certifica rubros; Contratista presenta certificación y gestiona cuadrilla (solo lectura para el cliente).

## 3. Motor "Mandar a Presupuestar" (botón inteligente en Resumen Final)

- Al presionar, dispara una **solicitud zonal múltiple**: envío simultáneo a 3 corralones físicos geolocalizados en la zona registrada de la obra.
- Los precios que devuelven los corralones se muestran con etiqueta clara de que **no son un precio firme** (son referencia), hasta validación manual.
- **Validación manual obligatoria**: botón "Validar y Confirmar Precios" antes de generar orden de compra o cerrar presupuesto definitivo.
- Exportación manual alternativa: PDF, Excel (.xlsx) o texto para WhatsApp.
- Motor de precios con **promedio automático**: en zonas sin comercios con membresía activa, toma referencia de 1 a 4 proveedores de la zona y genera un precio promedio estimado.

## 4. Solapa 2 (APU) — matriz heredable de coeficientes
- Gastos Generales, Imprevistos y Beneficio se definen **una vez a nivel obra** y se heredan automáticamente en todas las planillas de APU (evita tipear los mismos porcentajes ítem por ítem).
- Usuario Pro puede sobreescribir el coeficiente en un APU específico puntual (ej: rubro de mayor riesgo).
- Valores de referencia usados como default: Gastos Generales 10%, Imprevistos 7%, Beneficio 10%, EPP 1%. Impuestos siempre editables (IVA 21%, IIBB 3-5%, Ganancias aparte) para adaptarse a variaciones provinciales.
- Free: estos coeficientes quedan fijos/no editables (solo lectura, referencia formativa). Pro: editables, con cartel de advertencia legal al modificar (silenciable con "No volver a mostrar", guardado por usuario).

## 5. Solapa 3 (Materiales y Mano de Obra) — requisito UOCRA específico
- Debe actualizarse **al menos una vez por mes** según los acuerdos salariales que UOCRA publica oficialmente en su página.
- Debe tener **checkboxes de zonificación UOCRA** — al tildar una zona, mostrar un cuadro explicando a qué zonificación pertenece esa selección.

## 6. Modo "Carga Externa" (transversal a varias solapas)
Permite ingresar presupuestos cerrados o montos "llave en mano" sin pasar por el desglose de APU — pensado para contratistas o usuarios que solo necesitan gestión, no cálculo técnico. Al activarlo, la interfaz oculta los enlaces a APU y habilita directamente la Solapa 5 (Gestión/Certificaciones) para arrancar el control de avance de inmediato.

## 7. Lanzamiento y monetización (definiciones de negocio tempranas)

- **Google Play Store**: USD 25 pago único (cuenta de desarrollador) + período de prueba cerrada obligatorio (~14 días con usuarios mínimos) antes de publicación abierta.
- **Apple App Store**: USD 99/año (Apple Developer Program) + testeo previo vía TestFlight.
- **Publicidad (AdMob)**: la ganancia de anuncios es para el desarrollador (Sebastián), no para Google — Google paga un porcentaje por vista/clic.
- Modelo sugerido: Freemium con publicidad liviana en la versión gratuita, o versión PRO/suscripción sin anuncios (rango sugerido inicial: USD 3–5/mes, luego ajustado a $15.000 ARS / USD 12 en conversaciones posteriores).
- **Botón de sugerencias/feedback**: uno general (menú principal/perfil) para ideas de sistema, y opcionalmente uno específico por solapa técnica (ícono 💬) para feedback puntual sobre esa función.

## 8. Backup y control de versiones (recomendación original de Gemini)
- Git + GitHub como práctica estándar: cada avance importante se sube ("push"), permitiendo volver a cualquier punto anterior si algo se rompe.
- Complementar con copia periódica en `.zip` de la carpeta `lib/` en disco externo o Google Drive personal, como red de seguridad adicional fuera de la nube de Git.

## 9. Registro de obra con segmentación de perfil (idea original, para métricas)
Al registrar una obra, guardar además el perfil del usuario que la creó (Profesional, Constructor, Cliente) — no solo para permisos, sino para que el propio Sebastián pueda recibir alertas/métricas de uso de la plataforma (quién la está usando y cómo), pensado originalmente vía bot de Telegram o notificación interna.
