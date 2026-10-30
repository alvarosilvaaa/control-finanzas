import SwiftUI

/// Cerrar el mes en curso hoy (p. ej. porque has cobrado antes) y abrir el siguiente con el dinero que tú digas.
struct CerrarMesView: View {
    /// Se llama tras cerrar, con el mes que se acaba de abrir.
    var alCerrar: (Mes) -> Void = { _ in }

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var importeTexto = ""
    @State private var guardando = false
    @State private var error: String?

    private var nuevo: Mes { almacen.mesQueSeAbre }
    private var cerrado: Mes { nuevo.anterior }

    private var importe: Double? {
        Double(importeTexto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            .flatMap { $0 >= 0 ? ($0 * 100).rounded() / 100 : nil }
    }

    var body: some View {
        let r = almacen.resumen(de: cerrado)
        let habitual = almacen.base(de: nuevo)
        let sobrante = max(r.restante, 0)

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Gastado", value: Formato.eur(r.totalGastado))
                    LabeledContent("Presupuesto", value: Formato.eur(r.presupuesto))
                    LabeledContent(r.restante >= 0 ? "Te sobra" : "Te has pasado") {
                        Text(Formato.eur(abs(r.restante))).bold()
                            .foregroundStyle(r.restante >= 0 ? Tema.tinta : Tema.alerta)
                    }
                } header: {
                    Text("Cierras \(cerrado.nombre)")
                } footer: {
                    Text("Lo gastado desde hoy (también lo de esta mañana) contará en \(nuevo.nombre). Lo de días anteriores se queda en \(cerrado.nombre.lowercased()).")
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0,00", text: $importeTexto, prompt: Text("0,00"))
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .tecladoDecimal()
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("€").font(.title.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 8) {
                        Chip(texto: "\(Formato.eurSinDecimales(habitual)) habitual", icono: "arrow.counterclockwise",
                             color: Tema.tinta, seleccionado: importe == habitual) {
                            importeTexto = PresupuestoView.texto(habitual)
                        }
                        if sobrante >= 1 {
                            let total = ((habitual + sobrante) * 100).rounded() / 100
                            Chip(texto: "+ lo que sobra (\(Formato.eurSinDecimales(total)))", icono: "plus",
                                 color: Tema.tinta, seleccionado: importe == total) {
                                importeTexto = PresupuestoView.texto(total)
                            }
                        }
                    }
                } header: {
                    Text("¿Con cuánto empiezas \(nuevo.nombreMes)?")
                } footer: {
                    Text("Será el presupuesto de \(nuevo.nombre) y de los meses siguientes, hasta que lo cambies.")
                }
            }
            .estiloLimpio()
            .navigationTitle("Cerrar mes")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Abrir \(nuevo.nombreMes)") { Task { await cerrar() } }
                            .bold()
                            .disabled(importe == nil)
                    }
                }
            }
            .onAppear { if importeTexto.isEmpty { importeTexto = PresupuestoView.texto(habitual) } }
            .interactiveDismissDisabled(guardando)
            .alertaError($error)
            .ocultarTecladoFacil()
            .hojaMac(ancho: 480, alto: 520)
        }
    }

    private func cerrar() async {
        guard let importe else { return }
        let abierto = nuevo
        guardando = true
        defer { guardando = false }
        do {
            try await almacen.cerrarMes(empezandoCon: importe)
            Sistema.vibrarExito()
            alCerrar(abierto)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Aviso al final del mes para cerrarlo si ya has cobrado.
struct AvisoCerrarMes: View {
    let accion: () -> Void
    @Environment(Almacen.self) private var almacen

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.tinta)
                    .frame(width: 36, height: 36)
                    .background(Tema.tinta.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Ya has cobrado?").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Cierra el mes hoy y empieza \(almacen.mesQueSeAbre.nombreMes)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
