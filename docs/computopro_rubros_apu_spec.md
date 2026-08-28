# computoPRO — Spec consolidado: Solapa 1 (Rubros) + Solapa 2 (APU / APU sin materiales)
*Documento de cierre previo a implementación en Claude Code — no contiene código, solo lógica de negocio y permisos.*

---

## 1. Estructura de datos base (leída de PLANILLA_BASE_2_0_v3_CORREGIDA)

### RUBROS (solapa 1)
Columnas: `ITEM` / `DESCRIPCION` / `UND.` / `CANT.` / `P.UNITARIO` / `P.TOTAL ITEM`.
19 rubros (1 a 19, con Fundaciones y Estructuras H°A° ya separados como se había definido). Cada rubro tiene sus subitems, una fila `OTRO` de texto libre, y una fila `SUBTOTAL`.

### APU (contenido de Solapa 2 — vista "con materiales")
Por cada partida (ej. 2.1): bloque de Mano de obra (Oficial especializado / Oficial / Medio oficial / Ayudante / Ayuda de gremio) + Subtotal Mano de Obra (A) → bloque de hasta ~19 filas de Material + Subtotal Material (B) → resumen de 15 líneas:
Mano de obra(1) / Materiales(2) / Equipos(3) / Costo-Costo(4) / GG 15%(5) / Imprevistos 4%(7) / EPP-Seguridad 1.5%(8) / Costo Financiero 0%(9) / Beneficio 10%(10) / Costo total(11) / IVA 21% + IIBB 3% + Tasas 1.5%(12-14) / Costo total c/impuestos(15).

### APU_SIN_MATERIALES (contenido alternativo de la MISMA Solapa 2 — vista "mano de obra sola", PRO)
No es una tercera solapa — ver sección 3 para la lógica de UI. Mismo esquema de partidas pero sin materiales: Mano de obra(1) + Equipos(2) = Costo-costo sin mat(3) → GG fijo, igual valor absoluto que en APU completa (NO se recalcula) → Imprevistos recalculado sobre la nueva base → EPP y Costo Financiero fijos (iguales a APU) → Beneficio recalculado → **"Gestión de materiales de terceros" (4% editable, celda amarilla), aplicado sobre el monto de Materiales (B) de la APU completa** — el contratista cobra un fee de gestión por coordinar materiales aunque no los compre él → impuestos → total final.

---

## 2. Reglas de edición Free vs. PRO (base, ya cerradas)

- **Rubro 1 (Tareas Preliminares):** cantidad Y precio unitario 100% editables por Free y PRO. **No está correlacionado con APU** — carga directa e independiente.
- **Rubros 2 a 19:** el usuario edita la CANTIDAD directo en Rubros. El P.UNITARIO se arrastra por defecto desde APU (no se tipea a mano). Free solo toca Rubros; PRO puede tocar Rubros **y** APU (rendimientos, materiales, agregar subitems).
- **Fila "OTRO" en cada rubro:** texto libre + cantidad + precio, 100% editable por Free y PRO.

---

## 3. Selector "Tipo de Presupuesto" — CERRADO esta sesión

Opciones del selector: (1) Mano de obra sola · (2) Materiales + mano de obra · (3) Con impuestos · (4) Sin impuestos.

**Importante — corrección de UI (no son 3 solapas fijas):** la app tiene solo **dos solapas**, no tres. Solapa 1 = Rubros (siempre). Solapa 2 = **una única solapa cuyo contenido cambia dinámicamente** según lo que elija el selector — muestra el contenido de APU (con materiales) o el de APU sin materiales, nunca las dos a la vez ni como pestañas separadas.

- **Free:** solo puede elegir **"Materiales + mano de obra"**. Como no tiene acceso a la otra opción del selector, para Free la Solapa 2 siempre muestra APU (con materiales) — es fijo, no hay nada que alternar.
- **PRO:** puede tocar el selector y elegir "Mano de obra sola" también → cuando lo hace, el contenido de la Solapa 2 cambia dinámicamente a mostrar APU sin materiales. Puede ir y volver entre ambas vistas.
- Con/sin impuestos: **disponible para Free y PRO por igual**, y es independiente de cuál de las dos vistas (con/sin materiales) esté mostrando la Solapa 2.

## 4. Impuestos — CERRADO esta sesión

