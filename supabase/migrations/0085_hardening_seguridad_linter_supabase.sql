-- Hardening de seguridad — cierra los 3 hallazgos del linter de Supabase (2026-09-07), en el orden
-- de prioridad acordado con Seba. Diagnóstico completo función por función en la conversación que
-- originó esta migración (no hay doc en docs/ para esta pieza) — acá solo el fix.
--
-- Causa raíz común de los pasos 1 y 2: Postgres otorga EXECUTE sobre una función a PUBLIC
-- automáticamente al crearla (PUBLIC incluye a `anon`). Cada función de este proyecto ya tiene su
-- propio `grant execute ... to authenticated`, pero eso es aditivo — nunca reemplaza el
-- otorgamiento implícito a PUBLIC. Confirmado grepeando todo `supabase/migrations/`: cero `revoke`
-- en el historial completo. Por eso el linter marca ~20 funciones SECURITY DEFINER como
-- ejecutables sin sesión — es un patrón sistemático de las migraciones, no descuidos puntuales.
--
-- CORRECCIÓN DE SEBA AL APLICAR (2026-09-08): `revoke ... from public` solo no alcanzó — el rol
-- `anon` tenía además un `grant` directo (no solo el heredado de PUBLIC), probablemente parte de la
-- configuración default de Supabase al crear el proyecto/schema, no de ninguna migración de este
-- repo. Un `revoke` de PUBLIC no toca un grant directo a un rol específico — hacen falta los dos.
-- Todos los `revoke` de abajo quedaron `from public, anon` por eso. Verificado en producción:
-- ninguna función queda abierta al rol anónimo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), en el orden en que aparece
-- este archivo. No ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde
-- este entorno.

