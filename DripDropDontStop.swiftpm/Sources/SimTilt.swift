// Simulator-only keyboard tilt: the Simulator has no accelerometer, so
// arrow keys (or WASD) drive the tilt vector instead — hold ←/→ to lean
// the world, ↓ to steepen the pull, ↑ to ease it off; release to settle
// back to the gentle default downhill. Compiled out entirely on device.

#if targetEnvironment(simulator)
import SwiftUI

struct SimTiltKeys: ViewModifier {
    let model: GameModel
    @FocusState private var focused: Bool
    @State private var held = Set<String>()

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .focusable()
                .focused($focused)
                .onAppear { focused = true }
                .onKeyPress(phases: [.down, .up]) { press in
                    guard let name = keyName(press.key) else { return .ignored }
                    if press.phase == .up {
                        held.remove(name)
                    } else {
                        held.insert(name)
                    }
                    apply()
                    return .handled
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("⌨ ←→ tilt · ↓ dive · ↑ ease")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.trailing, 10)
                        .padding(.bottom, 2)
                }
        } else {
            content
        }
    }

    private func keyName(_ key: KeyEquivalent) -> String? {
        switch key {
        case .leftArrow: return "left"
        case .rightArrow: return "right"
        case .upArrow: return "up"
        case .downArrow: return "down"
        default:
            switch key.character.lowercased() {
            case "a": return "left"
            case "d": return "right"
            case "w": return "up"
            case "s": return "down"
            default: return nil
            }
        }
    }

    private func apply() {
        let dx: CGFloat = (held.contains("right") ? 0.55 : 0)
                        - (held.contains("left") ? 0.55 : 0)
        var dy: CGFloat = -0.55                       // the gentle default
        if held.contains("down") { dy -= 0.35 }       // dive harder
        if held.contains("up") { dy += 0.30 }         // ease off the pull
        model.tilt = CGVector(dx: dx, dy: dy)
    }
}
#endif
