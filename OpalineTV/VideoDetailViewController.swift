import AVKit
import UIKit

final class VideoDetailViewController: UIViewController {
    private let video: TVSearchVideo
    private let playbackClient = TVPlaybackClient()
    private var imageTask: URLSessionDataTask?

    private let thumbnailView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 24
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 46, weight: .bold)
        label.numberOfLines = 4
        return label
    }()

    private let metadataLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 26)
        label.textColor = .secondaryLabel
        label.numberOfLines = 3
        return label
    }()

    private let playButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("播放", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 34, weight: .bold)
        return button
    }()

    init(video: TVSearchVideo) {
        self.video = video
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "视频详情"

        titleLabel.text = video.title
        metadataLabel.text = [
            video.channelName,
            video.duration,
            video.viewCount
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")

        view.addSubview(thumbnailView)
        view.addSubview(titleLabel)
        view.addSubview(metadataLabel)
        view.addSubview(playButton)
        playButton.addTarget(
            self,
            action: #selector(play),
            for: .primaryActionTriggered
        )

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 70
            ),
            thumbnailView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 820),
            thumbnailView.heightAnchor.constraint(equalToConstant: 461),

            titleLabel.leadingAnchor.constraint(
                equalTo: thumbnailView.trailingAnchor,
                constant: 70
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -70
            ),
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.topAnchor),

            metadataLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metadataLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 30
            ),

            playButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            playButton.topAnchor.constraint(
                greaterThanOrEqualTo: metadataLabel.bottomAnchor,
                constant: 50
            ),
            playButton.bottomAnchor.constraint(
                lessThanOrEqualTo: thumbnailView.bottomAnchor
            ),
            playButton.widthAnchor.constraint(equalToConstant: 250),
            playButton.heightAnchor.constraint(equalToConstant: 82)
        ])

        loadThumbnail()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [playButton]
    }

    deinit {
        imageTask?.cancel()
    }

    private func loadThumbnail() {
        guard let url = video.thumbnailURL else { return }
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.thumbnailView.image = image
            }
        }
        imageTask?.resume()
    }

    @objc
    private func play() {
        playButton.isEnabled = false
        playButton.setTitle("正在准备…", for: .normal)
        playbackClient.preparePlayerItem(videoID: video.id) { [weak self] result in
            guard let self else { return }
            self.playButton.isEnabled = true
            self.playButton.setTitle("播放", for: .normal)
            switch result {
            case .success(let item):
                let controller = AVPlayerViewController()
                controller.player = AVPlayer(playerItem: item)
                self.present(controller, animated: true) {
                    controller.player?.play()
                }
            case .failure(let error):
                self.presentPlaybackError(error)
            }
        }
    }

    private func presentPlaybackError(_ error: Error) {
        let alert = UIAlertController(
            title: "无法播放",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "完成", style: .default))
        present(alert, animated: true)
    }
}