-- =====================================================================
-- Paso 1 (el que más importa) — calcular_factor_k_subitem: fuga real entre usuarios autenticados,
-- no solo con anon
-- =====================================================================
--
-- Hallazgo: las CTEs `config` (obra_presupuesto_config) e `impuestos` (obra_impuestos) de
-- 0078_redondear_montos_factor_k.sql leían directo por obra_id, sin pasar por is_obra_member — y
-- al ser SECURITY DEFINER eso saltea la RLS de esas dos tablas por completo. Costo-Costo y los
-- montos absolutos sí daban 0 para un no-miembro (dependen de calcular_composicion_detalle_subitem,
-- que sí filtra), pero los PORCENTAJES de configuración de la obra viajaban igual. Consecuencia
-- concreta: con solo un obra_id real (ni hace falta que el subitem_id exista), cualquier usuario
-- autenticado del sistema — no solo anon — podía leer Gastos Generales/Imprevistos/EPP/Costo
-- Financiero/Beneficio/Gestión de materiales de terceros e IVA/IIBB/Tasas de la obra de otro
-- usuario. Exactamente el dato que el proyecto define como más sensible (Coeficiente K "aislado y
-- privado... incluso para el Profesional en otras vistas", ver CLAUDE.md).
--
-- Fix: mismo patrón `autorizado`/is_obra_member que ya usan calcular_precio_apu_subitems (0059) y
-- calcular_composicion_detalle_subitem (0072), aplicado a las dos CTEs que leían sin ese gate.
-- Alcanza con gatear `config`: cada CTE de ahí en adelante (cm_*, sm_*, impuestos, impuestos_
-- totales, resumen, cierre) se conecta a la anterior con CROSS JOIN, nunca LEFT JOIN — una vez que
-- `config` da 0 filas para un no-miembro, toda la cascada da 0 filas, incluidas las dos ramas
-- finales que vuelven a leer obra_impuestos directo (siguen sin gate propio a propósito: ya
-- dependen de `cierre`, que queda vacío). El gate en `impuestos` es redundante hoy (ya depende de
-- `sm`, que también quedaría vacío) pero se deja explícito por consistencia con el resto del
-- proyecto y como defensa si alguien la reescribe en el futuro sin depender de `sm`.
--
-- Resultado: un no-miembro obtiene 0 filas en toda la función, mismo comportamiento fail-closed que
-- el resto del proyecto — sin excepción ni mensaje que confirme si la obra existe.
--
-- CREATE OR REPLACE, misma firma que 0078 — no hace falta DROP.

create or replace function calcular_factor_k_subitem(p_obra_id uuid, p_subitem_id uuid)
returns table(
  vista text,
  orden int,
  concepto text,
  pct numeric,
  base_texto text,
  base_monto numeric,
  monto numeric,
  costo_costo numeric,
  costo_total_trabajo numeric,
  precio_final numeric,
  insumos_con_precio int,
  insumos_total int,
  cierra_ok boolean
)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_presupuesto_config/obra_impuestos, así que el
    -- chequeo de membresía se repite acá a mano — mismo motivo y mismo patrón que
    -- calcular_precio_apu_subitems/calcular_composicion_detalle_subitem.
    select is_obra_member(p_obra_id) as ok
  ),
  detalle as (
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id)
  ),
  agregado as (
    select
      (count(*))::int as insumos_total,
      (count(*) filter (where d.precio_unitario is not null))::int as insumos_con_precio,
      coalesce(sum(d.rendimiento * d.precio_unitario) filter (where d.precio_unitario is not null), 0)
        as costo_costo,
      coalesce(sum(d.rendimiento * d.precio_unitario)
        filter (where d.tipo_componente = 'material' and d.precio_unitario is not null), 0)
        as materiales_subtotal
    from detalle d
  ),
  config as (
    -- Gate real del fix: sin membresía, esta CTE da 0 filas y toda la cascada de abajo la sigue.
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct,
           gestion_materiales_terceros_pct
    from obra_presupuesto_config c
    cross join autorizado a
    where c.obra_id = p_obra_id
      and a.ok
  ),
  cm_gg as (
    select a.*, co.*,
      a.costo_costo * co.gg_pct / 100 as gg_monto
    from agregado a
    cross join config co
  ),
  cm_imprevistos as (
    select cm_gg.*,
      (costo_costo + gg_monto) * imprevistos_pct / 100 as imprevistos_monto
    from cm_gg
  ),
  cm_epp as (
    select cm_imprevistos.*,
      (costo_costo + gg_monto + imprevistos_monto) * epp_pct / 100 as epp_monto
    from cm_imprevistos
  ),
  cm_cf as (
    select cm_epp.*,
      (costo_costo + gg_monto + imprevistos_monto + epp_monto) * costo_financiero_pct / 100
        as costo_financiero_monto
    from cm_epp
  ),
  cm_beneficio as (
    select cm_cf.*,
      (costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto)
        * beneficio_pct / 100 as beneficio_monto
    from cm_cf
  ),
  cm as (
    select cm_beneficio.*,
      costo_costo
        * (1 + gg_pct / 100) * (1 + imprevistos_pct / 100) * (1 + epp_pct / 100)
        * (1 + costo_financiero_pct / 100) * (1 + beneficio_pct / 100)
        as costo_total_trabajo_cm
    from cm_beneficio
  ),
  sm_base as (
    select cm.*,
      (costo_costo - materiales_subtotal) as costo_costo_sm
    from cm
  ),
  sm_imprevistos as (
    select sm_base.*,
      (costo_costo_sm + gg_monto) * imprevistos_pct / 100 as imprevistos_monto_sm
    from sm_base
  ),
  sm_beneficio as (
    select sm_imprevistos.*,
      (costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto)
        * beneficio_pct / 100 as beneficio_monto_sm
    from sm_imprevistos
  ),
  sm_gestion as (
    select sm_beneficio.*,
      materiales_subtotal * gestion_materiales_terceros_pct / 100 as gestion_materiales_terceros_monto
    from sm_beneficio
  ),
  sm as (
    select sm_gestion.*,
      ((costo_costo_sm + gg_monto) * (1 + imprevistos_pct / 100) + epp_monto + costo_financiero_monto)
        * (1 + beneficio_pct / 100)
        + gestion_materiales_terceros_monto
        as costo_total_trabajo_sm
    from sm_gestion
  ),
  impuestos as (
    -- Gate redundante hoy (ya depende de sm, que queda vacío antes), dejado explícito a propósito
    -- — ver comentario de cabecera.
    select oi.tipo, oi.nombre_otro, oi.porcentaje, oi.orden,
      sm.costo_total_trabajo_cm, sm.costo_total_trabajo_sm
    from obra_impuestos oi
    cross join sm
    cross join autorizado a
    where oi.obra_id = p_obra_id
      and a.ok
  ),
  impuestos_totales as (
    select
      sum(porcentaje) / 100 as impuestos_pct_total,
      sum(porcentaje * costo_total_trabajo_cm / 100) as impuestos_monto_cm,
      sum(porcentaje * costo_total_trabajo_sm / 100) as impuestos_monto_sm
    from impuestos
  ),
  resumen as (
    select sm.*,
      it.impuestos_monto_cm, it.impuestos_monto_sm,
      sm.costo_total_trabajo_cm * (1 + it.impuestos_pct_total) as precio_final_cm,
      sm.costo_total_trabajo_sm * (1 + it.impuestos_pct_total) as precio_final_sm
    from sm
    cross join impuestos_totales it
  ),
  cierre as (
    -- Chequeo de cierre sobre valores SIN redondear — ver comentario de cabecera de 0078.
    select resumen.*,
      (
        costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto + beneficio_monto
          = costo_total_trabajo_cm
        and costo_total_trabajo_cm + impuestos_monto_cm = precio_final_cm
      ) as cierra_ok_cm,
      (
        costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto
          + beneficio_monto_sm + gestion_materiales_terceros_monto = costo_total_trabajo_sm
        and costo_total_trabajo_sm + impuestos_monto_sm = precio_final_sm
      ) as cierra_ok_sm
    from resumen
  )
  -- === Salida sin cambios respecto a 0078 — las dos ramas de impuestos que vuelven a leer
  -- obra_impuestos directo (cross join obra_impuestos oi where oi.obra_id = p_obra_id) quedan sin
  -- gate propio a propósito: ya parten de `cierre`, vacío para un no-miembro. =====================
  select 'con_materiales', 1, 'Gastos Generales', gg_pct,
    'Costo-Costo', round(costo_costo, 2), round(gg_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 2, 'Imprevistos', imprevistos_pct,
    'Costo-Costo + GG', round(costo_costo + gg_monto, 2), round(imprevistos_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 3, 'EPP-Seguridad', epp_pct,
    'Costo-Costo + GG + Imprevistos', round(costo_costo + gg_monto + imprevistos_monto, 2), round(epp_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 4, 'Costo Financiero', costo_financiero_pct,
    'Costo-Costo + GG + Imprevistos + EPP',
    round(costo_costo + gg_monto + imprevistos_monto + epp_monto, 2), round(costo_financiero_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 5, 'Beneficio', beneficio_pct,
    'Costo-Costo + GG + Imprevistos + EPP + Costo Financiero',
    round(costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto, 2),
    round(beneficio_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 5 + oi.orden,
    case oi.tipo
      when 'iva' then 'IVA'
      when 'iibb' then 'Ingresos Brutos'
      when 'tasas_municipales' then 'Tasas Municipales'
      else coalesce(oi.nombre_otro, 'Otro')
    end,
    oi.porcentaje, 'Costo Total del Trabajo', round(c.costo_total_trabajo_cm, 2),
    round(oi.porcentaje * c.costo_total_trabajo_cm / 100, 2),
    round(c.costo_costo, 2), round(c.costo_total_trabajo_cm, 2), round(c.precio_final_cm, 2),
    c.insumos_con_precio, c.insumos_total, c.cierra_ok_cm
  from cierre c
  cross join obra_impuestos oi
  where oi.obra_id = p_obra_id
  union all
  select 'sin_materiales', 1, 'Gastos Generales', gg_pct,
    'Costo-Costo', round(costo_costo, 2), round(gg_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 2, 'Imprevistos', imprevistos_pct,
    'Costo-Costo + GG', round(costo_costo_sm + gg_monto, 2), round(imprevistos_monto_sm, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 3, 'EPP-Seguridad', epp_pct,
    'Costo-Costo + GG + Imprevistos', round(costo_costo + gg_monto + imprevistos_monto, 2), round(epp_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 4, 'Costo Financiero', costo_financiero_pct,
    'Costo-Costo + GG + Imprevistos + EPP',
    round(costo_costo + gg_monto + imprevistos_monto + epp_monto, 2), round(costo_financiero_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 5, 'Beneficio', beneficio_pct,
    'Costo-Costo + GG + Imprevistos + EPP + Costo Financiero',
    round(costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto, 2),
    round(beneficio_monto_sm, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 6, 'Gestión de materiales de terceros', gestion_materiales_terceros_pct,
    'Materiales de la vista con materiales', round(materiales_subtotal, 2), round(gestion_materiales_terceros_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 6 + oi.orden,
    case oi.tipo
      when 'iva' then 'IVA'
      when 'iibb' then 'Ingresos Brutos'
      when 'tasas_municipales' then 'Tasas Municipales'
      else coalesce(oi.nombre_otro, 'Otro')
    end,
    oi.porcentaje, 'Costo Total del Trabajo', round(c.costo_total_trabajo_sm, 2),
    round(oi.porcentaje * c.costo_total_trabajo_sm / 100, 2),
    round(c.costo_costo_sm, 2), round(c.costo_total_trabajo_sm, 2), round(c.precio_final_sm, 2),
    c.insumos_con_precio, c.insumos_total, c.cierra_ok_sm
  from cierre c
  cross join obra_impuestos oi
  where oi.obra_id = p_obra_id
  order by 1, 2;
$$;

revoke execute on function calcular_factor_k_subitem(uuid, uuid) from public, anon;

-- =====================================================================
-- Paso 2 — revocar EXECUTE de PUBLIC en el resto de las funciones SECURITY DEFINER
-- =====================================================================
--
-- Todas verificadas función por función (no de lista): cada una exige autoridad real
-- (usuario_id = auth.uid(), is_obra_member, tiene_rol_en_obra o equivalente) antes de cualquier
-- lectura sensible o escritura — con anon, auth.uid() es NULL y ningún chequeo de esa forma puede
-- dar true nunca. Revocar EXECUTE de PUBLIC y de anon no les cambia el comportamiento a un usuario
-- legítimo logueado: el `grant execute ... to authenticated` que cada una ya tiene sigue vigente,
-- es un otorgamiento independiente de esos dos.
--
-- Ninguna pasa a SECURITY INVOKER: la mayoría existe justamente para saltar la RLS de tablas que
-- ni un usuario autenticado puede leer directo (obra_members, precios, apu_composicion_items) —
-- convertirlas rompería su uso legítimo.

-- Etapa 3 — roles y permisos (0004)
revoke execute on function is_obra_member(uuid) from public, anon;
revoke execute on function tiene_rol_en_obra(uuid, text) from public, anon;
revoke execute on function puede_aprobar_monto(uuid, numeric) from public, anon;

-- Certificados — autoridad y ciclo de vida (0009, 0011, 0056)
revoke execute on function obra_modelo_es(uuid, text) from public, anon;
revoke execute on function puede_gestionar_certificado(uuid, numeric) from public, anon;
revoke execute on function emitir_certificado(uuid, boolean) from public, anon;
revoke execute on function marcar_certificado_leido(uuid) from public, anon;
revoke execute on function marcar_certificado_pagado(uuid, text, text[]) from public, anon;
revoke execute on function marcar_certificado_impactado(uuid, text[]) from public, anon;
revoke execute on function subir_pdf_firmado_certificado(uuid, text[]) from public, anon;
revoke execute on function proponer_anulacion_certificado(uuid, text) from public, anon;
revoke execute on function resolver_anulacion_certificado(uuid, boolean, text) from public, anon;

-- Proveedores / insumos / precios (0013)
revoke execute on function is_corralon_owner(uuid) from public, anon;
revoke execute on function calcular_precio_promedio_insumo(uuid) from public, anon;

-- APU — ownership y visibilidad (0018, 0019)
revoke execute on function is_apu_composicion_owner(uuid) from public, anon;
revoke execute on function puede_ver_apu_composicion(uuid) from public, anon;
revoke execute on function tiene_apu_ajena_visible_por_rubro(uuid) from public, anon;
revoke execute on function tiene_apu_ajena_visible_por_subitem(uuid) from public, anon;

-- Consolidado de insumos, precios de APU y composición (0042, 0059, 0072, 0052)
revoke execute on function consolidado_insumos_obra(uuid) from public, anon;
revoke execute on function calcular_precio_apu_subitems(uuid, uuid[]) from public, anon;
revoke execute on function calcular_composicion_detalle_subitem(uuid, uuid) from public, anon;
revoke execute on function calcular_monto_obra_subitems(uuid) from public, anon;

-- Importador (0081)
revoke execute on function confirmar_importacion(uuid) from public, anon;

-- Triggers SECURITY DEFINER (0014, 0020, 0033): no invocables por RPC (Postgres rechaza llamar
-- directo una función que retorna `trigger`), pero el linter las marca igual por tener EXECUTE
-- abierto a PUBLIC. Revocar no afecta el disparo del trigger — la ejecución de un trigger no
-- depende del privilegio EXECUTE del rol que hizo el INSERT/UPDATE.
revoke execute on function public.handle_new_user_perfil() from public, anon;
revoke execute on function public.handle_new_obra_presupuesto() from public, anon;
revoke execute on function public.handle_new_obra_member() from public, anon;

-- =====================================================================
-- Paso 3 — search_path sin fijar (10 funciones, todas SECURITY INVOKER)
-- =====================================================================
--
-- Gravedad menor que los pasos 1 y 2: el ataque de "search_path hijacking" depende de que la
-- función corra con privilegios AJENOS a quien la llama (por eso es crítico en SECURITY DEFINER) —
-- estas 10 son todas SECURITY INVOKER, corren siempre con los privilegios de quien llama, así que
-- un atacante manipulando su propio search_path solo se ataca a sí mismo. Se cierra igual porque es
-- gratis y buena práctica.
--
-- ALTER FUNCTION en vez de CREATE OR REPLACE: no hace falta tocar el cuerpo de ninguna, solo fijar
-- el search_path. Verificado que es seguro para las 10 — todas las tablas/funciones que referencian
-- (obras, certificados, certificado_subitems_avance, subitems, obra_subitems, hitos_certificacion,
-- escala_salarial_uocra, obra_presupuesto_config, obra_valor_hora_override, calcular_valor_hora_
-- mano_obra, calcular_monto_obra_subitems, calcular_avance_acumulado_subitem, calcular_avance_
-- ponderado_rubros) viven en public, así que set search_path = public no cambia ninguna resolución
-- de nombre existente.

alter function calcular_avance_hitos(uuid) set search_path = public;
alter function set_updated_at() set search_path = public;
alter function calcular_valor_hora_mano_obra(uuid, date) set search_path = public;
alter function proteger_id_admin_creador_inmutable() set search_path = public;
alter function calcular_monto_periodo_avance() set search_path = public;
alter function calcular_avance_acumulado_subitem(uuid) set search_path = public;
alter function calcular_avance_ponderado_rubros(uuid) set search_path = public;
alter function calcular_avance_ponderado_obra(uuid) set search_path = public;
alter function calcular_totales_certificado(uuid) set search_path = public;
alter function calcular_excesos_certificado(uuid) set search_path = public;

-- =====================================================================
-- Paso 4 — contraseñas filtradas: NO es SQL, queda afuera de esta migración
-- =====================================================================
--
-- Dashboard de Supabase → Authentication → Passwords → activar "Prevent use of leaked passwords".
-- Requiere plan Pro de Supabase — si el proyecto está en Free, este punto queda bloqueado hasta
-- upgradear, independiente de esta migración.

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) calcular_factor_k_subitem ya NO expone porcentajes de una obra ajena — logueado con un
--    usuario SIN membresía en la obra de prueba, esto tiene que devolver 0 filas (antes devolvía
--    las 12-13 filas de "con_materiales" con gg_pct/imprevistos_pct/etc. reales):
-- select * from calcular_factor_k_subitem(
--   '<obra_id_ajena>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );
--
-- 2) Logueado como miembro real de esa obra, el resultado tiene que ser IDÉNTICO al que ya
--    devolvía antes de esta migración (mismos 12-13 conceptos, mismos pct, mismo cierra_ok) — el
--    fix no cambia nada para un usuario autorizado.
--
-- 3) anon (sin sesión, con la anon key directa contra /rest/v1/rpc/) ya no puede ejecutar ninguna
--    de las funciones de los pasos 1 y 2 — tiene que devolver un error de permisos de Postgres
--    (42501, "permission denied for function ..."), no un resultado ni un error de negocio propio
--    de la función.
--
-- 4) Confirmar que no quedó ningún grant a PUBLIC sin revocar entre las tocadas acá:
-- select p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.prosecdef = true
-- order by p.proname;
-- -- Todas las filas de este listado tienen que dar anon_puede = false, salvo que en el futuro se
-- -- agregue una función SECURITY DEFINER nueva sin su propio revoke.
--
-- 5) Las 10 funciones del paso 3 muestran su search_path en pg_proc:
-- select proname, proconfig from pg_proc
-- where proname in (
--   'calcular_avance_hitos', 'set_updated_at', 'calcular_valor_hora_mano_obra',
--   'proteger_id_admin_creador_inmutable', 'calcular_monto_periodo_avance',
--   'calcular_avance_acumulado_subitem', 'calcular_avance_ponderado_rubros',
--   'calcular_avance_ponderado_obra', 'calcular_totales_certificado', 'calcular_excesos_certificado'
-- );
-- -- proconfig tiene que mostrar {search_path=public} en las 10.
