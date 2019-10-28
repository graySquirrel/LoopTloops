//
//  ViewController.swift
//  LoopTloops
//
//  Created by Fritz Ebner on 4/12/19.
//  Copyright © 2019 Fritz Ebner. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreMotion

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    private let motion = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private var position:SCNVector3 = SCNVector3Make(0,0,0)  // updated every frame 60fps
    private var rotation:simd_float3 =  simd_float3(0,0,0) // updated every frame 60fps
    private var lastPosition:SCNVector3 = SCNVector3Make(0,0,0) // updated slowly in startQueuedUpdates
    private var shouldStartUpdating: Bool = false
    private var maxDist:Float = 0
    private var minDist:Float = 0
    private var avgDist:Float = 0
    private var leftMinFromCamera:Float = 0
    private var leftMinFromCameraPoint:simd_float3 = simd_float3(0,0,0)
    private var rightMaxFromCamera:Float = 0
    private var rightMaxFromCameraPoint:simd_float3 = simd_float3(0,0,0)
    private var leftHit:Float = 0
    private var rightHit:Float = 0
    private var featurePointCount:Int = 0
    private var hallwayFeaturePointCount:Int = 0
    private var leftxyzPt:simd_float3 = simd_float3(0,0,0)
    private var rightxyzPt:simd_float3 = simd_float3(0,0,0)
    private var lastFeaturePointTimestamp:TimeInterval = 0
    private var trackingState:ARCamera.TrackingState = ARCamera.TrackingState.notAvailable
    private var worldMappingStatus:Int = 0 //ARFrame.WorldMappingStatus = ARFrame.WorldMappingStatus.notAvailable
    private var startDate: Date? = nil

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var heading: UILabel!
    @IBOutlet weak var X: UILabel!
    @IBOutlet weak var Y: UILabel!
    @IBOutlet weak var Z: UILabel!
    @IBOutlet weak var pitch: UILabel!
    @IBOutlet weak var yaw: UILabel!
    @IBOutlet weak var roll: UILabel!
    @IBOutlet weak var leftlim: UILabel!
    @IBOutlet weak var rightlim: UILabel!
    @IBOutlet weak var theStartButton: UIButton!
    @IBOutlet weak var maxFeatureDistance: UILabel!
    @IBOutlet weak var minFeatureDistance: UILabel!
    @IBOutlet weak var avgFeatureDistance: UILabel!
    @IBOutlet weak var hallcount: UILabel!
    @IBOutlet weak var totalptcount: UILabel!
    @IBOutlet weak var leftxyzLabel: UILabel!
    @IBOutlet weak var rightxyzLabel: UILabel!
    @IBOutlet weak var ipaddressoutlet: UITextField!
    @IBOutlet weak var roundTripMs: UILabel!
    @IBAction func ipaddressAction(_ sender: UITextField) {
        let defaults = UserDefaults.standard
        //print(sender.text)
        defaults.set(sender.text, forKey: "IPAddress")
    }
    
    @IBAction func startButton(_ sender: UIButton) {
        shouldStartUpdating = !shouldStartUpdating
        shouldStartUpdating ? (onStart()) : (onStop())
    }

    let documentsPath = NSSearchPathForDirectoriesInDomains(
        .documentDirectory, .userDomainMask, true)[0]
    
    private func writeToFile(content: String, fileName: String = "log.txt") {
        let contentWithNewLine = content+"\n"
        let filePath = NSHomeDirectory() + "/Documents/" + fileName
        let fileHandle = FileHandle(forWritingAtPath: filePath)
        if (fileHandle != nil) {
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(contentWithNewLine.data(using: String.Encoding.utf8)!)
        }
        else {
            do {
                try contentWithNewLine.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error while creating \(filePath)")
            }
        }
    }
    
    private func removeFile(fileName: String = "log.txt") {
        let filePath = NSHomeDirectory() + "/Documents/" + fileName
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: filePath) {
                // Delete file
                try fileManager.removeItem(atPath: filePath)
            } else {
                print("File does not exist")
            }
        }
        catch let error as NSError {
            print("An error took place: \(error)")
        }
        
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        removeFile()

        let defaults = UserDefaults.standard
        if let ipaddr = defaults.string(forKey: "IPAddress") {
            ipaddressoutlet.text = ipaddr
        } else {
            ipaddressoutlet.text = "10.24.40.51"
        }
        // Set the view's delegate
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints,
                                  ARSCNDebugOptions.showWorldOrigin]
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    private func resetsession() {
        // Create a session configuration
        self.sceneView.session.pause()

        let configuration = ARWorldTrackingConfiguration()
        //configuration.worldAlignment = .gravityAndHeading // compass heading is SHIT
        configuration.worldAlignment = .gravity
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        self.sceneView.session.run(configuration, options: [.resetTracking])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
        
    }
    
    private func callLidar(with urlString:String, at dt:Date) {
        // takes start, stop
        guard let myip = ipaddressoutlet.text else {
            print("ipaddress not texty")
            return
        }
        
        guard let requestUrl = URL(string: "http://"+myip+":5000/"+urlString) else { return }
        let request = URLRequest(url:requestUrl)
        print(request)
        URLSession.shared.dataTask(with: request) {
            (data, response, error) in
                            if let error = error {
                                print(error.localizedDescription)
                            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                                // You can use data received.
                                if let unwrap = data {
                                    let d = String(decoding: unwrap, as: UTF8.self)
                                    if urlString == "logfile" {
                                        self.removeFile(fileName: "lidarlog.txt")
                                        self.writeToFile(content: d, fileName: "lidarlog.txt")
                                        }
                                    else {
                                        print(urlString,d)
                                        let currentDateTime = Date()
                                        let formatter = DateFormatter()
                                        formatter.calendar = Calendar(identifier: .iso8601)
                                        formatter.locale = Locale(identifier: "en_US_POSIX")
                                        formatter.timeZone = TimeZone(secondsFromGMT: 0)
                                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
                                        let formattedString = formatter.string(from: currentDateTime)
                                        print("phone now is " + formattedString)
                                        let tdiff = Int(1000 * (currentDateTime.timeIntervalSince1970 - dt.timeIntervalSince1970))
                                        print("roundtrip time is ", tdiff)
                                        if urlString.contains("start") {
                                            let rttime = "roundtrip " + String(tdiff) + " ms"
                                            print("start roundtrip",rttime)
                                            DispatchQueue.main.async { [weak self] in
                                                self?.roundTripMs.text = rttime
                                            }
                                        }
                                    }
                                }
                            }
            }.resume()
    }
    
    private func onStart() {
        theStartButton.setTitle("Stop", for: .normal)
        startDate = Date()
        checkAuthorizationStatus()
        resetsession()
        let currentDateTime = Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        let formattedString = formatter.string(from: currentDateTime)
        print(formattedString)
        //let timestamp = NSDate().timeIntervalSince1970
        //let tsint = String(Int32(timestamp)) // this chops off the millis.  just mul by 1000 to get milliseconds
        //print(tsint)
        //let lidArg = "start?date=" + tsint formattedString
        let escapedString = formattedString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)

        let lidArg = "start?date=" + escapedString!
        //callLidar(with: "rtttest", at: currentDateTime)
        callLidar(with: lidArg, at: currentDateTime)
        startUpdating()
    }
    
    private func onStop() {
        theStartButton.setTitle("Start", for: .normal)
        startDate = nil
        sceneView.session.pause()
        stopUpdating()
        callLidar(with: "stop", at: Date())
        callLidar(with: "logfile", at: Date())
    }
    private func startUpdating() {
        startQueuedUpdates()
        
        if CMMotionActivityManager.isActivityAvailable() {
            //startTrackingActivityType()
        } else {
            //activityTypeLabel.text = "Not available"
        }
        
        if CMPedometer.isStepCountingAvailable() {
            //startCountingSteps()
        } else {
            //stepsCountLabel.text = "Not available"
        }
    }
    private func checkAuthorizationStatus() {
        switch CMMotionActivityManager.authorizationStatus() {
        case CMAuthorizationStatus.denied:
            onStop()
            //activityTypeLabel.text = "Not available"
            //stepsCountLabel.text = "Not available"
        default:break
        }
    }
    
    private func stopUpdating() {
        activityManager.stopActivityUpdates()
        //pedometer.stopUpdates()
        //pedometer.stopEventUpdates()
        motion.stopDeviceMotionUpdates()
    }
    // MARK: - ARSCNViewDelegate
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        sceneView.scene.rootNode.childNodes[0].transform = SCNMatrix4Mult(sceneView.scene.rootNode.childNodes[0].transform, SCNMatrix4MakeRotation(Float(Double.pi) / 8, 1, 0, 0))
        //sceneView.scene.rootNode.childNodes[0].transform = SCNMatrix4Mult(sceneView.scene.rootNode.childNodes[0].transform, SCNMatrix4MakeTranslation(0, 0, -1))
        sceneView.scene.rootNode.childNodes[0].transform = SCNMatrix4Mult(sceneView.scene.rootNode.childNodes[0].transform, SCNMatrix4MakeTranslation(0, 0, 0.25))
        self.view.endEditing(true)

    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera:ARCamera) {
        print("cameraDidChangeTrackingState")
    }
