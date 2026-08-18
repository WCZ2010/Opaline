import AVFoundation
import Foundation

enum TVPlaybackError: LocalizedError {
    case invalidResponse
    case unavailable(String)
    case noPlayableStream
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "YouTube 返回了无法识别的播放信息。"
        case .unavailable(let reason):
            return reason.isEmpty ? "此视频当前无法播放。" : reason
        case .noPlayableStream:
            return "此视频没有可直接播放的兼容流。"
        case .server(let status):
            return "播放请求失败（HTTP \(status)）。"
        }
    }
}

final class TVPlaybackClient {
    private let playerEndpoint = URL(
        string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
    )!
    private let clientVersion = "1.65.10"
    private let userAgent = "com.google.android.apps.youtube.vr.oculus/1.65.10 "
        + "(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

    func preparePlayerItem(
        videoID: String,
        completion: @escaping (Result<AVPlayerItem, Error>) -> Void
    ) {
        fetchVisitorData(videoID: videoID) { [weak self] visitorData in
            self?.requestPlayer(
                videoID: videoID,
                visitorData: visitorData,
                completion: completion
            )
        }
    }

    private func fetchVisitorData(
        videoID: String,
        completion: @escaping (String?) -> Void
    ) {
        var components = URLComponents(
            string: "https://www.youtube.com/watch"
        )!
        components.queryItems = [
            URLQueryItem(name: "v", value: videoID),
            URLQueryItem(name: "bpctr", value: "9999999999"),
            URLQueryItem(name: "has_verified", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-us,en;q=0.5", forHTTPHeaderField: "Accept-Language")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            completion(Self.extractVisitorData(data))
        }.resume()
    }

    private func requestPlayer(
        videoID: String,
        visitorData: String?,
        completion: @escaping (Result<AVPlayerItem, Error>) -> Void
    ) {
        var request = URLRequest(url: playerEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("28", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(
            clientVersion,
            forHTTPHeaderField: "X-YouTube-Client-Version"
        )
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let visitorData {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: playerBody(videoID: videoID)
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<AVPlayerItem, Error>
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse,
                      !(200 ... 299).contains(response.statusCode) {
                result = .failure(TVPlaybackError.server(response.statusCode))
            } else if let data {
                result = self?.parsePlayerResponse(
                    data,
                    visitorData: visitorData
                ) ?? .failure(TVPlaybackError.invalidResponse)
            } else {
                result = .failure(TVPlaybackError.invalidResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private func playerBody(videoID: String) -> [String: Any] {
        [
            "context": [
                "client": [
                    "clientName": "ANDROID_VR",
                    "clientVersion": clientVersion,
                    "hl": "en",
                    "gl": "US",
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0,
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3",
                    "androidSdkVersion": 32,
                    "osName": "Android",
                    "osVersion": "12L",
                    "userAgent": userAgent
                ]
            ],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]
    }

    private func parsePlayerResponse(
        _ data: Data,
        visitorData: String?
    ) -> Result<AVPlayerItem, Error> {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            return .failure(TVPlaybackError.invalidResponse)
        }
        if let status = root["playabilityStatus"] as? [String: Any],
           (status["status"] as? String) != "OK" {
            let reason = status["reason"] as? String ?? ""
            return .failure(TVPlaybackError.unavailable(reason))
        }
        guard let streamingData = root["streamingData"] as? [String: Any]
        else {
            return .failure(TVPlaybackError.noPlayableStream)
        }

        if let hls = streamingData["hlsManifestUrl"] as? String,
           let url = URL(string: hls) {
            return .success(AVPlayerItem(url: url))
        }

        let formats = streamingData["formats"] as? [[String: Any]] ?? []
        let selected = formats
            .filter {
                ($0["mimeType"] as? String)?.contains("video/mp4") == true
                    && ($0["url"] as? String)?.isEmpty == false
            }
            .max {
                ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0)
            }
        guard let rawURL = selected?["url"] as? String,
              let url = URL(string: rawURL) else {
            return .failure(TVPlaybackError.noPlayableStream)
        }
        var headers = [
            "User-Agent": userAgent,
            "X-YouTube-Client-Name": "28",
            "X-YouTube-Client-Version": clientVersion
        ]
        if let visitorData {
            headers["X-Goog-Visitor-Id"] = visitorData
        }
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return .success(AVPlayerItem(asset: asset))
    }

    private static func extractVisitorData(_ data: Data?) -> String? {
        guard let data,
              let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "\"VISITOR_DATA\":\""),
              let end = html[start.upperBound...].range(of: "\"") else {
            return nil
        }
        return String(html[start.upperBound..<end.lowerBound])
    }
}
