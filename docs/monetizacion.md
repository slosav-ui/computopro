computoPRO — Roadmap de monetización secundaria (documentado, no priorizado aún)



Contexto: proyecto 100% personal de Sebastián, sin Sergio ni la constructora. Bloqueo técnico actual sin resolver: mismatch id (int) / uuid en Supabase, y spec de roles de Etapa 3 en pausa.



1\. Motor de referidos por ranking (arquitectos PRO)

Trabajos con firma profesional → se sugieren 3 arquitectos de la zona, ordenados por actividad en la app, todos PRO. Pendiente: regla para zonas con <3 PRO disponibles.



2\. Bolsa de trabajos oculta (documentación sin firma)

Pool chico curado a mano (3-5), asignación por score objetivo (no subasta, no disponibilidad), rotación forzada, sin control de horario, facturación formal, T\&C de prestador independiente. Build en 4 fases: bot completitud → ranking → pool manual → anonimato. Requiere abogado laboralista antes de lanzar.



3\. Estándares de calidad

Plantillas maestras por documento + revisión en 3 capas (bot → par del pool → Sebastián por excepción). Evita cuello de botella y supervisión directa tipo relación laboral.



4\. Sistema de alertas automáticas

3 niveles de severidad (crítico/atención/informativo). Stack: Telegram → email de respaldo → WhatsApp al final. Infra: Supabase triggers + pg\_cron + tabla alertas.



5\. Motor de precios de materiales (APU)

Promedio de 2-3 corralones en \~200km, fallback MercadoLibre, autoservicio de carga de precios. Pieza central: schema unidad de compra vs. unidad de uso con factor de conversión. Mostrar rangos + fuente + fecha + outliers marcados + ajuste manual PRO, en vez de perseguir precisión absoluta.



6\. Onboarding de corralones sin fricción

Alta gratis, autoservicio, sin SLA que fiscalizar. Arranque manual mínimo: 2-3 corralones de contacto propio de Sebastián para romper el huevo-gallina inicial.



7\. Freemium para cliente final + creación de necesidad

Angulo de marketing: profesionales que presupuestan por analogía en vez de APU real. Herramienta con coeficientes K no editables da estimación rápida al cliente → funnel hacia profesional (conecta con punto 1). Requiere disclaimer visible de "estimación no vinculante".



8\. Plan PRO — prueba gratuita y precio (decisiones 2026-09-07)

Un mes gratis de PRO al registrarse. Al vencer, pasa a Free automáticamente — no es un plan pago desde el alta, es un período de prueba.

Si durante ese mes el usuario personalizó APU (rendimientos/insumos editados, ver `personalizar_item_apu`) y después cae a Free, esas personalizaciones no se borran: quedan guardadas en su usuario (misma tabla, mismo dueño), pero vuelve a ver la oficial hasta que sea PRO de nuevo — necesita PRO para usarlas, no para conservarlas. Esto tiene que quedar explicado desde antes de que el usuario empiece a cargar nada, en el arranque del mes de prueba — no como sorpresa recién cuando el mes se vence y deja de poder editar.

Precio orientativo: USD 15/mes. El equivalente en pesos no se fija como un segundo número aparte — se revisa periódicamente, porque un valor en ARS fijado de una vez se desactualiza (mismo problema que ya resuelve el USD Ref. BNA del Dashboard, que se actualiza al abrir la app en vez de quedar hardcodeado). Corrige el precio anterior que tenía anotado el roadmap (`CLAUDE.md`, "Monetización y lanzamiento": USD 12/mes o $15.000 ARS/mes) — ese valor queda obsoleto, no es un error de este documento.



9\. Desglose de Factor K es exclusivo de PRO (decisión 2026-09-07)

Free ve la composición de una partida completa — mano de obra con rendimientos, materiales con precio unitario y subtotal, el total de la partida, y el precio final ya armado en Cómputo. Lo que Free NO ve es el desglose de cómo se llega a ese precio: la cascada del Factor K, los porcentajes de cada concepto, las bases de cálculo, ni las líneas de impuesto por separado.

Motivo textual de Seba: "si no, lo que le estamos dando es que el Free se hace sus planillas y se va de acá, y no paga". El desglose del Factor K (Gastos Generales, Imprevistos, EPP, Costo Financiero, Beneficio, impuestos línea por línea, con sus bases explicadas) es exactamente la estructura de formación de precio que un profesional pagaría por replicar en su propia planilla si la tuviera completa y gratis. Que un PRO copie lo suyo a un Excel propio está bien — pagó por tenerlo.

**Corrige un criterio ya cerrado**: `docs/factor_k_apu_decisiones.md` §4 documentaba "Free ve todo, el panel de edición no agrega información nueva, el gate va solo en Editar" — ese criterio queda descartado para el desglose de Factor K específicamente (no para el resto de la app, donde "no ocultar la función, gatear la acción" sigue siendo la regla general). Aplica tanto al bloque de cabecera de la Solapa APU (`BloqueFactorK`, Paso A — porcentajes y bases sin monto) como al desglose por partida (`BloqueFactorKPartida`, Paso B — con montos reales). Free ve un aviso de función PRO en el lugar de cada uno, nunca un hueco sin explicación.



Pendientes legales transversales: ToS/Privacidad propios, Ley 25.326 (datos de ejecutores/CV), deslinde por variación de costos, esquema de facturación si la app intermedia cobros.

