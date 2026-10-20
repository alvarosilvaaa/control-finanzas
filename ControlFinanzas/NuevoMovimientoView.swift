import SwiftUI

struct NuevoMovimientoView: View {
    enum Tipo: String, CaseIterable { case gasto = "Gasto", ingreso = "Ingreso extra" }

    enum Metodo: String, CaseIterable, Identifiable {
        case bizum = "Bizum", efectivo = "Efectivo", tarjeta = "Tarjeta"
        var id: String { rawValue }
        /// Valor que se guarda en la hoja, igual que los que ya existen.
        var valorHoja: String { self == .tarjeta ? "MASTERCARD BSCARD" : rawValue }
        var icono: String {
            switch self {
            case .bizum: "iphone.radiowaves.left.and.right"
            case .efectivo: "banknote.fill"
            case .tarjeta: "creditcard.fill"
            }
        }
    }

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss

    @State private var tipo = Tipo.gasto
    @State private var importeTexto = ""
    @State private var concepto = ""
    @State private var categoria = ""
    @State private var metodo = Metodo.bizum
    @State private var fechaIngreso = Date()
    @State private var guardando = false
    @State private var error: String?
    @FocusState private var campo: Campo?

    enum Campo { case importe, concepto }

    private var importe: Double? {
        let limpio = importeTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let v = Double(limpio), v > 0 else { return nil }
        return (v * 100).rounded() / 100
    }

    private var categoriaFinal: String {
        categoria.isEmpty ? "Sin clasificar" : categoria
    }

    private var valido: Bool {
        guard importe != nil else { return false }
        if tipo == .ingreso { return true }
        return !concepto.trimmingCharacters(in: .whitespaces).isEmpty && !categoriaFinal.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(Tipo.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0,00", text: $importeTexto)
                            .tecladoDecimal()
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .focused($campo, equals: .importe)
                        Text("€").font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if tipo == .gasto {
                    seccionGasto
                } else {
                    Section {
                        TextField("Concepto (p. ej. Propina)", text: $concepto)
                        DatePicker("Fecha", selection: $fechaIngreso, displayedComponents: .date)
                    } footer: {
                        Text("Se suma al presupuesto del mes de esa fecha.")
                    }
                }
            }
            .navigationTitle(tipo == .gasto ? "Nuevo gasto" : "Ingreso extra")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { Task { await guardar() } }.bold().disabled(!valido)
                    }
                }
            }
            .onAppear { campo = .importe }
            .interactiveDismissDisabled(guardando)
            .alertaError($error)
            .hojaMac()
            .ocultarTecladoFacil()
        }
    }

    @ViewBuilder private var seccionGasto: some View {
        Section("Concepto") {
            TextField("¿En qué lo has gastado?", text: $concepto)
                .focused($campo, equals: .concepto)
                .submitLabel(.done)
            let sugerencias = almacen.sugerencias(para: concepto)
            if !sugerencias.isEmpty && !sugerencias.contains(where: { $0.concepto == concepto }) {
                ForEach(sugerencias, id: \.concepto) { s in
                    Button {
                        concepto = s.concepto
                        if s.categoria != "Sin clasificar" { categoria = s.categoria }
                        campo = nil
                    } label: {
                        HStack {
                            IconoCategoria(categoria: s.categoria, tamaño: 24)
                            Text(s.concepto).foregroundStyle(.primary)
                            Spacer()
                            Text(s.categoria).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        Section("Categoría") {
            SelectorCategoria(categoria: $categoria)
        }

        Section("Método de pago") {
            Picker("Método", selection: $metodo) {
                ForEach(Metodo.allCases) { m in Label(m.rawValue, systemImage: m.icono).tag(m) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func guardar() async {
        guard let importe else { return }
        guardando = true
        error = nil
        defer { guardando = false }
        do {
            let texto = concepto.trimmingCharacters(in: .whitespaces)
            if tipo == .gasto {
                try await almacen.añadirGasto(importe: importe, concepto: texto, categoria: categoriaFinal,
                                              metodo: metodo.valorHoja)
            } else {
                try await almacen.añadirIngreso(importe: importe, concepto: texto.isEmpty ? "Ingreso extra" : texto,
                                                fecha: fechaIngreso)
            }
            Sistema.vibrarExito()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
