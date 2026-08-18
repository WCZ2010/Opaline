import Foundation

struct TVSearchVideo: Hashable {
    let id: String
    let title: String
    let channelName: String
    let viewCount: String?
    let duration: String?
    let thumbnailURL: URL?
}

enum TVSearchError: LocalizedError {
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "YouTube 返回了无法识别的搜索结果。"
        case .server(let status):
            return "YouTube 搜索请求失败（HTTP \(status)）。"
        }
    }
}

final class TVSearchClient {
    private let endpoint = URL(
        string: "https://www.youtube.com/youtubei/v1/search"
    )!

    func search(
        query: String,
        completion: @escaping (Result<[TVSearchVideo], Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: requestBody(query: query)
        )

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<[TVSearchVideo], Error>
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse,
                      !(200 ... 299).contains(response.statusCode) {
                result = .failure(TVSearchError.server(response.statusCode))
            } else if let data,
                      let videos = Self.parseVideos(data) {
                result = videos.isEmpty
                    ? .failure(TVSearchError.invalidResponse)
                    : .success(videos)
            } else {
                result = .failure(TVSearchError.invalidResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private func requestBody(query: String) -> [String: Any] {
        [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20260206.01.00",
                    "hl": "zh-CN",
                    "gl": "US",
                    "platform": "DESKTOP"
                ],
                "user": ["enableSafetyMode": false],
                "request": ["useSsl": true]
            ],
            "query": query
        ]
    }

    private static func parseVideos(_ data: Data) -> [TVSearchVideo]? {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            return nil
        }
        var videos: [TVSearchVideo] = []
        collectVideos(in: root, into: &videos)
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    private static func collectVideos(
        in value: Any,
        into result: inout [TVSearchVideo]
    ) {
        if let dictionary = value as? [String: Any] {
            if let renderer = dictionary["videoRenderer"] as? [String: Any],
               let video = makeVideo(renderer) {
                result.append(video)
                return
            }
            if let lockup = dictionary["lockupViewModel"] as? [String: Any],
               let video = makeLockupVideo(lockup) {
                result.append(video)
                return
            }
            for child in dictionary.values {
                collectVideos(in: child, into: &result)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideos(in: child, into: &result)
            }
        }
    }

    private static func makeLockupVideo(
        _ lockup: [String: Any]
    ) -> TVSearchVideo? {
        guard let id = lockup["contentId"] as? String,
              id.count == 11,
              let metadata = lockup["metadata"] as? [String: Any],
              let model = metadata["lockupMetadataViewModel"] as? [String: Any],
              let titleObject = model["title"] as? [String: Any],
              let title = titleObject["content"] as? String,
              !title.isEmpty else {
            return nil
        }
        return TVSearchVideo(
            id: id,
            title: title,
            channelName: "",
            viewCount: nil,
            duration: lockupDuration(lockup),
            thumbnailURL: URL(
                string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
            )
        )
    }

    private static func lockupDuration(_ lockup: [String: Any]) -> String? {
        guard let contentImage = lockup["contentImage"] as? [String: Any],
              let thumbnail = contentImage["thumbnailViewModel"]
                as? [String: Any],
              let overlays = thumbnail["overlays"] as? [[String: Any]]
        else { return nil }
        for overlay in overlays {
            guard let bottom = overlay["thumbnailBottomOverlayViewModel"]
                    as? [String: Any],
                  let badges = bottom["badges"] as? [[String: Any]],
                  let badge = badges.first?["thumbnailBadgeViewModel"]
                    as? [String: Any],
                  let text = badge["text"] as? String else { continue }
            return text
        }
        return nil
    }

    private static func makeVideo(
        _ renderer: [String: Any]
    ) -> TVSearchVideo? {
        guard let id = renderer["videoId"] as? String, !id.isEmpty else {
            return nil
        }
        let thumbnail = URL(
            string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
        )
        return TVSearchVideo(
            id: id,
            title: text(renderer["title"]) ?? "Untitled",
            channelName: text(renderer["ownerText"]) ?? "",
            viewCount: text(renderer["viewCountText"]),
            duration: duration(renderer["thumbnailOverlays"]),
            thumbnailURL: thumbnail
        )
    }

    private static func text(_ value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let simpleText = dictionary["simpleText"] as? String {
            return simpleText
        }
        return (dictionary["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined()
    }

    private static func duration(_ value: Any?) -> String? {
        guard let overlays = value as? [[String: Any]] else { return nil }
        for overlay in overlays {
            guard let renderer = overlay["thumbnailOverlayTimeStatusRenderer"]
                as? [String: Any] else { continue }
            if let duration = text(renderer["text"]) {
                return duration
            }
        }
        return nil
    }
}
