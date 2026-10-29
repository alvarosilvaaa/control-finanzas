/**
 * API de "Control finanzas" para la app de iPhone.
 *
 * La app habla con este script mediante peticiones POST con un cuerpo JSON:
 *   { "token": "...", "action": "datos" | "nuevoGasto" | "editarGasto" | "borrarGasto" | "nuevaRegla"
 *                               | "nuevoIngreso" | "borrarIngreso" | "fijarPresupuesto" | "fijarLimite"
 *                               | "guardarDeseo" | "borrarDeseo" | "guardarReparto", ... }
 *
 * Los gastos nuevos se envían a través del mismo formulario de Google que usa
 * el atajo, así que entran por el mismo camino (Respuestas de formulario 1 → Gastos).
 */

// El token no se escribe aquí para que no acabe en GitHub. Se guarda en Apps Script:
// ⚙️ Configuración del proyecto → Propiedades del script → propiedad "TOKEN".
// Debe coincidir con el token que pongas en Ajustes dentro de la app.
const TOKEN = PropertiesService.getScriptProperties().getProperty('TOKEN');

const HOJA_GASTOS = 'Gastos';
const HOJA_RESPUESTAS = 'Respuestas de formulario 1';
const HOJA_REGLAS = 'Reglas';
const HOJA_PRESUPUESTO = 'Presupuesto';
const HOJA_INGRESOS = 'Ingresos extra';
const HOJA_FRECUENTES = 'Frecuentes';
const HOJA_LIMITES = 'Límites';
const HOJA_DESEOS = 'Wishlist';
const HOJA_REPARTOS = 'Repartos';
const CABECERAS_REPARTOS = ['Gasto', 'Concepto', 'Pagado', 'Partes', 'Te deben', 'Saldado'];
const CABECERAS_DESEOS = ['Id', 'Nombre', 'Precio', 'Enlace', 'Nota', 'Prioridad', 'Comprado', 'Añadido'];
const CABECERAS_FRECUENTES = ['Id', 'Concepto', 'Importe', 'Categoría', 'Método', 'Frecuencia', 'Día'];
const PRESUPUESTO_POR_DEFECTO = 450;

function doGet() {
  return json({ ok: true, mensaje: 'API de Control finanzas activa' });
}

function doPost(e) {
  let req;
  try {
    req = JSON.parse(e.postData.contents);
  } catch (_) {
    return json({ ok: false, error: 'Petición no válida' });
  }
  if (!TOKEN) return json({ ok: false, error: 'Falta la propiedad TOKEN en la configuración del script' });
  if (req.token !== TOKEN) return json({ ok: false, error: 'Token incorrecto' });

  try {
    switch (req.action) {
      case 'datos':
        return json(Object.assign({ ok: true }, leerDatos()));
      case 'nuevoGasto':
        conBloqueo(() => nuevoGasto(req));
        return json({ ok: true });
      case 'editarGasto':
        conBloqueo(() => editarGasto(req));
        return json({ ok: true });
      case 'borrarGasto':
        conBloqueo(() => borrarGasto(req));
        return json({ ok: true });
      case 'nuevaRegla':
        conBloqueo(() => nuevaRegla(req.palabra, req.categoria));
        return json({ ok: true });
      case 'nuevoIngreso':
        conBloqueo(() => nuevoIngreso(req));
        return json({ ok: true });
      case 'borrarIngreso':
        conBloqueo(() => borrarIngreso(req));
        return json({ ok: true });
      case 'guardarFrecuente':
        conBloqueo(() => guardarFrecuente(req));
        return json({ ok: true });
      case 'borrarFrecuente':
        conBloqueo(() => borrarFrecuente(req));
        return json({ ok: true });
      case 'fijarPresupuesto':
        conBloqueo(() => fijarPresupuesto(req));
        return json({ ok: true });
      case 'fijarLimite':
        conBloqueo(() => fijarLimite(req));
        return json({ ok: true });
      case 'guardarDeseo':
        conBloqueo(() => guardarDeseo(req));
        return json({ ok: true });
      case 'borrarDeseo':
        conBloqueo(() => borrarDeseo(req));
        return json({ ok: true });
      case 'guardarReparto':
        conBloqueo(() => guardarReparto(req));
        return json({ ok: true });
      default:
        return json({ ok: false, error: 'Acción desconocida: ' + req.action });
    }
  } catch (err) {
    return json({ ok: false, error: String((err && err.message) || err) });
  }
}

