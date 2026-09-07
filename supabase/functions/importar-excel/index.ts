// NO SE USA EN ESTA RONDA -- sin desplegar, sin invocar desde ningún lugar de lib/. Queda como
// referencia para la segunda tanda (PDF/foto). El parser de Excel real de esta ronda corre en el
// cliente: lib/services/excel_parser.dart, misma lógica de encabezados reescrita en Dart puro.
//
// Por qué se sacó de esta ronda (decisión explícita, ver CLAUDE.md "Importador de Excel/PDF" y el
// comentario de cabecera de excel_parser.dart): los dos motivos que originalmente justificaban un
// servidor (Capa 1 §3.B -- proteger una clave de IA, aplicar el límite de documentos/mes de Free)
// no aplican a esta ronda: sin IA no hay clave que proteger, y el importador pasó a ser PRO
// exclusivo, así que no hay límite que hacer cumplir del lado servidor. Sin esos dos motivos,
// sumar una segunda pieza de infraestructura (Deno, deploy manual aparte, logs propios) para un
// proyecto sostenido por una sola persona no se justificaba -- "consistencia con el diseño viejo"
// no alcanza. Por qué SÍ va a hacer falta en la segunda tanda: ahí el modelo de visión que lee
// PDF/foto necesita una clave real que proteger y tiene un costo por documento que controlar --
// los dos motivos originales, ahora sí vigentes. Este archivo queda escrito y sin tocar como punto
// de partida para ese momento, no para desplegarse ahora.
//
// Importador de Excel — Capa 2 (docs/importador_capa2_diseno_datos.md §7, §1): Edge Function del
// lado servidor, nunca desde el cliente Flutter (mismo motivo de Capa 1 §3.B: no exponer nada
// sensible en el binario y poder aplicar cualquier límite de costo desde el servidor). Esta ronda
// no usa IA -- parser determinístico por encabezado de columna reconocido, "mucho más simple que
// la IA lee el archivo" que anticipaba Capa 1 (§7).
//
// Dos acciones sobre la misma importación, en dos llamadas separadas porque el usuario elige la(s)
// hoja(s) DESPUÉS de ver la lista y ANTES de que se lea el contenido (Capa 1, decisión D):
//   - "listar_hojas": abre el archivo ya subido a Storage, devuelve los nombres de hoja, no toca
//     ninguna tabla.
//   - "procesar": vuelve a abrir el archivo, recorre `importaciones.hojas_seleccionadas` (ya
//     guardadas por la app entre las dos llamadas), reconoce encabezados y vuelca las filas en
//     `importaciones_items`.
//
// El cliente Supabase de acá se arma reenviando el Authorization del usuario (no service_role) --
// las mismas políticas de RLS que ya rigen `importaciones`/`importaciones_items`/el bucket
// `importaciones` (0080) se aplican también acá, sin necesitar un chequeo de autoridad aparte en
// este archivo.
//
// Desplegar a mano: `supabase functions deploy importar-excel` (Supabase CLI). No ejecutado
// automáticamente por Claude Code: sin acceso a la cuenta de Supabase desde este entorno, mismo
// motivo por el que las migraciones tampoco se aplican solas.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
// ?target=deno: xlsx (SheetJS) resuelve mejor así en el runtime de Edge Functions -- sin el
// target, esm.sh a veces sirve un build pensado para navegador que falla al importar bajo Deno.
import * as XLSX from 'https://esm.sh/xlsx@0.18.5?target=deno';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Encabezados reconocidos, en minúscula y sin acentos (ver normalizar()) -- "sinónimos
// razonables" de Capa 2 §7. Ampliar esta lista es seguro y no rompe nada existente: una fila cuyo
// encabezado no matchea ningún sinónimo simplemente no se reconoce como esa columna.
// Comparados siempre vía normalizar() (ver más abajo), que ya saca acentos -- no hace falta
// escribir cada variante acentuada acá, "capitulo" alcanza para matchear "Capítulo" también.
const CAMPOS: Record<string, string[]> = {
  rubro: ['rubro', 'item', 'capitulo', 'rubro/item'],
  descripcion: ['descripcion', 'detalle', 'concepto', 'tarea', 'designacion'],
  unidad: ['unidad', 'un', 'u', 'ud', 'unidad de medida', 'u.medida'],
  cantidad: ['cantidad', 'cant', 'cant.', 'computo'],
  precio_unitario: ['precio unitario', 'precio unit', 'p.unit', 'p. unitario', 'preciounitario', 'p.u.', 'precio unit.'],
};

