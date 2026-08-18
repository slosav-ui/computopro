-- Etapa 3 — Roles y Permisos, paso 5: RLS para obra_members, modificaciones_obra,
-- audit_log y libro_entradas.
--
-- Diseño acordado en conversación (no en docs/etapa3_roles_permisos_diseno_datos.md,
-- que dejó las políticas explícitamente fuera de alcance — ver su §2). Referencia
-- para el patrón: la tabla obras ya tiene 4 políticas (SELECT/INSERT/UPDATE/DELETE)
-- de dueño único, todas `id_admin_creador = auth.uid()`. Ese patrón no sirve tal
-- cual acá porque estas 4 tablas tienen múltiples roles por obra, no un dueño único.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Nota de estado (2026-08-18): aplicado en producción por el usuario, confirmado
-- en el dashboard de Supabase (Database → Policies) sobre las 4 tablas. Etapa 3
-- queda completa de punta a punta a nivel de datos + control de acceso en base;
-- falta solo conectar UserContext/obra_members a las pantallas (ver CLAUDE.md).

-- =====================================================================
-- Funciones helper
-- =====================================================================
--
-- SECURITY DEFINER: corren con privilegios del dueño de la función (postgres),
-- que por defecto ignora RLS sobre las tablas que posee. Sin esto, una política
-- de obra_members que consulta obra_members para verificar membresía dispararía
-- su propia RLS en bucle. `set search_path = public` fija la ruta de esquema
-- (hardening estándar en funciones SECURITY DEFINER, evita search_path hijacking).

create or replace function is_obra_member(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from obra_members
    where obra_id = p_obra_id and usuario_id = auth.uid() and activo
  );
$$;

create or replace function tiene_rol_en_obra(p_obra_id uuid, p_rol text)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from obra_members
    where obra_id = p_obra_id and usuario_id = auth.uid() and activo and rol = p_rol
      and (
        p_rol <> 'invitado_apoderado'
        or (delegacion_inicio is null and delegacion_fin is null)
        or now() between delegacion_inicio and delegacion_fin
      )
  );
$$;

-- admin_maestro/profesional/cliente_principal aprueban sin tope; invitado_apoderado
-- solo dentro de su delegación vigente y su tope_monto_aprobacion (§4 del diseño:
-- puede_aprobar_adicionales reusa el mismo tope que certificados).
create or replace function puede_aprobar_monto(p_obra_id uuid, p_monto numeric)
returns boolean language sql security definer set search_path = public stable as $$
  select
    tiene_rol_en_obra(p_obra_id, 'admin_maestro')
    or tiene_rol_en_obra(p_obra_id, 'profesional')
    or tiene_rol_en_obra(p_obra_id, 'cliente_principal')
    or exists (
      select 1 from obra_members
      where obra_id = p_obra_id and usuario_id = auth.uid() and activo
        and rol = 'invitado_apoderado' and puede_aprobar_adicionales
        and (tope_monto_aprobacion is null or p_monto <= tope_monto_aprobacion)
        and ((delegacion_inicio is null and delegacion_fin is null)
             or now() between delegacion_inicio and delegacion_fin)
    );
$$;

grant execute on function is_obra_member(uuid) to authenticated;
grant execute on function tiene_rol_en_obra(uuid, text) to authenticated;
grant execute on function puede_aprobar_monto(uuid, numeric) to authenticated;

-- =====================================================================
-- obra_members
-- =====================================================================

alter table obra_members enable row level security;

-- SELECT: abierto a cualquier miembro activo de la obra (mismo patrón que las
-- otras 3 tablas). Decisión revisada: no restringir a admin_maestro/profesional/
-- cliente_principal como se había propuesto primero, porque la cadena de
-- aprobación de adicionales (puede_aprobar_monto, arriba) necesita que cualquier
-- rol pueda resolver quién más participa de la obra, no solo la caja blanca.
--
-- Limitación conocida (no resuelta acá, ver nota general al final del archivo):
-- esta política no oculta columnas de monto (tope_monto_aprobacion) de roles
-- como Constructor que deberían estar en "vista operativa sin montos" — RLS es
-- por fila, no por columna. Queda pendiente de resolver en capa de app.
create policy obra_members_select on obra_members for select
using (is_obra_member(obra_id));

-- INSERT: bootstrap (el creador de la obra se autoasigna admin_maestro),
-- o admin_maestro invitando, o alguien con puede_invitar_terceros=true.
create policy obra_members_insert on obra_members for insert with check (
  (usuario_id = auth.uid()
    and exists (select 1 from obras o where o.id = obra_id and o.id_admin_creador = auth.uid()))
  or tiene_rol_en_obra(obra_id, 'admin_maestro')
  or exists (
    select 1 from obra_members m
    where m.obra_id = obra_members.obra_id and m.usuario_id = auth.uid()
      and m.activo and m.puede_invitar_terceros
  )
);

-- UPDATE: admin_maestro gestiona todo; cliente_principal solo puede tocar filas
-- de invitado_apoderado (es quien configura la delegación de firma, §6 del diseño).
create policy obra_members_update on obra_members for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or (tiene_rol_en_obra(obra_id, 'cliente_principal') and rol = 'invitado_apoderado')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or (tiene_rol_en_obra(obra_id, 'cliente_principal') and rol = 'invitado_apoderado')
);

-- Sin política DELETE: nadie borra filas. "Revocar sin borrar" (activo=false)
-- es el mecanismo documentado, no el delete físico.

-- =====================================================================
-- modificaciones_obra
-- =====================================================================

alter table modificaciones_obra enable row level security;

create policy modificaciones_obra_select on modificaciones_obra for select
using (is_obra_member(obra_id));

