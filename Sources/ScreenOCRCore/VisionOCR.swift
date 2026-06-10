#if canImport(Vision)
import Foundation
import Vision

/// Apple Vision 프레임워크 기반 OCR 어댑터.
/// Python 사이드카 없이 온디바이스 텍스트 인식을 수행한다.
public struct VisionOCREngine: OCRRecognizing {

    public init() {}

    public func recognizeText(in image: CapturedImage) async throws -> OCRDocument {
        guard let filePath = image.filePath else {
            throw VisionOCRError.missingImagePath(imageID: image.id)
        }

        let imageURL = URL(fileURLWithPath: filePath)

        // Vision 호출은 동기 API — Task.detached로 async 래핑
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw VisionOCRError.recognitionFailed(message: error.localizedDescription)
            }

            guard let observations = request.results else {
                return OCRDocument(lines: [])
            }

            // boundingBox: 정규화 좌표, y = 0이 하단 → 위→아래, 왼→오 순서로 정렬
            let sorted = observations.sorted {
                let midY0 = $0.boundingBox.midY
                let midY1 = $1.boundingBox.midY
                // y가 클수록 위쪽이므로 내림차순, 같은 행이면 x 오름차순
                if abs(midY0 - midY1) > 0.001 {
                    return midY0 > midY1
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }

            // 행 높이 중앙값 계산 (같은 행 판별 임계값용)
            let heights = sorted.map { $0.boundingBox.height }
            let medianHeight: CGFloat = {
                guard !heights.isEmpty else { return 0 }
                let s = heights.sorted()
                let mid = s.count / 2
                return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
            }()
            let rowThreshold = medianHeight * 0.6

            // Python _layout_text 와 같은 개념: 가까운 행끼리 공백으로 join
            var rows: [[VNRecognizedTextObservation]] = []
            for obs in sorted {
                if let lastRow = rows.last,
                   let lastObs = lastRow.last,
                   abs(obs.boundingBox.midY - lastObs.boundingBox.midY) <= max(rowThreshold, 0.005) {
                    rows[rows.count - 1].append(obs)
                } else {
                    rows.append([obs])
                }
            }

            // 각 행 내부는 x 오름차순으로 재정렬하고 공백 join
            let lines: [OCRLine] = rows.compactMap { rowObs in
                let inOrder = rowObs.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                let candidates = inOrder.compactMap { $0.topCandidates(1).first }
                guard !candidates.isEmpty else { return nil }
                let text = candidates.map(\.string).joined(separator: " ")
                let score = candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)
                return OCRLine(text: text, score: score)
            }

            return OCRDocument(
                lines: lines,
                metadata: ["engine": "vision"]
            )
        }.value
    }
}

public enum VisionOCRError: Error, LocalizedError, Equatable {
    case missingImagePath(imageID: String)
    case recognitionFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingImagePath(let imageID):
            return "Captured image has no file path: \(imageID)"
        case .recognitionFailed(let message):
            return "Vision OCR recognition failed: \(message)"
        }
    }
}

#endif