// ---------- Lectura ----------

function leerDatos() {
  const ss = SpreadsheetApp.getActive();

  const hojaGastos = ss.getSheetByName(HOJA_GASTOS);
  const gastos = [];
  const filas = hojaGastos.getLastRow() > 1
    ? hojaGastos.getRange(2, 1, hojaGastos.getLastRow() - 1, 5).getValues()
    : [];
  filas.forEach((f, i) => {
    const fecha = aFecha(f[0]);
    const importe = aNumero(f[1]);
    if (!fecha || importe === null) return;
    gastos.push({
      id: 'g' + (i + 2) + '-' + fecha.getTime(),
      fila: i + 2,
      fecha: fecha.toISOString(),
      importe: importe,
      concepto: String(f[2]).trim(),
      categoria: String(f[3]).trim() || 'Sin clasificar',
      metodo: String(f[4]).trim(),
    });
  });

  const reglas = [];
  const hojaReglas = ss.getSheetByName(HOJA_REGLAS);
  if (hojaReglas && hojaReglas.getLastRow() > 1) {
    hojaReglas.getRange(2, 1, hojaReglas.getLastRow() - 1, 2).getValues().forEach(f => {
      if (String(f[0]).trim()) reglas.push({ palabra: String(f[0]).trim(), categoria: String(f[1]).trim() });
    });
  }

  const presupuestos = [];
  const hojaPres = hojaPresupuesto();
  if (hojaPres.getLastRow() > 1) {
    hojaPres.getRange(2, 1, hojaPres.getLastRow() - 1, 3).getValues().forEach(f => {
      const mes = aMes(f[0]);
      const base = aNumero(f[1]);
      const inicio = claveTexto(f[2]);
      if (!mes || base === null) return;
      const p = { mes: mes, base: base };
      if (inicio) p.inicio = inicio;
      presupuestos.push(p);
    });
  }

  const ingresos = [];
  const hojaIng = obtenerHoja(HOJA_INGRESOS, ['Fecha', 'Importe', 'Concepto', 'Id']);
  if (hojaIng.getLastRow() > 1) {
    hojaIng.getRange(2, 1, hojaIng.getLastRow() - 1, 4).getValues().forEach(f => {
      const fecha = aFecha(f[0]);
      const importe = aNumero(f[1]);
      if (!fecha || importe === null) return;
      ingresos.push({ id: String(f[3]), fecha: fecha.toISOString(), importe: importe, concepto: String(f[2]).trim() });
    });
  }

  return {
    gastos: gastos,
    reglas: reglas,
    presupuestos: presupuestos,
    ingresos: ingresos,
    frecuentes: leerFrecuentes(),
    limites: leerLimites(),
    deseos: leerDeseos(),
    repartos: leerRepartos(),
    presupuestoPorDefecto: PRESUPUESTO_POR_DEFECTO,
  };
}

// ---------- Escritura ----------

