import SwiftUI

/// Fila horizontal de gastos frecuentes en el formulario de nuevo gasto.
struct FilaFrecuentes: View {
    let usar: (Frecuente) -> Void
    @Environment(Almacen.self) private var almacen

    var body: some View {
        let frecuentes = almacen.frecuentes
        let lista = frecuentes.isEmpty ? almacen.sugerenciasFrecuentes : frecuentes
        if lista.isEmpty {
            Text("Aún no tienes gastos frecuentes. Pulsa «Gestionar» para añadir el gimnasio, un Bizum semanal…")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lista) { f in
                        TarjetaFrecuente(frecuente: f, pendiente: f.pendiente(en: almacen.datos.gastos)) { usar(f) }
                    }
                }
                .padding(.vertical, 2)
            }
            if frecuentes.isEmpty {
                Text("Sugerencias según tu historial. Guárdalas en «Gestionar» para tenerlas siempre.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TarjetaFrecuente: View {
    let frecuente: Frecuente
    let pendiente: Bool
    let accion: () -> Void

    var body: some View {
        let estilo = EstiloCategoria.de(frecuente.categoria)
        Button(action: accion) {
            HStack(spacing: 8) {
                IconoCategoria(categoria: frecuente.categoria, tamaño: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(frecuente.concepto).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(frecuente.importe.map(Formato.eur) ?? "Sin importe")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if pendiente {
                    Text("Pendiente")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(estilo.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(pendiente ? Color.orange.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(frecuente.descripcion)
    }
}

/// Lista de frecuentes guardados y sugerencias para añadir.
struct GestionFrecuentesView: View {
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var editando: Frecuente?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if almacen.frecuentes.isEmpty {
                        Text("Todavía no has guardado ninguno.").foregroundStyle(.secondary)
                    }
                    ForEach(almacen.frecuentes) { f in
                        Button { editando = f } label: { FilaFrecuente(frecuente: f, pendiente: f.pendiente(en: almacen.datos.gastos)) }
                            .buttonStyle(.plain)
                    }
                    Button { editando = .nuevo() } label: { Label("Nuevo gasto frecuente", systemImage: "plus") }
                } header: {
                    Text("Tus gastos frecuentes")
                } footer: {
                    Text("Si les pones periodicidad, aparecen como «Pendiente» cuando toca pagarlos y aún no los has registrado.")
                }

                let sugerencias = almacen.sugerenciasFrecuentes
                if !sugerencias.isEmpty {
                    Section("Sugerencias según tu historial") {
                        ForEach(sugerencias) { f in
                            Button { editando = f } label: {
                                HStack {
                                    FilaFrecuente(frecuente: f, pendiente: false)
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Gastos frecuentes")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
            }
            .sheet(item: $editando) { EditarFrecuenteView(original: $0) }
            .hojaMac(ancho: 460, alto: 520)
        }
    }
}

private struct FilaFrecuente: View {
    let frecuente: Frecuente
    let pendiente: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconoCategoria(categoria: frecuente.categoria, tamaño: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(frecuente.concepto)
                Text(frecuente.descripcion).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if pendiente {
                Text("Pendiente").font(.caption.bold()).foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
    }
}

struct EditarFrecuenteView: View {
    typealias Metodo = NuevoMovimientoView.Metodo

    let original: Frecuente
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var f: Frecuente
    @State private var importeTexto: String
    @State private var categoria: String
    @State private var metodo: Metodo
    @State private var guardando = false
    @State private var confirmandoBorrado = false
    @State private var error: String?

    init(original: Frecuente) {
        self.original = original
        _f = State(initialValue: original)
        _importeTexto = State(initialValue: original.importe.map(PresupuestoView.texto) ?? "")
        _categoria = State(initialValue: original.categoria == "Sin clasificar" ? "" : original.categoria)
        _metodo = State(initialValue: Metodo(rawValue: Formato.metodo(original.metodo)) ?? .bizum)
    }

    private var esNuevo: Bool { original.id.hasPrefix("nuevo-") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Concepto (p. ej. Gimnasio)", text: $f.concepto, prompt: Text("Concepto (p. ej. Gimnasio)"))
                        .labelsHidden()
                    HStack {
                        TextField("Importe habitual", text: $importeTexto, prompt: Text("Importe habitual (opcional)"))
                            .labelsHidden()
                            .tecladoDecimal()
                        Text("€").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("El concepto debe coincidir con cómo aparece el gasto para saber si ya lo has registrado.")
                }

                Section("Categoría") { SelectorCategoria(categoria: $categoria) }

                Section("Método de pago") {
                    Picker("Método", selection: $metodo) {
                        ForEach(Metodo.allCases) { m in Label(m.rawValue, systemImage: m.icono).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Periodicidad") {
                    Picker("Se paga", selection: $f.frecuencia) {
                        ForEach(Frecuente.Frecuencia.allCases) { Text($0.nombre).tag($0) }
                    }
                    switch f.frecuencia {
                    case .mensual:
                        Picker("Día del mes", selection: Binding(get: { f.dia ?? 1 }, set: { f.dia = $0 })) {
                            ForEach(1...31, id: \.self) { Text("Día \($0)").tag($0) }
                        }
                    case .semanal:
                        Picker("Día de la semana", selection: Binding(get: { f.dia ?? 1 }, set: { f.dia = $0 })) {
                            ForEach(1...7, id: \.self) { Text(Frecuente.diasSemana[$0 - 1].capitalized).tag($0) }
                        }
                    case .ninguna:
                        EmptyView()
                    }
                }

                if !esNuevo {
                    Section {
                        Button("Borrar gasto frecuente", role: .destructive) { confirmandoBorrado = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(esNuevo ? "Nuevo frecuente" : "Editar frecuente")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { Task { await guardar() } }
                            .bold()
                            .disabled(f.concepto.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("¿Borrar «\(original.concepto)»?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { Task { await ejecutar { try await almacen.borrarFrecuente(original) } } }
            } message: {
                Text("Los gastos ya registrados no se tocan.")
            }
            .alertaError($error)
            .ocultarTecladoFacil()
            .hojaMac(alto: 600)
        }
    }

    private func guardar() async {
        var final = f
        final.concepto = f.concepto.trimmingCharacters(in: .whitespaces)
        final.importe = Double(importeTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        final.categoria = categoria.isEmpty ? "Sin clasificar" : categoria
        final.metodo = Formato.metodo(original.metodo) == metodo.rawValue ? original.metodo : metodo.valorHoja
        if final.frecuencia == .ninguna { final.dia = nil } else if final.dia == nil { final.dia = 1 }
        await ejecutar { try await almacen.guardarFrecuente(final) }
    }

    private func ejecutar(_ accion: () async throws -> Void) async {
        guardando = true
        defer { guardando = false }
        do {
            try await accion()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