- Ambos (Free y PRO) pueden alternar con/sin impuestos.
- **PRO** puede editar la composición y el % de cada impuesto individualmente (IVA, IIBB, Tasas Municipales, etc.).
- **Free** solo ve el **total agregado** de impuestos como un único porcentaje/monto sumado — no se le desglosa ni se le explica qué compone ese total (no ve "esto es IVA", "esto es IIBB", etc.).

## 5. Suelo y zona sismorresistente — CERRADO esta sesión

- El selector de tipo de suelo (1/2/3, default tipo 3) y el de zona sismorresistente (0 a 4, default zona 0 Bs. As.) están **disponibles tanto para Free como para PRO** — no es una restricción de plan, es una variante de cálculo interno para todos.

## 6. Catálogo personalizado PRO — CERRADO esta sesión

- Cuando un usuario PRO agrega rubros nuevos y/o APUs nuevas (no solo subitems), esas adiciones **quedan guardadas a ese usuario en particular** y están disponibles para reutilizar en sus futuras obras — no es un catálogo global compartido, es personal del usuario que lo creó.
- Nota de diseño (a validar en la próxima sesión técnica): esto es consistente con la regla ya cerrada de que el catálogo PRO editable vive asociado al `creador_usuario_id`, en la misma lógica de "caja blanca" que ya usamos para APU/Coeficiente K.

---

## 7. Instalaciones — red de contacto de instaladores por zona — CERRADO (versión V1) esta sesión

Idea base: en el rubro de Instalaciones, tener contactos de instaladores (agua, electricidad, gas, etc.) segmentados por zona, para no dejar al profesional gestionando ese contacto a mano desde cero.

**V1 — lo que se implementa ahora:**

- El instalador **NO es un rol de usuario propio de la app** (no tiene cuenta, no hace self-service de precios como el corralón). Es un **directorio curado**: Sebastián sugiere/agrega instaladores manualmente (con eventual asistencia de sugerencias), y el usuario Administrador de una obra también puede agregar los suyos propios. Mismo espíritu que el cold-start plan de corralones, pero sin proyectar todavía una cuenta propia para el instalador.
- La zonificación de instaladores es **una zonificación geográfica/de servicio distinta** a la zona sismorresistente CIRSOC-INPRES ya usada en Rubros/APU (esa no se toca, sigue siendo la norma técnica de cálculo de hierro/cemento). Son dos conceptos de "zona" separados y no deben mezclarse en el modelo de datos.
- **"Mandar a Presupuestar" en Instalaciones funciona en 3 etapas evolutivas** (no se implementan todas juntas):
  1. **Etapa 1 (ahora):** el usuario pide el precio de la instalación por fuera de la app (usando el contacto del directorio) y **carga el precio manualmente** en Rubros/APU cuando lo tiene. No hay integración automática — el directorio es solo un facilitador de contacto.
  2. **Etapa 2:** el usuario solicita el contacto del instalador (sugerido por la app o cargado por el Administrador) y se comunica por fuera de la app — un paso más asistido que la Etapa 1, pero todavía sin presupuestar dentro de la app.
  3. **Etapa 3 (mucho más adelante, app más madura):** solicitar la cotización directamente desde la app. Se define cuando corresponda, no ahora.
- Free vs. PRO para esta feature: **queda pendiente, no se decide todavía.**
- Nota de conexión: el criterio de cuándo/cómo un cliente puede pedir datos de un profesional (ya charlado en el motor de referidos por ranking de la herramienta freemium para cliente final) aplica también acá como referencia de criterio, aunque instaladores y profesionales sean actores distintos.

**Diferido a V2 (no se construye ahora, solo queda anotado para no perderlo):**
- Evaluar si conviene que el instalador tenga un rol de usuario propio (cuenta, self-service de precios/disponibilidad), similar al corralón — decisión basada en si hay demanda real de usuarios PRO pidiendo esto.
- Integrar instaladores al mismo framework de "Mandar a Presupuestar" con niveles de membresía (Partner Inicial / Suscripción Estándar / Socio Premium) que ya existe para corralones.
- Automatizar la Etapa 3 (pedido de cotización directo desde la app).

---

## 9. Motor de precios de materiales — Fase 1 automática (CERRADO esta sesión)

