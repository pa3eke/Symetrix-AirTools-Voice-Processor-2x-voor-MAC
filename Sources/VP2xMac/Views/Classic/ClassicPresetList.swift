import SwiftUI
import VP2xCore

struct ClassicPresetList: View {
    let title: String
    let entries: [ChannelPreset]
    @Binding var selection: Int?
    let accessibilityName: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !title.isEmpty { Text(title).font(.custom("Arial", size: 14)) }
            ScrollViewReader { reader in
            List(selection: $selection) {
                ForEach(entries) { preset in
                    Text("\(preset.name) (P\(String(format: "%02d", preset.slot)))")
                        .font(.custom("Arial", size: 16).weight(.bold))
                        .foregroundStyle(selection == preset.slot ? Color.white : preset.isEmpty ? Color(white: 0.60) : PresetChrome.cyan)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        .tag(preset.slot).id(preset.slot).help(preset.name)
                        .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
                        .listRowSeparator(.hidden)
                        .listRowBackground(selection == preset.slot ? Color(red: 0, green: 0.42, blue: 0.86) : PresetChrome.dark)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 19)
                .background(PresetChrome.dark).modifier(PresetBevel(sunken: true))
                .accessibilityLabel(accessibilityName)
                .onAppear { if let selection { reader.scrollTo(selection, anchor: .center) } }
            }
        }
    }
}
