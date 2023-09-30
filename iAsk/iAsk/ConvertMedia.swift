//
//  ConvertMedia.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/17/23.
//

import Foundation
import FFmpeg_Kit
import NanoID
import ImageIO

enum ConvertError: Error {
    case invalidURL
    case conversionFailed(String?)
}

extension ConvertMediaArgs.ItemArgs {
    struct FFmpegConfig {
        let command: String
        let url: URL
    }
    
    var ffmpegConfig: FFmpegConfig? {
        guard let file = self.inputFilePath, let url = URL(string: file) else {
            return nil
        }
        let urlWithoutExtension = url.deletingPathExtension()
        var outputExtension = self.outputExtension
        
        outputExtension = outputExtension?.replacingOccurrences(of: ".", with: "")
        
        if outputExtension == "jpeg" {
            outputExtension = "jpg"
        }
        
        let isMp3 = outputExtension == "mp3"
        if isMp3 {
            outputExtension = "m4a"
        }
        
        if url.pathExtension == "png" {
            if isAPNG(url: url) {
                print("Oh no, an animated PNG!")
            }
        }
        
        if outputExtension == nil || outputExtension == url.pathExtension {
            let id = ID()
            outputExtension = "\(id.generate()).\(url.pathExtension)"
        }
        let inputPath = "\'\(url.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)\'"
        let outputURL = urlWithoutExtension.appendingPathExtension(outputExtension!)
        let outputPath = "\'\(outputURL.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)\'"

        var command = self.command != nil ? " \(self.command!) " : ""
        
        let hasInput = command.contains(" -i ")
        
        if hasInput {
            var args = command.components(separatedBy: " -")
            args = args.filter { text in
                return !text.starts(with: "i ")
            }
            command = "-\(args.joined(separator: " -"))"
        }
        
        let commandComponents = command.components(separatedBy: "file://")
        
        command = commandComponents.first ?? command
        
        command = command.replacingOccurrences(of: "\"", with: "'")
        
        let combinedCommand = "-y -i \(inputPath)\(command) \(outputPath)"
        
        return FFmpegConfig(command: combinedCommand, url: outputURL)
    }
}

func convertFile(config: ConvertMediaArgs.ItemArgs.FFmpegConfig?) async throws -> URL {
    guard let config = config else {
        throw ConvertError.invalidURL
    }

    try await ffmpeg(command: config.command)
    
    var outputURL = config.url
    
    let id = ID()
    
    if outputURL.pathExtension == "apng",
       let url = changeFileExtension(url: outputURL, newExtension: "\(id.generate()).png")
    {
        outputURL = url
    }
    
    return outputURL
}

func makeVideoThumbnail(url: URL, outputURL: URL) async throws -> URL {

    let inputPath = "\'\(url.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)\'"
    let outputPath = "\'\(outputURL.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding!)\'"
    
    let command = "-y -i \(inputPath) -vf \'blackdetect=d=0.1:pic_th=0.4:pix_th=0.5\' -frames:v 1 \(outputPath)"
    
    try await ffmpeg(command: command)
    
    return outputURL
}

func ffmpeg(command: String) async throws {
    
    let session: FFmpegSession = FFmpegKit.execute(command)
    
    let returnCode = session.getReturnCode()
    
    let logs = session.getAllLogsAsString()
    
    if ReturnCode.isSuccess(returnCode) {
        print("success")
        return
    }
    else if ReturnCode.isCancel(returnCode) {
        print("cancel")
    }
    else {
        print("fail", FFmpegKitConfig.sessionState(toString: session.getState()))
    }
    
    throw ConvertError.conversionFailed(logs)
}

func printEncoders() {
    let session: FFmpegSession = FFmpegKit.execute("-encoders")
    
    let returnCode = session.getReturnCode()
    
    let logs = session.getAllLogsAsString()
    
    print(logs)
    
    if ReturnCode.isSuccess(returnCode) {
        print("success")
        return
    }
    else if ReturnCode.isCancel(returnCode) {
        print("cancel")
    }
    else {
        print("fail", FFmpegKitConfig.sessionState(toString: session.getState()))
    }
}

func isAPNG(url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return false
    }
    
    let count = CGImageSourceGetCount(source)
    return count > 1
}
