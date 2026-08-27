# Free Release Manual Acceptance

- [ ] Verify `shasum -a 256 -c SHA256SUMS` before installation.
- [ ] Download/extract the ZIP through a normal browser so quarantine is present.
- [ ] Record whether Control-click/right-click → Open succeeds on current macOS.
- [ ] If needed, record whether Privacy & Security → Open Anyway succeeds.
- [ ] Use `xattr -dr com.apple.quarantine /Applications/Loquat.app` only if both UI paths fail.
- [ ] Confirm startup shows no application-triggered Keychain or protected-resource prompt.
- [ ] Open Settings and save one test credential; record any Keychain ACL prompt.
- [ ] Quit/relaunch and confirm the credential remains readable.
- [ ] Replace the app with the next ad-hoc build and record whether macOS asks for Keychain access again.
- [ ] Confirm no API key appears in UserDefaults, logs, the ZIP, or `SHA256SUMS`.
