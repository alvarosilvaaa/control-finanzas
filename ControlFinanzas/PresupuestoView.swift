import SwiftUI

struct PresupuestoView: View {
    let mes: Mes

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var baseTexto = ""
    @State private var guardando = false
    @State private var error: String?
    @State private var añadiendoIngreso = false

    var body: some View {
        let r = almacen.resumen(de: mes)
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Base mensual")
                        Spacer()
                        TextField("450", text: $baseTexto, prompt: Text("450"))
                            .labelsHidden()
                            .tecladoDecimal()
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                        Text("€").foregroundStyle(.secondary)
                    }
                    Button("Guardar base") { Task { await guardarBase() } }
                        .disabled(baseNueva == nil || baseNueva == r.base || guardando)
                } header: {
                    Text(mes.nombre)
                } footer: {
                    Text("Se aplica a \(mes.nombre.lowercased()) y a los meses siguientes hasta que la vuelvas a cambiar.")
                }

                Section {
                    ForEach(r.ingresos) { i in
                        HStack {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(i.concepto)
                                Text(i.fecha.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+" + Formato.eur(i.importe)).bold()
                        }
                    }
                    .onDelete { indices in
                        let aBorrar = indices.map { r.ingresos[$0] }
                        Task {
                            for i in aBorrar { await ejecutar { try await almacen.borrarIngreso(i) } }
                        }
                    }
                    Button { añadiendoIngreso = true } label: { Label("Añadir ingreso extra", systemImage: "plus") }
                } header: {
                    Text("Ingresos extra")
                } footer: {
                    Text("Propinas, regalos, devoluciones… Se suman al presupuesto de este mes. Desliza para borrar.")
                }

                Section {
                    LabeledContent("Base", value: Formato.eur(r.base))
                    LabeledContent("Ingresos extra", value: "+" + Formato.eur(r.totalExtra))
                    LabeledContent("Presupuesto total") {
                        Text(Formato.eur(r.presupuesto)).bold().foregroundStyle(.primary)
                    }
                }
            }
            .estiloLimpio()
            .navigationTitle("Presupuesto")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else { Button("Hecho") { dismiss() } }
                }
            }
            .onAppear { baseTexto = Self.texto(r.base) }
            .alertaError($error)
            .hojaMac()
            .ocultarTecladoFacil()
            .sheet(isPresented: $añadiendoIngreso) {
                NuevoIngresoView(mes: mes)
            }
        }
    }

    private var baseNueva: Double? {
        Double(baseTexto.replacingOccurrences(of: ",", with: ".")).flatMap { $0 >= 0 ? $0 : nil }
    }

    private func guardarBase() async {
        guard let base = baseNueva else { return }
        await ejecutar { try await almacen.fijarPresupuesto(base, desde: mes) }
    }

    private func ejecutar(_ accion: () async throws -> Void) async {
        guardando = true
        defer { guardando = false }
        do {
            try await accion()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func texto(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "es_ES")))
    }
}

private struct NuevoIngresoView: View {
    let mes: Mes

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var importeTexto = ""
    @State private var concepto = "Propina"
    @State private var fecha = Date()
    @State private var guardando = false
    @State private var error: String?

    private var importe: Double? {
        Double(importeTexto.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Importe", text: $importeTexto, prompt: Text("Importe"))
                    .labelsHidden().tecladoDecimal()
                TextField("Concepto", text: $concepto, prompt: Text("Concepto"))
                    .labelsHidden()
                DatePicker("Fecha", selection: $fecha, in: mes.inicio...min(mes.fin.addingTimeInterval(-1), Date()),
                           displayedComponents: .date)
            }
            .estiloLimpio()
            .navigationTitle("Ingreso extra")
            .tituloEnLinea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Añadir") {
                            Task {
                                guardando = true
                                defer { guardando = false }
                                do {
                                    try await almacen.añadirIngreso(importe: importe!, concepto: concepto, fecha: fecha)
                                    dismiss()
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .disabled(importe == nil)
                    }
                }
            }
            .onAppear { if !mes.contiene(Date()) { fecha = mes.inicio } }
            .alertaError($error)
            .hojaMac(alto: 300)
            .ocultarTecladoFacil()
        }
        .presentationDetents([.medium])
    }
}
