-- Rubros/APU parte 2 — Migración 7: `obra_presupuesto_config` (1:1 con obras) + `obra_impuestos`.
-- Selector de tipo de presupuesto, con/sin impuestos, suelo, zona sismorresistente, y los % del
-- resumen APU (GG/Imprevistos/EPP/Beneficio/Gestión de materiales de terceros).
-- Ver docs/rubros_apu_permisos_selector_diseno_datos.md §2.5/§2.2 para el diseño completo.
--
-- Independiente de obra_subitems — solo depende de obras, que ya existe desde antes de esta
-- pieza.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table obra_presupuesto_config (
  obra_id uuid primary key references obras(id) on delete cascade,
  tipo_presupuesto text not null default 'materiales_mano_obra'
    check (tipo_presupuesto in ('materiales_mano_obra', 'mano_obra_sola')),
  aplica_impuestos boolean not null default true,
  tipo_suelo int not null default 3 check (tipo_suelo in (1, 2, 3)),
  zona_sismorresistente int not null default 0
    check (zona_sismorresistente between 0 and 4),
  gg_pct numeric not null default 15,
  imprevistos_pct numeric not null default 4,
  epp_pct numeric not null default 1.5,
  costo_financiero_pct numeric not null default 0,
  beneficio_pct numeric not null default 10,
  gestion_materiales_terceros_pct numeric not null default 4,
  updated_at timestamptz not null default now()
);

create table obra_impuestos (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  tipo text not null check (tipo in ('iva', 'iibb', 'tasas_municipales', 'otro')),
  nombre_otro text,       -- solo usado cuando tipo = 'otro'
  porcentaje numeric not null,
  orden int not null default 0,
  created_at timestamptz not null default now(),
  -- OJO — corrige una imprecisión del diseño original: el check no puede exigir
  -- "nombre_otro not null cuando tipo = 'otro'", porque el 'otro' se siembra vacío por defecto
  -- en cada obra nueva (nadie lo completó todavía) y esa regla lo hubiese bloqueado desde el
  -- primer insert del trigger de más abajo. La regla que sí tiene que valer siempre es la
  -- inversa: nombre_otro NUNCA se usa fuera de la fila 'otro' (evita basura en iva/iibb/tasas).
  constraint obra_impuestos_nombre_otro_solo_en_otro check (
    nombre_otro is null or tipo = 'otro'
  ),
  unique (obra_id, tipo)
);

-- =====================================================================
-- Trigger: alta automática de config + impuestos default al crear una obra
-- =====================================================================
--
-- Mismo patrón que perfiles (0014_perfiles.sql) — sin esto, cada obra nueva quedaría sin fila de
-- configuración hasta que algo la cree a mano, y la app rompería al leerla. SECURITY DEFINER +
-- search_path fijo, mismo hardening que el resto de las funciones de este tipo en el proyecto.
--
-- Valores default de obra_impuestos = los mismos de PLANILLA_BASE_2_0_v3_CORREGIDA.ods (IVA 21%,
-- IIBB 3%, Tasas Municipales 1.5%), más 'otro' en 0% sin nombre — el escape que un PRO completa
-- si necesita un impuesto adicional.

create or replace function public.handle_new_obra_presupuesto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.obra_presupuesto_config (obra_id) values (new.id)
  on conflict (obra_id) do nothing;

  insert into public.obra_impuestos (obra_id, tipo, porcentaje, orden) values
    (new.id, 'iva', 21, 1),
    (new.id, 'iibb', 3, 2),
    (new.id, 'tasas_municipales', 1.5, 3),
    (new.id, 'otro', 0, 4)
  on conflict (obra_id, tipo) do nothing;

  return new;
end;
$$;

create trigger on_obra_created_presupuesto
  after insert on obras
  for each row execute function public.handle_new_obra_presupuesto();

-- =====================================================================
-- Backfill: obras ya creadas antes de esta migración
-- =====================================================================

insert into obra_presupuesto_config (obra_id)
select id from obras
on conflict (obra_id) do nothing;

insert into obra_impuestos (obra_id, tipo, porcentaje, orden)
select o.id, v.tipo, v.porcentaje, v.orden
from obras o
cross join (values
  ('iva', 21::numeric, 1),
  ('iibb', 3::numeric, 2),
  ('tasas_municipales', 1.5::numeric, 3),
  ('otro', 0::numeric, 4)
) as v(tipo, porcentaje, orden)
on conflict (obra_id, tipo) do nothing;

-- =====================================================================
-- RLS
-- =====================================================================
--
-- SELECT abierto a cualquier miembro de la obra (is_obra_member). UPDATE restringido a
-- admin_maestro/profesional, mismo rol-gate que obra_subitems (0019) — la distinción Free/PRO
-- (PRO edita cada impuesto y el selector, Free solo ve el agregado y el selector fijo en
-- "materiales + mano de obra") sigue siendo capa de app, decisión G del diseño fundacional, no
-- una política de RLS nueva. Sin INSERT para el usuario (las filas se crean solas vía el trigger
-- de arriba) ni DELETE (obra_impuestos es un catálogo fijo de 4 filas por obra, se edita, no se
-- borra ni se agregan filas nuevas).

alter table obra_presupuesto_config enable row level security;

create policy obra_presupuesto_config_select on obra_presupuesto_config for select
using (is_obra_member(obra_id));

create policy obra_presupuesto_config_update on obra_presupuesto_config for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

alter table obra_impuestos enable row level security;

create policy obra_impuestos_select on obra_impuestos for select
using (is_obra_member(obra_id));

create policy obra_impuestos_update on obra_impuestos for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);
