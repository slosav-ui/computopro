-- Costo de mano de obra — solo documentación (COMMENT ON COLUMN), sin cambiar ningún valor.
-- Registra en el schema mismo el fundamento normativo de suss_pct/obra_social_patronal_pct/art_pct
-- y por qué el 28% de seguridad social del PDF de la liquidadora ("VALOR OBRERO-092026", sept-26,
-- no está en el repo) se descartó — decisión cerrada 2026-09-02.
--
-- El fundamento completo, con todas las decisiones de esta pieza, vive en
-- docs/costo_mano_de_obra_decisiones.md (referenciado desde CLAUDE.md) — leer ahí antes de tocar
-- cualquiera de estas columnas. Este archivo es solo el puntero visible desde Supabase, no
-- duplica el razonamiento completo a propósito: que el fundamento viva en un solo lugar es
-- justamente el problema que esta pieza vino a resolver.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- No confundir con las migraciones 0036-0039: esas cambiaron schema y datos. Esta es solo
-- metadata (COMMENT ON COLUMN).

comment on column obra_presupuesto_config.suss_pct is
  'Default 18% — Ley 27.541 art. 19, PyME/industria/construcción/agropecuario CON certificado '
  'MiPyME vigente. Alternativa 20,4%: sin certificado MiPyME, o empresas de servicios/comercio por '
  'encima de mediana empresa tramo 2. El 28% del PDF de la liquidadora ("Seguridad social '
  'Jubilación+Obra social") se descartó por falta de fundamento — ni 18+6 ni 20,4+6 lo explican. '
  'Fundamento completo y decisión en docs/costo_mano_de_obra_decisiones.md.';

comment on column obra_presupuesto_config.obra_social_patronal_pct is
  'Default 6% — Ley 23.660, se calcula aparte sobre el bruto. Ver el comment de suss_pct: el PDF '
  'de la liquidadora junta este concepto con SUSS en un 28% descartado por falta de fundamento. '
  'Fundamento completo en docs/costo_mano_de_obra_decisiones.md.';

comment on column obra_presupuesto_config.art_pct is
  'Default 10.23%. SIN VERIFICAR contra una póliza real — viene del PDF de la liquidadora '
  '("VALOR OBRERO-092026", sept-26), no de la ART contratada por el usuario. Pendiente abierto: '
  'reemplazar por la alícuota real. Detalle en docs/costo_mano_de_obra_decisiones.md.';

comment on column obra_presupuesto_config.fijos_operario_mensual is
  'Default 57.344,78 = 5 componentes fijos del PDF de la liquidadora (ART fija 1.905 + Seg. Vida '
  'Obligatorio 424,62 + Preocupacional 23.333,33 + Indumentaria 29.681,83 + Telegrama 2.000), todos '
  'verificados y coincidentes salvo la suma fija de ART (mismo pendiente que art_pct). Detalle en '
  'docs/costo_mano_de_obra_decisiones.md.';
