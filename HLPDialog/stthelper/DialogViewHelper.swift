/*******************************************************************************
 * Copyright (c) 2014, 2016  IBM Corporation, Carnegie Mellon University and others
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

import Foundation
import UIKit

public enum DialogViewState:String {
    case Unknown = "unknown"
    case Inactive = "inactive"
    case Speaking = "speaking"
    case Listening = "listening"
    case Recognized = "recognized"
    
    mutating func animTo(_ state:DialogViewState, target:DialogViewHelper) {
        let anims:[(from:DialogViewState,to:DialogViewState,anim:((DialogViewHelper)->Void))] = [
            (from:.Unknown, to:.Inactive, anim:{$0.inactiveAnim()}),
            (from:.Unknown, to:.Speaking, anim:{$0.speakpopAnim()}),
            (from:.Unknown, to:.Listening, anim:{$0.listenpopAnim()}),
            (from:.Unknown, to:.Recognized, anim:{$0.recognizeAnim()}),
            
            (from:.Inactive, to:.Recognized, anim:{$0.recognizeAnim()}),
            (from:.Speaking, to:.Recognized, anim:{$0.recognizeAnim()}),
            (from:.Listening, to:.Recognized, anim:{$0.recognizeAnim()}),
            
            (from:.Inactive, to:.Speaking, anim:{$0.speakpopAnim()}),
            (from:.Listening, to:.Speaking, anim:{$0.speakpopAnim()}),
            (from:.Recognized, to:.Speaking, anim:{$0.shrinkAnim(#selector($0.speakpopAnim)) }),
            
            (from:.Inactive, to:.Listening, anim:{$0.listenpopAnim()}),
            (from:.Speaking, to:.Listening, anim:{$0.listenpopAnim()}),
            (from:.Recognized, to:.Listening, anim:{$0.listenpopAnim()}),
            
            (from:.Speaking, to:.Inactive, anim:{$0.inactiveAnim()}),
            (from:.Listening, to:.Inactive, anim:{$0.inactiveAnim()}),
            (from:.Recognized, to:.Inactive, anim:{$0.inactiveAnim()})
        ]
        
        for tuple in anims {
            if (self == tuple.from && state == tuple.to) {
                tuple.anim(target);
            }
        }
        self = state;
    }
}

@objc
public protocol DialogViewDelegate {
    func dialogViewTapped()
}

@objcMembers
public class HelperView: UIView {
    var delegate: DialogViewDelegate?
    var bTabEnabled:Bool=false  // tap availability
    public var disabled:Bool = false {
        didSet {
            self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitStaticText
            if (disabled) {
                self.accessibilityTraits = self.accessibilityTraits | UIAccessibilityTraitNotEnabled
                self.layer.opacity = 0.25
            } else {
                self.layer.opacity = 1.0
            }
        }
    }
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.accessibilityLabel = NSLocalizedString("DialogSearch", tableName:nil, bundle: Bundle(for: type(of: self)), value: "", comment:"")
        self.isAccessibilityElement = true
        self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitStaticText | UIAccessibilityTraitNotEnabled
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }    
 
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (self.disabled) {
            return;
        }
        self.layer.opacity = 0.5
    }
    
    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (self.disabled) {
            return;
        }
        self.layer.opacity = 1.0
        delegate?.dialogViewTapped()
    }
}

@objcMembers
public class DialogViewHelper: NSObject {
    fileprivate var initialized: Bool = false
    
    fileprivate var background: AnimLayer!          // first circle
    fileprivate var circle: AnimLayer!              // second circle
    fileprivate var indicatorCenter: AnimLayer!     // speak indicator center / volume indicator
    fileprivate var indicatorLeft: AnimLayer!       // speak indicator left
    fileprivate var indicatorRight: AnimLayer!      // speak indicator right
    public var mainColor: CGColor = AnimLayer.blue
    public var subColor: CGColor = AnimLayer.white
    public var backgroundColor: CGColor = AnimLayer.gray
    fileprivate var micback: AnimLayer!     // mic background
    fileprivate var mic: CALayer!           // mic image
    fileprivate var micimgw:CGImage!        // mic white image
    fileprivate var micimgr:CGImage!        // mic red image
    fileprivate var power:Float = 0.0       // mic audio power
    fileprivate var recording = false       // recording flag
    fileprivate var threthold:Float = 80    // if power is bigger than threthold then volume indicator becomes biga
    fileprivate var maxScaleOfVolumeIndicator:Float = 1.4       // maximum scale for volume indicator
    fileprivate var speed:Float = 0.05      // reducing time
    
    fileprivate var timer:Timer!            // timer for animation
    fileprivate var outFilter:Float = 1.0   // lowpass filter param for max volume
    fileprivate var peakDuration:Float = 0.1// keep peak value for in this interval
    fileprivate var peakTimer:Float = 0
    
    fileprivate var bScale:Float=1.03       // small indication for mic input
    fileprivate var bDuration:Float=2.5     // breathing duration
    
    public var label: UILabel!
    
    fileprivate let Frequency:Float = 1.0/30.0
    fileprivate let MaxDB:Float = 110
    fileprivate var IconBackgroundSize:CGFloat = 139
    fileprivate var IconCircleSize:CGFloat = 113
    fileprivate var IconSize:CGFloat = 90
    fileprivate var IconSmallSize:CGFloat = 23
    fileprivate var SmallIconPadding:CGFloat = 33
    fileprivate var LabelHeight:CGFloat = 40
    fileprivate var ImageSize:CGFloat = 64
    
    fileprivate var ViewSize:CGFloat = 142
    public var helperView:HelperView!
    public var showsBackground:Bool = false
    public var scale:CGFloat = 1.0 {
        didSet {
            IconBackgroundSize = 139 * scale
            IconCircleSize = 113 * scale
            IconSize = 90 * scale
            IconSmallSize = 23 * scale
            SmallIconPadding = 33 * scale
            LabelHeight = 40 * scale
            ViewSize = 142 * scale
            ImageSize = 64 * scale
        }
    }
    
    fileprivate var viewState: DialogViewState {
        didSet {
            NSLog("\(viewState)")
        }
    }
    
    // MARK: - Public Properties
    
    public var state: DialogViewState {
        return viewState
    }
    
    public var delegate: DialogViewDelegate? {
        didSet {
            if helperView != nil {
                helperView!.delegate = delegate
            }
        }
    }
    
    // MARK: - Public Properties end
    
    
    override public init() {
        self.viewState = .Unknown
    }
    
    public func recognize() {
        DispatchQueue.main.async {
            self.viewState.animTo(.Recognized, target: self)
        }
    }
    
    public func speak() {
        DispatchQueue.main.async {
            self.viewState.animTo(.Speaking, target: self)
        }
    }
    
    public func listen() {
        DispatchQueue.main.async {
            self.viewState.animTo(.Listening, target: self)
        }
    }
    
    public func inactive() {
        DispatchQueue.main.async {
            self.viewState.animTo(.Inactive, target: self)
        }
    }
    
    func dialogViewTapped() {
        delegate?.dialogViewTapped()
    }
    
    public func setup(_ view:UIView, position:CGPoint) {
        self.setup(view, position:position, tapEnabled:false);
    }
    
    public func setup(_ view:UIView, position:CGPoint, tapEnabled:Bool) {
//        for direct layer rendering
//        let cx = position.x
//        let cy = position.y
//        let layerView = view
        
        helperView = HelperView(frame: CGRect(x: 0, y: 0, width: ViewSize, height: ViewSize))
        helperView.bTabEnabled = tapEnabled
        
        helperView.translatesAutoresizingMaskIntoConstraints = false;
        helperView.isOpaque = true
        let cx = ViewSize/2
        let cy = ViewSize/2
        let layerView = helperView
        
        view.addSubview(helperView)
        view.addConstraints([
            NSLayoutConstraint(
                item: helperView,
                attribute: .centerX,
                relatedBy: .equal,
                toItem: view,
                attribute: .left,
                multiplier: 1.0,
                constant: position.x
            ),
            NSLayoutConstraint(
                item: helperView,
                attribute: .centerY,
                relatedBy: .equal,
                toItem: view,
                attribute: .top,
                multiplier: 1.0,
                constant: position.y
            ),
            NSLayoutConstraint(
                item: helperView,
                attribute: .width,
                relatedBy: .equal,
                toItem: nil,
                attribute: .width,
                multiplier: 1.0,
                constant: ViewSize
            ),
            NSLayoutConstraint(
                item: helperView,
                attribute: .height,
                relatedBy: .equal,
                toItem: nil,
                attribute: .height,
                multiplier: 1.0,
                constant: ViewSize
            )
            ])
        
        func make(_ size:CGFloat, max:CGFloat, x:CGFloat, y:CGFloat, color:CGColor) -> AnimLayer {
            let layer = AnimLayer()
            layer.size = size
            layer.bounds = CGRect(x:0, y:0, width: max, height: max)
            layer.position = CGPoint(x:x, y:y)
            layerView?.layer.addSublayer(layer)
            layer.color = color
            layer.setNeedsDisplay()
            return layer
        }
        
        
        background = make(IconBackgroundSize, max: IconBackgroundSize, x: cx, y: cy,
                          color: showsBackground ? backgroundColor : AnimLayer.transparent)
        background.zPosition = 0
        circle = make(IconCircleSize, max: IconCircleSize, x: cx, y: cy, color: subColor)
        circle.zPosition = 1
        
        indicatorCenter = make(IconSmallSize, max:IconSize*3, x: cx, y: cy, color:mainColor)
        indicatorCenter.zPosition = 2
        indicatorCenter.opacity = 0
        indicatorLeft = make(IconSmallSize, max:IconSmallSize*2, x: cx-SmallIconPadding, y: cy, color:mainColor)
        indicatorLeft.zPosition = 2
        indicatorLeft.opacity = 0
        indicatorRight = make(IconSmallSize, max:IconSmallSize*2, x: cx+SmallIconPadding, y: cy, color:mainColor)
        indicatorRight.zPosition = 2
        indicatorRight.opacity = 0
        
        micback = make(IconSize, max:IconSize*2, x: cx, y: cy, color:mainColor)
        micback.zPosition = 3
        micback.opacity = 0
        mic = CALayer()
        mic.zPosition = 4
        mic.opacity = 0
        let bundle: Bundle = Bundle(for: type(of: self))
        let micMask: CGImage! = UIImage(named: "Mic_White", in: bundle, compatibleWith: nil)?.cgImage
        micimgw = icon(micMask, color: subColor)
        micimgr = icon(micMask, color: mainColor)
        mic.contents = micimgw
        mic.bounds = CGRect(x: 0, y: 0, width: ImageSize, height: ImageSize)
        mic.edgeAntialiasingMask = CAEdgeAntialiasingMask.layerLeftEdge.union(CAEdgeAntialiasingMask.layerRightEdge).union(CAEdgeAntialiasingMask.layerTopEdge).union(CAEdgeAntialiasingMask.layerBottomEdge)
        mic.position = CGPoint(x: cx, y: cy)
        layerView?.layer.addSublayer(mic)

        
        label = UILabel(frame: CGRect(x: 0, y: 0, width: 1000, height: LabelHeight))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont(name: "HelveticaNeue-Medium", size: 22)

        label.textAlignment = NSTextAlignment.center
        label.alpha = 0.3
        label.text = ""
        view.addSubview(label)
        
        view.addConstraints([
            NSLayoutConstraint(
                item: label,
                attribute: .centerX,
                relatedBy: .equal,
                toItem: view,
                attribute: .centerX,
                multiplier: 1.0,
                constant: 0
            ),
            NSLayoutConstraint(
                item: label,
                attribute: .centerY,
                relatedBy: .equal,
                toItem: view,
                attribute: .bottom,
                multiplier: 1.0,
                constant: CGFloat(-LabelHeight)
            ),
            NSLayoutConstraint(
                item: label,
                attribute: .width,
                relatedBy: .equal,
                toItem: view,
                attribute: .width,
                multiplier: 1.0,
                constant: 0
            ),
            NSLayoutConstraint(
                item: label,
                attribute: .height,
                relatedBy: .equal,
                toItem: nil,
                attribute: .height,
                multiplier: 1.0,
                constant: CGFloat(LabelHeight)
            )])
        
        //self.inactive()
        
        initialized = true
    }
    
    func setMaxPower(_ p:Float) {
        power = p;
    }
    
    
    // remove all animations
    public func reset() {
        timer?.invalidate()
        if initialized == false {
            return
        }
        for l:CALayer in [background, circle, indicatorCenter, indicatorLeft, indicatorRight, micback, mic] {
            l.removeAllAnimations()
        }
    }
    public func removeFromSuperview(){
        if let ttm = self.textTimer{
            ttm.invalidate()
        }
        self.label.text = ""
        self.label.removeFromSuperview()
        self.helperView.removeFromSuperview()
        self.text = ""
    }
    
    // MARK: - Anim Functions
    
    fileprivate func recognizeAnim() {
        NSLog("recognize anim")
        reset()
        circle.color = mainColor
        micback.color = subColor
        circle.setNeedsDisplay()
        micback.setNeedsDisplay()
        mic.contents = micimgr
        indicatorCenter.opacity = 0
        indicatorLeft.opacity = 0
        indicatorRight.opacity = 0
        micback.opacity = 1
        mic.opacity = 1
    }
    
    fileprivate func listenpopAnim() {
        NSLog("pop anim")
        reset()
        indicatorCenter.opacity = 1
        indicatorLeft.opacity = 0
        indicatorRight.opacity = 0
        micback.opacity = 0
        mic.opacity = 0
        mic.contents = micimgw
        indicatorCenter.size = 23
        micback.size = IconSize
        circle.color = subColor
        micback.color = mainColor
        circle.setNeedsDisplay()
        micback.setNeedsDisplay()
        
        
        let a1 = AnimLayer.scale(0.1, current:1, scale:IconSize, type:kCAMediaTimingFunctionLinear)
        indicatorCenter.add(a1, forKey: "scale")
        
        let a3 = AnimLayer.delay(AnimLayer.dissolve(0.1, type:kCAMediaTimingFunctionLinear), second:0.1);
        micback.add(a3, forKey: "dissolve")
        mic.add(a3, forKey: "dissolve")
        
        Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(listenAnim), userInfo: nil, repeats: false)
    }
    
    @objc fileprivate func listenAnim() {
        NSLog("listen anim")
        reset()
        circle.color = subColor
        micback.color = mainColor
        circle.setNeedsDisplay()
        micback.setNeedsDisplay()
        mic.opacity = 1
        mic.contents = micimgw
        indicatorCenter.size = IconSize
        indicatorCenter.opacity = 1
        indicatorLeft.opacity = 0
        indicatorRight.opacity = 0
        micback.size = IconSize
        micback.opacity = 1
        
        let a2 = AnimLayer.pulse(Double(bDuration), size: IconSize, scale: CGFloat(bScale))
        a2.repeatCount = 10000000
        micback.add(a2, forKey: "listen-breathing")
        
        timer = Timer.scheduledTimer(timeInterval: Double(Frequency), target: self, selector: #selector(listening(_:)), userInfo: nil, repeats: true)
    }
    
    @objc fileprivate func listening(_ timer:Timer) {
        var p:Float = power - threthold
        p = p / (MaxDB-threthold)
        p = max(p, 0)
        
        
        peakTimer -= Frequency
        
        if (peakTimer < 0) { // reduce max power gradually
            power -= MaxDB*Frequency/speed
            power = max(power, 0)
        }
        
        indicatorCenter.size = min(CGFloat(p * (maxScaleOfVolumeIndicator - 1.0) + 1.0) * IconSize, IconCircleSize)
        //NSLog("\(p), \(scale), \(indicatorCenter.size)")
        self.indicatorCenter.setNeedsDisplay()
    }
    
    fileprivate func shrinkAnim(_ sel:Selector) {
        if (mic.opacity == 0) {
            Timer.scheduledTimer(timeInterval: 0, target: self, selector: sel, userInfo: nil, repeats: false)
            return
        }
        
        NSLog("shrink anim")
        reset()
        indicatorCenter.opacity = 1
        indicatorLeft.opacity = 0
        indicatorRight.opacity = 0
        micback.opacity = 1
        mic.opacity = 1
        mic.contents = micimgw
        circle.color = subColor
        micback.color = mainColor
        circle.setNeedsDisplay()
        micback.setNeedsDisplay()
        
        let a1 = AnimLayer.dissolveOut(0.2, type: kCAMediaTimingFunctionEaseOut)
        let a2 = AnimLayer.scale(0.2, current: IconSize, scale: 0.0, type: kCAMediaTimingFunctionEaseOut)

        mic.add(a1, forKey: "shrink")
        micback.add(a1, forKey: "shrink")
        indicatorCenter.add(a2, forKey: "shrink")
        indicatorLeft.add(a2, forKey: "shrink")
        indicatorRight.add(a2, forKey: "shrink")
        
        
        Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: sel, userInfo: nil, repeats: false)
    }
    
    @objc fileprivate func speakpopAnim() {
        NSLog("speakpop anim")
        reset()
        indicatorCenter.opacity = 1
        indicatorLeft.opacity = 1
        indicatorRight.opacity = 1
        indicatorCenter.size = 1;
        indicatorLeft.size = 1;
        indicatorRight.size = 1;
        micback.opacity = 0
        mic.opacity = 0
        mic.contents = nil

        circle.color = subColor
        micback.color = mainColor
        circle.setNeedsDisplay()
        micback.setNeedsDisplay()
        
        let dissolve = AnimLayer.dissolve(0.2, type: kCAMediaTimingFunctionEaseOut)
        let scale = AnimLayer.scale(0.2, current: 1, scale: CGFloat(IconSmallSize), type:kCAMediaTimingFunctionLinear)
        
        indicatorLeft.add(dissolve, forKey: "speakpop1")
        indicatorLeft.add(scale, forKey: "speakpop2")
        indicatorCenter.add(dissolve, forKey: "speakpop1")
        indicatorCenter.add(scale, forKey: "speakpop2")
        indicatorRight.add(dissolve, forKey: "speakpop1")
        indicatorRight.add(scale, forKey: "speakpop2")
        
        Timer.scheduledTimer(timeInterval: 0.2, target: self,
                                               selector: #selector(speakAnim),
                                               userInfo: nil, repeats: false)
    }

    @objc fileprivate func speakAnim() {
        NSLog("speak anim")
        reset()
        indicatorCenter.opacity = 1
        indicatorLeft.opacity = 1
        indicatorRight.opacity = 1
        indicatorCenter.size = IconSmallSize;
        indicatorLeft.size = IconSmallSize;
        indicatorRight.size = IconSmallSize;
        indicatorCenter.setNeedsDisplay()
        indicatorLeft.setNeedsDisplay()
        indicatorRight.setNeedsDisplay()
        
        let pulse = AnimLayer.pulse(1/4.0, size: IconSmallSize, scale:1.03)
        pulse.repeatCount = 1000
        
        indicatorLeft.add(pulse, forKey: "speak1")
        indicatorCenter.add(pulse, forKey: "speak1")
        indicatorRight.add(pulse, forKey: "speak1")
    }
    
    fileprivate func inactiveAnim() {
        reset()
        indicatorCenter.opacity = 0
        indicatorLeft.opacity = 0
        indicatorRight.opacity = 0
        micback.opacity = 0
        mic.opacity = 0
        mic.contents = micimgw
        indicatorCenter.size = 23
        micback.size = IconSize
        circle.color = subColor
        micback.color = backgroundColor
        circle.setNeedsDisplay()
        micback.setNeedsDisplay()
        mic.contents = micimgr
        
        let a1 = AnimLayer.dissolve(0.2, type: kCAMediaTimingFunctionEaseOut)

        micback.add(a1, forKey: "inactive")
        mic.add(a1, forKey: "inactive")
    }
    
    // MARK: - Showing Text
    
    var textTimer:Timer?
    var textPos:Int = 0
    var text:String?
    public func showText(_ text:String) {
        
        let len = text.count
        
        if let currentText = self.label.text {
            if currentText.count < len ||
                self.label.text?.prefix(len-1).description != text {
                    textTimer?.invalidate()
                    textPos = (self.label.text?.count)!
                    textTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(DialogViewHelper.showText2(_:)), userInfo: nil, repeats: true)
            }
        } else {
            self.label.text = text
        }
        self.text = text
        NSLog("showText: \(text)")
    }
    
    func showText2(_ timer:Timer) {
        self.textPos += 1
        var part = self.text
        if (self.textPos < (self.text?.count)!) {
            part = self.text?.prefix(self.textPos-1).description
        }
        DispatchQueue.main.async {
 //           NSLog("showLabel: \(part)")
            self.label.text = part
        }
    }
    
    // MARK: - Utility Function
    
    static func delay(_ delay:Double, callback: @escaping ()->Void) {
        let time = DispatchTime.now() + Double((Int64)(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC);
        DispatchQueue.main.asyncAfter(deadline: time) {
            callback()
        }
    }

    func icon(_ image: CGImage, color: CGColor) -> CGImage {
        let rect: CGRect = CGRect(x:0, y:0, width:image.width, height:image.height)
        UIGraphicsBeginImageContext(rect.size)
        if let context: CGContext = UIGraphicsGetCurrentContext() {
            context.translateBy(x: CGFloat(context.width), y: CGFloat(context.height))
            context.rotate(by: CGFloat(Float.pi))
            context.clip(to: rect, mask: image)
            context.setFillColor(color)
            context.fill(rect)
            let img: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return img.cgImage!
        } else {
            UIGraphicsEndImageContext()
        }
        return image
    }
}
