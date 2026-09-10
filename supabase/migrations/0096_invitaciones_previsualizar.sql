-- Invitaciones, ajuste sobre la Tanda 1 (feedback de Seba, 2026-09-10 al probar el circuito):
-- aceptar_invitacion() aplica el código al primer usuario que tenga sesión activa cuando se
-- guardó como pendiente, sin mostrar a quién se está sumando -- si el celular cambia de manos, o
-- el código se guarda y después entra otra cuenta, se suma a la persona equivocada sin avisar.
--
-- previsualizar_invitacion(codigo): de solo lectura, sin efecto -- muestra a qué obra y con qué
-- rol se está por sumar alguien, ANTES de canjear. La usan dos lugares del lado de Dart: la
-- pantalla de ingresar código (para explicar qué sigue con todas las letras antes de mandar a
-- registrarse) y el chequeo automático al iniciar sesión (para pedir confirmación en vez de
-- aplicar en silencio).
--
-- Mismo criterio que aceptar_invitacion para "no encontrado": código inexistente, vencido, o ya
-- usado devuelven cero filas -- no se distingue el motivo.
--
-- Sin auth.uid(): a propósito, es el único caso del proyecto que necesita funcionar ANTES de
-- iniciar sesión (quien pega el código puede no tener cuenta todavía) -- por eso el grant de acá
-- abajo incluye `anon`, no solo `authenticated` (primera vez que esto pasa en el proyecto).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
create or replace function previsualizar_invitacion(p_codigo text)
returns table(obra_nombre text, rol text)
language plpgsql security definer set search_path = public as $$
declare
  v_inv invitaciones%rowtype;
begin
  select * into v_inv
  from invitaciones i
  where i.codigo = upper(trim(p_codigo))
    and i.estado = 'pendiente'
    and i.expira_en > now();

  if not found then
    return;
  end if;

  return query
    select o.nombre, v_inv.rol
    from obras o
    where o.id = v_inv.obra_id;
end;
$$;

grant execute on function previsualizar_invitacion(text) to authenticated, anon;
