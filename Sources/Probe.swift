import Foundation
import CommonCrypto

let mgDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
let mgPath = mgDir + "/com.apple.MobileGestalt.plist"
let backupDir = "/var/mobile/Documents/GestaltManager/backups"

// MARK: - Utilidades

func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname(name, &buf, &size, nil, 0)
    return String(cString: buf)
}

func statLine(_ path: String) -> String {
    var st = stat()
    if stat(path, &st) != 0 { return "stat falhou: \(String(cString: strerror(errno)))" }
    return "uid=\(st.st_uid) gid=\(st.st_gid) modo=\(String(st.st_mode & 0o7777, radix: 8)) tamanho=\(st.st_size)"
}

func listDir(_ path: String) -> String {
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: path)
        return "ok (\(items.count) itens)"
    } catch {
        return "erro: \((error as NSError).localizedDescription)"
    }
}

func describe(_ v: Any) -> String {
    switch v {
    case let n as NSNumber:
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true (bool)" : "false (bool)") : "\(n) (número)"
    case let s as String: return "\"\(s)\" (texto)"
    case let d as Data: return "<dados \(d.count) bytes>"
    case let a as [Any]: return "<array \(a.count)>"
    case let d as [String: Any]: return "<dict \(d.count)>"
    default: return "\(type(of: v))"
    }
}

// MARK: - Hash de chaves (algoritmo validado contra um par conhecido)

func md5Data(_ d: Data) -> Data {
    var out = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    d.withUnsafeBytes { p in _ = CC_MD5(p.baseAddress, CC_LONG(d.count), &out) }
    return Data(out)
}

private func cut2(_ s: String) -> String { String(s.dropLast(2)) }

/// Variantes candidatas do algoritmo de ofuscação. Só uma será usada: a que reproduzir o par conhecido.
func hashVariants(_ name: String) -> [(String, String)] {
    let baseData = Data(("MGCopyAnswer" + name).utf8)
    let bb = baseData.base64EncodedString()
    return [
        ("F: md5(base) -> base64 -> sem '=='", cut2(md5Data(baseData).base64EncodedString())),
        ("B: md5(base64(base)) -> base64 -> sem '=='", cut2(md5Data(Data(bb.utf8)).base64EncodedString())),
        ("A: md5(base64(base) sem 2 ultimos) -> base64 -> sem '=='", cut2(md5Data(Data(cut2(bb).utf8)).base64EncodedString())),
    ]
}

// Par nome/hash confirmado em fonte pública (gist de tihmstar).
let knownName = "DeviceSupportsDynamicIsland"
let knownHash = "YlEtTtHlNesRBMal1CqRaA"

func validatedVariantIndex() -> Int? {
    hashVariants(knownName).firstIndex(where: { $0.1 == knownHash })
}

// MARK: - Diagnóstico (somente leitura)

