import UIKit

// Modo helper: o mesmo binário é reiniciado com persona root e executa uma tarefa pontual.
let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--helper" {
    switch args[2] {
    case "probe":
        print(probeText(label: "helper (persona root)"))
    case "backup":
        print(doBackup())
    default:
        print("modo helper desconhecido: \(args[2])")
    }
    fflush(stdout)
    exit(0)
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
