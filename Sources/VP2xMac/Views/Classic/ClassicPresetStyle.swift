import SwiftUI

/// The fixed palette and bevels of the original VP2x preset utility.
enum PresetChrome {
    static let panel = Color(red: 0.67, green: 0.67, blue: 0.63)
    static let dark = Color(red: 0.12, green: 0.16, blue: 0.20)
    static let cyan = Color(red: 0, green: 0.94, blue: 1)
}

struct PresetBevel: ViewModifier {
    var sunken = false
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: w, y: 0))
                }.stroke(sunken ? Color.black.opacity(0.65) : Color.white.opacity(0.8), lineWidth: 2)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: 0))
                }.stroke(sunken ? Color.white.opacity(0.75) : Color.black.opacity(0.6), lineWidth: 2)
            }.allowsHitTesting(false)
        }
    }
}

struct PresetOperationStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var exit = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            if !exit {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(white: 0.38))
                    .frame(width: 23, height: 22)
                    .background(.linearGradient(colors: [.white, PresetChrome.panel, Color(white: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .modifier(PresetBevel(sunken: configuration.isPressed))
            }
            configuration.label
                .font(.custom("Arial Narrow", size: 12))
                .minimumScaleFactor(0.70)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: exit ? .center : .leading)
        }
        .padding(.horizontal, 3)
        .frame(height: 26)
        .foregroundStyle(exit ? Color.black : Color(white: enabled ? 0.83 : 0.53))
        .background {
            if exit {
                LinearGradient(colors: [.white, PresetChrome.panel, Color(white: 0.48)], startPoint: .top, endPoint: .bottom)
            } else { PresetChrome.dark }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .modifier(PresetBevel(sunken: configuration.isPressed))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black, lineWidth: 1))
        .opacity(enabled ? 1 : 0.60)
        .contentShape(Rectangle())
    }
}

struct PresetChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(.linearGradient(colors: selected ? [Color.yellow, Color(red: 0.86, green: 0.77, blue: 0.15)] : [.white, PresetChrome.panel, Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 18, height: 18)
                    .modifier(PresetBevel(sunken: true))
                Text(title).font(.custom("Arial", size: 12)).foregroundStyle(selected ? Color.yellow : Color(white: 0.8))
            }.padding(.horizontal, 5).frame(height: 26)
                .background(PresetChrome.dark).clipShape(RoundedRectangle(cornerRadius: 2))
                .modifier(PresetBevel())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(selected ? "Geselecteerd" : "Niet geselecteerd")
    }
}
