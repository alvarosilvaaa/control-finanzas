import SwiftUI

struct EditarGastoView: View {
    typealias Metodo = NuevoMovimientoView.Metodo

    let original: Gasto

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss

    @State private var importeTexto: String
    @State private var concepto: String
    @State private var fecha: Date
    @State private var categoria: String
    @State private var metodo: Metodo
    @State private var crearRegla: Bool
    @State private var palabraRegla: String
    @State private var guardando = false
    @State private var confirmandoBorrado = false
    @State private var error: String?
    // Reparto con el piso
    @State private var partes: [Reparto.Parte] = []
    @State private var saldado = false
    @State private var repartoOriginal: Reparto?
    @State private var cargado = false
    @State private var nuevaParteTexto = ""
    @State private var nuevaPersonas = 2

    init(gasto: Gasto) {
        original = gasto
        _importeTexto = State(initialValue: PresupuestoView.texto(gasto.total))
        _concepto = State(initialValue: gasto.concepto.trimmingCharacters(in: .whitespaces))
        _fecha = State(initialValue: gasto.fecha)
        _categoria = State(initialValue: gasto.categoria == "Sin clasificar" ? "" : gasto.categoria)
        _metodo = State(initialValue: Metodo(rawValue: Formato.metodo(gasto.metodo)) ?? .tarjeta)
        // Si llegó sin clasificar, lo normal es querer que ese comercio se clasifique solo a partir de ahora.
        _crearRegla = State(initialValue: gasto.categoria == "Sin clasificar")
        _palabraRegla = State(initialValue: gasto.concepto.trimmingCharacters(in: .whitespaces))
    }

