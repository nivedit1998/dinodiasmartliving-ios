import SwiftUI

struct DinodiaNavBarLogo: View {
    var body: some View {
        Image("DinodiaNavBarLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
            .accessibilityLabel("Dinodia")
    }
}
