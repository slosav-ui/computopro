-- Índices externos que la app usa y hoy están desconectados: CAC y cotización BNA.
-- Ver diagnóstico de la conversación (sin doc en docs/ para esta pieza; se documenta en
-- CLAUDE.md/diagnóstico general al aplicar). Puntos 1 y 2 del corte acordado con Seba —
-- el punto 3 (congelar el presupuesto del Modelo A para que el CAC tenga un monto original
-- contra el cual calcular) queda anotado al final de este archivo, no se construye acá.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Bug encontrado al diagnosticar, aparte del interruptor sin efecto: obras.mes_base_cac se
-- escribía como el string literal 'Agosto 2026' en CADA obra nueva, sin importar la fecha real
-- de creación (lib/presentation/dashboard/obras_list_screen.dart, _obrasRepository.crearObra) --
-- nadie lo notó porque nada leía la columna todavía. Se corrige acá (columna) y en el commit de
-- Dart que acompaña esta migración (que deja de hardcodear el string y usa el mes de creación
-- real). Como el bug escribía siempre el mismo literal, todas las obras existentes con
-- aplica_cac tienen exactamente ese valor -- se puede convertir con un mapeo directo, sin
-- adivinar fecha por fila.
-- =====================================================================

alter table obras alter column mes_base_cac type date using (
  case mes_base_cac
    when 'Agosto 2026' then date '2026-08-01'
    else null  -- valor inesperado (no debería existir) -- null, nunca una fecha inventada
  end
);

-- =====================================================================
-- indices_cac: serie CAMARCO (camarco.org.ar), publicada ~día 20 de cada mes con el valor del
-- mes anterior, en sus tres niveles -- Nivel General, Materiales, Mano de Obra. `mes` es el
-- primer día del mes que describe el índice (no el día de publicación).
--
-- Catálogo global, igual para todos los usuarios -- mismo criterio que `insumos`
-- (0013_rls_proveedores_precios.sql): se carga una vez por migración/SQL Editor, nunca por
-- usuario. Sin política de escritura a propósito: el alta es manual, doce veces al año --
-- automatizar esto (traerlo solo del sitio de CAMARCO) queda anotado como mejora futura, no para
-- ahora -- con pocos usuarios, cargarlo a mano es más confiable que un proceso que puede fallar
-- en silencio (decisión de Seba).
-- =====================================================================

create table indices_cac (
  mes date primary key,
  general numeric not null check (general > 0),
  materiales numeric not null check (materiales > 0),
  mano_obra numeric not null check (mano_obra > 0),
  created_at timestamptz not null default now()
);

alter table indices_cac enable row level security;

create policy indices_cac_select on indices_cac for select
using (auth.uid() is not null);

