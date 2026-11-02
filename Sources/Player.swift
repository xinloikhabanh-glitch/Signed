import SwiftUI
import AVFoundation

/// Trình phát nhạc nền dùng chung cho cả app (các file nhạc nằm trong Resources/)
final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Player()

    struct Track: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
    }

    @Published var tracks: [Track] = []
    @Published var index = 0
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var loopOne = false
    @Published var shuffle = false

    private var ap: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        var found: [URL] = []
        for ext in ["mp3", "m4a", "wav"] {
            found += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        found.sort { $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending }
        tracks = found.map { Track(url: $0, title: Player.titleOf($0)) }
        if !tracks.isEmpty { prepare(0, autoplay: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.ap, p.duration > 0 else { return }
            self.progress = p.currentTime / p.duration
        }
    }

    /// Bỏ phần đuôi sau " | " (tên tải từ YouTube hay rất dài)
    private static func titleOf(_ url: URL) -> String {
        var s = url.deletingPathExtension().lastPathComponent
        for sep in [" | ", " _ ", "｜"] {
            if let r = s.range(of: sep), r.lowerBound != s.startIndex {
                s = String(s[s.startIndex..<r.lowerBound])
            }
        }
        let t = s.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? url.lastPathComponent : t
    }

    private func prepare(_ i: Int, autoplay: Bool) {
        guard tracks.indices.contains(i) else { return }
        index = i
        ap?.stop()
        ap = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        guard let p = try? AVAudioPlayer(contentsOf: tracks[i].url) else {
            playing = false
            return
        }
        p.delegate = self
        p.prepareToPlay()
        ap = p
        progress = 0
        if autoplay {
            p.play()
            playing = true
        } else {
            playing = false
        }
    }

    func toggle() {
        guard let p = ap else { return }
        if p.isPlaying {
            p.pause()
            playing = false
        } else {
            p.play()
            playing = true
        }
    }

    func next() {
        guard !tracks.isEmpty else { return }
        var n = (index + 1) % tracks.count
        if shuffle && tracks.count > 1 {
            repeat { n = Int.random(in: 0..<tracks.count) } while n == index
        }
        prepare(n, autoplay: true)
    }

    func prev() {
        guard !tracks.isEmpty else { return }
        if let p = ap, p.currentTime > 3 {
            p.currentTime = 0
            return
        }
        prepare((index - 1 + tracks.count) % tracks.count, autoplay: true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if loopOne {
            player.currentTime = 0
            player.play()
        } else {
            next()
        }
    }
}

/// Thanh nhạc mini nằm trên cùng, hiện ở mọi tab
struct MiniPlayer: View {
    @ObservedObject var player: Player

    var body: some View {
        if player.tracks.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "music.note")
                        .foregroundColor(Color(red: 0.39, green: 0.82, blue: 1.0))
                    Text(player.tracks[player.index].title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { player.shuffle.toggle() } label: {
                        Image(systemName: "shuffle").opacity(player.shuffle ? 1 : 0.4)
                    }
                    Button { player.prev() } label: { Image(systemName: "backward.fill") }
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 18))
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                    Button { player.loopOne.toggle() } label: {
                        Image(systemName: "repeat.1").opacity(player.loopOne ? 1 : 0.4)
                    }
                }
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                GeometryReader { g in
                    Rectangle()
                        .fill(Color(red: 0.39, green: 0.82, blue: 1.0))
                        .frame(width: g.size.width * CGFloat(min(max(player.progress, 0), 1)))
                }
                .frame(height: 2)
            }
            .background(Color(red: 0.07, green: 0.09, blue: 0.13))
        }
    }
}