function nuevoGasto(req) {
  const importe = aNumero(req.importe);
  if (importe === null || importe <= 0) throw new Error('Importe no válido');
  const concepto = String(req.concepto || '').trim();
  if (!concepto) throw new Error('Falta el concepto');
  const categoria = String(req.categoria || 'Sin clasificar').trim();
  const metodo = String(req.metodo || '').trim();
  const importeTexto = String(importe).replace('.', ',');
  // Fecha elegida en la app (opcional). Si no llega, se usa la del envío.
  const fecha = req.fecha ? new Date(req.fecha) : null;
  if (fecha && isNaN(fecha)) throw new Error('Fecha no válida');

  const ss = SpreadsheetApp.getActive();
  const urlFormulario = ss.getFormUrl();

  if (!urlFormulario) {
    // Sin formulario vinculado: se escribe directamente en la hoja de respuestas.
    ss.getSheetByName(HOJA_RESPUESTAS).appendRow([fecha || new Date(), importeTexto, concepto, categoria, metodo]);
    return;
  }

  const form = FormApp.openByUrl(urlFormulario);
  const respuesta = form.createResponse();
  form.getItems().forEach(item => {
    const titulo = normalizar(item.getTitle());
    let valor = null;
    if (titulo.includes('importe')) valor = importeTexto;
    else if (titulo.includes('comercio') || titulo.includes('concepto')) valor = concepto;
    else if (titulo.includes('categor')) valor = categoria;
    else if (titulo.includes('tarjeta') || titulo.includes('metodo')) valor = metodo;
    if (valor !== null && valor !== '') respuesta.withItemResponse(crearRespuesta(item, valor));
  });
  const enviada = respuesta.submit();

  // El formulario siempre pone la hora del envío. Si se eligió otra fecha,
  // se espera a que la respuesta aparezca en la hoja y se le cambia la marca temporal.
  if (fecha && Math.abs(fecha.getTime() - enviada.getTimestamp().getTime()) > 60 * 1000) {
    const req2 = { fechaOriginal: enviada.getTimestamp().toISOString() };
    for (let intento = 0; intento < 20; intento++) {
      SpreadsheetApp.flush();
      try {
        const { hoja, fila, col } = localizarRespuesta(req2);
        hoja.getRange(fila, col.fecha).setValue(fecha);
        return;
      } catch (_) {
        Utilities.sleep(500);
      }
    }
    throw new Error('El gasto se ha guardado con la fecha de hoy: no se pudo cambiar la fecha. Edítalo para corregirla.');
  }
}

/**
 * Los gastos se editan en "Respuestas de formulario 1", que es de donde los lee la hoja Gastos.
 * La fila se localiza por su marca temporal original (con la fila como pista si hay empates).
 */
function editarGasto(req) {
  const { hoja, fila, col } = localizarRespuesta(req);
  const importe = aNumero(req.importe);
  if (importe === null || importe <= 0) throw new Error('Importe no válido');
  const concepto = String(req.concepto || '').trim();
  if (!concepto) throw new Error('Falta el concepto');
  const categoria = String(req.categoria || 'Sin clasificar').trim();

  if (req.fecha) {
    const fecha = new Date(req.fecha);
    if (isNaN(fecha)) throw new Error('Fecha no válida');
    hoja.getRange(fila, col.fecha).setValue(fecha);
  }
  hoja.getRange(fila, col.importe).setValue(String(importe).replace('.', ','));
  hoja.getRange(fila, col.concepto).setValue(concepto);
  hoja.getRange(fila, col.categoria).setValue(categoria);
  if (col.metodo && req.metodo != null) hoja.getRange(fila, col.metodo).setValue(String(req.metodo).trim());

  if (req.regla && categoria !== 'Sin clasificar') nuevaRegla(req.regla, categoria);
}

function borrarGasto(req) {
  const { hoja, fila } = localizarRespuesta(req);
  hoja.deleteRow(fila);
}

/** Añade (o actualiza) una regla en la hoja Reglas para que ese comercio se clasifique solo. */
function nuevaRegla(palabra, categoria) {
  palabra = String(palabra || '').trim();
  categoria = String(categoria || '').trim();
  if (!palabra || !categoria) throw new Error('Faltan la palabra o la categoría de la regla');
  // Las reglas se usan como expresión regular en la fórmula de Gastos: se escapan los símbolos.
  const patron = palabra.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const hoja = obtenerHoja(HOJA_REGLAS, ['Palabra', 'Categoría']);
  if (hoja.getLastRow() > 1) {
    const filas = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
    for (let i = 0; i < filas.length; i++) {
      if (String(filas[i][0]).trim().toLowerCase() === patron.toLowerCase()) {
        hoja.getRange(i + 2, 2).setValue(categoria);
        return;
      }
    }
  }
  hoja.appendRow([patron, categoria]);
}