- Bot 100% automático, sin intervención de Sebastián, para arrancar la cobertura de precios mientras no hay volumen real de corralones cargando datos propios.
- Fuente: MercadoLibre, vía su API pública de búsqueda (no scraping — más estable y evita problemas de ToS), filtrando por **envío gratis** como heurística de precio "todo incluido" (evita tener que estimar flete por separado, relevante en la zona Bariloche/El Bolsón/Villa La Angostura).
- Esta es la Fase 1 real y concreta del motor de precios que ya estaba anotado como "fallback a MercadoLibre si faltan corralones" — queda resuelta.
- Pendiente técnico (para cuando se diseñe en detalle): filtro de calidad de vendedor en ML, y regla de combinación cuando además hay datos de 1+ corralones (¿promedia con ML o ML queda solo como alerta de desvío?).

## 10. Directorio de Proveedores + "Mandar a Presupuestar" activado por el usuario (CERRADO esta sesión)

- Es la Fase 1 (bot de reclutamiento) del roadmap de proveedores ya documentado, pero con el disparador cambiado: en vez de una campaña de Sebastián, el disparador es **cada presupuesto real que un profesional termina**.
- Flujo: el profesional termina el presupuesto → elige 1, 2 o 3 corralones de una solapa Proveedores (nombre/dirección/WhatsApp/email, filtrable por zona) → les manda el listado de materiales para cotizar.
- Bifurcación según estado del corralón:
  1. **Corralón ya registrado** (aunque sea con `usuario_id` nulo, cargado en el cold-start): el pedido le llega como evento dentro de la app.
  2. **Corralón no registrado todavía**: el envío funciona como gancho de reclutamiento — mensaje de cara afuera (no es una alerta interna) explicando qué es computoPRO, qué gana el corralón apareciendo ahí, y pidiendo que devuelva el listado cotizado para cargarlo.
- **Incentivo agregado hoy:** ofrecer un **descuento a corralones que usan la app** como palanca adicional de reclutamiento, más allá de la sola visibilidad en el directorio.

### Pendiente de definir (no cierra el flujo de datos todavía)
- ¿El profesional puede tipear un corralón nuevo de puño y letra (nombre + WhatsApp) que ni siquiera está cargado en el sistema, disparando el mismo cold outreach? ¿O solo puede elegir entre los ya cargados?
- Canal de cold outreach hacia un corralón no registrado: ¿WhatsApp, email, o ambos? (Distinto del stack de alertas internas ya definido — Telegram/email/WhatsApp — porque esto es de cara afuera, hacia alguien que todavía no es usuario.)

## 11. Guión de cold-start manual (CERRADO — puesta en práctica del plan ya documentado)

- Sebastián contacta en persona (o por WhatsApp) a 2-3 corralones reales, les explica la app y les pide precio de su propio listado de materiales.
- A cambio les ofrece aparecer en la solapa de Proveedores dentro de la app — ese es el incentivo para que se tomen el trabajo de cotizar.
- Les deja un contacto/bot para dudas antes de que devuelvan el listado cargado.
- Mensaje sugerido de arranque para el bot de reclutamiento (ajustable):

  > *"Hola [Corralón], te escribimos de computoPRO, una app para arquitectos y constructores de la zona. Estamos armando el listado de precios de materiales de construcción y nos gustaría que ustedes sean uno de los proveedores de referencia. Les compartimos un listado de materiales — si nos pasan sus precios actuales, los cargamos y quedan visibles dentro de la app para que los profesionales les pidan presupuesto directamente a ustedes. Si usan la app activamente, tienen un descuento [a definir]. Cualquier duda, respondan por acá."*

- Esto no abre preguntas técnicas nuevas — es la ejecución práctica de la Fase 1 (bot de reclutamiento) y el cold-start plan ya cerrados anteriormente.

## 12. Pendiente para la próxima sesión

- Cerrar las 2 preguntas de la sección 10 (corralón tipeado a mano / canal de cold outreach).
- Decidir Free vs. PRO para "Mandar a Presupuestar" de Instalaciones (sección 7, punto pendiente).
- Recién con eso cerrado, pasar a diseño de datos concreto para Claude Code: tablas de `rubros`, `apu_items`, `apu_sin_materiales`, relación con `creador_usuario_id` para el catálogo personalizado PRO, tabla/función de precios ML, y cómo se engancha (si corresponde) con `obra_members`/proveedores para el directorio de Instaladores (V1, curado) y Directorio de Proveedores/corralones.
