import SwiftUI

/// Lista de cosas que quieres comprarte, con lo que suman y si te alcanza este mes.
struct WishlistView: View {
    @Environment(Almacen.self) private var almacen
    @Environment(\.openURL) private var abrir
    @State private var editando: Deseo?
    @State private var verComprados = false
    @State private var error: String?

    var body: some View {
        let deseos = almacen.deseos
        let pendientes = deseos.filter { !$0.comprado }
        let comprados = deseos.filter(\.comprado)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                cabecera(pendientes)

                VStack(alignment: .leading, spacing: 0) {
                    if pendientes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tu wishlist está vacía").font(.headline)
                            Text("Apunta aquí lo que te quieres comprar: así lo piensas dos veces y ves si te cabe en el presupuesto.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            botonAñadir.padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                    ForEach(pendientes) { fila($0) }
                }

                if !comprados.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button { withAnimation(.snappy) { verComprados.toggle() } } label: {
                            HStack {
                                Text("Comprados").font(.title3.bold())
                                Text("\(comprados.count)").foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(verComprados ? 0 : -90))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 6)
                        if verComprados { ForEach(comprados) { fila($0) } }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fondo)
        .refreshable { await almacen.recargar() }
        .toolbar {
            #if os(macOS)
            ToolbarItem { BotonRecargar() }
            #endif
            ToolbarItem(placement: .fin) {
                Button { editando = .nuevo() } label: { Label("Añadir deseo", systemImage: "plus") }
                    .help("Añadir algo a la wishlist")
            }
        }
        .sheet(item: $editando) { EditarDeseoView(original: $0).fontDesign(.rounded) }
        .alertaError($error)
    }

    // MARK: - Piezas