func probeText(label: String) -> String {
    var L: [String] = []
    let fm = FileManager.default

    L.append("-- Identidade (\(label))")
    L.append("uid=\(getuid()) euid=\(geteuid()) gid=\(getgid())")
    L.append("modelo=\(sysctlString("hw.machine")) build=\(sysctlString("kern.osversion"))")
    L.append("versão=\(ProcessInfo.processInfo.operatingSystemVersionString)")

    L.append("-- Acesso a diretórios")
    for p in ["/var/containers/Shared/SystemGroup", "/var/mobile/Containers/Data/Application", "/var/containers/Bundle/Application"] {
        L.append("\(p): \(listDir(p))")
    }

    L.append("-- Roothide")
    if let apps = try? fm.contentsOfDirectory(atPath: "/var/containers/Bundle/Application") {
        let jb = apps.filter { $0.hasPrefix(".jbroot") }
        L.append("jbroot em /var/containers/Bundle/Application: \(jb.isEmpty ? "não visível" : jb.joined(separator: ", "))")
    } else {
        L.append("jbroot: não foi possível listar /var/containers/Bundle/Application")
    }
    L.append("/var/jb existe: \(fm.fileExists(atPath: "/var/jb"))")

    var sfs = statfs()
    if statfs("/var", &sfs) == 0 {
        L.append("/var montado somente-leitura: \((sfs.f_flags & UInt32(MNT_RDONLY)) != 0)")
    }

    L.append("-- Arquivo MobileGestalt")
    L.append(mgPath)
    L.append("  \(statLine(mgPath))")
    L.append("  leitura(access)=\(access(mgPath, R_OK) == 0) escrita(access)=\(access(mgPath, W_OK) == 0)")
    L.append("  escrita no diretório pai=\(access(mgDir, W_OK) == 0)")
    if let items = try? fm.contentsOfDirectory(atPath: mgDir) {
        L.append("  itens no diretório: \(items.sorted().joined(separator: ", "))")
    }

    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: mgPath))
        L.append("  lido: \(data.count) bytes")
        var fmt = PropertyListSerialization.PropertyListFormat.binary
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
        L.append("  formato plist: \(fmt == .binary ? "binário" : (fmt == .xml ? "xml" : "outro"))")
        guard let root = obj as? [String: Any] else {
            L.append("  raiz não é dicionário")
            return L.joined(separator: "\n")
        }
        L.append("  chaves de topo: \(root.keys.sorted().joined(separator: ", "))")
        for k in root.keys.sorted() where k != "CacheExtra" {
            L.append("    \(k) = \(describe(root[k]!))")
        }
        if let extra = root["CacheExtra"] as? [String: Any] {
            L.append("  CacheExtra: \(extra.count) chaves (valores não listados por conterem identificadores do aparelho)")

            L.append("-- Validação do algoritmo de hash")
            let vIdx = validatedVariantIndex()
            if let i = vIdx {
                L.append("  variante validada: \(hashVariants(knownName)[i].0)")
            } else {
                L.append("  NENHUMA variante reproduziu o par conhecido; nomes não serão resolvidos")
            }

            L.append("-- Chaves de interesse")
            func show(_ title: String, _ hash: String) {
                if let v = extra[hash] { L.append("  \(title) [\(hash)] = \(describe(v))") }
                else { L.append("  \(title) [\(hash)] = ausente") }
            }
            show("DeviceSupportsDynamicIsland (nome confirmado)", knownHash)
            show("hash do Nugget/TweaksLoader para AOD (nome não confirmado)", "2OOJf1VhaM7NxfRok3HbWQ")
            if let i = vIdx {
                let names = ["ArtworkDeviceSubType", "ProductType", "HWModelStr", "DeviceClass",
                             "ArtworkDeviceProductDescription", "main-screen-width", "main-screen-height", "main-screen-scale"]
                for n in names {
                    let h = hashVariants(n)[i].1
                    show(n, h)
                }
            }
        } else {
            L.append("  CacheExtra ausente")
        }
    } catch {
        L.append("  ERRO ao ler/parsear: \((error as NSError).localizedDescription)")
    }
    return L.joined(separator: "\n")
}

// MARK: - Backup (único ponto que grava, e só em pasta própria)

func doBackup() -> String {
    let fm = FileManager.default
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: mgPath))
        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        try fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        chown("/var/mobile/Documents/GestaltManager", 501, 501)
        chown(backupDir, 501, 501)

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "MobileGestalt-\(sysctlString("kern.osversion"))-\(f.string(from: Date())).plist"
        let dest = backupDir + "/" + name

        try data.write(to: URL(fileURLWithPath: dest), options: .atomic)
        let back = try Data(contentsOf: URL(fileURLWithPath: dest))
        guard back == data else { return "ERRO: cópia divergente do original; backup descartado" }
        chown(dest, 501, 501)
        chmod(dest, 0o644)
        return "OK: backup verificado (\(data.count) bytes)\n\(dest)"
    } catch {
        return "ERRO no backup: \((error as NSError).localizedDescription)"
    }
}
