import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var inputText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var showCamera = false
    @State private var searchText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if vm.showHistory {
                historyPanel
            }

            messageList

            if let err = vm.errorMessage {
                errorView(err)
            }

            imagePreview
            Divider()
            inputBar
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(imageData: $selectedImageData)
                .ignoresSafeArea()
        }
    }

    // MARK: - 顶栏

    var topBar: some View {
        HStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)

            Text("老田的小助手")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))

            Spacer()

            Button(action: {
                isInputFocused = false
                withAnimation {
                    vm.showHistory.toggle()
                    if !vm.showHistory { searchText = "" }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("历史")
                }
                .font(.system(size: 24))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(vm.showHistory ? Color.gray : Color.orange.opacity(0.6))
                .cornerRadius(16)
            }

            Button(action: {
                isInputFocused = false
                vm.startNewChat()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("新对话")
                }
                .font(.system(size: 24))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.8))
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(Color(red: 1.0, green: 0.97, blue: 0.93))
    }

    // MARK: - 消息列表

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(vm.messages) { msg in
                        messageBubble(msg).id(msg.id)
                    }

                    if vm.isLoading && (vm.messages.last?.content.isEmpty ?? true) {
                        HStack {
                            loadingView
                            Spacer()
                        }
                        .padding(.horizontal, 30)
                        .id("loading")
                    }
                }
                .padding(.vertical, 24)
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.93))
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: vm.messages.count) {
                withAnimation {
                    if let last = vm.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: vm.messages.last?.content) {
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 错误提示

    func errorView(_ err: String) -> some View {
        Text(err)
            .font(.system(size: 24))
            .foregroundColor(.red)
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
    }

    // MARK: - 图片预览

    @ViewBuilder
    var imagePreview: some View {
        if let imageData = selectedImageData,
           let uiImage = UIImage(data: imageData) {
            HStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .cornerRadius(12)

                Button(action: {
                    selectedImageData = nil
                    selectedPhoto = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 8)
        }
    }

    // MARK: - 输入栏

    var inputBar: some View {
        HStack(spacing: 12) {

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 28))
                    Text("相册")
                        .font(.system(size: 16))
                }
                .foregroundColor(.orange)
                .frame(width: 56, height: 56)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(16)
            }
            .onChange(of: selectedPhoto) {
                Task {
                    if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                    }
                }
            }

            Button(action: { showCamera = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28))
                    Text("拍图")
                        .font(.system(size: 16))
                }
                .foregroundColor(.orange)
                .frame(width: 56, height: 56)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(16)
            }

            TextField("请在这里输入您的问题", text: $inputText, axis: .vertical)
                .font(.system(size: 28))
                .lineLimit(1...5)
                .padding(18)
                .background(Color(red: 0.96, green: 0.94, blue: 0.90))
                .cornerRadius(20)
                .focused($isInputFocused)

            Button(action: sendMessage) {
                Text("发送")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 18)
                    .background(canSend ? Color.orange : Color.gray.opacity(0.5))
                    .cornerRadius(20)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 16)
        .background(Color(red: 1.0, green: 0.97, blue: 0.93))
    }

    // MARK: - 历史面板

    var filteredHistory: [Conversation] {
        if searchText.isEmpty { return vm.history }
        return vm.history.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(searchText) ||
            conversation.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var historyPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)

                TextField("搜索历史对话", text: $searchText)
                    .font(.system(size: 26))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if filteredHistory.isEmpty {
                Text(searchText.isEmpty ? "还没有历史对话" : "没有找到相关对话")
                    .font(.system(size: 26))
                    .foregroundColor(.secondary)
                    .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredHistory) { conversation in
                            Button(action: {
                                searchText = ""
                                vm.loadConversation(conversation)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(conversation.title)
                                            .font(.system(size: 26, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(formatDate(conversation.date))
                                            .font(.system(size: 20))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(action: { vm.deleteConversation(conversation) }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 22))
                                            .foregroundColor(.red.opacity(0.6))
                                            .padding(10)
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 16)
                            }
                            Divider().padding(.horizontal, 30)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .background(Color(red: 1.0, green: 0.98, blue: 0.95))
    }

    // MARK: - 气泡

    func messageBubble(_ message: Message) -> some View {
        HStack(alignment: .top) {
            if message.isFromUser { Spacer(minLength: 60) }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if !message.isFromUser {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                    }
                    Text(message.isFromUser ? "我" : "小助手")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if let imageData = message.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .cornerRadius(16)
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 30))
                        .lineSpacing(12)
                        .padding(22)
                        .background(message.isFromUser
                            ? Color.orange.opacity(0.15)
                            : Color.white)
                        .cornerRadius(22)
                }
            }

            if !message.isFromUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 30)
    }

    // MARK: - 加载

    var loadingView: some View {
        HStack(spacing: 8) {
            Text("小助手正在思考")
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            ProgressView().scaleEffect(1.5)
        }
        .padding(22)
        .background(Color.white)
        .cornerRadius(22)
    }

    // MARK: - 辅助

    var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasImage = selectedImageData != nil
        return (hasText || hasImage) && !vm.isLoading
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }
        let imageData = selectedImageData
        inputText = ""
        selectedImageData = nil
        selectedPhoto = nil
        isInputFocused = false
        vm.send(text, imageData: imageData)
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
