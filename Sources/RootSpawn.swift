import Foundation
import Darwin

// Funções privadas de posix_spawn (mesmo padrão do RootHelper do TrollStore).
@_silgen_name("posix_spawnattr_set_persona_np")
private func _set_persona_np(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ personaId: uid_t, _ flags: UInt32) -> Int32
@_silgen_name("posix_spawnattr_set_persona_uid_np")
private func _set_persona_uid_np(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ uid: uid_t) -> Int32
@_silgen_name("posix_spawnattr_set_persona_gid_np")
private func _set_persona_gid_np(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>, _ gid: gid_t) -> Int32

struct SpawnResult {
    var ok: Bool
    var output: String
    var note: String
}

/// Reinicia o próprio executável com persona root e captura a saída.
func runAsRoot(_ extraArgs: [String]) -> SpawnResult {
    guard let exe = Bundle.main.executablePath else {
        return SpawnResult(ok: false, output: "", note: "executablePath indisponível")
    }
    var fds: [Int32] = [0, 0]
    if pipe(&fds) != 0 {
        return SpawnResult(ok: false, output: "", note: "pipe() falhou: \(String(cString: strerror(errno)))")
    }

    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }

    let r1 = _set_persona_np(&attr, 99, 1) // 1 = POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
    let r2 = _set_persona_uid_np(&attr, 0)
    let r3 = _set_persona_gid_np(&attr, 0)

    var fa: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fa)
    defer { posix_spawn_file_actions_destroy(&fa) }
    posix_spawn_file_actions_adddup2(&fa, fds[1], 1)
    posix_spawn_file_actions_adddup2(&fa, fds[1], 2)
    posix_spawn_file_actions_addclose(&fa, fds[0])

    let argv: [UnsafeMutablePointer<CChar>?] = ([exe] + extraArgs).map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"].map { strdup($0) } + [nil]

    var pid: pid_t = 0
    let rc = posix_spawn(&pid, exe, &fa, &attr, argv, envp)
    close(fds[1])

    if rc != 0 {
        close(fds[0])
        return SpawnResult(ok: false, output: "",
                           note: "posix_spawn falhou rc=\(rc) (\(String(cString: strerror(rc)))) persona_np=\(r1) uid=\(r2) gid=\(r3)")
    }

    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fds[0], &buf, buf.count)
        if n <= 0 { break }
        data.append(buf, count: n)
    }
    close(fds[0])
    var status: Int32 = 0
    waitpid(pid, &status, 0)

    let text = String(data: data, encoding: .utf8) ?? "<saída não UTF-8>"
    let exitCode = (status >> 8) & 0xff
    return SpawnResult(ok: exitCode == 0, output: text,
                       note: "filho pid=\(pid) saída=\(exitCode) persona_np=\(r1) uid=\(r2) gid=\(r3)")
}
