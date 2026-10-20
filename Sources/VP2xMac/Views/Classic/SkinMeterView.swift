import SwiftUI
import VP2xCore

/// Only this small view subscribes to the 30 Hz meter store.
struct SkinMeterView: View {
    let item: SkinControl
    @ObservedObject var meters: MeterStore
    private var raw: Int? { item.controller.flatMap { meters.values[$0] } }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: item.horizontal ? .leading : .bottom) {
                SkinImage(name: item.off)
                SkinImage(name: item.on)
                    .mask(alignment: item.horizontal ? .leading : .bottom) {
                        Rectangle().frame(width: item.horizontal ? geo.size.width * fraction : geo.size.width,
                                          height: item.horizontal ? geo.size.height : geo.size.height * fraction)
                    }
            }
        }.accessibilityLabel(item.name).accessibilityValue(raw.map(String.init) ?? "Offline")
    }
    private var fraction: Double {
        MeterScale.overlayFraction(raw: raw, controller: item.controller ?? 0,
                                   invertedArtwork: item.inverted)
    }
}

struct DeviceLogView: View {
    @ObservedObject var activity: DeviceActivity
    var body: some View {
        ScrollView {
            Text(activity.entries.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
