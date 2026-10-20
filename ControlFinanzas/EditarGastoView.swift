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

    init(gasto: Gasto) {
        original = gasto
        _importeTexto = State(initialValue: PresupuestoView.texto(gasto.importe))
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
        g.importe = importe ?? original.importe
        g.concepto = concepto.trimmingCharacters(in: .whitespaces)
        g.fecha = fecha
        g.categoria = categoriaFinal
        g.metodo = metodoHoja
        return g
    }

    private var hayCambios: Bool {
        let e = editado
        return e.importe != original.importe || e.concepto != original.concepto.trimmingCharacters(in: .whitespaces)
            || abs(e.fecha.timeIntervalSince(original.fecha)) >= 1 || e.categoria != original.categoria
            || e.metodo != original.metodo || reglaAplicable
    }

    private var reglaAplicable: Bool {
        crearRegla && !categoria.isEmpty && !palabraRegla.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var valido: Bool { importe != nil && !concepto.trimmingCharacters(in: .whitespaces).isEmpty }

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
            .navigationTitle("Editar gasto")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { Task { await guardar() } }.bold().disabled(!valido || !hayCambios)
                    }
                }
            }
            .confirmationDialog("¿Borrar este gasto?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
                Button("Borrar \(Formato.eur(original.importe)) · \(original.concepto)", role: .destructive) {
                    Task { await borrar() }
                }
            } message: {
                Text("Se eliminará también de tu hoja de Google.")
            }
            .interactiveDismissDisabled(guardando)
            .alertaError($error)
            .hojaMac(alto: 640)
            .ocultarTecladoFacil()
        }
    }

    private func guardar() async {
        await ejecutar {
            try await almacen.editarGasto(original, por: editado,
                                          regla: reglaAplicable ? palabraRegla.trimmingCharacters(in: .whitespaces) : nil)
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
