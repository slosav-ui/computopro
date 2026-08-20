-- Modelos de Certificación (A: Avance Medido / B: Hitos de Precio Cerrado), paso 1: columna
-- obras.modelo_certificacion + función de cambio con historial vía audit_log.
-- Ver docs/modelos_certificacion_diseno_datos.md, secciones 3 y 8, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Reusa audit_log en vez de crear una tabla de historial dedicada (§3 del diseño): audit_log
-- ya está pensada para esto (ver comentario en audit_log_entry.dart, "a futuro para
-- certificados, delegaciones de firma y moderación de contenido"). entidad_id queda en null
-- para entidad='obra' — obra_id ya identifica la obra sin necesidad de repetirlo (§7.5).

alter table obras
  add column modelo_certificacion text not null default 'avance_medido'
    check (modelo_certificacion in ('avance_medido', 'hitos_precio_cerrado'));

-- =====================================================================
-- cambiar_modelo_certificacion: update + insert en audit_log atómicos
-- =====================================================================
--
-- SECURITY INVOKER (no DEFINER): a diferencia de is_obra_member/tiene_rol_en_obra en
-- 0004_rls_etapa3.sql (que necesitan DEFINER para no disparar su propia RLS en bucle), acá
-- no hay ese problema — el update sobre obras y el insert en audit_log corren como el usuario
-- que llama, así que las políticas RLS existentes de ambas tablas se aplican tal cual.
--
-- Motivo obligatorio (validado acá, no solo en la capa de app): sin texto, la función falla
-- antes de tocar ninguna fila.
--
-- Concurrencia: el update lleva "and modelo_certificacion = v_modelo_anterior" (optimistic
-- concurrency) — si la obra ya cambió de modelo entre el select y el update, o si la política
-- UPDATE de obras no deja pasar a este usuario, la función distingue ambos casos y lanza una
-- excepción en vez de insertar un audit_log de un cambio que en realidad no ocurrió.
--
-- Limitación conocida (no resuelta acá, ver docs/modelos_certificacion_diseno_datos.md §8):
-- quién puede ejecutar esto con éxito depende pura y exclusivamente de la política UPDATE que
-- ya tiene la tabla obras (patrón de dueño único, id_admin_creador = auth.uid() según
-- CLAUDE.md/0004_rls_etapa3.sql) — no de si el usuario tiene rol admin_maestro en
-- obra_members. Si el Administrador de una obra fue reasignado después de creada (CLAUDE.md
-- documenta esto como posible: "el creador queda por defecto como Administrador, con opción
-- de cambiarlo después"), id_admin_creador podría no coincidir con quien hoy tiene el rol
-- admin_maestro. Alinear esto requeriría tocar la política UPDATE de obras (tabla anterior a
-- Etapa 3, sin migración propia en este repo) — fuera de alcance de este paso.

create or replace function cambiar_modelo_certificacion(
  p_obra_id uuid,
  p_modelo_nuevo text,
  p_motivo text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_modelo_anterior text;
begin
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo obligatorio para cambiar el modelo de certificación';
  end if;

  if p_modelo_nuevo not in ('avance_medido', 'hitos_precio_cerrado') then
    raise exception 'modelo_certificacion inválido: %', p_modelo_nuevo;
  end if;

  select modelo_certificacion into v_modelo_anterior from obras where id = p_obra_id;

  if v_modelo_anterior is null then
    raise exception 'obra % no encontrada', p_obra_id;
  end if;

  if v_modelo_anterior = p_modelo_nuevo then
    raise exception 'la obra ya está en el modelo %', p_modelo_nuevo;
  end if;

  update obras
  set modelo_certificacion = p_modelo_nuevo
  where id = p_obra_id and modelo_certificacion = v_modelo_anterior;

  if not found then
    raise exception 'sin permiso para modificar el modelo de certificación de esta obra, o la obra cambió de modelo concurrentemente';
  end if;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'cambiar_modelo_certificacion', 'obra', null,
    jsonb_build_object(
      'modelo_anterior', v_modelo_anterior,
      'modelo_nuevo', p_modelo_nuevo,
      'motivo', p_motivo
    )
  );
end;
$$;

grant execute on function cambiar_modelo_certificacion(uuid, text, text) to authenticated;