function localizarRespuesta(req) {
  const hoja = SpreadsheetApp.getActive().getSheetByName(HOJA_RESPUESTAS);
  const cabeceras = hoja.getRange(1, 1, 1, hoja.getLastColumn()).getValues()[0].map(normalizar);
  const buscar = (...claves) => {
    const i = cabeceras.findIndex(c => claves.some(k => c.includes(k)));
    return i >= 0 ? i + 1 : null;
  };
  const col = {
    fecha: buscar('marcatemporal', 'fecha') || 1,
    importe: buscar('importe') || 2,
    concepto: buscar('comercio', 'concepto') || 3,
    categoria: buscar('categor') || 4,
    metodo: buscar('tarjeta', 'metodo'),
  };

  const objetivo = new Date(req.fechaOriginal).getTime();
  if (isNaN(objetivo)) throw new Error('Falta la fecha original del gasto');
  const n = hoja.getLastRow() - 1;
  if (n < 1) throw new Error('No se ha encontrado el gasto');
  const fechas = hoja.getRange(2, col.fecha, n, 1).getValues();
  const coincidencias = [];
  fechas.forEach((f, i) => {
    const d = aFecha(f[0]);
    // Margen de 1 s por si el redondeo de milisegundos difiere entre la app y la hoja.
    if (d && Math.abs(d.getTime() - objetivo) < 1000) coincidencias.push(i + 2);
  });
  if (!coincidencias.length) throw new Error('No se ha encontrado el gasto. Recarga e inténtalo de nuevo.');
  const fila = coincidencias.includes(Number(req.fila)) ? Number(req.fila) : coincidencias[0];
  return { hoja, fila, col };
}

function nuevoIngreso(req) {
  const importe = aNumero(req.importe);
  if (importe === null || importe <= 0) throw new Error('Importe no válido');
  const fecha = req.fecha ? new Date(req.fecha) : new Date();
  const hoja = obtenerHoja(HOJA_INGRESOS, ['Fecha', 'Importe', 'Concepto', 'Id']);
  hoja.appendRow([fecha, importe, String(req.concepto || 'Ingreso extra').trim(), Utilities.getUuid()]);
}

function borrarIngreso(req) {
  const hoja = obtenerHoja(HOJA_INGRESOS, ['Fecha', 'Importe', 'Concepto', 'Id']);
  if (hoja.getLastRow() < 2) return;
  const ids = hoja.getRange(2, 4, hoja.getLastRow() - 1, 1).getValues();
  for (let i = ids.length - 1; i >= 0; i--) {
    if (String(ids[i][0]) === String(req.id)) hoja.deleteRow(i + 2);
  }
}

// ---------- Gastos frecuentes ----------
// Frecuencia: "mensual" (Día = día del mes, 1-31), "semanal" (Día = 1 lunes … 7 domingo) o "ninguna".

function leerFrecuentes() {
  const hoja = obtenerHoja(HOJA_FRECUENTES, CABECERAS_FRECUENTES);
  if (hoja.getLastRow() < 2) return [];
  return hoja.getRange(2, 1, hoja.getLastRow() - 1, 7).getValues()
    .filter(f => String(f[0]).trim() && String(f[1]).trim())
    .map(f => ({
      id: String(f[0]),
      concepto: String(f[1]).trim(),
      importe: aNumero(f[2]),
      categoria: String(f[3]).trim() || 'Sin clasificar',
      metodo: String(f[4]).trim(),
      frecuencia: ['mensual', 'semanal'].includes(String(f[5]).trim()) ? String(f[5]).trim() : 'ninguna',
      dia: Number(f[6]) || null,
    }));
}