/*
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
     
        return node
    }
*/

//    TODO: set delegate for this so it gets called. == just need to tell class it implements the ARSessionDelegate protocol
    func session(_ session: ARSession, didUpdate frame:ARFrame) {
        //print("didUpdate")
        let transform = frame.camera.transform
        let tinverse = transform.inverse
        position = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        //let p2 = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        rotation = frame.camera.eulerAngles
        
        // test translation from world to camera coordinates
        var worldPoint = matrix_identity_float4x4
//        translation.columns.3.x = transform.columns.3.x
//        translation.columns.3.y = transform.columns.3.y
//        translation.columns.3.z = transform.columns.3.z
//        let res = matrix_multiply(tinverse, translation)

        //let projection = frame.camera.projectionMatrix
        

        guard let rfp = frame.rawFeaturePoints else {return}
        if rfp.points.count > 0 {
            var dists:[Float] = []
            var pointsOfMinMax:[simd_float3] = [] //  x,y,z arrays of points relative to camera position.
            for point in rfp.points {
                //dists.append(simd_distance(point,p2))
                let x1 = Float(transform.columns.3.x)
                //let y1 = Float(transform.columns.3.y)
                let z1 = Float(transform.columns.3.z)
                let x2 = Float(point.x)
                let y2 = Float(point.y)
                let z2 = Float(point.z)
                //print(x1,y1,z1,x2,y2,z2)
                // find the position in front of the camera for each feature point
                worldPoint = matrix_identity_float4x4
                worldPoint.columns.3.x = x2
                worldPoint.columns.3.y = y2
                worldPoint.columns.3.z = z2
                let cameraPoint = matrix_multiply(tinverse, worldPoint)
                if (cameraPoint.columns.3.y < 1 && cameraPoint.columns.3.y > -0.5) {  // only track points that are not on floor or ceiling
                    pointsOfMinMax.append(simd_float3(cameraPoint.columns.3.x,cameraPoint.columns.3.y,cameraPoint.columns.3.z))
                }
                let dist = pow(x1 - x2, 2) + pow(z1 - z2, 2) // 2d distance, exclude Y, vertical
                let dist2 = dist.squareRoot()
                dists.append(dist2)
            }
            if (pointsOfMinMax.count > 0) {
                //leftMinFromCamera = exes.min()!
                //rightMaxFromCamera = exes.max()!
                let maxX = pointsOfMinMax.max(by: {$0.x < $1.x})?.x ?? 0
                let indexForPointWithMaxX = pointsOfMinMax.indices.filter{ pointsOfMinMax[$0].x == maxX}
                let minX = pointsOfMinMax.min(by: {$0.x < $1.x})?.x ?? 0
                let indexForPointWithMinX = pointsOfMinMax.indices.filter{ pointsOfMinMax[$0].x == minX}
                leftMinFromCameraPoint = pointsOfMinMax[indexForPointWithMinX[0]]
                leftMinFromCamera = leftMinFromCameraPoint.x
                rightMaxFromCameraPoint = pointsOfMinMax[indexForPointWithMaxX[0]]
                rightMaxFromCamera = rightMaxFromCameraPoint.x
                hallwayFeaturePointCount = pointsOfMinMax.count
            } else {
                leftMinFromCamera = 0
                rightMaxFromCamera = 0
                leftMinFromCameraPoint = simd_float3(0,0,0)
                rightMaxFromCameraPoint = simd_float3(0,0,0)
                hallwayFeaturePointCount = 0
            }
            maxDist = dists.max()!
            minDist = dists.min()!
            avgDist = dists.reduce(0,+)/Float(dists.count)
            featurePointCount = dists.count
            trackingState = frame.camera.trackingState
            worldMappingStatus = frame.worldMappingStatus.rawValue
            lastFeaturePointTimestamp = Date().timeIntervalSince1970
            
        } else {
            maxDist = 0
            minDist = 0
            avgDist = 0
            featurePointCount = 0
            worldMappingStatus = 0
            leftMinFromCamera = 0
            rightMaxFromCamera = 0
            hallwayFeaturePointCount = 0
        }
        //print(position)
        
        //print(rotation)
        //print(projection)
        //print("=================")
        
        // lets do a hit test at left and right to see what we get.
        // x,y in camera space is normalized for hit test, so x and y between 0 and 1 from top LEFT
        // at pitch == 0, use y = 0.5 and at pitch = -0.7, y should be 0 - only valid for my iPhone7
        //
        if (rotation.x > 0 || rotation.x < -0.7) {  // pitch not in range
            leftHit = 0
            rightHit = 0
        } else {
            let ypt = Double(0.5 + rotation.x * 0.5/0.7)
            //print(ypt)
            let leftPoint = CGPoint(x:0.0,y:ypt)
            let hitTestResultLeft:[ARHitTestResult] = frame.hitTest(leftPoint, types:.featurePoint)
            if (hitTestResultLeft.count > 0) {
                leftHit = Float(hitTestResultLeft[0].distance)
                worldPoint = hitTestResultLeft[0].worldTransform
                let cameraPoint = matrix_multiply(tinverse, worldPoint)
                leftxyzPt.x = cameraPoint.columns.3.x
                leftxyzPt.y = cameraPoint.columns.3.y
                leftxyzPt.z = cameraPoint.columns.3.z
            } else {
                leftHit = 0.0
                leftxyzPt.x = 0
                leftxyzPt.y = 0
                leftxyzPt.z = 0
            }
            let rightPoint = CGPoint(x:1.0,y:ypt)
            let hitTestResultRight:[ARHitTestResult] = frame.hitTest(rightPoint, types:.featurePoint)
            if (hitTestResultRight.count > 0) {
                rightHit = Float(hitTestResultRight[0].distance)
                worldPoint = hitTestResultRight[0].worldTransform
                let cameraPoint = matrix_multiply(tinverse, worldPoint)
                rightxyzPt.x = cameraPoint.columns.3.x
                rightxyzPt.y = cameraPoint.columns.3.y
                rightxyzPt.z = cameraPoint.columns.3.z

            } else {
                rightHit = 0.0
                rightxyzPt.x = 0
                rightxyzPt.y = 0
                rightxyzPt.z = 0
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    private func startQueuedUpdates() {
        if motion.isDeviceMotionAvailable {       self.motion.deviceMotionUpdateInterval = 1.0 / 3.0
            self.motion.showsDeviceMovementDisplay = true
            self.motion.startDeviceMotionUpdates(
                using: .xMagneticNorthZVertical,
                to: OperationQueue.main, withHandler: { (data, error) in
                    // Make sure the data is valid before accessing it.
                    if let validData = data {
                        // Get the attitude relative to the magnetic north reference frame.
                        //let roll = validData.attitude.roll  // around z axis looking through the front face
                        //let pitch = validData.attitude.pitch // around x axis left right when phone is portrait
                        //let yaw = validData.attitude.yaw    // around y axis when phone is portait
                        let headingVal = validData.heading
                        //let accel = validData.userAcceleration
                        //let x = round(100*accel.x)/100
                        //let y = round(100*accel.y)/100
                        //let z = round(100*accel.z)/100
                        //let a = round(100*sqrt(pow(accel.x,2) + pow(accel.y,2)))/100
                        //let d = round(100*atan2(accel.y,accel.x))/100
                        DispatchQueue.main.async {
                            self.heading.text = String(headingVal)
                            //self.userAcceleration.text = String(a) + " " + String(d)
                            let formatter = DateFormatter()
                            // initially set the format based on your datepicker date / server String
                            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS"
                            let myString = formatter.string(from: Date()) // string purpose I add here
                            //print(self.position)
                            print("rotation \(self.rotation)")
                            //let deltaPos = SCNVector3Make(self.position.x - self.lastPosition.x,
                            //                              self.position.y - self.lastPosition.y,
                            //                              self.position.z - self.lastPosition.z)
                            self.lastPosition = self.position
                            //print(deltaPos)
                            let pitch = self.rotation.x
                            let yaw = self.rotation.y
                            let roll = self.rotation.z
                            self.X.text = String(self.position.x)
                            self.Y.text = String(self.position.y)
                            self.Z.text = String(self.position.z)
                            self.pitch.text = String(pitch)
                            self.yaw.text = String(yaw)
                            self.roll.text = String(roll)
                            self.leftlim.text = String(self.leftMinFromCamera)
                            self.rightlim.text = String(self.rightMaxFromCamera)
                            self.hallcount.text = String(self.hallwayFeaturePointCount)
                            self.totalptcount.text = String(self.featurePointCount)
                            let featurePointTimeDiff = Date().timeIntervalSince1970 - self.lastFeaturePointTimestamp

                            self.leftxyzLabel.text = String(format:"left %.2f,%.2f,%.2f",
                                                            self.leftxyzPt.x, self.leftxyzPt.y, self.leftxyzPt.z)
                            self.rightxyzLabel.text = String(format:"rght %.2f,%.2f,%.2f",
                                                            self.rightxyzPt.x, self.rightxyzPt.y, self.rightxyzPt.z)
                            self.maxFeatureDistance.text = String(self.maxDist)
                            self.minFeatureDistance.text = String(self.minDist)
                            self.avgFeatureDistance.text = String(self.avgDist)
                            //print("\(myString), HEADING, \(String(describing: self.heading.text!))")
                            self.writeToFile(content: "\(myString), HEADING, \(String(describing: self.heading.text!))")
                            self.writeToFile(content: "\(myString), pitch, \(pitch)")
                            self.writeToFile(content: "\(myString), yaw, \(yaw)")
                            self.writeToFile(content: "\(myString), roll, \(roll)")
                            self.writeToFile(content: "\(myString), x, \(self.position.x)")
                            self.writeToFile(content: "\(myString), y, \(self.position.y)")
                            self.writeToFile(content: "\(myString), z, \(self.position.z)")
                            self.writeToFile(content: "\(myString), maxDist, \(self.maxDist)")
                            self.writeToFile(content: "\(myString), minDist, \(self.minDist)")
                            self.writeToFile(content: "\(myString), avgDist, \(self.avgDist)")
                            self.writeToFile(content: "\(myString), leftMinFromCamera, \(self.leftMinFromCamera)")
                            self.writeToFile(content: "\(myString), leftMinFromCameraY, \(self.leftMinFromCameraPoint.y)")
                            self.writeToFile(content: "\(myString), leftMinFromCameraZ, \(self.leftMinFromCameraPoint.z)")
                            self.writeToFile(content: "\(myString), rightMaxFromCamera, \(self.rightMaxFromCamera)")
                            self.writeToFile(content: "\(myString), rightMaxFromCameraY, \(self.rightMaxFromCameraPoint.y)")
                            self.writeToFile(content: "\(myString), rightMaxFromCameraZ, \(self.rightMaxFromCameraPoint.z)")
                            self.writeToFile(content: "\(myString), leftHit, \(self.leftHit)") // distance
                            self.writeToFile(content: "\(myString), leftHitX, \(self.leftxyzPt.x)") // distance
                            self.writeToFile(content: "\(myString), leftHitY, \(self.leftxyzPt.y)") // distance
                            self.writeToFile(content: "\(myString), leftHitZ, \(self.leftxyzPt.z)") // distance
                            self.writeToFile(content: "\(myString), rightHit, \(self.rightHit)") // distance
                            self.writeToFile(content: "\(myString), rightHitX, \(self.rightxyzPt.x)") // distance
                            self.writeToFile(content: "\(myString), rightHitY, \(self.rightxyzPt.y)") // distance
                            self.writeToFile(content: "\(myString), rightHitZ, \(self.rightxyzPt.z)") // distance
                            self.writeToFile(content: "\(myString), featurePointCount, \(self.featurePointCount)")
                            self.writeToFile(content: "\(myString), hallwayFeaturePointCount, \(self.hallwayFeaturePointCount)")
                            self.writeToFile(content: "\(myString), featurePointTimeDiff, \(featurePointTimeDiff)")
                            self.writeToFile(content: "\(myString), trackingState, \(self.trackingState)")
                            self.writeToFile(content: "\(myString), worldMappingStatus, \(self.worldMappingStatus)")
                            print("\(myString), trackingState, \(self.trackingState)")
                            print("\(myString), worldMappingStatus, \(self.worldMappingStatus)")
                            //self.resetsession() // makes all sorts of flashy yuck. i think its not good for my poor little phone.
                        }
                        
                        // Use the motion data in your app.
                    }
            })
        }
        else {
            DispatchQueue.main.async {
                self.heading.text = "ITS NOT AVAILABLE"
            }
        }
    }
}
