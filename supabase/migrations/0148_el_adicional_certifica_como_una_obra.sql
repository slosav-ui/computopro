-- 0148 -- El adicional certifica como una obra: certificados de verdad, no un porcentaje suelto
--
-- Pedido de Seba (2026-09-14), con su PDF real en la mano:
--
--   *"Que el adicional certifique partida por partida, con su propio número de certificado y sus
--   retenciones, igual que la obra. El camino chico me deja a mitad de camino y hay que rehacerlo
--   igual."*
--
-- `CERTIFICADO 1 ADICIONAL.pdf` tiene número, fecha, porcentaje por partida, fondo de reparo del 5%
-- y neto a pagar. La app guardaba de todo eso **un solo número**: el porcentaje del adicional entero.
--
-- ================== ESTO REVIERTE UNA DECISIÓN, Y CONVIENE SABER POR QUÉ ==================
--
-- `docs/adicionales_quitas_demasias_diagnostico.md` §14 cerró lo contrario: *"un porcentaje y un
-- monto certificado por adicional aprobado, **sin ciclo de vida propio**"*, con el argumento de que
-- *"construir un segundo circuito de certificación reducido para adicionales sería duplicar lo que
-- ya existe"*. La ambigüedad A de §14.2 recomendó "solo registro".
--
-- **El argumento era bueno y sigue siendo bueno: duplicar el circuito sería un error.** Lo que
-- cambió es la evidencia -- el PDF real, que en ese momento no estaba sobre la mesa -- y lo que
-- mostró es que el adicional **no necesita un circuito reducido: necesita el mismo**.
--
-- Y acá está el punto que vuelve esta migración chica: **no hay nada que duplicar.** Un adicional
-- presupuestado ya ES una obra (`obras`, con `obra_madre_id`, desde la `0113`). Tiene sus partidas,
-- sus miembros, su `anticipo_pct` y su `fondo_reparo_pct`, y `certificados` ya cuelga de `obra_id`
-- con numeración propia por obra. **La maquinaria de certificación ya funciona sobre una obra hija
-- tal como está.** Lo único que faltaba era dejarla usar y que la madre se entere.
--
-- O sea que esto no construye un segundo circuito: **borra el segundo circuito** (el porcentaje
-- suelto) y deja el primero.
--
-- ================== QUÉ CAMBIA, EN UNA LÍNEA ==================
--
-- `modificaciones_obra.porcentaje_avance` y `monto_certificado` dejan de ser un dato que alguien
-- escribe y pasan a ser **el resumen derivado de los certificados de la obra hija**.
--
-- Nadie los vuelve a tipear: se recalculan solos cada vez que un certificado de esa hija cambia de
-- estado. La lista de adicionales y la tarjeta del dashboard siguen leyendo las mismas dos columnas
-- y no se enteran del cambio.
--
-- ================== ANTES DE APLICAR: MIRÁ QUÉ SE VA A RECALCULAR ==================
--
-- El Paso 4 recalcula todos los adicionales aprobados. Un adicional que tenga avance cargado con la
-- función vieja y **ningún certificado en su hija va a volver a cero**, porque ese avance no está
-- respaldado por ningún certificado. Correr esto ANTES para ver a cuáles les pasa:
--
--   select m.id, m.descripcion, m.porcentaje_avance, m.monto_certificado,
--          (select count(*) from certificados c
--            where c.obra_id = m.obra_hija_id and c.estado not in ('borrador','anulado')) as certificados
--   from modificaciones_obra m
--   where m.tipo = 'adicional' and m.estado = 'aprobado' and m.porcentaje_avance > 0
--   order by 5, 3 desc;
--
-- Las filas con `certificados = 0` son las que pierden el número. En este proyecto la única es el
-- adicional de Galpón Mix, que se vuelve a cargar con el script de seed -- por eso se recalcula sin
-- más. Si apareciera alguna otra, pará y avisá antes de aplicar.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de la `0147`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- el resumen del adicional, derivado de sus certificados
-- =====================================================================
--
-- Las dos cuentas usan funciones que ya existen y que ya rigen para la obra madre, a propósito: el
-- adicional tiene que medirse igual que la obra, no parecido.
--
--   * el porcentaje es el **avance ponderado por monto** (`calcular_avance_ponderado_obra`, 0052) --
--     el mismo que muestra la obra. Ponderado y no promedio simple: certificar el 100% de una
--     partida de $100 en un adicional de $3.657 no es "el 25% del adicional".
--   * el monto es la **suma de lo certificado por sus certificados vivos**. Se usa `monto_pactado`
--     (lo firmado) con `monto` de respaldo para los certificados anteriores a la `0105`, que no
--     tienen pactado.
--
-- `security definer`: la llaman triggers que corren con la identidad de quien tocó el certificado,
-- y esa persona puede no tener permiso de UPDATE sobre la fila del adicional (desde la `0116`
-- prácticamente nadie lo tiene).