function guardarFrecuente(req) {
  const concepto = String(req.concepto || '').trim();
  if (!concepto) throw new Error('Falta el concepto');
  const importe = req.importe == null || req.importe === '' ? '' : aNumero(req.importe);
  const fila = [
    req.id ? String(req.id) : Utilities.getUuid(),
    concepto,
    importe === null ? '' : importe,
    String(req.categoria || 'Sin clasificar').trim(),
    String(req.metodo || '').trim(),
    ['mensual', 'semanal'].includes(req.frecuencia) ? req.frecuencia : 'ninguna',
    Number(req.dia) || '',
  ];
  const hoja = obtenerHoja(HOJA_FRECUENTES, CABECERAS_FRECUENTES);
  if (req.id && hoja.getLastRow() > 1) {
    const ids = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
    for (let i = 0; i < ids.length; i++) {
      if (String(ids[i][0]) === String(req.id)) {
        hoja.getRange(i + 2, 1, 1, fila.length).setValues([fila]);
        return;
      }
    }
  }
  hoja.appendRow(fila);
}

function borrarFrecuente(req) {
  const hoja = obtenerHoja(HOJA_FRECUENTES, CABECERAS_FRECUENTES);
  if (hoja.getLastRow() < 2) return;
  const ids = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
  for (let i = ids.length - 1; i >= 0; i--) {
    if (String(ids[i][0]) === String(req.id)) hoja.deleteRow(i + 2);
  }
}

/**
 * Fija la base de un mes. Con "inicio" (fecha ISO) también fija cuándo empieza ese periodo,
 * para cerrar el mes anterior antes del día 1; "inicio" vacío vuelve a empezar el día 1.
 */
function fijarPresupuesto(req) {
  const mes = aMes(req.mes);
  const base = aNumero(req.base);
  if (!mes) throw new Error('Mes no válido');
  if (base === null || base < 0) throw new Error('Presupuesto no válido');
  const cambiaInicio = req.inicio !== undefined && req.inicio !== null;
  const inicio = cambiaInicio ? String(req.inicio).trim() : '';
  if (inicio && isNaN(new Date(inicio))) throw new Error('Fecha de inicio no válida');
  const hoja = hojaPresupuesto();
  if (hoja.getLastRow() > 1) {
    const meses = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
    for (let i = 0; i < meses.length; i++) {
      if (aMes(meses[i][0]) === mes) {
        hoja.getRange(i + 2, 2).setValue(base);
        if (cambiaInicio) hoja.getRange(i + 2, 3).setValue(inicio);
        return;
      }
    }
  }
  hoja.appendRow([mes, base, inicio]);
}

/** Hoja Presupuesto con la columna "Inicio" (texto, para que Sheets no convierta las fechas). */
function hojaPresupuesto() {
  const hoja = obtenerHoja(HOJA_PRESUPUESTO, ['Mes', 'Base', 'Inicio']);
  if (!String(hoja.getRange(1, 3).getValue()).trim()) {
    hoja.getRange(1, 3).setValue('Inicio').setFontWeight('bold');
  }
  hoja.getRange('C:C').setNumberFormat('@');
  return hoja;
}

// ---------- Límites por categoría ----------

function leerLimites() {
  const hoja = obtenerHoja(HOJA_LIMITES, ['Categoría', 'Límite mensual']);
  if (hoja.getLastRow() < 2) return [];
  return hoja.getRange(2, 1, hoja.getLastRow() - 1, 2).getValues()
    .map(f => ({ categoria: String(f[0]).trim(), limite: aNumero(f[1]) }))
    .filter(l => l.categoria && l.limite !== null && l.limite > 0);
}

/** Fija el límite mensual de una categoría. Sin límite (o 0) lo quita. */
function fijarLimite(req) {
  const categoria = String(req.categoria || '').trim();
  if (!categoria) throw new Error('Falta la categoría');
  const limite = req.limite == null ? null : aNumero(req.limite);
  if (limite !== null && limite < 0) throw new Error('Límite no válido');
  const hoja = obtenerHoja(HOJA_LIMITES, ['Categoría', 'Límite mensual']);
  if (hoja.getLastRow() > 1) {
    const nombres = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
    for (let i = nombres.length - 1; i >= 0; i--) {
      if (String(nombres[i][0]).trim().toLowerCase() === categoria.toLowerCase()) {
        if (limite === null || limite === 0) hoja.deleteRow(i + 2);
        else hoja.getRange(i + 2, 1, 1, 2).setValues([[categoria, limite]]);
        return;
      }
    }
  }
  if (limite !== null && limite > 0) hoja.appendRow([categoria, limite]);
}

