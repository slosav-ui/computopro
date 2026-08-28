-- Rubros/APU parte 2 — Migración 1: tabla `perfiles`, flag mínimo Free/PRO (es_pro).
-- Ver docs/rubros_apu_permisos_selector_diseno_datos.md, decisión 6 (§1) y schema en §2.6, para
-- el diseño completo.
--
-- Primera tabla de perfil de usuario del proyecto — hasta ahora auth.users (100% Supabase Auth)
-- era la única fuente de identidad, sin ninguna fila propia en public. Deliberadamente mínima:
-- solo lo que esta pieza necesita para empezar a anclar Free/PRO en algo más que capa de app. Es,
-- en chico, el primer paso de la pieza más grande "Sistema de Registro/Login de Usuarios" que
-- CLAUDE.md ya tenía pendiente sin diseñar (método de registro, datos profesionales, etc.) —
-- cuando se diseñe completa, esta tabla es candidata a extenderse, no a duplicarse.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table perfiles (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  es_pro boolean not null default false,
  created_at timestamptz not null default now()
);

-- =====================================================================
-- Backfill: usuarios ya registrados antes de esta migración
-- =====================================================================
--
-- Sin esto, cualquier usuario dado de alta antes de hoy quedaría sin fila en perfiles hasta que
-- se le cree una a mano — el trigger de abajo solo dispara en altas nuevas. Todos arrancan en
-- es_pro = false (Free); cargar a mano el es_pro = true de quien corresponda desde el SQL Editor
-- después de correr esta migración.

insert into perfiles (usuario_id)
select id from auth.users
on conflict (usuario_id) do nothing;

-- =====================================================================
-- Trigger: alta automática de la fila al crear la cuenta
-- =====================================================================
--
-- Patrón estándar de Supabase (trigger AFTER INSERT sobre auth.users) — sin esto, cada usuario
-- nuevo se registraría sin fila en perfiles y quedaría sin nada que la política de SELECT de
-- abajo le muestre. SECURITY DEFINER porque el trigger corre disparado desde auth.users (schema
-- distinto a public) y necesita escribir en perfiles con privilegio elevado — en el instante del
-- signup el usuario nuevo todavía no tiene una sesión autenticada con la que hacerlo por sí
-- mismo. search_path fijo, mismo hardening que el resto de las funciones SECURITY DEFINER del
-- proyecto (ver is_obra_member en 0004_rls_etapa3.sql).

create or replace function public.handle_new_user_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (usuario_id) values (new.id)
  on conflict (usuario_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created_perfil
  after insert on auth.users
  for each row execute function public.handle_new_user_perfil();

-- =====================================================================
-- RLS
-- =====================================================================
--
-- SELECT: cada usuario ve solo su propia fila (auth.uid() = usuario_id), mismo patrón que ya
-- usa corralones (0013_rls_proveedores_precios.sql) — la app necesita leer es_pro para decidir
-- qué mostrar habilitado.
--
-- Deliberadamente SIN política de UPDATE ni INSERT para el usuario autenticado. Si hubiera
-- UPDATE con "using/with check: usuario_id = auth.uid()" (el patrón que usan la mayoría de las
-- tablas de dueño de este proyecto), cualquier usuario Free podría hacer
-- "update perfiles set es_pro = true where usuario_id = auth.uid()" llamando directo a la API de
-- Supabase, sin pasar por la UI de la app, y ponerse PRO gratis — es_pro es exactamente la
-- columna que no le corresponde tocar a quien la posee. Como hoy perfiles no tiene ninguna otra
-- columna que un usuario necesite editar por su cuenta, la fila queda de solo lectura para el
-- usuario: alta automática por el trigger/backfill de arriba, cambios de es_pro exclusivamente a
-- mano vía SQL Editor (service_role, ignora RLS) hasta que exista un sistema de planes/pagos real
-- que dispare el cambio de forma controlada (ej. una función SECURITY DEFINER llamada desde un
-- webhook de pago, no un UPDATE directo del usuario).

alter table perfiles enable row level security;

create policy perfiles_select on perfiles for select
using (usuario_id = auth.uid());
