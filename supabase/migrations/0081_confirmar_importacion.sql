-- Importador — Capa 2 §5: FKs reservadas de importaciones_items (0080) hacia rubros/subitems, y la
-- función atómica confirmar_importacion(). Ver docs/importador_capa2_diseno_datos.md §5 para el
-- diseño completo.
--
-- Mismo motivo que ya llevó a emitir_certificado()/aprobar_ajuste_contrato() a una función atómica
-- en vez de una secuencia de llamadas desde Dart: una importación de 40 líneas es varias filas de
-- obra_subitems a la vez, y cortarse a mitad de camino (13 partidas creadas, 27 no) deja la obra en
-- un estado confuso, no un error prolijo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table importaciones_items
  add constraint importaciones_items_rubro_id_fkey foreign key (rubro_id) references rubros(id),
  add constraint importaciones_items_subitem_id_fkey foreign key (subitem_id) references subitems(id);

-- =====================================================================
-- confirmar_importacion
-- =====================================================================
--
-- Recorre los importaciones_items de la importación con rubro_id/subitem_id ya resueltos (§3 del
-- diseño: acción "elegir del catálogo" o "crear como propia" -- una fila descartada, o sin
-- resolver todavía, queda afuera sin más). Por cada uno, upsert en obra_subitems por
-- (obra_id, subitem_id): si ya existe una fila para ese subítem en esa obra, actualiza
-- cantidad/precio/es_aplicable; si no, la crea. Sin unique constraint formal en obra_subitems que
-- soporte un ON CONFLICT (0019 lo dejó así a propósito, un subítem puede repetirse por sector) --
-- se resuelve con un SELECT previo dentro de la misma función en vez de ON CONFLICT.
--
-- El precio importado es SIEMPRE manual (docs/importador_capa2_diseno_datos.md §4): se escribe en
-- precio_unitario_manual sin importar si el rubro usa APU, exactamente el caso que
-- subitems_screen.dart ya sabe priorizar desde el commit anterior a esta migración.
--
-- Todo o nada: si cualquier fila del lote falla (ej. un check constraint), la excepción aborta la
-- transacción completa de la función -- ninguna fila queda a mitad de camino. Recién si el lote
-- entero entra bien se marca importaciones.estado = 'confirmado'.

create or replace function confirmar_importacion(p_importacion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_item record;
  v_obra_subitem_id uuid;
begin
  select obra_id, estado into v_obra_id, v_estado
  from importaciones
  where id = p_importacion_id;

  if v_obra_id is null then
    raise exception 'importación % no encontrada', p_importacion_id;
  end if;

  if v_estado <> 'pendiente_revision' then
    raise exception 'importación % no está pendiente de revisión (estado actual: %)', p_importacion_id, v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro') or tiene_rol_en_obra(v_obra_id, 'profesional')) then
    raise exception 'sin autoridad para confirmar esta importación';
  end if;

  for v_item in
    select * from importaciones_items
    where importacion_id = p_importacion_id
      and rubro_id is not null
      and subitem_id is not null
  loop
    select id into v_obra_subitem_id
    from obra_subitems
    where obra_id = v_obra_id and subitem_id = v_item.subitem_id;

    if v_obra_subitem_id is not null then
      update obra_subitems
      set cantidad = coalesce(v_item.cantidad, 0),
          precio_unitario_manual = v_item.precio_unitario,
          es_aplicable = true,
          ultima_modificacion_usuario_id = auth.uid(),
          updated_at = now()
      where id = v_obra_subitem_id;
    else
      insert into obra_subitems (
        obra_id, rubro_id, subitem_id, cantidad, precio_unitario_manual,
        es_aplicable, agregado_por_usuario_id
      ) values (
        v_obra_id, v_item.rubro_id, v_item.subitem_id, coalesce(v_item.cantidad, 0),
        v_item.precio_unitario, true, auth.uid()
      );
    end if;
  end loop;

  update importaciones
  set estado = 'confirmado',
      confirmado_por_usuario_id = auth.uid(),
      confirmado_at = now()
  where id = p_importacion_id;
end;
$$;

grant execute on function confirmar_importacion(uuid) to authenticated;
