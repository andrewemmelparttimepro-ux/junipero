import SwiftUI

// Kept as a minimal struct so existing references compile.
// The left panel now shows status inline — this is effectively unused
// but harmless to keep around.

struct HermesStatusWidget: View {
    @EnvironmentObject private var bootstrap: HermesBootstrap

    var body: some View {
        EmptyView()
    }
}
