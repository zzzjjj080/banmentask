import SwiftUI

/// 画面のいちばん下（接続の情報の下）に置く「コーヒーを奢る」。
///
/// 正本は `~/Claude/shared/TipJar/CoffeeTip-Akiwaku.swift.txt`。
/// この画面は黒地・独自レイアウトなので、`Form` 用の `Section` 版ではなくこちらを下敷きにした。
/// 送っても機能は変わらない。「寄付」「Donation」とは書かない。
struct CoffeeTipSection: View {
    @Bindable var tipJar: TipJar

    private let tint = Color.orange
    private let dim = Color(white: 0.55)
    private let fill = Color(white: 0.09)
    private let edge = Color(white: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("このアプリが気に入ったら")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(dim)
                .tracking(1.5)

            switch tipJar.state {
            case .thanks:
                thanks
            case .failed(let message):
                notice(message, color: .red)
                closeButton
            case .unavailable:
                notice("いまは受け付けられません", color: dim)
            default:
                button
            }

            gratitude
        }
        .task { await tipJar.load() }
        // 購入が通った瞬間だけ鳴らす。承認待ちが後から届く場合もここを通る。
        .onChange(of: tipJar.cups) { _, _ in Haptic.success() }
    }

    private var button: some View {
        Button {
            Haptic.confirm()
            Task { await tipJar.tip() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.body)
                    .foregroundStyle(tint)
                Text("開発者にコーヒーを奢る")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                if let price = tipJar.displayPrice {
                    Text(price)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                } else {
                    ProgressView().controlSize(.small).tint(dim)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(14)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.55), lineWidth: 1))
            // Spacer は描画を持たないので、これが無いと余白を押しても反応しない
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tipJar.canTip || tipJar.state == .purchasing)
        .accessibilityIdentifier("buyCoffee")
    }

    private var thanks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("ありがとうございます", systemImage: "cup.and.saucer.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            closeButton
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(edge, lineWidth: 1))
    }

    /// 奢ってくれた人にだけ出すお礼。消耗型は復元されないので、機種変更で消える。
    /// 消えても嘘にはならない書き方にしてある。
    @ViewBuilder
    private var gratitude: some View {
        switch tipJar.cups {
        case 0:
            EmptyView()
        case 1:
            Text("奢ってくれてありがとうございました")
                .font(.caption).foregroundStyle(tint)
        default:
            Text("\(tipJar.cups) 回も奢ってくれてありがとうございました")
                .font(.caption).foregroundStyle(tint)
        }
    }

    private var closeButton: some View {
        Button("閉じる") {
            Haptic.tap()
            tipJar.dismissThanks()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
    }

    private func notice(_ text: String, color: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(color)
    }
}
