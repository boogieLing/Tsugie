import SwiftUI

struct CalendarPlaceholderView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Placeholder.title)
                    .font(.largeTitle.weight(.bold))
                Text(L10n.Placeholder.desc1)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(L10n.Placeholder.desc2)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TsugieClosePillButton(action: onClose, accessibilityLabel: L10n.Common.close)
                }
            }
        }
    }
}
