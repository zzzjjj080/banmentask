import SwiftUI

/// 「時計ではこう見えます」のプレビュー。
/// Apple Watch（ステンレスケース＋黒バンド）の中に、インフォグラフ モジュラー風の文字盤を描く。
/// 中央の横長スロットが盤面タスク。周りの日付・時刻・下段3つは雰囲気用のダミー。
/// 横長スロットの描画ルールは実際のウィジェットと同じ（2行同じフォント、長い方に合わせて一緒に縮む）。
struct WatchMockView: View {
    let lines: [FaceLine]
    let layout: FaceLayout

    private let caseW: CGFloat = 232
    private let caseH: CGFloat = 282
    private let screenW: CGFloat = 206
    private let screenH: CGFloat = 256

    var body: some View {
        ZStack {
            band
            watchCase
            crownAndButton
            screen
        }
        .frame(width: caseW + 40, height: caseH + 60)
    }

    // MARK: - 筐体

    private var band: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08), Color(white: 0.14)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 128, height: caseH + 60)
    }

    private var watchCase: some View {
        RoundedRectangle(cornerRadius: 54, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.55), Color(white: 0.30)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1.5)
            )
            .overlay(
                // ベゼルとガラスの境目
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.55), lineWidth: 5)
                    .padding(7)
            )
            .frame(width: caseW, height: caseH)
            .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
    }

    private var crownAndButton: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.45)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 12, height: 44)
                .overlay(Rectangle().fill(.red.opacity(0.85)).frame(width: 2).offset(x: 3))
                .offset(x: caseW / 2 + 4, y: -56)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.4)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 8, height: 58)
                .offset(x: caseW / 2 + 2, y: 18)
        }
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
