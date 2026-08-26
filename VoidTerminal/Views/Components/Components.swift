import SwiftUI

// MARK: - Avatar URL 拼接
private func resolveAvatarURL(_ url: String?) -> URL? {
    guard let url = url, !url.isEmpty else { return nil }
    if url.hasPrefix("http://") || url.hasPrefix("https://") {
        return URL(string: url)
    }
    var base = ServerConfig.shared.baseURL
    if base.hasSuffix("/") { base.removeLast() }
    let path = url.hasPrefix("/") ? url : "/" + url
    return URL(string: base + path)
}

// MARK: - Cached Avatar View（带内存缓存 + 失败重试）
struct AvatarView: View {
    let name: String
    var avatarURL: String?
    var size: CGFloat = 44
    var gradient: Gradient = Gradient(colors: [Color(hex: "3b82f6"), Color(hex: "8b5cf6")])
    @State private var loadedImage: UIImage?
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else if let url = resolveAvatarURL(avatarURL), !loadFailed {
                CachedAvatar(url: url, size: size, cornerRadius: size * 0.22, gradient: gradient,
                             fallbackText: String(name.prefix(1)))
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.vtText)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CachedAvatar：使用 ImageCacheManager 双层缓存（内存+磁盘）
private struct CachedAvatar: View {
    let url: URL
    let size: CGFloat
    let cornerRadius: CGFloat
    let gradient: Gradient
    let fallbackText: String
    @State private var image: UIImage?
    @State private var failed: Bool = false

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                placeholder
                    .task { await load() }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(fallbackText)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.vtText)
        }
        .frame(width: size, height: size)
    }

    private func load() async {
        // 先查缓存（内存→磁盘，命中则瞬间返回）
        if let cached = ImageCacheManager.shared.cachedImage(for: url) {
            image = cached
            return
        }
        // 缓存未命中，走网络下载并自动缓存
        if let img = await ImageCacheManager.shared.loadImage(from: url) {
            await MainActor.run { self.image = img }
        } else {
            await MainActor.run { self.failed = true }
        }
    }
}

// MARK: - CachedAsyncImage：消息图片缓存视图
/// 替代 AsyncImage，使用 ImageCacheManager 双层缓存
/// 首次加载走网络，之后全部走缓存（内存→磁盘），不再重复下载
struct CachedAsyncImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    var placeholderColor: Color = Color.gray.opacity(0.3)

    @State private var image: UIImage?
    @State private var loadState: LoadState = .idle

    enum LoadState { case idle, loading, loaded, failed }

    var body: some View {
        Group {
            switch loadState {
            case .loaded:
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            case .loading, .idle:
                placeholderColor
                    .overlay(ProgressView().tint(.white.opacity(0.6)))
            case .failed:
                placeholderColor
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.system(size: 20))
                    )
            }
        }
        .task { await load() }
    }

    private func load() async {
        // 先查缓存
        if let cached = ImageCacheManager.shared.cachedImage(for: url) {
            image = cached
            loadState = .loaded
            return
        }
        loadState = .loading
        if let img = await ImageCacheManager.shared.loadImage(from: url) {
            image = img
            loadState = .loaded
        } else {
            loadState = .failed
        }
    }
}

// MARK: - Toast
struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.vt(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .padding(.top, 20)
    }
}

// MARK: - Modal Sheet
struct ModalView<Content: View>: View {
    let title: String
    @Binding var isPresented: Bool
    let content: Content

    init(title: String, isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            VStack(spacing: 16) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark").foregroundColor(.gray)
                    }
                }
                content
            }
            .padding(20)
            .background(Color.vtPanel)
            .cornerRadius(14)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Primary Button
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.vt(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "062"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isDisabled ? Color.gray : Color(hex: "07c160"))
                .cornerRadius(8)
        }
        .disabled(isDisabled)
    }
}

// MARK: - Custom TextField
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.vtBG)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.vtBorder, lineWidth: 1)
        )
        .foregroundColor(.vtText)
        .autocapitalization(.none)
        .disableAutocorrection(true)
    }
}
