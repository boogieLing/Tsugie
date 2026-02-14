import SwiftUI

struct CalendarPlaceholderView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("時めぐり")
                    .font(.largeTitle.weight(.bold))
                Text("日历页是时间维度语义，与地图页的位置维度语义独立。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("第一阶段仅保留独立页面占位，后续阶段接入完整月历与当日抽屉。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        onClose()
                    }
                }
            }
        }
    }
}
