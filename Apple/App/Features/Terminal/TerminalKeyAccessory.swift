#if os(iOS)
import ServerControl
import SwiftTerm
import UIKit

/// The editable key row above the keyboard.
final class TerminalKeyAccessory: UIInputView {
    private weak var terminal: SwiftTerm.TerminalView?
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var control: UIButton?

    init(terminal: SwiftTerm.TerminalView, layout: TerminalAccessoryLayout) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34),
        ])
        show(layout)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ layout: TerminalAccessoryLayout) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        control = nil
        for key in layout.keys { stack.addArrangedSubview(button(for: key)) }
        stack.addArrangedSubview(dismissButton())
    }

    private func button(for key: TerminalAccessoryKey) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = key.label
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.press(key)
        })
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        if key.action == .controlToggle { control = button }
        return button
    }

    private func dismissButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "keyboard.chevron.compact.down")
        return UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            _ = self?.terminal?.resignFirstResponder()
        })
    }

    private func press(_ key: TerminalAccessoryKey) {
        UIDevice.current.playInputClick()
        guard let terminal else { return }
        switch key.action {
        case .controlToggle:
            terminal.controlModifier.toggle()
            control?.isSelected = terminal.controlModifier
            control?.configuration?.baseBackgroundColor = terminal.controlModifier ? .tintColor : nil
        case .arrow(let direction):
            terminal.send(arrowBytes(direction, application: terminal.getTerminal().applicationCursor))
        case .bytes(let bytes):
            terminal.send(bytes)
        case .text(let text):
            terminal.send(txt: text)
        }
    }

    private func arrowBytes(_ direction: TerminalArrow, application: Bool) -> [UInt8] {
        let letter: String
        switch direction {
        case .up: letter = "A"
        case .down: letter = "B"
        case .right: letter = "C"
        case .left: letter = "D"
        }
        return Array(("\u{1B}" + (application ? "O" : "[") + letter).utf8)
    }
}

extension TerminalKeyAccessory: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
#endif