// ---------- Wishlist ----------
// Prioridad: "alta", "media" o "baja". Comprado: "sí" o vacío.

function leerDeseos() {
  const hoja = obtenerHoja(HOJA_DESEOS, CABECERAS_DESEOS);
  if (hoja.getLastRow() < 2) return [];
  return hoja.getRange(2, 1, hoja.getLastRow() - 1, CABECERAS_DESEOS.length).getValues()
    .filter(f => String(f[0]).trim() && String(f[1]).trim())
    .map(f => {
      const añadido = aFecha(f[7]);
      return {
        id: String(f[0]),
        nombre: String(f[1]).trim(),
        precio: aNumero(f[2]),
        enlace: String(f[3]).trim(),
        nota: String(f[4]).trim(),
        prioridad: ['alta', 'baja'].includes(String(f[5]).trim()) ? String(f[5]).trim() : 'media',
        comprado: ['sí', 'si', 'true', 'x'].includes(String(f[6]).trim().toLowerCase()),
        añadido: (añadido || new Date(0)).toISOString(),
      };
    });
}

function guardarDeseo(req) {
  const nombre = String(req.nombre || '').trim();
  if (!nombre) throw new Error('Falta el nombre');
  const precio = req.precio == null || req.precio === '' ? null : aNumero(req.precio);
  const fila = [
    req.id ? String(req.id) : Utilities.getUuid(),
    nombre,
    precio === null ? '' : precio,
    String(req.enlace || '').trim(),
    String(req.nota || '').trim(),
    ['alta', 'baja'].includes(req.prioridad) ? req.prioridad : 'media',
    req.comprado ? 'sí' : '',
    fechaISO(req.añadido) || new Date(),
  ];
  const hoja = obtenerHoja(HOJA_DESEOS, CABECERAS_DESEOS);
  if (req.id && hoja.getLastRow() > 1) {
    const ids = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
    for (let i = 0; i < ids.length; i++) {
      if (String(ids[i][0]) === String(req.id)) {
        hoja.getRange(i + 2, 1, 1, fila.length).setValues([fila]);
        return;
      }
    }
  }
  hoja.appendRow(fila);
}

/** Fecha en formato ISO (la que envía la app), o null. */
function fechaISO(v) {
  if (!v) return null;
  const d = new Date(v);
  return isNaN(d) ? null : d;
}

function borrarDeseo(req) {
  const hoja = obtenerHoja(HOJA_DESEOS, CABECERAS_DESEOS);
  if (hoja.getLastRow() < 2) return;
  const ids = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
  for (let i = ids.length - 1; i >= 0; i--) {
    if (String(ids[i][0]) === String(req.id)) hoja.deleteRow(i + 2);
  }
}

// ---------- Repartos del piso ----------
// Cada fila dice qué parte de un gasto es compartida. "Gasto" es la marca temporal del gasto en
// formato ISO (lo que lo identifica) y "Partes" una lista JSON: [{"importe": 5, "personas": 2}, …].

function claveTexto(v) {
  if (v instanceof Date && !isNaN(v)) return v.toISOString();
  return String(v || '').trim();
}

function leerRepartos() {
  const hoja = obtenerHoja(HOJA_REPARTOS, CABECERAS_REPARTOS);
  if (hoja.getLastRow() < 2) return [];
  return hoja.getRange(2, 1, hoja.getLastRow() - 1, CABECERAS_REPARTOS.length).getValues()
    .map(f => {
      let partes = [];
      try { partes = JSON.parse(String(f[3] || '[]')); } catch (e) { partes = []; }
      partes = (Array.isArray(partes) ? partes : [])
        .map(p => ({ importe: aNumero(p.importe), personas: Math.max(1, Math.round(Number(p.personas) || 0)) }))
        .filter(p => p.importe !== null && p.importe > 0 && p.personas >= 2);
      return { clave: claveTexto(f[0]), partes: partes, saldado: String(f[5]).trim().toLowerCase() === 'sí' };
    })
    .filter(r => r.clave && r.partes.length);
}

