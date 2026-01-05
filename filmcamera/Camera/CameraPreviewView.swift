//
//  CameraPreviewView.swift
//  iOS Vibe Film Camera
//
//  UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // No updates needed
    }
}

class VideoPreviewView: UIView {
    var session: AVCaptureSession? {
        didSet {
            previewLayer.session = session
        }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
    }
}
