import AppKit
import Darwin
import Foundation

let argument = CommandLine.arguments.count == 2 ? CommandLine.arguments[1] : ""
let scenario: DiagnosticsScenario
switch DiagnosticsScenario.parse(argument) {
case .success(let parsed):
    scenario = parsed
case .failure(let error):
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(64)
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = DiagnosticsAppDelegate(scenario: scenario)
application.delegate = delegate
application.run()