/** Crea, cambia o (sin partes) quita el reparto de un gasto. claveAnterior sirve si cambió la fecha del gasto. */
function guardarReparto(req) {
  const clave = String(req.clave || '').trim();
  if (!clave) throw new Error('Falta el gasto');
  const buscar = String(req.claveAnterior || clave).trim();
  const partes = (Array.isArray(req.partes) ? req.partes : [])
    .map(p => ({ importe: aNumero(p.importe), personas: Math.round(Number(p.personas) || 0) }))
    .filter(p => p.importe !== null && p.importe > 0 && p.personas >= 2);
  const teDeben = partes.reduce((s, p) => s + p.importe - p.importe / p.personas, 0);
  const fila = [clave, String(req.concepto || '').trim(), aNumero(req.pagado) || '', JSON.stringify(partes),
                Math.round(teDeben * 100) / 100, req.saldado ? 'sí' : ''];

  const hoja = obtenerHoja(HOJA_REPARTOS, CABECERAS_REPARTOS);
  if (hoja.getLastRow() > 1) {
    const claves = hoja.getRange(2, 1, hoja.getLastRow() - 1, 1).getValues();
    for (let i = claves.length - 1; i >= 0; i--) {
      if (claveTexto(claves[i][0]) === buscar || claveTexto(claves[i][0]) === clave) {
        if (!partes.length) { hoja.deleteRow(i + 2); continue; }
        hoja.getRange(i + 2, 1, 1, fila.length).setValues([fila]);
        return;
      }
    }
  }
  if (partes.length) hoja.appendRow(fila);
}

// ---------- Utilidades ----------

function crearRespuesta(item, valor) {
  switch (item.getType()) {
    case FormApp.ItemType.TEXT: return item.asTextItem().createResponse(valor);
    case FormApp.ItemType.PARAGRAPH_TEXT: return item.asParagraphTextItem().createResponse(valor);
    case FormApp.ItemType.MULTIPLE_CHOICE: return item.asMultipleChoiceItem().createResponse(valor);
    case FormApp.ItemType.LIST: return item.asListItem().createResponse(valor);
    case FormApp.ItemType.CHECKBOX: return item.asCheckboxItem().createResponse([valor]);
    default: throw new Error('Tipo de pregunta no soportado en el formulario: ' + item.getTitle());
  }
}

function obtenerHoja(nombre, cabeceras) {
  const ss = SpreadsheetApp.getActive();
  let hoja = ss.getSheetByName(nombre);
  if (!hoja) {
    hoja = ss.insertSheet(nombre);
    hoja.getRange(1, 1, 1, cabeceras.length).setValues([cabeceras]).setFontWeight('bold');
    hoja.setFrozenRows(1);
    if (nombre === HOJA_PRESUPUESTO || nombre === HOJA_REPARTOS) hoja.getRange('A:A').setNumberFormat('@');
  }
  return hoja;
}

function conBloqueo(fn) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try { fn(); } finally { lock.releaseLock(); }
}

function aFecha(v) {
  if (v instanceof Date && !isNaN(v)) return v;
  if (typeof v !== 'string' || !v.trim()) return null;
  // Formato "d/m/aaaa h:mm:ss"
  const m = v.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
  if (!m) return null;
  return new Date(+m[3], +m[2] - 1, +m[1], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0));
}

function aNumero(v) {
  if (typeof v === 'number') return isNaN(v) ? null : v;
  let s = String(v == null ? '' : v).replace(/[€\s]/g, '');
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
  if (!s) return null;
  const n = Number(s);
  return isNaN(n) ? null : n;
}

function aMes(v) {
  if (v instanceof Date && !isNaN(v)) {
    return Utilities.formatDate(v, SpreadsheetApp.getActive().getSpreadsheetTimeZone(), 'yyyy-MM');
  }
  const m = String(v || '').trim().match(/^(\d{4})-(\d{1,2})$/);
  return m ? m[1] + '-' + ('0' + m[2]).slice(-2) : null;
}

function normalizar(s) {
  return String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, '');
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
