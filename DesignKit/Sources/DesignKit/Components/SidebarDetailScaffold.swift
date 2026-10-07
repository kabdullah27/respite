import SwiftUI

/// Scaffold window utama — pola sidebar+detail native Mac, dipake di semua app
/// yang punya lebih dari 1 "modul"/section, bukan single-page dashboard.
public struct SidebarDetailScaffold<Sidebar: View, Detail: View>: View {
    let sidebar: Sidebar
    let detail: Detail

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.detail = detail()
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }
}
