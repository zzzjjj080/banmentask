import SwiftUI

/// 「時計ではこう見えます」のプレビュー。
/// 中央の横長スロットが盤面タスク。周りの日付・時刻・下段3つは雰囲気用のダミー。
/// 横長スロットの描画ルールは実際のウィジェットと同じ（2行同じフォント、長い方に合わせて一緒に縮む）。
///
/// **腕時計の実物を描かないこと。** バンド・竜頭・側面ボタン・金属ケースは描かない。
/// 1.0 (2) はアイコンが Apple Watch に似ているとして 5.2.5 で却下された（引き継ぎ書 4-107）。
/// ここは「画面のプレビュー」に留め、機種が分かる装飾は付けない。
struct WatchMockView: View {
    let lines: [FaceLine]
    let layout: FaceLayout

    private let caseW: CGFloat = 232
    private let caseH: CGFloat = 282
    private let screenW: CGFloat = 206
    private let screenH: CGFloat = 256

    var body: some View {
        ZStack {
            bezel
            screen
        }
        .frame(width: caseW, height: caseH)
    }

    // MARK: - 枠

    /// 画面のまわりの黒い縁だけ。機種の分かる形にはしない
    private var bezel: some View {
        RoundedRectangle(cornerRadius: 46, style: .continuous)
            .fill(Color(white: 0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(Color(white: 0.28), lineWidth: 1)
            )
            .frame(width: caseW, height: caseH)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
    }

    // MARK: - 画面

    private var screen: some View {
        RoundedRectangle(cornerRadius: 42, style: .continuous)
            .fill(.black)
            .frame(width: screenW, height: screenH)
            .overlay(face.padding(.horizontal, 14).padding(.vertical, 16))
            .overlay(
                // ガラスの映り込み
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .clear],
                                         startPoint: .topLeading, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
    }

    /// インフォグラフ モジュラー風
    private var face: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                dateComplication
                Spacer()
                Text(Date.now, style: .time)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 6)
            rectangularSlot
            Spacer(minLength: 6)
            HStack {
                activityRings
                Spacer()
                gauge(value: 0.62, tint: .cyan, label: "22°")
                Spacer()
                gauge(value: 0.87, tint: .green, label: "87")
            }
            .padding(.horizontal, 2)
        }
    }

    private var dateComplication: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
            Text(Date.now.formatted(.dateTime.day()))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    /// 盤面タスクの横長スロット。実際のウィジェットと同じ描画ルール。
    private var rectangularSlot: some View {
        (lines.isEmpty ? Text("タスクなし").foregroundStyle(Color(white: 0.5)) : FaceStyle.coloredText(lines, layout: layout))
            .font(.system(size: 18, weight: .semibold))
            .lineLimit(max(1, lines.count))
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 96, alignment: .leading)
            .padding(.horizontal, 10)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var activityRings: some View {
        ZStack {
            ring(0.75, color: .red, radius: 20, width: 5)
            ring(0.55, color: .green, radius: 14, width: 5)
            ring(0.9, color: .cyan, radius: 8, width: 5)
        }
        .frame(width: 44, height: 44)
    }

    private func ring(_ value: Double, color: Color, radius: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: width)
            Circle()
                .trim(from: 0, to: value)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    private func gauge(value: Double, tint: Color, label: String) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: value)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }
}
