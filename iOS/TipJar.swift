import Foundation
import Observation
import StoreKit

/// 「コーヒーを奢る」ボタンの窓口。
///
/// 消耗型（Consumable）なので何度でも送れる。送ってもアプリの機能は変わらない。
/// 累計の杯数だけ端末内に残す。**StoreKitは消耗型を復元しないので、
/// 機種変更や再インストールで杯数は0に戻る。** UIには「この端末で」と書くこと。
///
/// 使い方:
/// ```swift
/// @State private var tipJar = TipJar(productID: "com.zzzjjj080.Jansan.coffee")
/// ```
@MainActor
@Observable
final class TipJar {
    enum State: Equatable {
        case idle
        case loading
        /// 製品が取れなかった。App Store Connect側が未登録か、通信できていない
        case unavailable
        case purchasing
        case thanks
        case failed(String)
    }

    /// App Store Connect で作る製品ID。向こうと1文字でも違うと `unavailable` になる
    let productID: String

    private(set) var product: Product?
    private(set) var state: State = .idle

    /// この端末での累計杯数
    private(set) var cups: Int

    private let defaults: UserDefaults
    private let cupsKey = "tipjar.cups"
    private var updates: Task<Void, Never>?

    init(productID: String, defaults: UserDefaults = .standard) {
        self.productID = productID
        self.defaults = defaults
        self.cups = defaults.integer(forKey: cupsKey)
    }

    /// 表示する金額はStoreKitが返すものをそのまま使う。
    /// 国によって価格も通貨も変わるため、アプリ側で「¥200」と決め打ちしてはいけない
    var displayPrice: String? { product?.displayPrice }

    /// 画面が出るタイミングで呼ぶ。2回目以降は何もしない
    func load() async {
        startListening()
        await finishUnfinished()

        guard product == nil, state != .loading else { return }
        state = .loading
        do {
            product = try await Product.products(for: [productID]).first
            state = product == nil ? .unavailable : .idle
        } catch {
            state = .unavailable
        }
    }

    func tip() async {
        guard let product else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    state = .failed("購入を確認できませんでした")
                    return
                }
                await record(transaction)
                state = .thanks
            case .userCancelled:
                state = .idle
            case .pending:
                // ファミリー共有の購入承認待ちなど。完了は Transaction.updates から後で届く
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed("購入できませんでした")
        }
    }

    func dismissThanks() {
        state = .idle
    }

    /// 画面を閉じるときなどに呼ぶ。呼ばなくても害はない
    func stopListening() {
        updates?.cancel()
        updates = nil
    }

    // MARK: - 取引の後始末

    /// 承認待ちだった購入や、アプリが落ちて finish できなかった分がここに届く
    private func startListening() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.record(transaction)
            }
        }
    }

    /// 前回 finish しそこねた取引を拾う。放置すると毎回 updates に流れ続ける
    private func finishUnfinished() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            await record(transaction)
        }
    }

    /// 消耗型は finish を呼ばないと未処理の取引として残り続ける
    private func record(_ transaction: Transaction) async {
        if transaction.productID == productID, transaction.revocationDate == nil {
            cups += 1
            defaults.set(cups, forKey: cupsKey)
        }
        await transaction.finish()
    }
}