-- INSERT: quien solicita se solicita a sí mismo.
--
-- Limitación conocida, aceptada para esta versión: el diseño doc (§4) distingue
-- solicitado_por ("quien detectó", puede ser el Constructor) de subido_por
-- ("quien tiene Dirección Técnica y lo eleva formalmente") como roles
-- potencialmente distintos. Esta política los colapsa al mismo auth.uid() en el
-- INSERT porque el schema actual no tiene un estado intermedio (tipo
-- 'pendiente_elevacion') para modelar el traspaso en dos tiempos. Si ese flujo en
-- dos pasos se vuelve necesario, hace falta una migración de schema que agregue
-- ese estado antes de poder separar ambos campos en la política.
--
-- El caso "autogestión total" (misma persona = cliente_principal + profesional +
-- constructor) puede insertar directo en 'aprobado', autoaprobándose sin fricción
-- (§4/§6.6 del diseño) — el registro se genera igual, para no perder trazabilidad.
create policy modificaciones_obra_insert on modificaciones_obra for insert with check (
  is_obra_member(obra_id) and solicitado_por = auth.uid() and subido_por = auth.uid()
  and (
    estado = 'pendiente'
    or (
      estado = 'aprobado' and aprobado_por = auth.uid()
      and tiene_rol_en_obra(obra_id, 'cliente_principal')
      and tiene_rol_en_obra(obra_id, 'profesional')
      and tiene_rol_en_obra(obra_id, 'constructor')
    )
  )
);

-- UPDATE: transiciones de estado. Quien puede aprobar (según monto/rol) puede
-- mover a aprobado/rechazado/devuelto; el subido_por puede editar y volver a
-- 'pendiente' un registro que estaba 'devuelto' (corrección, §6.5 del diseño).
create policy modificaciones_obra_update on modificaciones_obra for update using (
  is_obra_member(obra_id)
  and (puede_aprobar_monto(obra_id, monto_total) or (estado = 'devuelto' and subido_por = auth.uid()))
) with check (
  puede_aprobar_monto(obra_id, monto_total) or subido_por = auth.uid()
);

-- Sin política DELETE: el historial de transiciones vive en audit_log, la fila
-- de modificaciones_obra no se destruye.

-- =====================================================================
-- audit_log
-- =====================================================================

alter table audit_log enable row level security;

-- SELECT: cada uno ve las entradas de sus propias acciones, más el rol con
-- autoridad de supervisión (admin_maestro/profesional/cliente_principal) ve
-- todo el log de esa obra. Constructor/veedor/apoderado sin delegación no
-- navegan el log completo, solo lo que hicieron ellos mismos.
create policy audit_log_select on audit_log for select using (
  usuario_id = auth.uid()
  or (obra_id is not null and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'cliente_principal')
  ))
);

-- INSERT: cualquiera puede registrar una acción propia (no puede firmar la
-- acción de otro usuario_id).
create policy audit_log_insert on audit_log for insert with check (
  usuario_id = auth.uid() and (obra_id is null or is_obra_member(obra_id))
);

-- Sin UPDATE ni DELETE para nadie (ni siquiera admin_maestro): "Audit Log
-- inalterable" es requisito explícito de CLAUDE.md/blindaje legal.

-- =====================================================================
-- libro_entradas
-- =====================================================================

alter table libro_entradas enable row level security;

-- SELECT: abierto a cualquier miembro activo, sin distinción por libro. Coincide
-- con que invitado_veedor es lectura pasiva total en toda la app — no hay razón
-- para que lea Libro de Obra pero no Órdenes de Servicio/Notas de Pedido.
create policy libro_entradas_select on libro_entradas for select
using (is_obra_member(obra_id));

-- INSERT: rama por libro según la matriz de escritura del diseño (§5/§6.7).
-- invitado_veedor nunca aparece en ninguna rama -> queda excluido de escribir,
-- incluso como hija, sin necesidad de chequeo aparte.
create policy libro_entradas_insert on libro_entradas for insert with check (
  autor_usuario_id = auth.uid()
  and tiene_rol_en_obra(obra_id, autor_rol)
  and case libro
    when 'obra' then
      autor_rol in ('admin_maestro','profesional','constructor','cliente_principal','invitado_apoderado')
    when 'orden_servicio' then
      (entrada_padre_id is null and autor_rol = 'profesional')
      or (entrada_padre_id is not null and autor_rol = 'constructor')
    when 'nota_pedido' then
      (entrada_padre_id is null and autor_rol = 'constructor')
      or (entrada_padre_id is not null and autor_rol in ('profesional','cliente_principal'))
    else false
  end
);

-- Sin UPDATE ni DELETE: bitácora de tipo legal, append-only (coherente con
-- "no reemplaza al Libro de Obra rubricado" del diseño §5).

-- =====================================================================
-- Limitación general conocida, aceptada para esta versión (decisión revisada
-- con el consultor del usuario, no resuelta en este archivo):
--
-- RLS controla qué FILAS se pueden leer/escribir, no qué COLUMNAS. Filas de
-- modificaciones_obra u obra_members visibles para un rol como Constructor
-- ("vista operativa, sin montos") siguen trayendo columnas de monto completas
-- (monto_total, tope_monto_aprobacion, etc.) — no hay redacción por columna acá.
-- Ocultar esos valores en pantalla queda a cargo de la capa de app, con los
-- getters que ya tiene UserContext (puedeVerMontosYAPU, esVistaOperativa,
-- puedeAprobarCertificados). Si en algún momento hace falta que el dato ni
-- siquiera viaje al cliente (no solo que la UI lo oculte), ahí sí va a hacer
-- falta una vista SQL con un subconjunto de columnas por rol.
-- =====================================================================
