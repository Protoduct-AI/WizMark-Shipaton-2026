#if DEBUG
import Foundation
import SwiftData
import os

/// Fills a debug build with believable data for demos and screenshots.
///
///     xcrun simctl launch <udid> com.protoductai.wizmark -seedDemoData
///
/// Everything here is invented. URLs point at example.com, which RFC 2606
/// reserves for exactly this purpose, and no third-party title, description or
/// image is reproduced — so the result can be recorded and published without
/// borrowing anyone's content. Bookmarks carry pre-filled AI fields rather than
/// calling the extraction service, which keeps a recording deterministic and
/// costs nothing.
///
/// Seeding is skipped when collections already exist, so a rerun does not
/// duplicate anything.
enum DemoSeed {

    private static let logger = Logger(subsystem: "com.protoductai.wizmark", category: "DemoSeed")

    /// Remembered across launches so a UI runner can relaunch between scenes
    /// without the app falling back to the first-run flow. Reinstalling clears it.
    static var isRequested: Bool {
        let key = "debug_demo_seeded"
        let store = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-seedDemoData") {
            store.set(true, forKey: key)
            return true
        }
        return store.bool(forKey: key)
    }

    @MainActor
    static func seedIfRequested(into context: ModelContext) {
        guard isRequested else { return }

        // A demo starts from an app already in use, so the first-run flow is
        // marked done rather than being clicked through on every recording.
        Storage.set(true, for: .hasCompletedOnboarding)

        let existing = (try? context.fetch(FetchDescriptor<BookmarkCollection>())) ?? []
        guard existing.isEmpty else {
            logger.info("Demo seed skipped: \(existing.count) collection(s) already present")
            return
        }

        for spec in specs {
            let collection = BookmarkCollection(
                name: spec.name,
                icon: spec.icon,
                color: spec.color
            )
            context.insert(collection)

            for (index, entry) in spec.bookmarks.enumerated() {
                let bookmark = entry.build(order: index)
                bookmark.collection = collection
                context.insert(bookmark)
            }
        }

        do {
            try context.save()
            logger.info("Demo seed inserted \(specs.count) collection(s)")
        } catch {
            logger.error("Demo seed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Downloads a photo once and returns a local file URL for it.
    ///
    /// Wikimedia answers 403 to requests without a User-Agent, and `AsyncImage`
    /// does not let one be set — so the cards sat on spinners. Fetching here
    /// with a proper header and handing SwiftUI a file URL also means the demo
    /// works with the network off.
    @MainActor
    private static func localCopy(of remote: String) -> String? {
        guard let url = URL(string: remote) else { return nil }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("demo-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent(String(abs(remote.hashValue)) + ".jpg")
        if FileManager.default.fileExists(atPath: file.path) {
            return file.absoluteString
        }

        var request = URLRequest(url: url)
        request.setValue(
            "WizMark-Demo/1.0 (https://wizmark.protoductai.com)",
            forHTTPHeaderField: "User-Agent"
        )

        // Seeding runs once at launch before anything is on screen, so a short
        // synchronous fetch is simpler than threading async through the seed.
        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            payload = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 15)

        guard let payload, (try? payload.write(to: file)) != nil else {
            logger.error("Demo photo fetch failed: \(remote, privacy: .public)")
            return nil
        }
        return file.absoluteString
    }

    /// Photos for the seeded bookmarks.
    ///
    /// A random photo service was tried first and produced a train carriage on
    /// a café bookmark, which reads as a bug rather than a demo. These are
    /// picked to match what each bookmark is about.
    ///
    /// All are CC0 or public domain on Wikimedia Commons: usable commercially,
    /// no attribution required, no share-alike obligation to carry into a
    /// recording.
    private enum Photo {
        static let coffee = commons(
            "9/90/Close-up_of_Woman_Holding_Coffee_Cup_at_Cafe_%2828217840617%29.jpg",
            "Close-up_of_Woman_Holding_Coffee_Cup_at_Cafe_%2828217840617%29.jpg"
        )
        static let cafeTable = commons(
            "7/7e/Cup_of_coffee_in_Caf%C3%A9_Butter_-_Prenzlauer_Berg%2C_Berlin.jpg",
            "Cup_of_coffee_in_Caf%C3%A9_Butter_-_Prenzlauer_Berg%2C_Berlin.jpg"
        )
        static let pastry = commons(
            "6/62/Cronut_at_Sweet_Pea_Bake_Shop_-_Feburary_2026_-_Sarah_Stierch.jpg",
            "Cronut_at_Sweet_Pea_Bake_Shop_-_Feburary_2026_-_Sarah_Stierch.jpg"
        )
        static let pasta = commons(
            "d/d0/Pasta_%281%29.jpg",
            "Pasta_%281%29.jpg"
        )
        static let misoSoup = commons(
            "3/34/JP_%E6%97%A5%E6%9C%AC_Japan_%E4%BA%AC%E9%83%BD_Kyoto_%E5%9B%9B%E6%A2%9D_Shijo_side_Sukiya_Restaurant_food_%E6%97%A5%E6%9C%AC%E9%BA%B5%E8%B1%89%E6%B9%AF_Miso_soup_bowl_June_2026_N13P_01.jpg",
            "JP_%E6%97%A5%E6%9C%AC_Japan_%E4%BA%AC%E9%83%BD_Kyoto_%E5%9B%9B%E6%A2%9D_Shijo_side_Sukiya_Restaurant_food_%E6%97%A5%E6%9C%AC%E9%BA%B5%E8%B1%89%E6%B9%AF_Miso_soup_bowl_June_2026_N13P_01.jpg"
        )
        static let bookshelf = commons(
            "1/16/Public_Bookcase_-_Park_Komensk%C3%A9ho_East%2C_Ko%C5%A1ice%2C_SK.jpg",
            "Public_Bookcase_-_Park_Komensk%C3%A9ho_East%2C_Ko%C5%A1ice%2C_SK.jpg"
        )
        static let publicBookcase = commons(
            "4/45/Public_Bookcase_Tiensesteenweg.jpg",
            "Public_Bookcase_Tiensesteenweg.jpg",
            scaled: false
        )

        /// Commons serves a scaled rendition under /thumb/<path>/<width>px-<file>.
        /// Some originals have no rendition, hence `scaled`.
        private static func commons(
            _ path: String,
            _ file: String,
            scaled: Bool = true
        ) -> String {
            let base = "https://upload.wikimedia.org/wikipedia/commons"
            return scaled
                ? "\(base)/thumb/\(path)/1280px-\(file)"
                : "\(base)/\(path)"
        }
    }

    // MARK: - Content

    private struct CollectionSpec {
        let name: String
        let icon: String?
        let color: String?
        let bookmarks: [BookmarkSpec]
    }

    private struct BookmarkSpec {
        let url: String
        let title: String
        let description: String
        let siteName: String
        let tags: [String]
        /// Photo shown on the card. See `Photo`.
        var image: String? = nil
        var summary: String? = nil
        var category: String? = nil
        var placeName: String? = nil
        var placeAddress: String? = nil
        var businessHours: String? = nil
        var phoneNumber: String? = nil
        var recipe: String? = nil
        var rating: String? = nil
        /// A round-up page: several places on one bookmark.
        var places: [ExtractedPlace] = []
        var note: String? = nil
        /// Seeds a failed extraction so the error state can be seen.
        var failure: String? = nil
        var daysAgo: Int = 0

        @MainActor
        func build(order: Int) -> Bookmark {
            let bookmark = Bookmark(url: url, title: title, description: description)
            bookmark.thumbnailUrl = image.flatMap(DemoSeed.localCopy(of:))
            bookmark.siteName = siteName
            bookmark.tags = tags
            bookmark.displayOrder = order
            bookmark.createdAt = Calendar.current.date(
                byAdding: .day, value: -daysAgo, to: Date()
            ) ?? Date()
            bookmark.updatedAt = bookmark.createdAt

            bookmark.aiSummary = summary
            bookmark.aiCategory = category
            bookmark.aiPlaceName = placeName
            bookmark.aiPlaceAddress = placeAddress
            bookmark.aiBusinessHours = businessHours
            bookmark.aiPhoneNumber = phoneNumber
            bookmark.aiRecipe = recipe
            bookmark.aiRating = rating
            if !places.isEmpty {
                bookmark.extractedPlaces = places
            }
            bookmark.note = note
            if let failure {
                bookmark.aiStatus = "failed"
                bookmark.aiError = failure
                bookmark.aiEnrichedAt = bookmark.createdAt
            } else if summary != nil || placeName != nil || recipe != nil {
                bookmark.aiStatus = "done"
                bookmark.aiEnrichedAt = bookmark.createdAt
            }
            return bookmark
        }
    }

    private static let specs: [CollectionSpec] = [
        CollectionSpec(
            name: "行きたいカフェ",
            icon: "cup.and.saucer.fill",
            color: "#E8833A",
            bookmarks: [
                BookmarkSpec(
                    url: "https://example.com/cafe/kohaku",
                    title: "焙煎室のある喫茶 琥珀",
                    description: "自家焙煎の深煎りと、日替わりの焼き菓子。",
                    siteName: "example.com",
                    tags: ["カフェ", "自家焙煎"],
                    image: Photo.coffee,
                    summary: "駅から徒歩7分の自家焙煎店。深煎りのブレンドと日替わりの焼き菓子が看板で、平日昼は比較的空いている。",
                    category: "カフェ",
                    placeName: "焙煎室のある喫茶 琥珀",
                    placeAddress: "東京都渋谷区神南1-19-11",
                    businessHours: "9:00〜18:00（水曜定休）",
                    phoneNumber: "03-0000-0000",
                    rating: "4.3 / 5",
                    daysAgo: 1
                ),
                BookmarkSpec(
                    url: "https://example.com/cafe/hakoniwa",
                    title: "本と珈琲 箱庭",
                    description: "蔵書1万冊。長居のできる読書向きの席。",
                    siteName: "example.com",
                    tags: ["カフェ", "読書"],
                    image: Photo.bookshelf,
                    summary: "蔵書を自由に読める喫茶店。電源席が6席あり作業にも向く。ランチは平日限定。",
                    category: "カフェ",
                    placeName: "本と珈琲 箱庭",
                    placeAddress: "東京都目黒区青葉台1-14-5",
                    businessHours: "11:00〜21:00（無休）",
                    daysAgo: 3
                ),
                BookmarkSpec(
                    url: "https://example.com/cafe/roundup",
                    title: "休日に行きたい街の喫茶 3選",
                    description: "一日で回れる距離にある、雰囲気の違う3軒。",
                    siteName: "example.com",
                    tags: ["カフェ", "まとめ"],
                    image: Photo.cafeTable,
                    summary: "徒歩と電車で一日で回れる3軒をまとめた記事。焙煎、蔵書、焼き菓子とそれぞれ性格が違う。",
                    category: "カフェ",
                    places: [
                        ExtractedPlace(
                            name: "焙煎室のある喫茶 琥珀",
                            address: "東京都渋谷区神南1-19-11",
                            phone: "03-0000-0000",
                            hours: "9:00〜18:00（水曜定休）",
                            rating: "4.3 / 5"
                        ),
                        ExtractedPlace(
                            name: "本と珈琲 箱庭",
                            address: "東京都目黒区青葉台1-14-5",
                            hours: "11:00〜21:00（無休）",
                            rating: "4.1 / 5"
                        ),
                        ExtractedPlace(
                            name: "朝市とスコーン",
                            address: "神奈川県鎌倉市小町2-10-4",
                            hours: "土日 8:00〜13:00"
                        ),
                    ],
                    daysAgo: 0
                ),
                BookmarkSpec(
                    url: "https://example.com/cafe/asaichi",
                    title: "朝市とスコーン",
                    description: "土日のみ営業。焼きたてを朝8時から。",
                    siteName: "example.com",
                    tags: ["カフェ", "週末"],
                    image: Photo.pastry,
                    summary: "週末限定のベーカリーカフェ。8時開店で、昼前には売り切れることが多い。",
                    category: "カフェ",
                    placeName: "朝市とスコーン",
                    placeAddress: "神奈川県鎌倉市小町2-10-4",
                    businessHours: "土日 8:00〜13:00",
                    note: "次の土曜、開店直後に行く",
                    daysAgo: 5
                ),
            ]
        ),
        CollectionSpec(
            name: "作りたいレシピ",
            icon: "fork.knife",
            color: "#3AA76D",
            bookmarks: [
                BookmarkSpec(
                    url: "https://example.com/recipe/tomato-pasta",
                    title: "30分でできる基本のトマトパスタ",
                    description: "材料5つ。平日の夜に作れる分量で。",
                    siteName: "example.com",
                    tags: ["レシピ", "パスタ"],
                    image: Photo.pasta,
                    summary: "トマト缶を使った基本のパスタ。にんにくを弱火で温めるところから始め、全体で30分。",
                    category: "レシピ",
                    recipe: "材料（2人分）\nスパゲッティ 200g / トマト缶 1缶 / にんにく 2片 / オリーブオイル 大さじ2 / 塩\n\n手順\n1. にんにくを薄切りにし、弱火で香りを出す\n2. トマト缶を加えて10分煮る\n3. 表示より1分短く茹でた麺を和える",
                    daysAgo: 2
                ),
                BookmarkSpec(
                    url: "https://example.com/recipe/miso-soup",
                    title: "だしから作るきのこの味噌汁",
                    description: "冷蔵で3日もつ、だしの取り置き付き。",
                    siteName: "example.com",
                    tags: ["レシピ", "和食"],
                    image: Photo.misoSoup,
                    summary: "昆布と鰹のだしを一度に多めに取り、3日分を作り置きする手順。きのこは3種を混ぜる。",
                    category: "レシピ",
                    recipe: "材料（4人分）\n昆布 10g / 削り節 20g / きのこ3種 200g / 味噌 大さじ4\n\n手順\n1. 昆布を30分水に浸す\n2. 沸騰直前で昆布を取り出し、削り節を加えて火を止める\n3. きのこを煮て、火を止めてから味噌を溶く",
                    daysAgo: 6
                ),
            ]
        ),
        CollectionSpec(
            name: "あとで読む",
            icon: "book.fill",
            color: "#4C7DF0",
            bookmarks: [
                BookmarkSpec(
                    url: "https://example.com/notes/typography",
                    title: "画面の中の文字組みについて",
                    description: "行間と字間を決めるときの手がかり。",
                    siteName: "example.com",
                    tags: ["デザイン", "タイポグラフィ"],
                    image: Photo.cafeTable,
                    summary: "本文の行間は文字サイズの1.5〜1.7倍を起点に、行長に応じて調整するという指針をまとめた記事。",
                    category: "デザイン",
                    daysAgo: 4
                ),
                BookmarkSpec(
                    url: "https://example.com/notes/offline",
                    title: "解析が終わらなかった記事",
                    description: "保存はできているが、AI 解析だけが失敗している状態。",
                    siteName: "example.com",
                    tags: ["技術"],
                    failure: "通信できませんでした。接続を確認して、もう一度お試しください。",
                    daysAgo: 1
                ),
                BookmarkSpec(
                    url: "https://example.com/notes/sqlite",
                    title: "小さなデータベースの選び方",
                    description: "端末内に置くデータの持ち方を比べる。",
                    siteName: "example.com",
                    tags: ["技術", "データベース"],
                    image: Photo.publicBookcase,
                    summary: "端末内保存の選択肢を、書き込み頻度・同期の有無・移行のしやすさの3点で比較している。",
                    category: "技術",
                    daysAgo: 8
                ),
            ]
        ),
    ]
}
#endif
