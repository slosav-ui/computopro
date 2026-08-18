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



Pendientes legales transversales: ToS/Privacidad propios, Ley 25.326 (datos de ejecutores/CV), deslinde por variación de costos, esquema de facturación si la app intermedia cobros.