    private var importe: Double? {
        Double(importeTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            .flatMap { $0 > 0 ? ($0 * 100).rounded() / 100 : nil }
    }

    private var categoriaFinal: String { categoria.isEmpty ? "Sin clasificar" : categoria }

    /// Conserva el nombre exacto de la tarjeta si no se ha cambiado el método.
    private var metodoHoja: String {
        Formato.metodo(original.metodo) == metodo.rawValue ? original.metodo : metodo.valorHoja
    }

    private var editado: Gasto {
        var g = original
        g.importe = importe ?? original.total
        g.pagado = nil
        g.concepto = concepto.trimmingCharacters(in: .whitespaces)
        g.fecha = fecha
        g.categoria = categoriaFinal
        g.metodo = metodoHoja
        return g
    }

    private var hayCambios: Bool {
        let e = editado
        return e.importe != original.total || e.concepto != original.concepto.trimmingCharacters(in: .whitespaces)
            || abs(e.fecha.timeIntervalSince(original.fecha)) >= 1 || e.categoria != original.categoria
            || e.metodo != original.metodo || reglaAplicable
    }

    private var repartoCambiado: Bool {
        partes != (repartoOriginal?.partes ?? []) || (!partes.isEmpty && saldado != (repartoOriginal?.saldado ?? false))
    }

    private var totalTicket: Double { importe ?? original.total }
    private var totalCompartido: Double { partes.reduce(0) { $0 + $1.importe } }
    private var repartoValido: Bool { totalCompartido <= totalTicket + 0.001 }

    private var nuevaParte: Double? {
        Double(nuevaParteTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            .flatMap { $0 > 0 ? Reparto.redondear($0) : nil }
    }

    private var reglaAplicable: Bool {
        crearRegla && !categoria.isEmpty && !palabraRegla.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var valido: Bool {
        importe != nil && !concepto.trimmingCharacters(in: .whitespaces).isEmpty && repartoValido
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0,00", text: $importeTexto, prompt: Text("0,00"))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .tecladoDecimal()
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("€").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                seccionReparto

                Section {
                    TextField("Concepto", text: $concepto, prompt: Text("Concepto"))
                        .labelsHidden()
                    DatePicker("Fecha", selection: $fecha, in: ...Date())
                }

                Section("Categoría") {
                    SelectorCategoria(categoria: $categoria)
                }

                Section {
                    Toggle("Clasificar siempre así", isOn: $crearRegla)
                    if crearRegla {
                        TextField("Texto que debe contener", text: $palabraRegla, prompt: Text("Texto que debe contener"))
                            .labelsHidden()
                            .sinMayusculas()
                    }
                } footer: {
                    if crearRegla {
                        Text(categoria.isEmpty
                             ? "Elige una categoría para crear la regla."
                             : "Los gastos cuyo comercio contenga «\(palabraRegla)» irán a \(categoria), también los pagos automáticos que lleguen a partir de ahora. Puedes acortar el texto (p. ej. «peluqueria»).")
                    } else {
                        Text("Crea una regla en la hoja para que este comercio se clasifique solo.")
                    }
                }

                Section("Método de pago") {
                    Picker("Método", selection: $metodo) {
                        ForEach(Metodo.allCases) { m in Label(m.rawValue, systemImage: m.icono).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Borrar gasto", role: .destructive) { confirmandoBorrado = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .estiloLimpio()
            .navigationTitle("Editar gasto")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { Task { await guardar() } }.bold().disabled(!valido || !(hayCambios || repartoCambiado))
                    }
                }
            }
            .confirmationDialog("¿Borrar este gasto?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
                Button("Borrar \(Formato.eur(original.total)) · \(original.concepto)", role: .destructive) {
                    Task { await borrar() }
                }
            } message: {
                Text("Se eliminará también de tu hoja de Google.")
            }
            .interactiveDismissDisabled(guardando)
            .alertaError($error)
            .hojaMac(alto: 640)
            .ocultarTecladoFacil()
            .onAppear {
                guard !cargado else { return }
                cargado = true
                repartoOriginal = almacen.reparto(de: original)
                partes = repartoOriginal?.partes ?? []
                saldado = repartoOriginal?.saldado ?? false
            }
        }
    }

    // MARK: - Reparto con el piso

    private var seccionReparto: some View {
        Section {
            ForEach(Array(partes.enumerated()), id: \.offset) { i, p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Formato.eur(p.importe)) entre \(p.personas)").font(.body.weight(.semibold))
                        Text("Tu parte \(Formato.eur(p.tuParte)) · te deben \(Formato.eur(p.teDeben))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { partes.remove(at: i) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar")
                }
            }

            HStack(spacing: 10) {
                TextField("Importe", text: $nuevaParteTexto, prompt: Text("Importe compartido"))
                    .labelsHidden()
                    .tecladoDecimal()
                Stepper("entre \(nuevaPersonas)", value: $nuevaPersonas, in: 2...12)
                    .fixedSize()
                Button {
                    guard let importe = nuevaParte else { return }
                    partes.append(Reparto.Parte(importe: importe, personas: nuevaPersonas))
                    nuevaParteTexto = ""
                    Sistema.ocultarTeclado()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tema.tinta)
                .disabled(nuevaParte == nil)
                .accessibilityLabel("Añadir parte")
            }

            if !partes.isEmpty {
                let r = Reparto(clave: "", partes: partes, saldado: saldado)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tu parte").font(.caption).foregroundStyle(.secondary)
                        Text(Formato.eur(r.tuParte(de: totalTicket))).font(.title3.bold()).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Te deben").font(.caption).foregroundStyle(.secondary)
                        Text(Formato.eur(r.teDeben)).font(.title3.bold()).monospacedDigit()
                    }
                }
                .padding(.vertical, 2)
                Toggle("Ya me lo han pagado", isOn: $saldado)
            }
        } header: {
            Text("Repartir con el piso")
        } footer: {
            if !repartoValido {
                Text("Lo compartido (\(Formato.eur(totalCompartido))) no puede superar el total del ticket.")
                    .foregroundStyle(Tema.alerta)
            } else if partes.isEmpty {
                Text("Indica qué parte del ticket es compartida y entre cuántas personas (contándote a ti). En el presupuesto solo contará tu parte.")
            } else {
                Text("En el presupuesto y en los resúmenes solo cuenta tu parte. El ticket sigue siendo de \(Formato.eur(totalTicket)).")
            }
        }
    }

    private func guardar() async {
        let nuevo = editado
        await ejecutar {
            if hayCambios {
                try await almacen.editarGasto(original, por: nuevo,
                                              regla: reglaAplicable ? palabraRegla.trimmingCharacters(in: .whitespaces) : nil)
            }
            // Si cambió la fecha, el reparto se mueve con el gasto (se identifica por su fecha).
            let fechaCambiada = nuevo.clave != original.clave
            if repartoCambiado || (fechaCambiada && repartoOriginal != nil) {
                try await almacen.guardarReparto(nuevo, claveAnterior: original.clave, partes: partes, saldado: saldado)
            }
        }
    }

    private func borrar() async {
        await ejecutar { try await almacen.borrarGasto(original) }
    }

    private func ejecutar(_ accion: () async throws -> Void) async {
        guardando = true
        error = nil
        defer { guardando = false }
        do {
            try await accion()
            Sistema.vibrarExito()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
