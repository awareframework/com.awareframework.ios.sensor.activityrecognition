//
//  ActivityRecognitionSensor.swift
//  com.aware.ios.sensor.activityrecognition
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import UIKit
import CoreMotion
import com_awareframework_ios_sensor_core

public class ActivityRecognitionSensor: AwareSensor {

    public static let TAG = "AWARE::ActivityRecognition"
    public var CONFIG:ActivityRecognitionSensor.Config = Config()
    var LAST_ACTIVITY:ActivityRecognitionData = ActivityRecognitionData()
    
    var motionActivityManager:CMMotionActivityManager?
    var timer:Timer? = nil
    var inRecoveryLoop = false
    
    public class Config:SensorConfig{
        
        public var interval:Int = 10 // min
        {
            didSet {
                if self.interval <= 0 {
                    print("[ActivityRecognition][Illegal Parameter]",
                          "The `interval` value has to be greater than 0.",
                          "This paprameter ('\(self.interval)') is ignored.")
                    self.interval = oldValue
                }
            }
        }
        
        public var sensorObserver:ActivityRecognitionObserver?
        
        public override init() {
            super.init()
            dbPath = "aware_activityrecognition"
        }
        
        public override func set(config: Dictionary<String, Any>) {
            super.set(config: config)
            if let interval = config["interval"] as? Int {
                self.interval = interval
            }
        }
        
        public func apply(closure:(_ config: ActivityRecognitionSensor.Config) -> Void) -> Self {
            closure(self)
            return self
        }
    }
    
    public override convenience init() {
        self.init( ActivityRecognitionSensor.Config())
    }
    
    public init(_ config:ActivityRecognitionSensor.Config) {
        super.init()
        CONFIG = config
        initializeDbEngine(config: config)
    }
    
    public override func start() {
        guard self.timer == nil else {
            return
        }
        guard self.motionActivityManager == nil else {
            return
        }
        if CMMotionActivityManager.isActivityAvailable() {
            self.motionActivityManager = CMMotionActivityManager()
            self.timer = Timer.scheduledTimer(withTimeInterval: Double(self.CONFIG.interval)*60.0, repeats: true, block: { timer in
                if !self.inRecoveryLoop {
                    self.getActivityRecognitionData()
                }else{
                    if self.CONFIG.debug { print(ActivityRecognitionSensor.TAG, "skip: a recovery roop is running") }
                }
            })
            self.timer?.fire()
            self.notificationCenter.post(name: .actionAwareActivityRecognitionStart, object: self)
        }else{
            if self.CONFIG.debug {
                print(ActivityRecognitionSensor.TAG, "CMMotionActivityManager is not available.")
            }
        }
    }
    
