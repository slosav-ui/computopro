-- Modelos de Certificación, paso 2: hitos_certificacion (Modelo B) + monto_total_contratado.
-- Ver docs/modelos_certificacion_diseno_datos.md, secciones 4, 5 y 6, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Nota de alcance: monto_total_contratado se agrega acá (no era parte del paso 2 tal como se
-- había nombrado) porque calcular_avance_hitos() divide por esa columna — sin ella la función
-- no tiene contra qué calcular el %. anticipo_pct/fondo_reparo_pct (también diseñados en §6)
-- quedan fuera de este archivo: no los necesita nada de lo de acá, van en una migración aparte.
--
-- Nota de alcance (RLS): a diferencia de 0001-0003 (que quedaron sin RLS hasta el paso
-- consolidado 0004_rls_etapa3.sql), acá se agrega la RLS de hitos_certificacion en el mismo
-- archivo de creación — pedido explícito del usuario, para no dejar la tabla abierta ni un
-- momento entre creación y RLS. Se apoya en las mismas funciones helper SECURITY DEFINER que ya
-- existen (is_obra_member, tiene_rol_en_obra de 0004_rls_etapa3.sql), sin funciones nuevas.
--
-- Quién puede escribir hitos: el pedido original decía "el Administrador define libremente los
-- hitos", pero sin la palabra "únicamente" — a diferencia de obras.modelo_certificacion, donde
-- sí se cerró explícitamente "únicamente el Administrador" (§8 del diseño). Para no ser más
-- restrictivo de lo que se pidió, la política de escritura de abajo sigue en cambio la matriz de
-- permisos de Gestión de Obra ya documentada en CLAUDE.md ("Admin Maestro / Profesional: edición
-- total... aprobación de certificados y adicionales sin restricción"): admin_maestro Y
-- profesional pueden crear/editar/rescindir hitos, no solo admin_maestro. Marcado como decisión
-- a confirmar si el criterio real es más restrictivo (ver aviso fuera de este archivo).

alter table obras
  add column monto_total_contratado numeric;  -- Modelo B, ver §6/§7.1 del diseño

create table hitos_certificacion (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  descripcion text not null,               -- libre: "Pago mensual - Agosto 2026", "Al terminar la estructura"
  monto numeric not null check (monto > 0),
  estado text not null default 'activo'
    check (estado in ('activo', 'finalizado', 'rescindido')),
  contratista_nombre text,                 -- null = contrato principal (§7.3); con valor = Subcontrato
  hito_anterior_id uuid references hitos_certificacion(id),  -- retoma el trabajo de un hito rescindido (§4)
  motivo_rescision text,
  creado_por uuid not null references auth.users(id),
  fecha_creacion timestamptz not null default now(),
  fecha_finalizacion timestamptz,          -- se completa al pasar a 'finalizado'
  check (estado <> 'rescindido' or motivo_rescision is not null)
);

-- =====================================================================
-- calcular_avance_hitos: % de avance del contrato principal (Modelo B)
-- =====================================================================
--
-- Solo cuenta hitos 'finalizado' del contrato principal (contratista_nombre is null) — los
-- Subcontratos comparten esta misma tabla pero no deben mezclarse con el % que ve el Cliente
-- (§4/§7.3 del diseño). Binario: un hito 'activo' aporta 0 hasta que pasa a 'finalizado', sin
-- certificación parcial dentro del hito (§7.2, definición cerrada).
--
-- STABLE (no VOLATILE): no escribe nada, el resultado solo depende de los datos leídos — permite
-- que el planner la optimice en consultas que la llaman varias veces en la misma transacción.
create or replace function calcular_avance_hitos(p_obra_id uuid)
returns numeric language sql stable as $$
  select coalesce(
    100.0 * sum(monto) filter (where estado = 'finalizado')
      / nullif((select monto_total_contratado from obras where id = p_obra_id), 0),
    0
  )
  from hitos_certificacion
  where obra_id = p_obra_id and contratista_nombre is null;
$$;

grant execute on function calcular_avance_hitos(uuid) to authenticated;

-- =====================================================================
-- RLS
-- =====================================================================

alter table hitos_certificacion enable row level security;

-- SELECT: abierto a cualquier miembro activo de la obra, mismo patrón que obra_members y
-- libro_entradas — Cliente/Veedor necesitan ver el % de avance y el historial de hitos, y ese
-- avance se calcula sobre estas filas.
--
-- Limitación conocida, igual que el resto de Etapa 3 (ver nota general al final de
-- 0004_rls_etapa3.sql): RLS filtra filas, no columnas. Un rol en "vista operativa sin montos"
-- como Constructor puede leer igual el campo monto de cualquier hito visible — ocultarlo queda
-- en la capa de app (UserContext), no acá.
create policy hitos_certificacion_select on hitos_certificacion for select
using (is_obra_member(obra_id));

-- INSERT: admin_maestro o profesional (ver nota de alcance arriba), y solo se pueden autoasignar
-- como creado_por — no pueden registrar un hito a nombre de otro usuario.
create policy hitos_certificacion_insert on hitos_certificacion for insert with check (
  creado_por = auth.uid()
  and (tiene_rol_en_obra(obra_id, 'admin_maestro') or tiene_rol_en_obra(obra_id, 'profesional'))
);

-- UPDATE: solo mientras el hito sigue 'activo' (USING exige el estado viejo) — una vez
-- 'finalizado' o 'rescindido' ninguna fila hace match acá, así que queda congelada de hecho
-- (append-only real, sin necesitar una condición aparte que la excluya explícitamente). Cubre
-- tanto la edición de monto/descripcion mientras está activo (§7.4) como la transición a
-- 'finalizado' o 'rescindido' (el check constraint de la tabla ya exige motivo_rescision para
-- este último).
create policy hitos_certificacion_update on hitos_certificacion for update using (
  estado = 'activo'
  and (tiene_rol_en_obra(obra_id, 'admin_maestro') or tiene_rol_en_obra(obra_id, 'profesional'))
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro') or tiene_rol_en_obra(obra_id, 'profesional')
);

-- Sin política DELETE: append-only, igual que el resto de Etapa 3 — "rescindir" (no borrar) es
-- el mecanismo para cerrar un hito que no va a completarse, y queda visible en el historial tal
-- como pide el diseño original.
