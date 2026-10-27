import UIKit
import SwiftUI

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = UIHostingController(rootView: ContentView())
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

struct ContentView: View {
    @State private var report = "Toque em \"Executar diagnóstico\". Nada é alterado no sistema."
    @State private var running = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Gestalt Manager — Fase 0")
                .font(.headline)
            Text("Somente leitura. O único arquivo gravado é o backup, em /var/mobile/Documents/GestaltManager.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Executar diagnóstico") { runDiagnostic() }
                Button("Backup do MobileGestalt") { runBackup() }
            }
            .disabled(running)

            Button("Copiar relatório") { UIPasteboard.general.string = report }

            ScrollView {
                Text(report)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    private func saveReport(_ text: String) -> String {
        let dir = "/var/mobile/Documents/GestaltManager"
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let path = "\(dir)/relatorio-\(f.string(from: Date())).txt"
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            return "Relatório salvo em \(path)"
        } catch {
            return "Não foi possível salvar o relatório: \((error as NSError).localizedDescription)"
        }
    }

    private func runDiagnostic() {
        running = true
        report = "Executando..."
        DispatchQueue.global().async {
            var out = "Gestalt Manager — Fase 0 (somente leitura)\n\(stamp())\n\n"
            out += "=== [1] Processo do app (sem helper) ===\n"
            out += probeText(label: "app") + "\n\n"
            out += "=== [2] Helper via persona root ===\n"
            let res = runAsRoot(["--helper", "probe"])
            out += "spawn: \(res.note)\n"
            out += res.output.isEmpty ? "(sem saída do helper)\n" : res.output + "\n"
            out += "\n" + saveReport(out)
            DispatchQueue.main.async {
                report = out
                running = false
            }
        }
    }

    private func runBackup() {
        running = true
        report = "Fazendo backup..."
        DispatchQueue.global().async {
            var out = "Backup do MobileGestalt\n\(stamp())\n\n"
            let res = runAsRoot(["--helper", "backup"])
            out += "[helper root] \(res.note)\n\(res.output)\n"
            if !res.ok || res.output.contains("ERRO") {
                out += "\n[tentativa no processo do app]\n\(doBackup())\n"
            }
            DispatchQueue.main.async {
                report = out
                running = false
            }
        }
    }
}
