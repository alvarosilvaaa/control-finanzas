import SwiftUI

/// Sección de ahorro: consejos calculados con tus gastos y límites por categoría.
struct AhorroView: View {
    @Environment(Almacen.self) private var almacen
    @State private var editando: EdicionLimite?

    var body: some View {
        #if os(iOS)
        NavigationStack {
            contenido
                .navigationTitle("Ahorro")
                .refreshable { await almacen.recargar() }
        }
        #else
        contenido
            .navigationTitle("Ahorro")
            .navigationSubtitle(Mes.actual.nombre)
            .toolbar {
                ToolbarItem { BotonRecargar() }
                ToolbarItem {
                    Button { editando = .nuevo } label: { Label("Añadir límite", systemImage: "plus") }
                        .help("Añadir un límite por categoría")
                }
            }
        #endif
    }

    private var contenido: some View {
        let consejos = almacen.consejos
        return ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Titulo(texto: "Consejos", detalle: "Calculados con tus gastos de \(Mes.actual.nombreMes.lowercased())")
                    if consejos.isEmpty {
                        Text("Aún no hay suficientes gastos este mes para darte consejos. Vuelve en unos días.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    ForEach(consejos) { c in
                        FilaConsejo(consejo: c) { categoria in editando = .categoria(categoria) }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Titulo(texto: "Límites por categoría", detalle: "Topes mensuales que tú decides")
                    if almacen.limites.isEmpty {
                        Text("Ponle un tope a las categorías donde más se te escapa el dinero (bares, restaurantes…) y te avisaré cuando te acerques.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    ForEach(almacen.limites, id: \.categoria) { l in
                        Button { editando = .categoria(l.categoria) } label: {
                            FilaLimite(limite: l, gastado: almacen.gastado(en: l.categoria))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { editando = .nuevo } label: {
                        Label("Añadir límite", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tema.tinta)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fondo)
        .sheet(item: $editando) { e in
            EditarLimiteView(categoriaInicial: e.categoria).fontDesign(.rounded)
        }
    }
}

/// Qué límite se está editando: uno nuevo o el de una categoría concreta.
private enum EdicionLimite: Identifiable {
    case nuevo
    case categoria(String)
    var id: String { categoria ?? "nuevo" }
    var categoria: String? { if case .categoria(let c) = self { c } else { nil } }
}

private struct Titulo: View {
    let texto: String
    let detalle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(texto).font(.title3.bold())
            Text(detalle).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct FilaConsejo: View {
    let consejo: Consejo
    let ponerLimite: (String) -> Void

    private var color: Color { consejo.tipo == .alerta ? Tema.alerta : Tema.tinta }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: consejo.icono)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(consejo.titulo).font(.body.weight(.semibold)).foregroundStyle(color)
                Text(consejo.texto).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let categoria = consejo.limiteSugerido {
                    Button { ponerLimite(categoria) } label: {
                        Text("Poner límite a \(categoria)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Tema.tinta.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

private struct FilaLimite: View {
    let limite: LimiteCategoria
    let gastado: Double

    var body: some View {
        let progreso = limite.limite > 0 ? gastado / limite.limite : 0
        let pasado = gastado > limite.limite
        let color: Color = pasado ? Tema.alerta : Tema.tinta
        HStack(spacing: 14) {
            IconoCategoria(categoria: limite.categoria, tamaño: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(limite.categoria).font(.body.weight(.semibold))
                    Spacer()
                    Text("\(Formato.eur(gastado)) de \(Formato.eurSinDecimales(limite.limite))")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tema.tinta.opacity(0.08))
                        Capsule().fill(color).frame(width: geo.size.width * min(progreso, 1))
                    }
                }
                .frame(height: 6)
                Text(pasado ? "\(Formato.eur(gastado - limite.limite)) por encima del límite"
                            : "Te quedan \(Formato.eur(limite.limite - gastado))")
                    .font(.caption).foregroundStyle(pasado ? Tema.alerta : .secondary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Crear, cambiar o quitar el límite mensual de una categoría.
struct EditarLimiteView: View {
    let categoriaInicial: String?
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var categoria = ""
    @State private var importeTexto = ""
    @State private var guardando = false
    @State private var error: String?

    private var existente: Double? { almacen.limite(de: categoria) }
    private var importe: Double? {
        Double(importeTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Categoría") {
                    if let categoriaInicial {
                        HStack(spacing: 12) {
                            IconoCategoria(categoria: categoriaInicial, tamaño: 30)
                            Text(categoriaInicial).font(.body.weight(.semibold))
                        }
                    } else {
                        Picker("Categoría", selection: $categoria) {
                            Text("Elige una").tag("")
                            ForEach(almacen.categorias, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Límite mensual", text: $importeTexto, prompt: Text("Límite mensual"))
                            .labelsHidden()
                            .tecladoDecimal()
                        Text("€").foregroundStyle(.secondary)
                    }
                    if let sugerido = almacen.limiteSugerido(para: categoria), !categoria.isEmpty {
                        Button("Usar \(Formato.eurSinDecimales(sugerido)) (sugerido)") {
                            importeTexto = PresupuestoView.texto(sugerido)
                        }
                    }
                } header: {
                    Text("Límite al mes")
                } footer: {
                    if !categoria.isEmpty { Text(resumen) }
                }

                if existente != nil {
                    Section {
                        Button("Quitar límite", role: .destructive) { Task { await guardar(nil) } }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .estiloLimpio()
            .navigationTitle(existente == nil ? "Nuevo límite" : "Editar límite")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { Task { await guardar(importe) } }
                            .bold()
                            .disabled(categoria.isEmpty || (importe ?? 0) <= 0)
                    }
                }
            }
            .alertaError($error)
            .ocultarTecladoFacil()
            .hojaMac(ancho: 440, alto: 380)
        }
        .onAppear {
            categoria = categoriaInicial ?? ""
            if let actual = almacen.limite(de: categoria) { importeTexto = PresupuestoView.texto(actual) }
        }
    }

    /// "Este mes llevas 55,90 €. Tu media de los últimos meses es 40 €."
    private var resumen: String {
        var texto = "Este mes llevas \(Formato.eur(almacen.gastado(en: categoria)))."
        if let media = almacen.mediaPrevia(de: categoria) {
            texto += " Tu media de los últimos meses es \(Formato.eurSinDecimales(media))."
        }
        return texto + " Te avisaré al llegar al 80 %."
    }

    private func guardar(_ limite: Double?) async {
        guardando = true
        defer { guardando = false }
        do {
            try await almacen.fijarLimite(limite, para: categoria)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
