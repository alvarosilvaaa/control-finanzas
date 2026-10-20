# Finanzas

App personal de control de gastos para **iPhone** y **Mac** (SwiftUI), conectada a una hoja de Google Sheets.

- **Registrar gastos** manuales (Bizum, efectivo, tarjeta) que llegan a la hoja por el mismo formulario que la automatización de pagos.
- **Resumen visual** del mes: presupuesto restante, ritmo de gasto, gráficos por categoría.
- **Resumen mensual** con comparación frente al mes anterior.
- **Editar y clasificar** gastos, con reglas automáticas por comercio.
- **Presupuesto** editable e ingresos extra (propinas…).

## Estructura

| Carpeta | Contenido |
|---|---|
| `ControlFinanzas/` | Código de la app (compartido iPhone + Mac; lo específico de Mac está en `MacViews.swift`) |
| `AppsScript/Codigo.gs` | API en Google Apps Script que lee y escribe en la hoja |
| `actualizar_mac.sh` | Compila e instala la app de Mac en `/Applications/Finanzas.app` |
| `INSTRUCCIONES.md` | Puesta en marcha paso a paso |
