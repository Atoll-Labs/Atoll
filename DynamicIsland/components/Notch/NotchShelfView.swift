
import SwiftUI

struct NotchShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel

    var body: some View {
        ShelfView()
            .environmentObject(vm)
    }
}

