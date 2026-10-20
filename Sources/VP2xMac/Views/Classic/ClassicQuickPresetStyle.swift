import SwiftUI

struct ClassicQuickPresetStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(LinearGradient(colors: [PresetChrome.dark, Color(red: 0.08, green: 0.11, blue: 0.14)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .modifier(PresetBevel(sunken: configuration.isPressed))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black, lineWidth: 1))
            .opacity(enabled ? 1 : 0.65)
            .contentShape(Rectangle())
    }
}

struct QuickPresetLamp: View {
    let lit: Bool
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: lit ? [.white, .yellow, Color(red: 0.75, green: 0.65, blue: 0.08)] : [Color(white: 0.8), PresetChrome.panel, Color(white: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 22, height: 22)
            .modifier(PresetBevel(sunken: true))
            .overlay(Rectangle().stroke(.black, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
