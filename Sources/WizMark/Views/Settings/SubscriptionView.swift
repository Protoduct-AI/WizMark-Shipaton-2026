import RevenueCat
import StoreKit
import SwiftUI

struct SubscriptionView: View {

    @Environment(AppServices.self) private var services
    @State private var isPurchasing = false
    @State private var error: String?
    @State private var showRestoreSuccess = false
    @State private var storeProducts: [String: Product] = [:]

    private var purchaseService: PurchaseService { services.purchases }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                if purchaseService.isSubscribed {
                    subscribedBadge
                } else {
                    featuresSection
                    packagesSection
                }
                adFreeSection
                restoreSection
            }
            .padding()
        }
        .navigationTitle("WizMark Pro")
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "subscription.errorTitle", defaultValue: "エラー"), isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            if let error { Text(error) }
        }
        .alert(String(localized: "subscription.restoreCompleteTitle", defaultValue: "復元完了"), isPresented: $showRestoreSuccess) {
            Button("OK") {}
        } message: {
            Text(String(localized: "subscription.restoreCompleteMessage", defaultValue: "購入履歴が復元されました"))
        }
        .task {
            if !purchaseService.isInitialized {
                await purchaseService.configure()
            }
            await loadStoreProducts()
        }
    }

    private func loadStoreProducts() async {
        let ids = ["wizmark_pro_annual", "wizmark_pro_monthly", "wizmark_ad_free"]
        guard let products = try? await Product.products(for: ids) else { return }
        for p in products {
            storeProducts[p.id] = p
        }
    }

    private func localizedPrice(for productId: String, fallback: String) -> String {
        storeProducts[productId]?.displayPrice ?? fallback
    }

    private func freeTrialText(weeks: Int) -> String {
        String(localized: "subscription.freeTrial.weeks \(weeks)")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            HStack(spacing: 0) {
                Text("WizMark")
                    .font(.custom("BlackOpsOne-Regular", size: 28))
                    .overlay {
                        LinearGradient(
                            colors: [.blue, .purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask {
                            Text("WizMark")
                                .font(.custom("BlackOpsOne-Regular", size: 28))
                        }
                    }
                Text(" Pro")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            Text(String(localized: "subscription.subtitle", defaultValue: "全機能開放・広告非表示・AI無制限"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Subscribed

    private var subscribedBadge: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(String(localized: "subscription.subscribedBadge", defaultValue: "Pro プランに加入中"))
                .font(.headline)
            if let info = purchaseService.customerInfo,
               let expiration = info.entitlements["pro"]?.expirationDate {
                Text(String(localized: "subscription.nextRenewal", defaultValue: "次回更新: \(expiration.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "eye.slash.fill", color: .yellow, title: String(localized: "subscription.feature.adFree", defaultValue: "広告非表示"), description: String(localized: "subscription.feature.adFree.description", defaultValue: "すべての広告を完全に削除"))
            Divider()
            featureRow(icon: "sparkles", color: .purple, title: String(localized: "subscription.feature.aiSummary", defaultValue: "AI 要約・タグ自動生成"), description: String(localized: "subscription.feature.aiSummary.description", defaultValue: "ブックマークの内容をAIが自動分析"))
            featureRow(icon: "mappin.and.ellipse", color: .purple, title: String(localized: "subscription.feature.placeExtraction", defaultValue: "店名・住所・電話番号の抽出"), description: String(localized: "subscription.feature.placeExtraction.description", defaultValue: "Google検索を活用して正確な情報を取得"))
            featureRow(icon: "clock", color: .purple, title: String(localized: "subscription.feature.businessHours", defaultValue: "営業時間・イベント日時"), description: String(localized: "subscription.feature.businessHours.description", defaultValue: "営業時間やイベント情報を自動抽出"))
            featureRow(icon: "star", color: .purple, title: String(localized: "subscription.feature.reviews", defaultValue: "レビュー評価の収集"), description: String(localized: "subscription.feature.reviews.description", defaultValue: "食べログ・Googleなど複数ソースの評価"))
            featureRow(icon: "fork.knife", color: .purple, title: String(localized: "subscription.feature.recipe", defaultValue: "レシピの自動抽出"), description: String(localized: "subscription.feature.recipe.description", defaultValue: "料理レシピを構造化して保存"))
            featureRow(icon: "folder.badge.gearshape", color: .purple, title: String(localized: "subscription.feature.autoClassify", defaultValue: "コレクション自動分類"), description: String(localized: "subscription.feature.autoClassify.description", defaultValue: "AIが最適なコレクションに自動振り分け"))
            Divider()
            featureRow(icon: "square.and.arrow.up", color: .yellow, title: String(localized: "subscription.feature.export", defaultValue: "データエクスポート"), description: String(localized: "subscription.feature.export.description", defaultValue: "JSON / CSV でデータ書き出し"))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Packages

    private var packagesSection: some View {
        VStack(spacing: 12) {
            let subscriptionPackages = purchaseService.offerings.filter { $0.packageType != .lifetime }
            if subscriptionPackages.isEmpty {
                fallbackPackageCard(title: String(localized: "subscription.plan.annual", defaultValue: "年間プラン"), price: localizedPrice(for: "wizmark_pro_annual", fallback: "¥9,800"), period: String(localized: "subscription.period.year", defaultValue: "/ 年"), badge: String(localized: "subscription.badge.recommended", defaultValue: "おすすめ・2ヶ月分お得"), productId: "wizmark_pro_annual", highlighted: true)
                fallbackPackageCard(title: String(localized: "subscription.plan.monthly", defaultValue: "月間プラン"), price: localizedPrice(for: "wizmark_pro_monthly", fallback: "¥980"), period: String(localized: "subscription.period.month", defaultValue: "/ 月"), productId: "wizmark_pro_monthly")
            } else {
                if !subscriptionPackages.contains(where: { $0.packageType == .annual }) {
                    fallbackPackageCard(title: String(localized: "subscription.plan.annual", defaultValue: "年間プラン"), price: localizedPrice(for: "wizmark_pro_annual", fallback: "¥9,800"), period: String(localized: "subscription.period.year", defaultValue: "/ 年"), badge: String(localized: "subscription.badge.recommended", defaultValue: "おすすめ・2ヶ月分お得"), productId: "wizmark_pro_annual", highlighted: true)
                }
                let sorted = subscriptionPackages.sorted { ($0.packageType == .annual ? 0 : 1) < ($1.packageType == .annual ? 0 : 1) }
                ForEach(sorted, id: \.identifier) { package in
                    packageCard(package)
                }
            }
        }
    }

    private func fallbackPackageCard(title: String, price: String, period: String, badge: String? = nil, productId: String = "", highlighted: Bool = false) -> some View {
        Button {
            Task { await purchaseWithStoreKit(productId: productId) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(highlighted ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(highlighted ? .yellow : Color.gray.opacity(0.5), in: .capsule)
                    }
                    Text(title)
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Text(period)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let product = storeProducts[productId],
                       let intro = product.subscription?.introductoryOffer,
                       intro.paymentMode == .freeTrial {
                        Text(freeTrialText(weeks: intro.period.value))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                if isPurchasing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }
            }
            .padding()
            .background(highlighted ? Color.yellow.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(highlighted ? Color.yellow : Color.yellow.opacity(0.3), lineWidth: highlighted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    private func packageCard(_ package: RevenueCat.Package) -> some View {
        Button {
            purchasePackage(package)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(packageTitle(package))
                        .font(.headline)
                    Text(package.localizedPriceString)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    if let intro = package.storeProduct.introductoryDiscount {
                        Text(String(localized: "subscription.introOffer", defaultValue: "最初の\(intro.subscriptionPeriod.value)\(periodUnit(intro.subscriptionPeriod.unit))は無料"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                if isPurchasing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    // MARK: - Ad Free

    @ViewBuilder
    private var adFreeSection: some View {
        if !purchaseService.shouldHideAds {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.slash.fill")
                                .foregroundStyle(.orange)
                            Text(String(localized: "subscription.adFree.title", defaultValue: "広告非表示"))
                                .font(.title3.bold())
                        }
                        Text(String(localized: "subscription.adFree.price", defaultValue: "\(localizedPrice(for: "wizmark_ad_free", fallback: "¥980"))（買い切り）"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(String(localized: "subscription.adFree.description", defaultValue: "一度の購入で広告を永久に非表示にします。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                adFreePurchaseButton
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            )
        } else if purchaseService.isAdFree && !purchaseService.isSubscribed {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(String(localized: "subscription.adFree.purchased", defaultValue: "広告非表示 購入済み"))
                    .font(.subheadline)
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var adFreePurchaseButton: some View {
        let adFreePackage = purchaseService.offerings.first { $0.packageType == .lifetime }
        if let adFreePackage {
            Button {
                purchasePackage(adFreePackage)
            } label: {
                HStack {
                    Text(String(localized: "subscription.adFree.purchaseButton", defaultValue: "\(adFreePackage.localizedPriceString) で広告を非表示にする"))
                        .font(.headline)
                    Spacer()
                    if isPurchasing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                }
                .padding()
                .foregroundStyle(.white)
                .background(.orange, in: .rect(cornerRadius: 12))
            }
            .disabled(isPurchasing)
        } else {
            Text(String(localized: "subscription.adFree.comingSoon", defaultValue: "近日公開予定"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }

    // MARK: - Restore

    private var restoreSection: some View {
        Button {
            restorePurchases()
        } label: {
            Text(String(localized: "subscription.restorePurchases", defaultValue: "以前の購入を復元"))
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func purchasePackage(_ package: RevenueCat.Package) {
        isPurchasing = true
        Task {
            do {
                try await purchaseService.purchase(package: package)
            } catch {
                self.error = error.localizedDescription
            }
            isPurchasing = false
        }
    }

    private func restorePurchases() {
        Task {
            do {
                try await purchaseService.restorePurchases()
                if purchaseService.isSubscribed || purchaseService.isAdFree {
                    showRestoreSuccess = true
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func purchaseWithStoreKit(productId: String) async {
        guard !productId.isEmpty else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                error = String(localized: "subscription.error.productNotFound", defaultValue: "商品が見つかりません。しばらくしてからお試しください。")
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified:
                    try await purchaseService.restorePurchases()
                case .unverified:
                    error = String(localized: "subscription.error.verificationFailed", defaultValue: "購入の検証に失敗しました")
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func packageTitle(_ package: RevenueCat.Package) -> String {
        switch package.packageType {
        case .weekly: return String(localized: "subscription.plan.weekly", defaultValue: "週間プラン")
        case .monthly: return String(localized: "subscription.plan.monthly", defaultValue: "月間プラン")
        case .twoMonth: return String(localized: "subscription.plan.twoMonth", defaultValue: "2ヶ月プラン")
        case .threeMonth: return String(localized: "subscription.plan.threeMonth", defaultValue: "3ヶ月プラン")
        case .sixMonth: return String(localized: "subscription.plan.sixMonth", defaultValue: "半年プラン")
        case .annual: return String(localized: "subscription.plan.annual", defaultValue: "年間プラン")
        case .lifetime: return String(localized: "subscription.plan.lifetime", defaultValue: "買い切り")
        default: return package.storeProduct.localizedTitle
        }
    }

    private func periodUnit(_ unit: RevenueCat.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return String(localized: "subscription.period.day", defaultValue: "日間")
        case .week: return String(localized: "subscription.period.week", defaultValue: "週間")
        case .month: return String(localized: "subscription.period.monthUnit", defaultValue: "ヶ月")
        case .year: return String(localized: "subscription.period.yearUnit", defaultValue: "年間")
        @unknown default: return ""
        }
    }
}