// Rango U+0300 a U+036F = "Combining Diacritical Marks" -- lo que normalize('NFD') separa de la
// letra base (á -> a + acento como carácter aparte). Escrito con \u en vez de los caracteres
// literales para no depender de que el archivo viaje siempre en UTF-8 intacto por git/editores.
function normalizar(valor: unknown): string {
  return String(valor ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase();
}

/// Una fila es "encabezado" si nombra al menos descripción + (cantidad o precio unitario) -- el
/// mínimo real para que una fila de datos siguiente sea una partida útil. Devuelve el índice de
/// columna de cada campo reconocido, o null si esta fila no alcanza ese mínimo.
function detectarEncabezados(fila: unknown[]): Record<string, number> | null {
  const mapa: Record<string, number> = {};
  fila.forEach((celda, indice) => {
    const texto = normalizar(celda);
    if (!texto) return;
    for (const [campo, sinonimos] of Object.entries(CAMPOS)) {
      if (campo in mapa) continue;
      if (sinonimos.some((s) => normalizar(s) === texto)) mapa[campo] = indice;
    }
  });
  if (mapa.descripcion === undefined) return null;
  if (mapa.cantidad === undefined && mapa.precio_unitario === undefined) return null;
  return mapa;
}

function aNumero(valor: unknown): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  if (typeof valor === 'number') return valor;
  const texto = String(valor).trim().replace(/\./g, '').replace(',', '.');
  const numero = Number(texto);
  return Number.isFinite(numero) ? numero : null;
}

function aTextoONull(valor: unknown): string | null {
  if (valor === null || valor === undefined) return null;
  const texto = String(valor).trim();
  return texto === '' ? null : texto;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  const jsonHeaders = { ...CORS_HEADERS, 'Content-Type': 'application/json' };
  const error = (mensaje: string, status = 400) =>
    new Response(JSON.stringify({ error: mensaje }), { status, headers: jsonHeaders });

  let body: { importacion_id?: string; accion?: string };
  try {
    body = await req.json();
  } catch {
    return error('Cuerpo de la solicitud inválido, se esperaba JSON.');
  }

  const { importacion_id, accion } = body;
  if (!importacion_id || !accion) return error('Faltan importacion_id/accion.');
  if (accion !== 'listar_hojas' && accion !== 'procesar') return error(`Acción desconocida: ${accion}.`);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } },
  );

  const { data: importacion, error: errImportacion } = await supabase
    .from('importaciones')
    .select('id, archivo_storage_path, hojas_seleccionadas, tipo_archivo')
    .eq('id', importacion_id)
    .single();

  if (errImportacion || !importacion) {
    // La RLS de 0080 filtra por membresía de obra -- "no encontrada" y "sin permiso" se ven igual
    // acá adentro, sin distinguirlas (mismo criterio fail-closed del resto del proyecto).
    return error('Importación no encontrada o sin permiso.', 404);
  }
  if (importacion.tipo_archivo !== 'excel') {
    return error('Esta función solo lee Excel en esta ronda (PDF/foto quedan para la segunda tanda).');
  }

  const { data: archivo, error: errArchivo } = await supabase.storage
    .from('importaciones')
    .download(importacion.archivo_storage_path);
  if (errArchivo || !archivo) {
    return error('No se pudo leer el archivo desde Storage.', 500);
  }

  const buffer = new Uint8Array(await archivo.arrayBuffer());
  const workbook = XLSX.read(buffer, { type: 'array' });

  if (accion === 'listar_hojas') {
    return new Response(JSON.stringify({ hojas: workbook.SheetNames }), { headers: jsonHeaders });
  }

  // accion === 'procesar'
  const hojas = (importacion.hojas_seleccionadas as string[] | null) ?? [];
  if (hojas.length === 0) return error('No hay hojas seleccionadas -- guardalas antes de procesar.');

  const filas: Record<string, unknown>[] = [];
  let orden = 0;

  for (const nombreHoja of hojas) {
    const hoja = workbook.Sheets[nombreHoja];
    if (!hoja) continue; // hoja elegida que ya no existe en el archivo -- se ignora, no se corta todo
    const matriz = XLSX.utils.sheet_to_json(hoja, { header: 1, defval: null, blankrows: false }) as unknown[][];

    let encabezados: Record<string, number> | null = null;
    for (const fila of matriz) {
      if (!encabezados) {
        encabezados = detectarEncabezados(fila);
        continue; // la propia fila de encabezado nunca se guarda como partida
      }
      const descripcion = aTextoONull(fila[encabezados.descripcion]);
      if (descripcion === null) continue; // fila vacía en la columna clave -- se salta, no se inventa nada

      orden += 1;
      filas.push({
        importacion_id,
        orden,
        rubro_texto: encabezados.rubro !== undefined ? aTextoONull(fila[encabezados.rubro]) : null,
        descripcion_texto: descripcion,
        unidad_texto: encabezados.unidad !== undefined ? aTextoONull(fila[encabezados.unidad]) : null,
        cantidad: encabezados.cantidad !== undefined ? aNumero(fila[encabezados.cantidad]) : null,
        precio_unitario:
          encabezados.precio_unitario !== undefined ? aNumero(fila[encabezados.precio_unitario]) : null,
        // Catch-all, mismo patrón que libro_entradas.adjuntos/audit_log.detalle (Capa 1 §2.1):
        // respaldo de la fila cruda para cuando el parser se equivocó y hay que revisar el original.
        datos_originales: { hoja: nombreHoja, fila_original: fila },
      });
    }
  }

  if (filas.length === 0) {
    return error('No se encontraron filas con encabezados reconocidos en las hojas elegidas.', 422);
  }

  const { error: errInsert } = await supabase.from('importaciones_items').insert(filas);
  if (errInsert) return error(errInsert.message, 500);

  return new Response(JSON.stringify({ insertadas: filas.length }), { headers: jsonHeaders });
});
