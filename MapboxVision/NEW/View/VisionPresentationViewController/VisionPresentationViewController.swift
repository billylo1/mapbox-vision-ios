import Foundation
import UIKit
import AVFoundation
import MetalKit
import AVKit
import MapboxVisionNative

private let contentInset: CGFloat = 16
private let safeAreaContentInset: CGFloat = 2
private let innerRelativeInset: CGFloat = 10

/**
    Object that is capable of presenting objects emitted from `VisionManager`.
*/
public final class VisionPresentationViewController: UIViewController {

    // MARK: Properties

    /**
        Control the visibility of the Mapbox logo.
    */
    public var isLogoVisible: Bool {
        get {
            return !logoView.isHidden
        }
        set {
            logoView.isHidden = !newValue
        }
    }

//    public func showLogo(show: Bool) {
//
//    }

    // MARK: Private properties

    private var contentContainerConstraints = [NSLayoutConstraint]()
    private weak var output: VisionPresentationViewControllerOutput!

    private var activeView: UIView

//    private var videoStreamView: VideoStreamView
//    private var segmentationView: MTKView
    private var detectionsView: DetectionsView

    private var backgroundView: UIView
    private var contentView: UIView

    private var logoView: UIView
    private var measurementStackView: UIStackView

    private var segmentationFPSLabel: UILabel
    private var detectionFPSLabel: UILabel
    private var mergedSegDetectFPSLabel: UILabel
    private var roadConfidenceFPSLabel: UILabel
    private var coreUpdateFPSLabel: UILabel

    private func view(for mode: VisualizationMode) -> UIView {
        switch mode {
        case .clear:
            return videoStreamView
        case .segmentation:
            return segmentationView
        case .detection:
            return detectionsView
        }
    }
  
