import SwiftUI

// MARK: - Avatar View
struct AvatarView: View {
    let name: String
    var avatarURL: String?
    var size: CGFloat = 44
    var gradient: Gradient = Gradient(colors: [Color(hex: "3b82f6"), Color(hex: "8b5cf6")])

    var body: some View {
        Group {
            if let url = avatarURL, !url.isEmpty, let imgURL = URL(string: url.hasPrefix("http") ? url : ServerConfig.shared.baseURL + url) {
                AsyncImage(url: imgURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
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
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Toast
struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 14))
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
            .background(Color(hex: "161a22"))
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
                .font(.system(size: 15, weight: .semibold))
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
        .background(Color(hex: "0f1117"))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "262c38"), lineWidth: 1)
        )
        .foregroundColor(.white)
        .autocapitalization(.none)
        .disableAutocorrection(true)
    }
}