    @ViewBuilder private func cabecera(_ pendientes: [Deseo]) -> some View {
        let conPrecio = pendientes.compactMap(\.precio)
        let total = conPrecio.reduce(0, +)
        let restante = almacen.resumen(de: .actual).restante
        let alcanza = pendientes.filter { ($0.precio ?? .infinity) <= restante }

        VStack(alignment: .leading, spacing: 6) {
            Text("Te quieres comprar").font(.subheadline).foregroundStyle(.secondary)
            Text(Formato.eur(total)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            Text(pendientes.count == 1 ? "1 deseo pendiente" : "\(pendientes.count) deseos pendientes")
                .font(.subheadline).foregroundStyle(.secondary)
            if !pendientes.isEmpty {
                Group {
                    if restante <= 0 {
                        Text("Este mes ya has gastado todo el presupuesto: mejor esperar al mes que viene.")
                    } else if alcanza.isEmpty {
                        Text("Este mes te quedan \(Formato.eur(restante)): no te alcanza para ninguno sin pasarte.")
                    } else {
                        Text("Este mes te quedan \(Formato.eur(restante)): te alcanza para \(alcanza.count == 1 ? "1 de ellos" : "\(alcanza.count) de ellos") sin pasarte.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(restante <= 0 ? Tema.alerta : .secondary)
                .padding(.top, 4)
            }
        }
    }

    private var botonAñadir: some View {
        Button { editando = .nuevo() } label: {
            Label("Añadir deseo", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Tema.tinta.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fila(_ d: Deseo) -> some View {
        Button { editando = d } label: { FilaDeseo(deseo: d) }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    var copia = d
                    copia.comprado.toggle()
                    Task { await ejecutar { try await almacen.guardarDeseo(copia) } }
                } label: {
                    Label(d.comprado ? "Marcar como pendiente" : "Marcar como comprado",
                          systemImage: d.comprado ? "arrow.uturn.backward" : "checkmark.circle")
                }
                if let url = d.url {
                    Button { abrir(url) } label: { Label("Abrir enlace", systemImage: "safari") }
                }
                Divider()
                Button(role: .destructive) {
                    Task { await ejecutar { try await almacen.borrarDeseo(d) } }
                } label: { Label("Borrar", systemImage: "trash") }
            }
    }

    private func ejecutar(_ accion: () async throws -> Void) async {
        do { try await accion() } catch { self.error = error.localizedDescription }
    }
}

private struct FilaDeseo: View {
    let deseo: Deseo

    private var detalle: String {
        var partes: [String] = []
        if deseo.comprado { partes.append("Comprado") } else { partes.append("Prioridad \(deseo.prioridad.rawValue)") }
        if !deseo.nota.isEmpty { partes.append(deseo.nota) }
        return partes.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: deseo.comprado ? "checkmark" : (deseo.prioridad == .alta ? "star.fill" : "gift"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tema.tinta)
                .frame(width: 44, height: 44)
                .background(Tema.tinta.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(deseo.nombre)
                        .font(.body.weight(.semibold))
                        .strikethrough(deseo.comprado)
                        .lineLimit(1)
                    if deseo.url != nil {
                        Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(detalle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(deseo.precio.map(Formato.eur) ?? "—")
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(deseo.comprado ? .secondary : .primary)
        }
        .padding(.vertical, 10)
        .opacity(deseo.comprado ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}

/// Crear o editar un deseo.
struct EditarDeseoView: View {
    let original: Deseo
    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var abrir
    @State private var d: Deseo
    @State private var precioTexto: String
    @State private var guardando = false
    @State private var confirmandoBorrado = false
    @State private var error: String?

    init(original: Deseo) {
        self.original = original
        _d = State(initialValue: original)
        _precioTexto = State(initialValue: original.precio.map(PresupuestoView.texto) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Qué quieres comprar", text: $d.nombre, prompt: Text("Qué quieres comprar (p. ej. AirPods)"))
                        .labelsHidden()
                    HStack {
                        TextField("Precio", text: $precioTexto, prompt: Text("Precio aproximado (opcional)"))
                            .labelsHidden()
                            .tecladoDecimal()
                        Text("€").foregroundStyle(.secondary)
                    }
                }

                Section("Prioridad") {
                    Picker("Prioridad", selection: $d.prioridad) {
                        ForEach(Deseo.Prioridad.allCases) { Text($0.nombre).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    TextField("Enlace", text: $d.enlace, prompt: Text("Enlace a la tienda (opcional)"))
                        .labelsHidden()
                        .tecladoURL()
                        .autocorrectionDisabled()
                    TextField("Nota", text: $d.nota, prompt: Text("Nota (talla, color, dónde está más barato…)"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...4)
                    if let url = d.url {
                        Button { abrir(url) } label: { Label("Abrir enlace", systemImage: "safari") }
                    }
                }

                if !original.esNuevo {
                    Section {
                        Toggle("Ya lo he comprado", isOn: $d.comprado)
                    }
                    Section {
                        Button("Borrar de la wishlist", role: .destructive) { confirmandoBorrado = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .estiloLimpio()
            .navigationTitle(original.esNuevo ? "Nuevo deseo" : "Editar deseo")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Guardar") { Task { await guardar() } }
                            .bold()
                            .disabled(d.nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("¿Borrar «\(original.nombre)»?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { Task { await ejecutar { try await almacen.borrarDeseo(original) } } }
            }
            .alertaError($error)
            .ocultarTecladoFacil()
            .hojaMac(ancho: 460, alto: 520)
        }
    }

    private func guardar() async {
        var final = d
        final.nombre = d.nombre.trimmingCharacters(in: .whitespaces)
        final.enlace = d.enlace.trimmingCharacters(in: .whitespaces)
        final.nota = d.nota.trimmingCharacters(in: .whitespacesAndNewlines)
        final.precio = Double(precioTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        await ejecutar { try await almacen.guardarDeseo(final) }
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

/// Pestaña "Más" del iPhone: muestra la pantalla elegida en su menú desplegable.
struct MasView: View {
    enum Seccion: String, CaseIterable, Identifiable {
        case meses, wishlist, ajustes
        var id: String { rawValue }
        var titulo: String {
            switch self {
            case .meses: "Meses"
            case .wishlist: "Wishlist"
            case .ajustes: "Ajustes"
            }
        }
        var icono: String {
            switch self {
            case .meses: "calendar"
            case .wishlist: "gift"
            case .ajustes: "gearshape"
            }
        }
    }

    let seccion: Seccion

    var body: some View {
        switch seccion {
        case .meses:
            MesesView()
        case .wishlist:
            NavigationStack {
                WishlistView().navigationTitle("Wishlist")
            }
        case .ajustes:
            AjustesView()
        }
    }
}

/// Menú flotante que se despliega sobre la pestaña "Más".
struct MenuMas: View {
    let actual: MasView.Seccion?
    let elegir: (MasView.Seccion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(MasView.Seccion.allCases) { s in
                Button { elegir(s) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: s.icono)
                            .font(.body.weight(.semibold))
                            .frame(width: 24)
                        Text(s.titulo).font(.body.weight(.semibold))
                        Spacer()
                        if s == actual {
                            Image(systemName: "checkmark").font(.footnote.weight(.bold))
                        }
                    }
                    .foregroundStyle(Tema.tinta)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s != MasView.Seccion.allCases.last { Divider().padding(.leading, 56) }
            }
        }
        .frame(width: 230)
        .background(Color.fondo, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Tema.tinta.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }
}
