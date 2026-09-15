import SwiftUI
import AppKit

/// Tab "Xu hướng": lấy video hot từ Bilibili + phân tích chủ đề thịnh hành bằng GPT.
struct TrendingView: View {

    @ObservedObject var vm: AppViewModel

    /// State của nguồn đang xem
    private var state: TrendingState { vm.currentTrending }

    /// Toast thông báo copy
    @State private var showCopyToast = false
    @State private var copyToastText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xu hướng \(vm.trendingSource.rawValue)")
                        .font(.headline)
                    Text(state.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    vm.loadTrending()
                } label: {
                    if state.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Lấy xu hướng", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .disabled(state.isLoading)
            }
            .padding(.bottom, 6)

            // Chọn nguồn: Bilibili / Douyin (đổi nguồn được kể cả khi nguồn kia đang tải)
            Picker("", selection: $vm.trendingSource) {
                ForEach(TrendingSource.allCases) { src in
                    Text(src.rawValue).tag(src)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            if let at = state.generatedAt {
                HStack {
                    Text("Cập nhật: \(at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            Divider()

            if state.isEmpty && !state.isLoading {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if !state.topics.isEmpty {
                            topicsSection
                        }
                        if !state.keywords.isEmpty {
                            keywordsSection
                        }
                        if !state.videos.isEmpty {
                            videosSection
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopyToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(copyToastText)
                        .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.gray.opacity(0.2)))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopyToast)
    }

    /// Hiện toast rồi tự ẩn sau 1.5s.
    private func flashToast(_ text: String) {
        copyToastText = text
        showCopyToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyToast = false
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(.pink.opacity(0.6))
            Text("Chưa có dữ liệu")
                .font(.headline)
            Text("Bấm \"Lấy xu hướng\" để tải \(vm.trendingSource == .bilibili ? "video hot từ Bilibili" : "từ khóa hot từ Douyin").\nCó OpenAI key sẽ tự gom chủ đề + dịch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Topics

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔥 Chủ đề đang hot (\(state.topics.count))")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(state.topics.enumerated()), id: \.element.id) { idx, topic in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(idx + 1). \(topic.name)")
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(topic.videoCount) mục")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !topic.summary.isEmpty {
                        Text(topic.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !topic.keywords.isEmpty {
                        // Từ khóa dạng chip
                        FlexibleChips(items: topic.keywords)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Keywords (Douyin)

    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🔎 Từ khóa hot (\(state.keywords.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    copyAllKeywords()
                } label: {
                    Label("Copy tất cả", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(Array(state.keywords.enumerated()), id: \.element.id) { idx, kw in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(kw.wordVi ?? kw.word)
                            .font(.callout)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        if kw.wordVi != nil {
                            Text(kw.word)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                    Text("🔥 \(kw.hotFormatted)")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    // Nút copy nhanh cho từng từ khóa
                    Button {
                        copyToClipboard(kw.wordVi ?? kw.word)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy từ khóa")
                }
                .padding(.vertical, 5)
                .contextMenu {
                    if let vi = kw.wordVi {
                        Button("Copy tiếng Việt") { copyToClipboard(vi) }
                    }
                    Button("Copy tiếng Trung") { copyToClipboard(kw.word) }
                    if let vi = kw.wordVi {
                        Button("Copy cả hai") { copyToClipboard("\(vi) (\(kw.word))") }
                    }
                }
                Divider()
            }
        }
    }

    // MARK: - Copy helpers

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flashToast("Đã copy!")
    }

    /// Copy toàn bộ danh sách từ khóa (mỗi dòng: "tiếng Việt (tiếng Trung) — hot").
    private func copyAllKeywords() {
        let lines = state.keywords.enumerated().map { idx, kw -> String in
            let name = kw.wordVi.map { "\($0) (\(kw.word))" } ?? kw.word
            return "\(idx + 1). \(name) — 🔥\(kw.hotFormatted)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        flashToast("Đã copy \(state.keywords.count) từ khóa!")
    }

    // MARK: - Videos

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📺 Video hot (\(state.videos.count))")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(Array(state.videos.enumerated()), id: \.element.id) { idx, video in
                Button {
                    vm.openTrendingVideo(video)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            // Ưu tiên tiêu đề tiếng Việt nếu có
                            Text(video.titleVi ?? video.title)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if video.titleVi != nil {
                                Text(video.title)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 8) {
                                if !video.tname.isEmpty {
                                    Text(video.tname)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                }
                                Text("👁 \(video.viewFormatted)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !video.author.isEmpty {
                                    Text("· \(video.author)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Mở video trên Bilibili")

                Divider()
            }
        }
    }
}

// MARK: - Flexible chips (từ khóa xuống dòng tự động)

private struct FlexibleChips: View {
    let items: [String]

    var body: some View {
        // Bố cục đơn giản: dùng wrap bằng cách chia dòng thủ công qua LazyVGrid adaptive
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { kw in
                Text(kw)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.pink.opacity(0.15), in: Capsule())
            }
        }
    }
}