-- Serie 2026 verificada por Seba (enero-abril, junio, julio) + mayo buscado y confirmado contra
-- una nota de prensa que cita la cifra en puntos de CAMARCO directamente (ver fuente abajo) --
-- ninguno de los siete valores está interpolado ni inventado.
insert into indices_cac (mes, general, materiales, mano_obra) values
  ('2026-01-01', 19209.4, 21778.0, 15444.4),
  ('2026-02-01', 19453.0, 22007.9, 15708.2),
  ('2026-03-01', 19771.2, 22204.2, 16205.2),
  ('2026-04-01', 20493.2, 22870.0, 17009.6),
  -- Mayo: no confirmado por Seba, buscado en fuentes públicas. General/mano de obra citan el
  -- comunicado de CAMARCO en puntos exactos; materiales surge de la misma nota (23.500,2),
  -- consistente con la variación mensual de +2,8% que publicó CAMARCO ese mes contra abril
  -- (22.870,0 × 1,028 ≈ 23.510 -- dentro del margen de redondeo de la cifra publicada, no
  -- calculado por esta migración: el número cargado es el que cita la fuente, no una cuenta
  -- propia). Fuente: https://mercado.com.ar/ladrillos-y-proyectos/indicador-camarco-el-costo-de-construir-en-caba-subio-26-en-mayo
  -- (cita el comunicado de CAMARCO del 22/06/2026, https://www.camarco.org.ar/2026/06/22/indicador-camarco-mayo-2026/).
  ('2026-05-01', 21035.6, 23500.2, 17423.2),
  ('2026-06-01', 21641.1, 23901.9, 18327.3),
  ('2026-07-01', 21960.7, 24149.4, 18752.8);

-- =====================================================================
-- cotizacion_dolar_bna: cotización de referencia del Banco Nación -- fila única (mismo criterio
-- de "no hace falta serie histórica" que el resto de esta pieza: es un valor de referencia
-- puntual para mostrar/convertir, no una redeterminación con cociente entre dos fechas como el
-- CAC). Se pisa con UPDATE cada vez que se actualiza -- constraint `id = 1` para que nunca pueda
-- haber una segunda fila por error.
--
-- Antes de esto no vivía en ninguna tabla: lib/presentation/dashboard/obras_list_screen.dart
-- tenía `_dolarBnaCompra`/`_dolarBnaVenta` como `final double` hardcodeados en el código Dart --
-- no es que estuviera desactualizada, es que solo podía cambiar recompilando la app entera.
-- Mismo criterio de carga manual que el CAC (decisión de Seba): automatizar la actualización con
-- aviso ante variación > 5% queda pendiente, anotado hace tiempo en el diagnóstico general
-- (docs/diagnostico_general_producto.md §3.8).
-- =====================================================================

create table cotizacion_dolar_bna (
  id smallint primary key default 1 check (id = 1),
  compra numeric not null check (compra > 0),
  venta numeric not null check (venta > compra),
  actualizado_en date not null default current_date
);

alter table cotizacion_dolar_bna enable row level security;

create policy cotizacion_dolar_bna_select on cotizacion_dolar_bna for select
using (auth.uid() is not null);

insert into cotizacion_dolar_bna (compra, venta, actualizado_en) values (1485, 1535, current_date);

-- =====================================================================
-- factor_cac_obra: cociente índice-destino/índice-origen para una obra puntual -- el número por
-- el que se multiplica un monto pactado en `mes_base_cac` para expresarlo en pesos de hoy.
--
-- Sin fallback al mes anterior si falta el índice de origen o de destino -- a propósito, pedido
-- explícito de Seba: "si alguien tiene una obra con ajuste y todavía no se publicó el índice, hay
-- que avisar, no calcular con el mes anterior en silencio". `raise exception` en los dos casos,
-- nunca un valor aproximado.
-- =====================================================================

create or replace function factor_cac_obra(p_obra_id uuid, p_serie text default 'general')
returns numeric
language plpgsql security definer set search_path = public stable as $$
declare
  v_mes_base date;
  v_indice_base numeric;
  v_indice_actual numeric;
  v_mes_actual date := date_trunc('month', current_date)::date;
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'No sos miembro de esta obra.';
  end if;

  if p_serie not in ('general', 'materiales', 'mano_obra') then
    raise exception 'Serie de índice CAC inválida: %', p_serie;
  end if;

  select mes_base_cac into v_mes_base from obras where id = p_obra_id;
  if v_mes_base is null then
    raise exception 'Esta obra no tiene mes base de CAC configurado.';
  end if;

  select case p_serie
           when 'general' then general
           when 'materiales' then materiales
           when 'mano_obra' then mano_obra
         end
    into v_indice_base
  from indices_cac where mes = v_mes_base;

  if v_indice_base is null then
    raise exception 'No hay índice CAC (%) cargado para el mes base de esta obra (%).', p_serie, v_mes_base;
  end if;

  select case p_serie
           when 'general' then general
           when 'materiales' then materiales
           when 'mano_obra' then mano_obra
         end
    into v_indice_actual
  from indices_cac where mes = v_mes_actual;

  if v_indice_actual is null then
    raise exception 'Todavía no se cargó el índice CAC (%) de este mes (%).', p_serie, v_mes_actual;
  end if;

  return v_indice_actual / v_indice_base;
end;
$$;

grant execute on function factor_cac_obra(uuid, text) to authenticated;
revoke execute on function factor_cac_obra(uuid, text) from public, anon;

-- =====================================================================
-- calcular_saldo_pendiente_hitos: la conexión real del interruptor al Modelo B.
--
-- Por qué el Modelo B y no el A: el Modelo B ya tiene un monto congelado real
-- (`obras.monto_total_contratado`, fijo desde que se carga -- ver 0008_ajuste_contrato.sql) y
-- cada hito certificado guarda su propio `monto` fijo, inmutable una vez 'finalizado'
-- (0006_hitos_certificacion.sql, política UPDATE que solo deja tocar filas 'activo'). El saldo
-- pendiente = monto_total_contratado − suma de hitos finalizados del contrato principal, y ESE
-- número es al que tiene sentido aplicarle el cociente de factor_cac_obra.
--
-- El Modelo A no tiene un monto congelado equivalente todavía -- calcular_presupuesto_vivo_obra
-- (0091) recalcula en vivo desde los precios actuales de insumos cada vez que se llama, así que
-- no hay ningún "monto original" contra el cual calcular el cociente sin ajustar dos veces
-- (una por Mat y MO, otra por CAC). Esto no es un olvido de esta migración: es la decisión de
-- negocio del 2026-08-31 (memoria de proyecto "precio congelado vs. recalculado" -- el precio
-- queda congelado al presentar el presupuesto, se actualiza solo por el coeficiente pactado,
-- nunca recalculando desde insumos) sin su mecanismo técnico construido todavía. Confirmado por
-- Seba en esta misma conversación: el congelamiento del Modelo A no es una pieza aparte para
-- después, es el prerrequisito de esta — queda anotado como la pieza siguiente, no como este
-- archivo.
--
-- Solo serie 'general': el Modelo B no guarda ningún split materiales/mano de obra de
-- `monto_total_contratado` (es un monto único, a diferencia de las partidas del Modelo A, que sí
-- separan `materiales_subtotal` dentro de la cascada de Factor K) -- aplicar dos índices distintos
-- acá exigiría inventar una proporción que hoy no se carga en ningún lado. Si en el futuro se
-- necesita ese split para Modelo B, es una pieza de diseño aparte, no una extensión mecánica de
-- esta función.
-- =====================================================================

create or replace function calcular_saldo_pendiente_hitos(p_obra_id uuid)
returns numeric
language plpgsql security definer set search_path = public stable as $$
declare
  v_monto_total numeric;
  v_aplica_cac boolean;
  v_certificado numeric;
  v_pendiente_base numeric;
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'No sos miembro de esta obra.';
  end if;

  select monto_total_contratado, aplica_cac into v_monto_total, v_aplica_cac
  from obras where id = p_obra_id;

  if v_monto_total is null then
    raise exception 'Esta obra no tiene monto total contratado cargado.';
  end if;

  select coalesce(sum(monto), 0) into v_certificado
  from hitos_certificacion
  where obra_id = p_obra_id and estado = 'finalizado' and contratista_nombre is null;

  v_pendiente_base := v_monto_total - v_certificado;

  if v_aplica_cac then
    return v_pendiente_base * factor_cac_obra(p_obra_id, 'general');
  end if;

  return v_pendiente_base;
end;
$$;

grant execute on function calcular_saldo_pendiente_hitos(uuid) to authenticated;
revoke execute on function calcular_saldo_pendiente_hitos(uuid) from public, anon;

-- =====================================================================
-- PENDIENTE ANOTADO, NO SE CONSTRUYE ACÁ -- punto 3 del corte, pieza siguiente (no "para más
-- adelante" -- confirmado por Seba: es el prerrequisito para que el CAC sirva en el Modelo A,
-- que es el que usa).
-- =====================================================================
--
-- Decisión de negocio ya cerrada (2026-08-31, memoria de proyecto "precio congelado vs.
-- recalculado", palabras del usuario): "el presupuesto se confecciona con los precios oficiales
-- a la fecha y queda congelado ahí. Desde ese momento, el CAC es el que actualiza los precios de
-- la obra en curso mes a mes, para certificar. Mat y MO sigue su propio camino con los precios
-- reales del mercado, pero eso no toca el presupuesto ya presentado." El criterio YA está
-- decidido -- lo que falta es el mecanismo técnico: un snapshot del presupuesto (probablemente
-- por partida, materiales y mano de obra separados, para que la app pueda usar
-- factor_cac_obra(obra, 'materiales') y factor_cac_obra(obra, 'mano_obra') como pidió Seba) en
-- el momento de "presentar" el presupuesto -- que hoy ni siquiera existe como estado de la obra.
-- Sin este snapshot, calcular_presupuesto_vivo_obra (0091) sigue siendo el único número que hay,
-- y multiplicarlo por el CAC ajustaría dos veces (una por precio de insumo actualizado en Mat y
-- MO, otra por el índice).
