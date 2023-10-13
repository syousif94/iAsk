//
//  Vision.swift
//  iAsk
//
//  Created by Sammy Yousif on 10/9/23.
//

import Vision
import UIKit
import PDFKit

enum TextRecognitionError: Error {
    case failedToLoadImage
    case failedToLoadPDF
}

struct TextObservation: Codable {
    struct BoundingBox: Codable {
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }
    
    let text: String
    let confidence: Float
    let boundingBox: BoundingBox
}

struct DataDimensions: Codable {
    let width: Float
    let height: Float
}

struct DataResult: Codable {
    let results: [TextObservation]
    let dimensions: DataDimensions
    
    var orderedText: String {
        let sortedResults = results.sorted {
            if $0.boundingBox.y != $1.boundingBox.y {
                return $0.boundingBox.y < $1.boundingBox.y
            } else {
                return $0.boundingBox.x < $1.boundingBox.x
            }
        }
        return sortedResults.map { $0.text }.joined(separator: " ")
    }
}

func recognizeText(from image: CGImage) throws -> [TextObservation] {
    let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try requestHandler.perform([request])
    guard let observations = request.results else {
        return []
    }
    return observations.compactMap { observation in
        guard let topCandidate = observation.topCandidates(1).first else {
            return nil
        }
        let boundingBox = TextObservation.BoundingBox(x: Float(observation.boundingBox.origin.x),
                                                      y: Float(observation.boundingBox.origin.y),
                                                      width: Float(observation.boundingBox.size.width),
                                                      height: Float(observation.boundingBox.size.height))
        return TextObservation(text: topCandidate.string,
                               confidence: Float(topCandidate.confidence),
                               boundingBox: boundingBox)
    }
}

func getTextFromImage(from url: URL) throws -> DataResult {
    guard let image = UIImage(contentsOfFile: url.path)?.cgImage else {
        throw TextRecognitionError.failedToLoadImage
    }
    let results = try recognizeText(from: image)
    let dimensions = DataDimensions(width: Float(image.width), height: Float(image.height))
    return DataResult(results: results, dimensions: dimensions)
}

func getTextFromPDF(from url: URL) throws -> DataResult {
    guard let pdfDocument = PDFDocument(url: url) else {
        throw TextRecognitionError.failedToLoadPDF
    }
    var results = [TextObservation]()
    for pageIndex in 0..<pdfDocument.pageCount {
        guard let page = pdfDocument.page(at: pageIndex) else { continue }
        guard let pageImage = page.thumbnail(of: CGSize(width: page.bounds(for: .mediaBox).width, height: page.bounds(for: .mediaBox).height), for: .mediaBox).cgImage else { continue }
        let pageResults = try recognizeText(from: pageImage)
        results.append(contentsOf: pageResults)
    }
    let dimensions = DataDimensions(width: Float(pdfDocument.page(at: 0)?.bounds(for: .mediaBox).size.width ?? 0),
                                    height: Float(pdfDocument.page(at: 0)?.bounds(for: .mediaBox).size.height ?? 0))
    return DataResult(results: results, dimensions: dimensions)
}