    private lazy var segmentationDrawer: SegmentationDrawer? = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure("SegmentationDrawer: Can't create MTLDevice")
            return nil
        }
        return SegmentationDrawer(device: device)
    }()


    s
    private let videoStreamView: VideoStreamView = {
        return VideoStreamView()
    }()

    private let segmentationView: MTKView = {
        return SegmentationView()
    }()







    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let detectionsView: DetectionsView = {
        let view = DetectionsView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }()

    private let logoView: UIView = {
        let view = UIImageView(image: VisionImages.logo.image)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0.5
        return view
    }()

    private lazy var segmentationFPSLabel: UILabel = fpsLabel()
    private lazy var detectionFPSLabel: UILabel = fpsLabel()
    private lazy var mergedSegDetectFPSLabel: UILabel = fpsLabel()
    private lazy var roadConfidenceFPSLabel: UILabel = fpsLabel()
    private lazy var coreUpdateFPSLabel: UILabel = fpsLabel()

    private lazy var measurementStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            fpsStack(views: [fpsLabel(text: "Segmentation:"), segmentationFPSLabel]),
            fpsStack(views: [fpsLabel(text: "Detection:"), detectionFPSLabel]),
            fpsStack(views: [fpsLabel(text: "Merged S+D:"), mergedSegDetectFPSLabel]),
            fpsStack(views: [fpsLabel(text: "Road conf:"), roadConfidenceFPSLabel]),
            fpsStack(views: [fpsLabel(text: "Core update:"), coreUpdateFPSLabel]),
            ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.distribution = .equalCentering
        stack.spacing = innerRelativeInset
        stack.isHidden = true

        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        stack.insertSubview(backgroundView, at: 0)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: stack.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
            ])

        return stack
    }()

    // MARK: Lifecycle

    /// :nodoc:
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }
    
    /// :nodoc:
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        setupContentView()
    }
    
    /// :nodoc:
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupContentView()
    }
    
    /// :nodoc:
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.setupContentView()
        })
    }

    // MARK: Public functions

    /**
     Set visualization mode.
     */
    public var frameVisualizationMode: VisualizationMode = .clear {
        didSet {
            let previousTopView = view(for: oldValue)
            previousTopView.isHidden = true

            let newTopView = view(for: frameVisualizationMode)
            backgroundView.bringSubviewToFront(newTopView)
        }
    }

    public func setClearVisualizationMode() {
        output.set(visualizationMode: .clear)
    }

    public func setSegmentationVisualizationMode() {
        output.set(visualizationMode: .segmentation)
    }

    public func setDetectionVisualizationMode() {
        output.set(visualizationMode: .detection)
    }


    // MARK: Private functions

    private func setupContentView() {
        NSLayoutConstraint.deactivate(contentContainerConstraints)
        
        var leadingInset: CGFloat = contentInset
        var trailingInset: CGFloat = contentInset
        
        if view.safeAreaInsets.right > 0 {
            // iPhone X in landscape
            let uiOrientation = UIApplication.shared.statusBarOrientation
            if uiOrientation == .landscapeRight {
                // notch is on the left
                leadingInset = view.safeAreaInsets.left
            } else if uiOrientation == .landscapeLeft {
                // notch is on the right
                trailingInset = view.safeAreaInsets.right
            }
        }
        
        let topInset = view.safeAreaInsets.top > 0 ? safeAreaContentInset + view.safeAreaInsets.top : contentInset
        let bottomInset = contentInset
        
        contentContainerConstraints = [
            contentView.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottomInset),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leadingInset),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -trailingInset),
        ]
        
        NSLayoutConstraint.activate(contentContainerConstraints)
    }
    
    private func setupLayout() {
        setupBackgroundView()
        
        setupContentLayout()
        
        view.addSubview(logoView)
        NSLayoutConstraint.activate([
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalToSystemSpacingBelow: logoView.bottomAnchor, multiplier: 1),
            view.safeAreaLayoutGuide.rightAnchor.constraint(equalToSystemSpacingAfter: logoView.rightAnchor, multiplier: 1),
        ])
    }
    
    private func setupBackgroundView() {
        view.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        backgroundView.addSubview(videoStreamView)
        NSLayoutConstraint.activate([
            videoStreamView.topAnchor.constraint(equalTo: view.topAnchor),
            videoStreamView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoStreamView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoStreamView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        backgroundView.addSubview(segmentationView)
        NSLayoutConstraint.activate([
            segmentationView.topAnchor.constraint(equalTo: view.topAnchor),
            segmentationView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            segmentationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        backgroundView.addSubview(detectionsView)
        NSLayoutConstraint.activate([
            detectionsView.topAnchor.constraint(equalTo: view.topAnchor),
            detectionsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            detectionsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            detectionsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    
    private func setupContentLayout() {
        view.addSubview(contentView)
        
        contentView.addSubview(measurementStack)
        NSLayoutConstraint.activate([
            measurementStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            measurementStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        ])
    }
    
    private func fpsLabel(text: String? = nil) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = UIFont(name: "Menlo", size: 10)
        label.text = text
        return label
    }
    
    private func fpsStack(views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = innerRelativeInset
        stack.distribution = .equalCentering
        return stack
    }
}

extension VisionPresentationViewController: VisionPresentationViewControllerPublicInput {

}

extension VisionPresentationViewController: VisionPresentationViewControllerInput {
    
    /**
        Display sample buffer (e.g. taken from `VideoSource`).
    */
    public func present(sampleBuffer: CMSampleBuffer) {
        guard frameVisualizationMode == .clear else { return }
        
        DispatchQueue.main.async {
            guard self.viewIfLoaded?.window != nil else { return }
            
            self.videoStreamView.isHidden = false
            self.videoStreamView.enqueue(sampleBuffer)
        }
    }
    
    /// :nodoc:
    public func present(fps: FPSValue?) {
        measurementStack.isHidden = fps == nil
        guard let fps = fps else { return }
        segmentationFPSLabel.text = String(format: "%.2f", fps.segmentation)
        detectionFPSLabel.text = String(format: "%.2f", fps.detection)
        mergedSegDetectFPSLabel.text = String(format: "%.2f", fps.mergedSegmentationDetection)
        roadConfidenceFPSLabel.text = String(format: "%.2f", fps.roadConfidence)
        coreUpdateFPSLabel.text = String(format: "%.2f", fps.coreUpdate)
    }
    
    /**
        Display frame segmentation.
    */
    public func present(segmentation: FrameSegmentation) {
        guard frameVisualizationMode == .segmentation else { return }
        
        if segmentationView.delegate == nil {
            segmentationView.delegate = segmentationDrawer
        }
    
        segmentationView.isHidden = false
        
        segmentationView.drawableSize = segmentation.frame.image.size.cgSize
        segmentationDrawer?.set(segmentation)
        segmentationView.draw()
    }
    
    /**
        Display frame detections.
    */
    public func present(detections: FrameDetections) {
        guard
            frameVisualizationMode == .detection,
            let image = detections.frame.image.getUIImage()
        else { return }
        
        let imageSize = detections.frame.image.size.cgSize
        
        let values = detections.detections.map { detection -> BasicDetection in
            let rect = detection.boundingBox.convertedToAbsoluteCoordinates(relativeTo: imageSize)
                                            .convertedForAspectRatioFill(from: imageSize, to: detectionsView.bounds.size)
            return BasicDetection(boundingBox: rect, objectType: detection.detectionClass)
        }
        
        detectionsView.isHidden = false
        detectionsView.present(detections: values, at: image)
    }
}

private extension CGRect {
    func convertedForAspectRatioFill(from: CGSize, to: CGSize) -> CGRect {
        let leftTop = origin.convertForAspectRatioFill(from: from, to: to)
        let rightBottom = CGPoint(x: maxX, y: maxY).convertForAspectRatioFill(from: from, to: to)
        return CGRect(x: leftTop.x, y: leftTop.y, width: rightBottom.x - leftTop.x, height: rightBottom.y - leftTop.y)
    }

    func convertedToAbsoluteCoordinates(relativeTo frameSize: CGSize) -> CGRect {
        return CGRect(x: frameSize.width * self.origin.x,
                      y: frameSize.height * self.origin.y,
                      width: frameSize.width * self.size.width,
                      height: frameSize.height * self.size.height)
    }
}