import Foundation
import Combine
import SwiftUI

struct Message: Identifiable, Codable {
    var id = UUID()
    var content: String
    let isFromUser: Bool
    var imageDataBase64: String?

    var imageData: Data? {
        guard let base64 = imageDataBase64 else { return nil }
        return Data(base64Encoded: base64)
    }

    init(content: String, isFromUser: Bool, imageData: Data? = nil) {
        self.content = content
        self.isFromUser = isFromUser
        self.imageDataBase64 = imageData?.base64EncodedString()
    }
}

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var title: String
    var messages: [Message]
    var date: Date
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var history: [Conversation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showHistory = false

    let apiKey = "sk-hiddenhiddenhidden"
    let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    var currentConversationID: UUID?

    init() {
        loadHistory()
        addWelcome()
    }

    func addWelcome() {
        messages.append(Message(
            content: "田老先生，您好！我是您的小助手。您可以问我时事科技、文学历史什么都行。也可以点左边的按钮发张图片给我看。有什么想聊想问的，您随时说。",
            isFromUser: false
        ))
    }

    // MARK: - 新对话

    func startNewChat() {
        saveCurrentChat()
        messages.removeAll()
        addWelcome()
        currentConversationID = nil
    }

    // MARK: - 保存当前对话

    func saveCurrentChat() {
        let realMessages = messages.filter { $0.isFromUser }
        guard !realMessages.isEmpty else { return }

        let title = realMessages.first?.content ?? "对话"
        let shortTitle = String(title.prefix(20))

        let conversation = Conversation(
            title: shortTitle,
            messages: messages,
            date: Date()
        )

        if let existingIndex = history.firstIndex(where: { $0.id == currentConversationID }) {
            history[existingIndex] = conversation
        } else {
            history.insert(conversation, at: 0)
            currentConversationID = conversation.id
        }

        saveHistory()
    }

    // MARK: - 加载旧对话

    func loadConversation(_ conversation: Conversation) {
        saveCurrentChat()
        messages = conversation.messages
        currentConversationID = conversation.id
        showHistory = false
    }

    // MARK: - 删除旧对话

    func deleteConversation(_ conversation: Conversation) {
        history.removeAll { $0.id == conversation.id }
        saveHistory()
    }

    // MARK: - 本地存储

    private var savePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_history.json")
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: savePath)
        } catch {
            print("保存失败：", error)
        }
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: savePath)
            history = try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            print("没有历史记录或读取失败")
            history = []
        }
    }

    // MARK: - 发消息

    func send(_ text: String, imageData: Data? = nil) {
        let userText = text.isEmpty ? "请帮我看看这张图片" : text
        messages.append(Message(content: userText, isFromUser: true, imageData: imageData))
        isLoading = true
        errorMessage = nil

        // 先添加一条空的助手消息，用于流式填充
        let assistantMsg = Message(content: "", isFromUser: false)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        Task {
            do {
                if let imageData = imageData {
                    // 图片识别不用流式，直接返回
                    let reply = try await callVisionAPI(text: userText, imageData: imageData)
                    messages[assistantIndex].content = reply
                } else {
                    // 文字对话用流式
                    try await callTextAPIStream(assistantIndex: assistantIndex)
                }
                saveCurrentChat()
            } catch {
                print("出错了：", error)
                // 如果助手消息还是空的，删掉它
                if messages[assistantIndex].content.isEmpty {
                    messages.remove(at: assistantIndex)
                }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - 流式文字对话

    private func callTextAPIStream(assistantIndex: Int) async throws {

        let systemPrompt = """
        你正在和一位叫田德宽的老先生对话，他笔名田野，今年九十岁，住在山东聊城茌平。他1956年大学物理专业毕业，有很好的文化素养和科学功底。他关心时政、科技前沿和历史，思维清晰，见解独到。

        请你做到以下几点：

        用平等、尊重的语气和他交流，称呼他"田老"或"您"。不要居高临下，不要哄小孩式的语气。他是一位有学识的长者，请像和一位老学者聊天那样自然交流。

        回答要有内容、有深度，不要敷衍。他喜欢有实质的讨论，不喜欢空话套话。

        用通顺的中文自然段落来回答。不要用项目符号、编号列表、星号、破折号、任何markdown格式。

        涉及科技话题，可以适当用一些大白话的概念，他能理解。但不要用任何英文缩写、不要用任何网络流行语，用中文表达。

        涉及健康和用药问题，给出参考信息后务必提醒他咨询医生。

        涉及时政话题，客观陈述事实和不同观点，不要偏激。

        如果搜索到了网络信息，自然地融入回答中，不要说"根据搜索结果"之类的话。

        不确定的事情就坦诚说不确定，不要编造。
        """


        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        // 不包含最后那条空的助手消息
        for msg in messages.prefix(assistantIndex).suffix(20) {
            if msg.imageData == nil {
                apiMessages.append([
                    "role": msg.isFromUser ? "user" : "assistant",
                    "content": msg.content
                ])
            }
        }

        let body: [String: Any] = [
            "model": "qwen-plus",
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 2000,
            "enable_search": true,
            "stream": true
        ]

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "服务暂时出了问题，请稍后再试"])
        }

        for try await line in bytes.lines {
            // 每行格式：data: {...}
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                break
            }

            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String
            else {
                continue
            }

            messages[assistantIndex].content += content
        }

        // 如果最终还是空的
        if messages[assistantIndex].content.isEmpty {
            messages[assistantIndex].content = "抱歉，没有收到回复，请再问一次。"
        }
    }

    // MARK: - 图片识别

    private func callVisionAPI(text: String, imageData: Data) async throws -> String {

        let systemPrompt = """
        你正在和一位叫田德宽的老先生对话，他笔名田野，今年九十岁，住在山东聊城茌平。他1956年大学物理专业毕业，有很好的文化素养和科学功底。他关心时政、科技前沿和历史，思维清晰，见解独到。

        请你做到以下几点：

        用平等、尊重的语气和他交流，称呼他"田老"或"您"。不要居高临下，不要哄小孩式的语气。他是一位有学识的长者，请像和一位老学者聊天那样自然交流。

        回答要有内容、有深度，不要敷衍。他喜欢有实质的讨论，不喜欢空话套话。

        用通顺的中文自然段落来回答，段落之间空一行。不要用项目符号、编号列表、星号、破折号、任何markdown格式。

        涉及科技话题，可以适当用专业概念，他能理解。但尽量少用英文缩写，用中文表达。

        涉及健康和用药问题，给出参考信息后务必提醒他咨询医生。

        涉及时政话题，客观陈述事实和不同观点，不要偏激。

        如果搜索到了网络信息，自然地融入回答中，不要说"根据搜索结果"之类的话。

        不确定的事情就坦诚说不确定，不要编造。
        他给你发了一张图片，请仔细看图片内容，用自然、平等的语气回答。称呼他"田老"或"您"。

        用通顺的中文自然段落回答，段落间空一行。不要用项目符号、编号列表、星号、破折号、任何markdown格式。

        如果图片是药品、食品说明书等，帮他把关键信息讲清楚，涉及用药务必提醒咨询医生。

        如果图片内容不清楚，就坦诚说看不太清，请他再拍一张。
        """


        let compressedData = compressImage(imageData)
        let base64 = compressedData.base64EncodedString()
        print("图片大小：\(compressedData.count / 1024) KB")

        let userContent: [[String: Any]] = [
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ],
            [
                "type": "text",
                "text": text
            ]
        ]

        let apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent]
        ]

        let body: [String: Any] = [
            "model": "qwen-vl-plus",
            "messages": apiMessages,
            "max_tokens": 2000,
            "enable_search": true
        ]

        return try await doRequest(body: body)
    }

    // MARK: - 普通请求（图片用）

    private func doRequest(body: [String: Any]) async throws -> String {

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "服务暂时出了问题，请稍后再试"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw NSError(domain: "", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "没有收到有效回复，请重新提问"])
        }

        return content
    }

    // MARK: - 压缩图片

    private func compressImage(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let maxSize: CGFloat = 1024
        let width = image.size.width
        let height = image.size.height

        var newImage = image
        if width > maxSize || height > maxSize {
            let scale = min(maxSize / width, maxSize / height)
            let newWidth = width * scale
            let newHeight = height * scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: newWidth, height: newHeight))
            newImage = renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            }
        }

        return newImage.jpegData(compressionQuality: 0.6) ?? data
    }
}

