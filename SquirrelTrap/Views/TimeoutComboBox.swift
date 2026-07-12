import AppKit
import SwiftUI

/// A native combo box (free-form text entry + dropdown of presets) for picking
/// the auto-dismiss timeout — SwiftUI has no built-in equivalent to NSComboBox.
struct TimeoutComboBox: NSViewRepresentable {
    @Binding var value: Double
    let options: [Double]

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.addItems(withObjectValues: options.map(Self.string(for:)))
        comboBox.stringValue = Self.string(for: value)
        comboBox.font = .systemFont(ofSize: 12)
        comboBox.completes = false
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        let stringValue = Self.string(for: value)
        if nsView.stringValue != stringValue {
            nsView.stringValue = stringValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    private static func string(for value: Double) -> String {
        String(Int(value))
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        let value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        func controlTextDidChange(_ notification: Notification) {
            commit(from: notification.object)
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            commit(from: notification.object)
        }

        // Typed values are clamped rather than rejected, so a stray "0" or a
        // huge number can't produce a broken (zero/negative or absurdly long) Timer interval.
        private func commit(from object: Any?) {
            guard let comboBox = object as? NSComboBox, let number = Double(comboBox.stringValue) else { return }
            value.wrappedValue = min(max(number, 1), 300)
        }
    }
}