create or replace function recalcular_avance_adicional(p_obra_hija_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mod_id uuid;
  v_estado text;
  v_pct numeric;
  v_monto numeric;
begin
  select id, estado into v_mod_id, v_estado
  from modificaciones_obra
  where obra_hija_id = p_obra_hija_id;

  -- No es la hija de ningún adicional (o es una obra normal): nada que hacer. Silencioso, no error
  -- -- el trigger corre sobre TODOS los certificados y la enorme mayoría son de obras madre.
  if v_mod_id is null then
    return;
  end if;

  -- El check `modificaciones_obra_avance_solo_aprobado_check` (0120) solo admite avance distinto de
  -- cero en un adicional aprobado. Un certificado sobre la hija de un adicional que todavía no se
  -- aprobó (o que se rechazó) no puede mover el resumen: se deja en cero y listo.
  if v_estado <> 'aprobado' then
    update modificaciones_obra
    set porcentaje_avance = 0, monto_certificado = 0
    where id = v_mod_id and (porcentaje_avance <> 0 or monto_certificado <> 0);
    return;
  end if;

  v_pct := coalesce(calcular_avance_ponderado_obra(p_obra_hija_id), 0);

  select coalesce(sum(coalesce(c.monto_pactado, c.monto, 0)), 0)
    into v_monto
  from certificados c
  where c.obra_id = p_obra_hija_id
    and c.estado not in ('borrador', 'anulado');

  update modificaciones_obra
  set porcentaje_avance = least(greatest(v_pct, 0), 100),
      monto_certificado = greatest(v_monto, 0)
  where id = v_mod_id;
end;
$$;

revoke execute on function recalcular_avance_adicional(uuid) from public, anon, authenticated;

comment on function recalcular_avance_adicional(uuid) is
  'Recalcula el resumen de un adicional (porcentaje_avance, monto_certificado) a partir de los '
  'certificados de su obra hija. Nadie la llama a mano: la disparan los triggers de 0148.';


-- =====================================================================
-- Paso 2 -- que se recalcule solo
-- =====================================================================
--
-- Sobre `certificados` y no sobre `certificado_subitems_avance`: mientras el certificado es borrador
-- no cuenta para nada (ni el ponderado ni el monto lo miran), así que cargar avance no tiene que
-- disparar nada. Lo que mueve el resumen es que el certificado **cambie de estado**: emitirse o
-- anularse.
--
-- `after` y no `before`: el resumen se calcula sobre la fila ya escrita.
--
-- ================== POR QUÉ NO DISPARA EN DELETE (corregido antes de aplicar) ==================
--
-- La primera versión también disparaba en `delete`, y eso rompía el borrado de una obra. La cadena:
-- borrar una obra madre hace cascade sobre la hija, que hace cascade sobre sus certificados, que
-- dispararía este trigger -- y el recálculo termina en `calcular_monto_congelado_ajustado`, que
-- **exige membresía**. Desde el SQL Editor no hay sesión, así que el borrado abortaba.
--
-- No es hipotético: es exactamente lo que le pasa al script de carga de la obra real, que arranca
-- borrando la corrida anterior.
--
-- Y no hace falta: **un certificado no se borra nunca en uso normal** -- anular es un estado, no un
-- delete, y la tabla no tiene política de DELETE. Los únicos deletes son cascades de borrar la obra
-- entera, y ahí el resumen no importa porque la fila que lo guarda se está yendo también.

create or replace function certificados_recalcular_adicional()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform recalcular_avance_adicional(new.obra_id);

  -- Un UPDATE que mueve el certificado de una obra a otra no pasa hoy por ninguna función, pero si
  -- pasara, la obra vieja también tiene que recalcularse -- si no queda con el monto de un
  -- certificado que ya no es suyo.
  if tg_op = 'UPDATE' and old.obra_id is distinct from new.obra_id then
    perform recalcular_avance_adicional(old.obra_id);
  end if;

  return new;
end;
$$;

drop trigger if exists certificados_recalcular_adicional on certificados;
create trigger certificados_recalcular_adicional
after insert or update on certificados
for each row execute function certificados_recalcular_adicional();


-- =====================================================================
-- Paso 3 -- se cierra el circuito viejo
-- =====================================================================
--
-- `certificar_avance_adicional` (0120) escribía el porcentaje a mano. Con el Paso 2 esa escritura
-- duraría hasta el próximo certificado y después se pisaría sola, que es la peor forma de romper:
-- funciona, y un rato después el número cambia sin que nadie lo haya tocado.
--
-- **No se borra la función, se la hace fallar con un mensaje que dice qué hacer.** Un `drop` le
-- daría a quien la llame un "function does not exist", que no explica nada; así el error es una
-- instrucción. Mismo criterio con el que la `0125` dejó dicho quién emite en vez de solo negar.

create or replace function certificar_avance_adicional(
  p_modificacion_id uuid,
  p_porcentaje numeric
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'el avance de un adicional ya no se carga como un porcentaje suelto: desde la 0148 el adicional emite sus propios certificados, con su número, sus partidas y sus retenciones. Abrí el adicional y usá Gestión de Obra, igual que en la obra.';
end;
$$;

comment on function certificar_avance_adicional(uuid, numeric) is
  'OBSOLETA desde 0148. Falla a propósito con un mensaje que indica el camino nuevo, en vez de '
  'borrarse: un "function does not exist" no le dice nada a quien la llame.';


-- =====================================================================
-- Paso 4 -- poner al día lo que ya está cargado
-- =====================================================================
--
-- Recalcula todos los adicionales aprobados con la regla nueva. Leé la advertencia de la cabecera
-- antes de correr esto: los que tengan avance viejo sin certificados detrás vuelven a cero, porque
-- ese avance no está respaldado por ningún documento.
--
-- ================== POR QUÉ ESTE BLOQUE SE HACE PASAR POR UN USUARIO ==================
--
-- La primera versión de este paso fallaba al aplicarse con "No sos miembro de esta obra", y el
-- motivo es una trampa que este proyecto ya conoce: el recálculo termina llamando a
-- `calcular_monto_congelado_ajustado` (`0105`), que exige `is_obra_member`. **En el SQL Editor no
-- hay sesión, así que `auth.uid()` es null y nadie es miembro de nada.** La `0106` ya lo había
-- dejado escrito: *"un no-miembro (o una sesión sin auth.uid(), como el SQL Editor..."*.
--
-- De las dos salidas posibles, esta es la que NO debilita nada:
--
--   * **Saltear el chequeo** obligaría a que el recálculo no use `calcular_avance_ponderado_obra`
--     sino una copia de su cuenta sin el gate. Eso pone la definición de "avance ponderado" en dos
--     lugares, que es exactamente lo que la `0147` evitó a propósito dos días atrás. Y el chequeo no
--     sobra: en uso normal el recálculo lo dispara una persona emitiendo un certificado, y ahí
--     tiene que regir.
--   * **Prestarle la identidad de un miembro real de cada obra hija**, que es lo que hace este
--     bloque. El mismo truco de claims que ya usan las verificaciones de la `0130` y el script de
--     carga de la obra real.
--
-- La identidad se toma de `obra_members` de cada hija -- no se inventa ni se pide: si la hija no
-- tiene ningún miembro activo, se saltea y lo dice, porque sin miembros tampoco hay nadie que pueda
-- ver ese adicional en la app.

do $$
declare
  v_hija uuid;
  v_usuario uuid;
  v_antes numeric;
  v_despues numeric;
  v_tocados int := 0;
  v_saltados int := 0;
  v_a_cero int := 0;
begin
  for v_hija in
    select obra_hija_id from modificaciones_obra
    where tipo = 'adicional' and obra_hija_id is not null
  loop
    select usuario_id into v_usuario
    from obra_members
    where obra_id = v_hija and activo
    limit 1;

    if v_usuario is null then
      v_saltados := v_saltados + 1;
      raise notice 'Adicional de la obra hija % salteado: no tiene ningún miembro activo.', v_hija;
      continue;
    end if;

    select porcentaje_avance into v_antes
    from modificaciones_obra where obra_hija_id = v_hija;

    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', v_usuario, 'role', 'authenticated')::text,
      true
    );

    perform recalcular_avance_adicional(v_hija);

    select porcentaje_avance into v_despues
    from modificaciones_obra where obra_hija_id = v_hija;

    v_tocados := v_tocados + 1;
    if coalesce(v_antes, 0) > 0 and coalesce(v_despues, 0) = 0 then
      v_a_cero := v_a_cero + 1;
      raise notice 'Adicional de la obra hija %: % %% -> 0 (no tenía certificados detrás).',
        v_hija, v_antes;
    end if;
  end loop;

  -- Devolver la sesión a como estaba. `true` en set_config ya la ata a la transacción, así que esto
  -- es por prolijidad: que el resto del script no herede una identidad prestada.
  perform set_config('request.jwt.claims', '', true);

  raise notice 'Recalculados %, salteados %, vueltos a cero %.', v_tocados, v_saltados, v_a_cero;
end $$;


-- =====================================================================
-- Lo que NO hace esta migración, y hay que saberlo
-- =====================================================================
--
-- 1) **No toca la emisión.** `emitir_certificado` ya funciona sobre una obra hija sin cambios: la
--    autoridad sale de `puede_emitir_certificado` sobre esa obra, y `crear_adicional_presupuestado`
--    (0113) le copia los miembros de la madre. La numeración ya es por obra, así que el primero de
--    un adicional es el Nº 1 -- exactamente como dice el PDF.
--
-- 2) **No toca las retenciones.** La hija tiene su propio `anticipo_pct` y `fondo_reparo_pct`. En el
--    PDF del adicional son 0% y 5%, distintos de los de la obra (20% y 5%), y eso ya se puede
--    representar. Ojo: hoy `crear_adicional_presupuestado` NO copia esos dos valores de la madre,
--    así que la hija nace con los que tenga el default -- conviene poder editarlos desde la pantalla
--    de configuración del adicional (va en la lista de archivos).
--
-- 3) **No arregla la base de cálculo del fondo de reparo.** Sigue en pie el hallazgo 1 de
--    `docs/certificado_base_de_calculo_hallazgos.md`: la app retiene sobre el bruto y el papel sobre
--    el neto de anticipo. En un adicional con anticipo 0% las dos cuentas coinciden, así que el
--    certificado del adicional de Galpón Mix va a dar exacto igual -- pero no porque esté resuelto.
--
-- 4) **No decide qué pasa con el cobro.** Un certificado de adicional recorre los mismos estados
--    (emitido → leído → pagado → cerrado) porque son los de la tabla, y eso responde de hecho la
--    ambigüedad A de §14.2 por la Opción 1 ampliada: se cobra por el mismo circuito, aparte del
--    certificado de la obra. Si eso no es lo que pasa en la realidad, decilo antes de usarlo.


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) La función vieja avisa en vez de escribir:
--    select certificar_avance_adicional('<un adicional aprobado>', 10);
--    -- tiene que fallar con el mensaje que indica el camino nuevo. Leerlo entero.
--
-- 2) El resumen quedó derivado. Con el adicional de Galpón Mix ya recargado por el script:
--    select m.porcentaje_avance, m.monto_certificado,
--           (select count(*) from certificados c where c.obra_id = m.obra_hija_id) as certificados
--    from modificaciones_obra m where m.tipo = 'adicional' and m.estado = 'aprobado';
--
-- 3) *** EL CIRCUITO COMPLETO, que es el punto de la migración. Sobre la obra hija del adicional:
--    crear un certificado, cargarle avance por partida, emitirlo. Después:
--    - el certificado tiene número 1, su fondo de reparo y su neto a pagar;
--    - `modificaciones_obra` del adicional se actualizó SOLA, sin llamar a nada;
--    - el porcentaje es el ponderado por monto, no el promedio simple de las partidas.
--
-- 4) Que anular lo revierta: anular ese certificado y ver el resumen volver a cero.
--
-- 5) Que un certificado de una obra normal no rompa nada: emitir uno en la obra madre y confirmar
--    que ningún adicional cambió (el trigger corre igual, pero `recalcular_avance_adicional` sale
--    en la primera línea porque esa obra no es hija de nadie).
