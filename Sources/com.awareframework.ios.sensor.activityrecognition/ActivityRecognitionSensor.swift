//
//  ActivityRecognitionSensor.swift
//  com.aware.ios.sensor.activityrecognition
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

//import UIKit
import CoreMotion
import com_awareframework_ios_core

public class ActivityRecognitionSensor: AwareSensor {

    public static let TAG = "AWARE::ActivityRecognition"
    public var CONFIG:ActivityRecognitionSensor.Config = Config()
    var LAST_ACTIVITY:ActivityRecognitionData?
    
    // The timer, requests and cursor updates are coordinated on the main queue.
    private var motionActivityManager: CMMotionActivityManager?
    private var timer: Timer?
    private var isQuerying = false
    private var isSaving = false
    private static let historyLimit: TimeInterval = 7 * 24 * 60 * 60
    private static let maxWindowsPerTick = 60
    // Historical queries can lag by several minutes. Give recent empty windows time to settle.
    private static let publicationGrace: TimeInterval = 5 * 60
    /// Rows are written here, one batch at a time in the order they were collected: off the main
    /// thread and off the queue that delivers the query results. `.utility`, since storing data is not work
    /// the user waits for (a queue created for each save ran at the receiving queue's priority).
    private let saveQueue = DispatchQueue(label: "com.awareframework.ios.sensor.activityrecognition.save", qos: .utility)
    
    public class Config:SensorConfig{

        public var sampleIntervalSeconds:Int = 600
        {
            didSet {
                if self.sampleIntervalSeconds <= 0 {
                    print("[ActivityRecognition][Illegal Parameter]",
                          "The `sampleIntervalSeconds` value has to be greater than 0.",
                          "This paprameter ('\(self.sampleIntervalSeconds)') is ignored.")
                    self.sampleIntervalSeconds = oldValue
                }
            }
        }

        public var sensorObserver:ActivityRecognitionObserver?

        public override init() {
            super.init()
            dbPath = "aware_activity_recognition"
            dbTableName = ActivityRecognitionData.TABLE_NAME
        }

        public override func set(config: Dictionary<String, Any>) {
            super.set(config: config)
            if let sampleIntervalSeconds = config["sampleIntervalSeconds"] as? Int {
                self.sampleIntervalSeconds = sampleIntervalSeconds
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
    

    /// Creates this sensor's table if it does not exist yet, so that the first save does not fail.
    /// Failures are logged: without the table, the data cannot be saved or uploaded.
    private func initializeTables() {
        guard CONFIG.dbType == .sqlite else { return }
        guard let queue = (dbEngine as? SQLiteEngine)?.getSQLiteInstance() else {
            print(ActivityRecognitionSensor.TAG, "[Error] Cannot open the database '\(CONFIG.dbPath)'. The table is not created.")
            return
        }
        let tables: [(name: String, create: () throws -> Void)] = [
            (ActivityRecognitionData.databaseTableName, { ActivityRecognitionData.createTable(queue: queue) }),
        ]
        for table in tables {
            do {
                try table.create()
            } catch {
                print(ActivityRecognitionSensor.TAG, "[Error] Cannot create the table '\(table.name)': \(error)")
            }
        }
    }

    public init(_ config:ActivityRecognitionSensor.Config) {
        super.init()
        CONFIG = config
        initializeDbEngine(config: config)
        initializeTables()
        
        super.syncConfig = DbSyncConfig().apply{config in
            config.debug = self.CONFIG.debug
            config.serverType = self.CONFIG.serverType
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
        }
        
    }
    
    public override func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }
        guard motionActivityManager == nil else { return }
        guard CMMotionActivityManager.isActivityAvailable() else {
            if self.CONFIG.debug {
                print(ActivityRecognitionSensor.TAG, "CMMotionActivityManager is not available.")
            }
            return
        }
        motionActivityManager = CMMotionActivityManager()
        timer = Timer.scheduledTimer(withTimeInterval: Double(CONFIG.sampleIntervalSeconds), repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.getActivityRecognitionData()
        }
        timer?.fire()
        notificationCenter.post(name: .actionAwareActivityRecognitionStart, object: self)
    }

