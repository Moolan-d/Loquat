import AppKit
import Darwin
import Foundation
import InstantTranslationApp

if CommandLine.arguments.count == 4,
   CommandLine.arguments[1] == "--adhoc-keychain-round-trip-probe"
{
    do {
        try AdHocKeychainRoundTripProbe.run(
            service: CommandLine.arguments[2],
            account: CommandLine.arguments[3]
        )
        print("ad-hoc Keychain round trip passed")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ad-hoc Keychain round trip failed\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
