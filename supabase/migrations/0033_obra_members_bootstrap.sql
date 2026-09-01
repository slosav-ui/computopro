-- Bootstrap de obra_members al crear una obra.
--
-- Bug encontrado en conversación (no hay doc en docs/ para esta pieza): ObrasRepository.crearObra()
-- solo inserta en `obras`, nunca en `obra_members` -- no hay, ni hubo nunca, ningún código en lib/
-- que inserte esa fila. Toda obra creada desde la app nace sin ningún miembro, lo que la deja
-- inutilizable en cualquier pantalla que ya dependa de UserContext/obra_members (hoy la solapa APU
-- de PresupuestosScreen, ver CLAUDE.md). No es un cambio de criterio: la política
-- obra_members_insert (0004_rls_etapa3.sql) ya preveía el bootstrap desde el diseño original
-- ("usuario_id = auth.uid() and ... obras.id_admin_creador = auth.uid()") -- faltó el código que lo
-- ejecutara.
--
-- Mismo patrón que 0014_perfiles.sql y 0020_obra_presupuesto_config.sql (trigger `after insert on
-- obras`, SECURITY DEFINER, backfill en la misma migración). Trigger separado y migración aparte
-- en vez de sumarse a 0020: responsabilidad distinta (permisos, no configuración de presupuesto) y
-- 0020 ya está aplicada en producción -- no se edita una migración histórica.
--
-- Verificado antes de escribir esta migración (conteo real en producción, 2026-09-01):
-- `id_admin_creador` se escribe siempre y con valor real en el único call site de crearObra()
-- (ObrasListScreen solo renderiza con sesión activa, ver AuthGate) -- el guard de abajo es
-- defensivo, no cubre un caso que se haya observado. Conteo de obras sin ninguna fila en
-- obra_members: 1 reparable ("OBRE PRUEBA 2"), 0 con id_admin_creador null.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Trigger: alta automática del creador como admin_maestro
-- =====================================================================

create or replace function public.handle_new_obra_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.id_admin_creador is not null then
    insert into public.obra_members (obra_id, usuario_id, rol)
    values (new.id, new.id_admin_creador, 'admin_maestro')
    on conflict (obra_id, usuario_id, rol) do nothing;
  end if;

  return new;
end;
$$;

create trigger on_obra_created_member
  after insert on obras
  for each row execute function public.handle_new_obra_member();

-- =====================================================================
-- Backfill: obras ya creadas antes de esta migración
-- =====================================================================
--
-- Acotado a obras sin NINGUNA fila en obra_members (no a "toda obra con id_admin_creador"),
-- a propósito: es la condición exacta que se midió (count = 1) y la que corresponde al problema
-- que se está arreglando -- revivir obras huérfanas, no reinsertar admin_maestro en una obra donde
-- a su creador se le haya sacado ese rol después. Ese caso no existe hoy, pero la migración debe
-- decir exactamente lo que hace.

insert into obra_members (obra_id, usuario_id, rol)
select o.id, o.id_admin_creador, 'admin_maestro'
from obras o
where o.id_admin_creador is not null
  and not exists (select 1 from obra_members m where m.obra_id = o.id)
on conflict (obra_id, usuario_id, rol) do nothing;

-- =====================================================================
-- Diagnóstico manual -- no forma parte de la migración, no ejecutar en bloque
-- =====================================================================
--
-- Obras huérfanas que el backfill de arriba no puede reparar solo (sin id_admin_creador para
-- saber a quién asignar admin_maestro). No inventar un valor por defecto acá: asignar el dueño
-- equivocado es un problema de acceso, no un dato cosmético. Revisar a mano en el SQL Editor caso
-- por caso si aparece alguna.
--
-- select id, nombre, created_at
-- from obras o
-- where o.id_admin_creador is null
--   and not exists (select 1 from obra_members m where m.obra_id = o.id);