    public func getActivityRecognitionData() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.getActivityRecognitionData() }
            return
        }
        fetchNextWindow(remaining: Self.maxWindowsPerTick)
    }

    private func fetchNextWindow(remaining: Int) {
        guard remaining > 0, !isQuerying, !isSaving,
              let manager = motionActivityManager, let cursor = getLastUpdateDateTime() else { return }

        let now = Date()
        let fromDate = max(cursor, now.addingTimeInterval(-Self.historyLimit))
        let toDate = fromDate.addingTimeInterval(Double(CONFIG.sampleIntervalSeconds))
        guard toDate > fromDate, toDate <= now else { return }

        isQuerying = true
        manager.queryActivityStarting(from: fromDate, to: toDate, to: .main) { [weak self, weak manager] activities, error in
            guard let self, let manager, self.motionActivityManager === manager else { return }
            self.isQuerying = false

            if let error = error as NSError? {
                // For this API Core Motion reports CMErrorUnknown when the range has no samples.
                if error.domain == CMErrorDomain, error.code == Int(CMErrorUnknown.rawValue),
                   Date().timeIntervalSince(toDate) >= Self.publicationGrace {
                    self.advanceCursor(to: toDate)
                    self.fetchNextWindow(remaining: remaining - 1)
                } else if self.CONFIG.debug {
                    print(Self.TAG, "Activity history query failed: \(error)")
                }
                return
            }
            guard let activities else { return }

            let (rows, lastActivity) = self.makeRows(from: activities, start: fromDate, end: toDate)
            if self.CONFIG.dbType == .none {
                self.finishWindow(rows, lastActivity: lastActivity, end: toDate, manager: manager, remaining: remaining)
                return
            }
            guard let engine = self.dbEngine else {
                if self.CONFIG.debug { print(Self.TAG, "Activity history could not be saved: no database engine.") }
                return
            }

            // Keep the write slot until this accepted save finishes, even across a stop/start.
            self.isSaving = true
            self.saveQueue.async { [weak self, weak manager] in
                engine.save(rows) { error in
                    DispatchQueue.main.async { [weak self, weak manager] in
                        guard let self else { return }
                        self.isSaving = false
                        if let error {
                            if self.CONFIG.debug { print(Self.TAG, "Activity history save failed: \(error)") }
                            return
                        }
                        self.finishWindow(rows, lastActivity: lastActivity, end: toDate, manager: manager, remaining: remaining)
                    }
                }
            }
        }
    }

    private func makeRows(from activities: [CMMotionActivity], start: Date, end: Date)
        -> (rows: [ActivityRecognitionData], lastActivity: ActivityRecognitionData?) {
        var lastActivity = LAST_ACTIVITY
        var rows = Self.activitiesForWindow(activities, range: start..<end, timestamp: \.startDate).map { activity in
            var data = ActivityRecognitionData([:])
            data.timestamp = Int64(max(start, activity.startDate).timeIntervalSince1970 * 1000)
            data.automotive = activity.automotive
            data.cycling = activity.cycling
            data.running = activity.running
            data.stationary = activity.stationary
            data.unknown = activity.unknown
            data.walking = activity.walking
            data.confidence = activity.confidence.rawValue
            data.label = CONFIG.label
            if (activity.confidence == .high || activity.confidence == .medium), !data.unknown,
               data.automotive || data.cycling || data.running || data.stationary || data.walking {
                lastActivity = data
            }
            return data
        }
        if rows.isEmpty {
            var data = ActivityRecognitionData([:])
            data.timestamp = Int64(start.timeIntervalSince1970 * 1000)
            data.automotive = lastActivity?.automotive ?? false
            data.cycling = lastActivity?.cycling ?? false
            data.running = lastActivity?.running ?? false
            data.stationary = lastActivity?.stationary ?? false
            data.unknown = lastActivity?.unknown ?? false
            data.walking = lastActivity?.walking ?? false
            data.confidence = lastActivity?.confidence ?? -1
            data.label = CONFIG.label
            rows.append(data)
        }
        return (rows, lastActivity)
    }

    // Core Motion may report the activity already in progress at the start of a query.
    // Keep this carry-in unless a transition occurred at the start; defer events at the end.
    static func activitiesForWindow<Activity>(_ activities: [Activity], range: Range<Date>,
                                               timestamp: KeyPath<Activity, Date>) -> [Activity] {
        var result = activities.filter { range.contains($0[keyPath: timestamp]) }
        if !result.contains(where: { $0[keyPath: timestamp] == range.lowerBound }),
           let carryIn = activities.last(where: { $0[keyPath: timestamp] < range.lowerBound }) {
            result.insert(carryIn, at: 0)
        }
        return result
    }

    private func finishWindow(_ rows: [ActivityRecognitionData], lastActivity: ActivityRecognitionData?,
                              end: Date, manager: CMMotionActivityManager?, remaining: Int) {
        advanceCursor(to: end)
        guard let manager, motionActivityManager === manager else { return }
        LAST_ACTIVITY = lastActivity
        CONFIG.sensorObserver?.onActivityChanged(data: rows)
        guard motionActivityManager === manager else { return }
        notificationCenter.post(name: .actionAwareActivityRecognition, object: self)
        guard motionActivityManager === manager else { return }
        fetchNextWindow(remaining: remaining - 1)
    }

    private func advanceCursor(to end: Date) {
        if let cursor = UserDefaults.standard.object(forKey: Self.KEY_LAST_UPDATE_DATETIME) as? Date,
           cursor >= end { return }
        setLastUpdateDateTime(end)
    }

    public override func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        guard motionActivityManager != nil else { return }
        timer?.invalidate()
        timer = nil
        motionActivityManager = nil
        isQuerying = false
        notificationCenter.post(name: .actionAwareActivityRecognitionStop, object: self)
    }
    
    public override func sync(force: Bool = false) {
        self.notificationCenter.post(name: .actionAwareActivityRecognitionSync , object: self)
        if let engine = self.dbEngine, let syncConfig = self.syncConfig{
            engine.startSync(syncConfig)
        }
    }
    
    public override func set(label:String){
        self.CONFIG.label = label
        self.notificationCenter.post(name: .actionAwareActivityRecognitionSetLabel,
                                     object: self,
                                     userInfo: [ActivityRecognitionSensor.EXTRA_LABEL:label])
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
        }
        guard let start = Calendar.current.dateInterval(of: .hour, for: Date())?.start else { return nil }
        setLastUpdateDateTime(start)
        return start
    }

    public func setLastUpdateDateTime(_ datetime: Date) {
        UserDefaults.standard.set(datetime, forKey: ActivityRecognitionSensor.KEY_LAST_UPDATE_DATETIME)
    }
    
}
