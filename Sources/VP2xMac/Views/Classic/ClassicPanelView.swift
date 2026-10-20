import SwiftUI

struct ClassicPanelView: View {
    let panelID: Int
    @ObservedObject var device: DeviceStore
    let selectedPanel: Int
    let activate: (Int) -> Void
    var body: some View {
        if let panel = SkinLayout.shared.panel(panelID) {
            ZStack(alignment: .topLeading) {
                SkinImage(name: panel.background).frame(width: panel.width, height: panel.height)
                // The shipped output bitmap contains an unused Dante section;
                // this VP2x exposes analog/AES3 only. Hide the entire unused box.
                if panelID == 18 || panelID == 19 {
                    Rectangle().fill(Color(red: 0.6862745, green: 0.6784314, blue: 0.6549020))
                        .frame(width: 114, height: 108).offset(x: 129, y: 234)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                ForEach(panel.controls) { item in
                    if item.kind == "Graph" {
                        ClassicResponseGraph(panelID: panelID, device: device)
                            .frame(width: item.width, height: item.height)
                            .offset(x: item.x, y: item.y)
                    } else {
                        SkinControlView(item: item, device: device, selectedPanel: selectedPanel, activate: activate)
                            .offset(x: item.x, y: item.y)
                    }
                }
            }.frame(width: panel.width, height: panel.height, alignment: .topLeading)
        }
    }
}