    public func getActivityRecognitionData(){
        if let maManager = motionActivityManager , let fromDate = self.getLastUpdateDateTime(){
            let now = Date()
            let diffBetweemNowAndFromDate = now.minutes(from: fromDate)
            // if self.CONFIG.debug{ print(ActivityRecognitionSensor.TAG, "diff: \(diffBetweemNowAndFromDate) min") }
            if diffBetweemNowAndFromDate > Int(CONFIG.interval) {
                let toDate = fromDate.addingTimeInterval(60.0*Double(self.CONFIG.interval))
                maManager.queryActivityStarting(from: fromDate, to: toDate, to: .main) { (activities, error) in
                    // save pedometer data
                    var dataArray = Array<ActivityRecognitionData>()
                    if let uwActivities = activities {
                        if uwActivities.count == 0 {
                            // USE_LAST_ACTIVITY
                            let data = ActivityRecognitionData()
                            data.timestamp = Int64(fromDate.timeIntervalSince1970*1000)
                            data.automotive = self.LAST_ACTIVITY.automotive
                            data.cycling = self.LAST_ACTIVITY.cycling
                            data.running = self.LAST_ACTIVITY.running
                            data.stationary = self.LAST_ACTIVITY.stationary
                            data.unknown = self.LAST_ACTIVITY.unknown
                            data.walking = self.LAST_ACTIVITY.walking
                            data.confidence = self.LAST_ACTIVITY.confidence
                            data.label = self.CONFIG.label
                            dataArray.append(data)
                        }else{
                            for activity in uwActivities {
                                let data = ActivityRecognitionData()
                                data.timestamp = Int64(activity.startDate.timeIntervalSince1970*1000)
                                data.automotive = activity.automotive
                                data.cycling = activity.cycling
                                data.running = activity.running
                                data.stationary = activity.stationary
                                data.unknown = activity.unknown
                                data.walking = activity.walking
                                data.confidence = activity.confidence.rawValue
                                data.label = self.CONFIG.label
                                dataArray.append(data)
                                
                                switch activity.confidence {
                                case .high,.medium:
                                    if !data.unknown && (data.automotive || data.cycling || data.running || data.stationary || data.walking ) {
                                        self.LAST_ACTIVITY = data
                                        print(ActivityRecognitionSensor.TAG, "LAST_ACTIVITY: \(data)")
                                    }
                                case .low:
                                    continue
                                @unknown default:
                                    continue
                                }
                            }
                        }
                        
                        if self.CONFIG.debug {
                            // print(ActivityRecognitionSensor.TAG, "" )
                        }
                        
                        if let observer = self.CONFIG.sensorObserver {
                            observer.onActivityChanged(data:dataArray)
                        }
                        
                        if let engine = self.dbEngine {
                            let queue = DispatchQueue(label: "com.awareframework.ios.sensor.activityrecognition.save.queue")
                            queue.async {
                                engine.save(dataArray){error in
                                    if error == nil {
                                        DispatchQueue.main.async {
                                            self.setLastUpdateDateTime(toDate)
                                            let diffBetweenNowAndToDate = now.minutes(from: toDate)
                                            if diffBetweenNowAndToDate > Int(self.CONFIG.interval){
                                                self.inRecoveryLoop = true;
                                                self.getActivityRecognitionData()
                                            }else{
                                                self.inRecoveryLoop = false;
                                            }
                                            self.notificationCenter.post(name: .actionAwareActivityRecognition , object: self)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }else{
                self.inRecoveryLoop = false;
            }
        }
    }
    
    public override func stop() {
        if let uwTimer = timer {
            uwTimer.invalidate()
            timer = nil
            motionActivityManager = nil
            self.notificationCenter.post(name: .actionAwareActivityRecognitionStop , object: self)
        }
    }
    
    public override func sync(force: Bool = false) {
        if let engine = self.dbEngine {
            engine.startSync(ActivityRecognitionData.TABLE_NAME , ActivityRecognitionData.self, DbSyncConfig().apply{config in
                config.debug = self.CONFIG.debug
                config.dispatchQueue = DispatchQueue(label: "com.awareframework.ios.sensor.activityrecognition.sync.queue")
                config.completionHandler = { (status, error) in
                    var userInfo: Dictionary<String,Any> = [ActivityRecognitionSensor.EXTRA_STATUS :status]
                    if let e = error {
                        userInfo[ActivityRecognitionSensor.EXTRA_ERROR] = e
                    }
                    self.notificationCenter.post(name: .actionAwareActivityRecognitionSyncCompletion ,
                                                 object: self,
                                                 userInfo:userInfo)
                }
            })
            self.notificationCenter.post(name: .actionAwareActivityRecognitionSync , object: self)
        }
    }
    
    public override func set(label:String){
        self.CONFIG.label = label
        self.notificationCenter.post(name: .actionAwareActivityRecognitionSetLabel,
                                     object: self,
                                     userInfo: [ActivityRecognitionSensor.EXTRA_LABEL:label])
    }
}

extension Date {
    /// Returns the amount of minutes from another date
    func minutes(from date: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: self).minute ?? 0
    }
}

public protocol ActivityRecognitionObserver {
    func onActivityChanged(data:Array<ActivityRecognitionData>)
}

extension Notification.Name{
    public static let actionAwareActivityRecognition = Notification.Name(ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION)
    public static let actionAwareActivityRecognitionStart = Notification.Name(ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_START)
    public static let actionAwareActivityRecognitionStop = Notification.Name(ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_STOP)
    public static let actionAwareActivityRecognitionSync = Notification.Name(ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_SYNC)
    public static let actionAwareActivityRecognitionSetLabel = Notification.Name(ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_SET_LABEL)
    public static let actionAwareActivityRecognitionSyncCompletion = Notification.Name(ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_SYNC_COMPLETION)
}

extension ActivityRecognitionSensor{
    public static let ACTION_AWARE_ACTIVITYRECOGNITION       = "com.awareframework.ios.sensor.activityrecognition.ACTION_AWARE_ACTIVITYRECOGNITION"
    public static let ACTION_AWARE_ACTIVITYRECOGNITION_START = "com.awareframework.ios.sensor.activityrecognition.ACTION_AWARE_ACTIVITYRECOGNITION_START"
    public static let ACTION_AWARE_ACTIVITYRECOGNITION_STOP  = "com.awareframework.ios.sensor.activityrecognition.ACTION_AWARE_ACTIVITYRECOGNITION_STOP"
    public static let ACTION_AWARE_ACTIVITYRECOGNITION_SET_LABEL = "com.awareframework.ios.sensor.activityrecognition.ACTION_AWARE_ACTIVITYRECOGNITION_SET_LABEL"
    public static let ACTION_AWARE_ACTIVITYRECOGNITION_SYNC  = "com.awareframework.ios.sensor.activityrecognition.ACTION_AWARE_ACTIVITYRECOGNITION_SENSOR_SYNC"
    public static let ACTION_AWARE_ACTIVITYRECOGNITION_SYNC_COMPLETION = "com.awareframework.ios.sensor.activityrecognition.ACTION_AWARE_ACTIVITYRECOGNITION_SYNC_SUCCESS_COMPLETION"
    public static var EXTRA_LABEL = "label"
    public static let EXTRA_STATUS = "status"
    public static let EXTRA_ERROR = "error"
}

extension ActivityRecognitionSensor {
    
    public static let KEY_LAST_UPDATE_DATETIME = "com.aware.ios.sensor.activityrecognition.key.last_update_datetime";
    
    public func getFomattedDateTime(_ date:Date) -> Date?{
        let calendar = Calendar.current
        let year  = calendar.component(.year,   from: date)
        let month = calendar.component(.month,  from: date)
        let day   = calendar.component(.day,    from: date)
        let hour  = calendar.component(.hour,   from: date)
        let min   = calendar.component(.minute, from: date)
        let newDate = calendar.date(from: DateComponents(year:year, month:month, day:day, hour:hour, minute:min))
        return newDate
    }
    
    public func getLastUpdateDateTime() -> Date? {
        if let datetime = UserDefaults.standard.object(forKey: ActivityRecognitionSensor.KEY_LAST_UPDATE_DATETIME) as? Date {
            return datetime
        }else{
            let date = Date()
            let calendar = Calendar.current
            let year  = calendar.component(.year,   from: date)
            let month = calendar.component(.month,  from: date)
            let day   = calendar.component(.day,    from: date)
            let hour  = calendar.component(.hour,    from: date)
            let newDate = calendar.date(from: DateComponents(year:year, month:month, day:day, hour:hour, minute:0))
            if let uwDate = newDate {
                self.setLastUpdateDateTime(uwDate)
                return uwDate
            }else{
                if self.CONFIG.debug { print(ActivityRecognitionSensor.TAG, "[Error] KEY_LAST_UPDATE_DATETIME is null." ) }
                return nil
            }
        }
    }
    
    public func setLastUpdateDateTime(_ datetime:Date){
        if let newDateTime = self.getFomattedDateTime(datetime) {
            UserDefaults.standard.set(newDateTime, forKey:ActivityRecognitionSensor.KEY_LAST_UPDATE_DATETIME)
            UserDefaults.standard.synchronize()
            return
        }
        if self.CONFIG.debug { print(ActivityRecognitionSensor.TAG, "[Error] Date Time is null.") }
    }
    
}
