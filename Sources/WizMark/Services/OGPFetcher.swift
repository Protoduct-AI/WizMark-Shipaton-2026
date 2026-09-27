import Foundation
import os

actor OGPFetcher {

    static let shared = OGPFetcher()

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "OGPFetcher")

    struct OGPData {
        var title: String?
        var description: String?
        var imageUrl: String?
        var siteName: String?
        var favicon: String?
    }

    func fetch(url urlString: String) async -> OGPData {
        // 1. Try platform-specific oEmbed
        if let oembed = await fetchOEmbed(url: urlString), oembed.title != nil {
            return oembed
        }
        // 2. Try HTML meta tag parsing
        let html = await fetchHTML(url: urlString)
        if html.title != nil { return html }
        // 3. Fallback: noembed.com (free oEmbed proxy, handles many sites)
        if let noembed = await fetchNoembed(url: urlString) {
            return noembed
        }
        // 4. Fallback: Microlink API (renders JS, extracts metadata)
        if let microlink = await fetchMicrolink(url: urlString) {
            return microlink
        }
        return html
    }

    // MARK: - oEmbed (YouTube, TikTok, X/Twitter)

    private func fetchOEmbed(url: String) async -> OGPData? {
        let lowered = url.lowercased()

        var oembedUrl: String?

        if lowered.contains("youtube.com/watch") || lowered.contains("youtu.be/") {
            oembedUrl = "https://www.youtube.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)&format=json"
        } else if lowered.contains("tiktok.com/") {
            oembedUrl = "https://www.tiktok.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)"
        } else if lowered.contains("x.com/") || lowered.contains("twitter.com/") {
            oembedUrl = "https://publish.twitter.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)"
        } else if lowered.contains("instagram.com/") {
            oembedUrl = "https://api.instagram.com/oembed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)"
        }

        guard let endpoint = oembedUrl, let requestUrl = URL(string: endpoint) else { return nil }

        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            var ogp = OGPData()
            ogp.title = json?["title"] as? String
            ogp.description = json?["author_name"] as? String
            ogp.imageUrl = json?["thumbnail_url"] as? String
            ogp.siteName = json?["provider_name"] as? String

            // X/Twitter oEmbed doesn't return thumbnail, extract from HTML content
            if ogp.imageUrl == nil, let html = json?["html"] as? String {
                if let imgRange = html.range(of: #"https://pbs\.twimg\.com/[^"'\s]+"#, options: .regularExpression) {
                    ogp.imageUrl = String(html[imgRange])
                }
            }

            if ogp.title != nil || ogp.imageUrl != nil {
                logger.info("oEmbed success for \(url)")
                return ogp
            }
        } catch {
            logger.debug("oEmbed failed for \(url): \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - HTML Meta Tag Parsing

    private func fetchHTML(url: String) async -> OGPData {
        guard let requestUrl = URL(string: url) else { return OGPData() }

        var request = URLRequest(url: requestUrl)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
            else { return OGPData() }

            return parse(html: html, baseUrl: requestUrl)
        } catch {
            logger.warning("HTML fetch failed for \(url): \(error.localizedDescription)")
            return OGPData()
        }
    }

    // MARK: - Noembed (free oEmbed proxy for many sites)

    private func fetchNoembed(url: String) async -> OGPData? {
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requestUrl = URL(string: "https://noembed.com/embed?url=\(encoded)") else { return nil }

        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard json?["error"] == nil else { return nil }

            var ogp = OGPData()
            ogp.title = json?["title"] as? String
            ogp.description = json?["author_name"] as? String
            ogp.imageUrl = json?["thumbnail_url"] as? String
            ogp.siteName = json?["provider_name"] as? String

            if ogp.title != nil || ogp.imageUrl != nil {
                logger.info("Noembed success for \(url)")
                return ogp
            }
        } catch {
            logger.debug("Noembed failed for \(url): \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Microlink (renders JS, extracts metadata)

    private func fetchMicrolink(url: String) async -> OGPData? {
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requestUrl = URL(string: "https://api.microlink.io/?url=\(encoded)") else { return nil }

        do {
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dataObj = json?["data"] as? [String: Any] else { return nil }

            var ogp = OGPData()
            ogp.title = dataObj["title"] as? String
            ogp.description = dataObj["description"] as? String
            ogp.siteName = dataObj["publisher"] as? String

            if let imageObj = dataObj["image"] as? [String: Any] {
                ogp.imageUrl = imageObj["url"] as? String
            }
            if let logoObj = dataObj["logo"] as? [String: Any] {
                ogp.favicon = logoObj["url"] as? String
            }

            if ogp.title != nil || ogp.imageUrl != nil {
                logger.info("Microlink success for \(url)")
                return ogp
            }
        } catch {
            logger.debug("Microlink failed for \(url): \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - HTML Parsing

    private func parse(html: String, baseUrl: URL) -> OGPData {
        var data = OGPData()

        // og: tags
        data.title = meta(html, property: "og:title")
            ?? meta(html, property: "twitter:title")
            ?? tag(html, "title")
        data.description = meta(html, property: "og:description")
            ?? meta(html, property: "twitter:description")
            ?? meta(html, name: "description")
        data.imageUrl = meta(html, property: "og:image")
            ?? meta(html, property: "twitter:image")
            ?? meta(html, property: "twitter:image:src")
        data.siteName = meta(html, property: "og:site_name")

        // Resolve relative image URL
        if let img = data.imageUrl, !img.hasPrefix("http") {
            data.imageUrl = URL(string: img, relativeTo: baseUrl)?.absoluteString
        }

        data.favicon = "\(baseUrl.scheme ?? "https")://\(baseUrl.host() ?? "")/favicon.ico"

        return data
    }

    // MARK: - Helpers

    private func meta(_ html: String, property: String) -> String? {
        // property="X" content="Y"
        let p1 = #"<meta[^>]+property\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']*)["']"#
        if let v = extractContent(html, pattern: p1) { return decode(v) }
        // content="Y" property="X"
        let p2 = #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]+property\s*=\s*["']\#(property)["']"#
        if let v = extractContent(html, pattern: p2) { return decode(v) }
        return nil
    }

    private func meta(_ html: String, name: String) -> String? {
        let p1 = #"<meta[^>]+name\s*=\s*["']\#(name)["'][^>]+content\s*=\s*["']([^"']*)["']"#
        if let v = extractContent(html, pattern: p1) { return decode(v) }
        let p2 = #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]+name\s*=\s*["']\#(name)["']"#
        if let v = extractContent(html, pattern: p2) { return decode(v) }
        return nil
    }

    private func extractContent(_ html: String, pattern: String) -> String? {
        guard let match = html.range(of: pattern, options: .regularExpression) else { return nil }
        let sub = String(html[match])
        let contentPattern = #"content\s*=\s*["']([^"']*)["']"#
        guard let cRange = sub.range(of: contentPattern, options: .regularExpression) else { return nil }
        let raw = String(sub[cRange])
            .replacingOccurrences(of: #"content\s*=\s*["']"#, with: "", options: .regularExpression)
        let value = raw.hasSuffix("\"") || raw.hasSuffix("'") ? String(raw.dropLast()) : raw
        return value.isEmpty ? nil : value
    }

    private func tag(_ html: String, _ name: String) -> String? {
        let p = "<\(name)[^>]*>([^<]*)</\(name)>"
        guard let match = html.range(of: p, options: .regularExpression) else { return nil }
        let content = String(html[match])
            .replacingOccurrences(of: "<\(name)[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</\(name)>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : decode(content)
    }

    private func decode(_ s: String) -> String {
        var result = s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")

        // Decode numeric HTML entities: &#xHEX; and &#DEC;
        let hexPattern = #"&#x([0-9a-fA-F]+);"#
        while let range = result.range(of: hexPattern, options: .regularExpression) {
            let entity = String(result[range])
            let hex = entity.dropFirst(3).dropLast()
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(range, with: String(scalar))
            } else { break }
        }
        let decPattern = #"&#([0-9]+);"#
        while let range = result.range(of: decPattern, options: .regularExpression) {
            let entity = String(result[range])
            let dec = entity.dropFirst(2).dropLast()
            if let code = UInt32(dec), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(range, with: String(scalar))
            } else { break }
        }
        return result
    }
}
