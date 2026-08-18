//
//  ViewController.swift
//  OpalineTV
//
//  Created by wcz on 2026/8/18.
//

import UIKit

final class HomeViewController: UIViewController {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Opaline for Apple TV"
        label.font = .systemFont(ofSize: 54, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private let startButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("开始探索", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 34, weight: .semibold)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        view.addSubview(titleLabel)
        view.addSubview(startButton)

        startButton.addTarget(
            self,
            action: #selector(startButtonPressed),
            for: .primaryActionTriggered
        )

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(
                equalTo: view.centerYAnchor,
                constant: -70
            ),
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 55
            ),
            startButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            startButton.heightAnchor.constraint(equalToConstant: 80)
        ])
    }

    @objc
    private func startButtonPressed() {
        navigationController?.pushViewController(
            SearchViewController(),
            animated: true
        )
    }
}
