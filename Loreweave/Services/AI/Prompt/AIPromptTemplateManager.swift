//
//  AIPromptTemplateManager.swift
//  Loreweave
//
//  AI 프롬프트 템플릿 관리 - JSON 파일에서 CLI별 템플릿 로드
//  템플릿 파일 위치: Resources/AIPromptTemplates.json
//

import Foundation

/// CLI별 설정 구조
struct CLIConfig: Codable {
    let templates: Templates

    struct Templates: Codable {
        let contextWrapper: TemplateItem
        let contextCard: TemplateItem
        let contextSeparator: SeparatorItem
    }

    struct TemplateItem: Codable {
        let description: String
        let template: String
    }

    struct SeparatorItem: Codable {
        let description: String
        let value: String
    }


}

/// 프롬프트 템플릿 JSON 전체 구조
struct AIPromptTemplatesFile: Codable {
    let version: String
    let description: String
    let claude: CLIConfig
    let chatgpt: CLIConfig
}

/// 프롬프트 템플릿 매니저 (싱글톤)
final class AIPromptTemplateManager {
    static let shared = AIPromptTemplateManager()

    private var templatesFile: AIPromptTemplatesFile?

    private init() {
        loadTemplates()
    }

    // MARK: - Template Loading

    /// JSON 파일에서 템플릿 로드
    private func loadTemplates() {
        guard let url = Bundle.main.url(forResource: "AIPromptTemplates", withExtension: "json") else {
            print("⚠️ AIPromptTemplateManager: AIPromptTemplates.json 파일을 찾을 수 없음")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            templatesFile = try decoder.decode(AIPromptTemplatesFile.self, from: data)
            print("✅ AIPromptTemplateManager: 템플릿 로드 완료 (v\(templatesFile?.version ?? "?"))")
        } catch {
            print("❌ AIPromptTemplateManager: 템플릿 파싱 실패 - \(error)")
        }
    }

    /// 템플릿 리로드 (개발용)
    func reloadTemplates() {
        loadTemplates()
    }

    // MARK: - CLI Config Access

    /// CLI 타입에 대한 설정 가져오기
    private func getConfig(for cliType: AICLIType) -> CLIConfig? {
        switch cliType {
        case .claude:
            return templatesFile?.claude
        case .chatgpt:
            return templatesFile?.chatgpt
        }
    }

    // MARK: - Prompt Building

    /// 컨텍스트가 포함된 프롬프트 생성 (CLI별 템플릿 사용)
    /// - Parameters:
    ///   - userInput: 사용자 입력
    ///   - taggedCards: 태그된 대화 카드들 (질문, 답변 쌍)
    ///   - cliType: CLI 타입
    /// - Returns: 최종 프롬프트
    func buildPromptWithContext(
        userInput: String,
        taggedCards: [(question: String, answer: String)],
        cliType: AICLIType = .claude
    ) -> String {
        guard !taggedCards.isEmpty else {
            return userInput
        }

        let config = getConfig(for: cliType)
        let cardTemplate = config?.templates.contextCard.template ?? "[이전 대화 참조]\n질문: {{question}}\n답변: {{answer}}"
        let separator = config?.templates.contextSeparator.value ?? "\n\n"
        let wrapperTemplate = config?.templates.contextWrapper.template ?? "다음 이전 대화 내용을 참조하여 질문에 답변해주세요:\n\n{{context}}\n\n---\n현재 질문: {{userInput}}"

        // 각 카드를 템플릿에 적용
        let contextParts = taggedCards.map { card in
            Self.render(cardTemplate, values: ["question": card.question, "answer": card.answer])
        }

        // 컨텍스트 합치기
        let contextSection = contextParts.joined(separator: separator)

        // 최종 프롬프트 생성
        return Self.render(wrapperTemplate, values: ["context": contextSection, "userInput": userInput])
    }

    static func render(_ template: String, values: [String: String], doubleBraces: Bool = true) -> String {
        let expression = doubleBraces ? "\\{\\{([A-Za-z]+)\\}\\}" : "\\{([A-Za-z]+)\\}"
        guard let pattern = try? NSRegularExpression(pattern: expression) else { return template }
        var result = template
        for match in pattern.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: template),
                  let range = Range(match.range, in: result), let value = values[String(template[keyRange])] else { continue }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

}
