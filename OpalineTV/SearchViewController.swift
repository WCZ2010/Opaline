import AVKit
import UIKit

final class SearchViewController: UIViewController {
    private let client = TVSearchClient()
    private let playbackClient = TVPlaybackClient()
    private var videos: [TVSearchVideo] = []
    private var pendingSearchWorkItem: DispatchWorkItem?

    private lazy var searchController: UISearchController = {
        let resultsController = UIViewController()
        resultsController.view.backgroundColor = .black
        let controller = UISearchController(
            searchResultsController: resultsController
        )
        controller.searchBar.placeholder = "搜索 YouTube"
        controller.searchBar.delegate = self
        return controller
    }()

    private let searchButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("输入搜索内容", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 30, weight: .semibold)
        return button
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 520, height: 390)
        layout.minimumInteritemSpacing = 44
        layout.minimumLineSpacing = 44
        layout.sectionInset = UIEdgeInsets(top: 45, left: 70, bottom: 60, right: 70)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.register(
            SearchResultCell.self,
            forCellWithReuseIdentifier: SearchResultCell.reuseIdentifier
        )
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "在上方搜索 YouTube"
        label.font = .systemFont(ofSize: 34)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "搜索"
        view.backgroundColor = .black

        view.addSubview(searchButton)
        view.addSubview(collectionView)
        view.addSubview(statusLabel)
        searchButton.addTarget(
            self,
            action: #selector(beginSearchEntry),
            for: .primaryActionTriggered
        )
        NSLayoutConstraint.activate([
            searchButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 24
            ),
            searchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 380),
            searchButton.heightAnchor.constraint(equalToConstant: 76),
            collectionView.topAnchor.constraint(
                equalTo: searchButton.bottomAnchor,
                constant: 20
            ),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [searchButton]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    @objc
    private func beginSearchEntry() {
        present(searchController, animated: true)
    }

    private func search(for rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        statusLabel.isHidden = false
        statusLabel.text = "正在搜索…"
        videos = []
        collectionView.reloadData()

        client.search(query: query) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let videos):
                self.videos = videos
                self.statusLabel.isHidden = !videos.isEmpty
                self.statusLabel.text = videos.isEmpty ? "没有找到视频" : nil
                self.collectionView.reloadData()
            case .failure(let error):
                self.statusLabel.isHidden = false
                self.statusLabel.text = error.localizedDescription
            }
        }
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        pendingSearchWorkItem?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.search(for: query)
            }
        }
        pendingSearchWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1,
            execute: workItem
        )
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        pendingSearchWorkItem?.cancel()
        let query = searchBar.text ?? ""
        dismiss(animated: true) { [weak self] in
            self?.search(for: query)
        }
    }
}

extension SearchViewController: UICollectionViewDataSource,
    UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        videos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SearchResultCell.reuseIdentifier,
            for: indexPath
        ) as! SearchResultCell
        cell.configure(with: videos[indexPath.item])
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let video = videos[indexPath.item]
        preparePlayback(for: video)
    }

    private func preparePlayback(for video: TVSearchVideo) {
        let loading = UIAlertController(
            title: video.title,
            message: "正在准备播放…",
            preferredStyle: .alert
        )
        present(loading, animated: true)

        playbackClient.preparePlayerItem(videoID: video.id) { [weak self] result in
            guard let self else { return }
            loading.dismiss(animated: true) {
                switch result {
                case .success(let item):
                    let playerController = AVPlayerViewController()
                    playerController.player = AVPlayer(playerItem: item)
                    self.present(playerController, animated: true) {
                        playerController.player?.play()
                    }
                case .failure(let error):
                    self.presentPlaybackError(error)
                }
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

private final class SearchResultCell: UICollectionViewCell {
    static let reuseIdentifier = "SearchResultCell"

    private let thumbnailView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(white: 0.2, alpha: 1)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var imageTask: URLSessionDataTask?
    private var representedVideoID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        contentView.layer.cornerRadius = 20
        contentView.layer.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 27, weight: .semibold)
        titleLabel.numberOfLines = 2
        detailLabel.font = .systemFont(ofSize: 19)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(thumbnailView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 292),
            stack.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        representedVideoID = nil
        thumbnailView.image = nil
        titleLabel.text = nil
        detailLabel.text = nil
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        coordinator.addCoordinatedAnimations {
            self.transform = self.isFocused
                ? CGAffineTransform(scaleX: 1.06, y: 1.06)
                : .identity
            self.contentView.backgroundColor = self.isFocused
                ? UIColor(white: 0.27, alpha: 1)
                : UIColor(white: 0.12, alpha: 1)
        }
    }

    func configure(with video: TVSearchVideo) {
        representedVideoID = video.id
        imageTask?.cancel()
        thumbnailView.image = nil
        titleLabel.text = video.title
        detailLabel.text = [
            video.channelName,
            video.duration,
            video.viewCount
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        guard let url = video.thumbnailURL else { return }
        let videoID = video.id
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self?.representedVideoID == videoID else { return }
                self?.thumbnailView.image = image
            }
        }
        imageTask?.resume()
    }
}
