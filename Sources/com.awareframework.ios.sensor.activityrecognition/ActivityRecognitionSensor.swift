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
    // Historical queries can lag by several minutes. Give recent empty windows time to settle.
    private static let publicationGrace: TimeInterval = 5 * 60
    /// Rows are written here, one batch at a time in the order they were collected: off the main
    /// thread and off the queue that delivers the query results. `.utility`, since storing data is not work
    /// the user waits for (a queue created for each save ran at the receiving queue's priority).
    private let saveQueue = DispatchQueue(label: "com.awareframework.ios.sensor.activityrecognition.save", qos: .utility)

    // MARK: Debug trace (CONFIG.debug): see HistoryTrace. Main queue only.
    let trace = HistoryTrace(name: "activityrecognition", tag: ActivityRecognitionSensor.TAG)
    private static let stallThreshold: TimeInterval = 120
    private var runID = 0
    private var tickCount = 0
    private var querySeq = 0
    private var queryStartedAt: Date?
    private var queryWindow: (start: Date, end: Date)?
    private var saveStartedAt: Date?
    
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
        runID += 1
        trace.isEnabled = CONFIG.debug
        trace.log("START run=\(runID) interval=\(CONFIG.sampleIntervalSeconds)s authorization=\(Self.authorizationDescription()) cursor=\(trace.format(UserDefaults.standard.object(forKey: Self.KEY_LAST_UPDATE_DATETIME) as? Date)) isQuerying=\(isQuerying) isSaving=\(isSaving)")
        timer = Timer.scheduledTimer(withTimeInterval: Double(CONFIG.sampleIntervalSeconds), repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.traceTick()
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
        // Each tick catches up to now: a window takes a few milliseconds, so there is no per-tick limit
        fetchNextWindow(done: 0)
    }

    private func fetchNextWindow(done: Int) {
        guard !isQuerying else { return traceTickEnd(done, "busy: query #\(querySeq) outstanding \(age(queryStartedAt))") }
        guard !isSaving else { return traceTickEnd(done, "busy: save outstanding \(age(saveStartedAt))") }
        guard let manager = motionActivityManager else { return traceTickEnd(done, "no manager (stopped)") }
        guard let cursor = getLastUpdateDateTime() else { return traceTickEnd(done, "no cursor") }

        let now = Date()
        let fromDate = max(cursor, now.addingTimeInterval(-Self.historyLimit))
        let toDate = fromDate.addingTimeInterval(Double(CONFIG.sampleIntervalSeconds))
        guard toDate > fromDate, toDate <= now else {
            return traceTickEnd(done, "caught up (cursor=\(trace.format(cursor)))")
        }

        isQuerying = true
        querySeq += 1
        let seq = querySeq
        let run = runID
        let issuedAt = Date()
        queryStartedAt = issuedAt
        queryWindow = (fromDate, toDate)
        manager.queryActivityStarting(from: fromDate, to: toDate, to: .main) { [weak self, weak manager] activities, error in
            guard let self else { return }
            let queryMs = Int(Date().timeIntervalSince(issuedAt) * 1000)
            guard let manager, self.motionActivityManager === manager else {
                self.trace.log("LATE query #\(seq) of run \(run) answered after \(queryMs)ms; current run=\(self.runID) isQuerying=\(self.isQuerying)")
                return
            }
            self.isQuerying = false
            self.queryStartedAt = nil

            if let error = error as NSError? {
                // For this API Core Motion reports CMErrorUnknown when the range has no samples.
                if error.domain == CMErrorDomain, error.code == Int(CMErrorUnknown.rawValue),
                   Date().timeIntervalSince(toDate) >= Self.publicationGrace {
                    self.trace.log("WIN #\(seq) \(self.trace.format(fromDate)) empty (CMErrorUnknown) query=\(queryMs)ms")
                    self.advanceCursor(to: toDate)
                    self.fetchNextWindow(done: done + 1)
                } else {
                    self.trace.log("QUERY #\(seq) FAILED \(self.trace.format(fromDate))..\(self.trace.format(toDate)) after \(queryMs)ms error=\(error.domain)/\(error.code) \(error.localizedDescription) authorization=\(Self.authorizationDescription())")
                    if self.CONFIG.debug {
                        print(Self.TAG, "Activity history query failed: \(error)")
                    }
                }
                return
            }
            guard let activities else {
                self.trace.log("QUERY #\(seq) returned nil activities without error after \(queryMs)ms")
                return
            }

            let (rows, lastActivity) = self.makeRows(from: activities, start: fromDate, end: toDate)
            if self.CONFIG.dbType == .none {
                self.finishWindow(rows, lastActivity: lastActivity, end: toDate, manager: manager, done: done)
                return
            }
            guard let engine = self.dbEngine else {
                if self.CONFIG.debug { print(Self.TAG, "Activity history could not be saved: no database engine.") }
                return
            }

            // Keep the write slot until this accepted save finishes, even across a stop/start.
            self.isSaving = true
            let saveQueuedAt = Date()
            self.saveStartedAt = saveQueuedAt
            let activityCount = activities.count
            self.saveQueue.async { [weak self, weak manager] in
                let saveBeganAt = Date()
                engine.save(rows) { error in
                    let savedAt = Date()
                    DispatchQueue.main.async { [weak self, weak manager] in
                        guard let self else { return }
                        self.isSaving = false
                        self.saveStartedAt = nil
                        let waitMs = Int(saveBeganAt.timeIntervalSince(saveQueuedAt) * 1000)
                        let saveMs = Int(savedAt.timeIntervalSince(saveBeganAt) * 1000)
                        if let error {
                            self.trace.log("SAVE #\(seq) FAILED after wait=\(waitMs)ms save=\(saveMs)ms error=\(error)")
                            if self.CONFIG.debug { print(Self.TAG, "Activity history save failed: \(error)") }
                            return
                        }
                        self.trace.log("WIN #\(seq) \(self.trace.format(fromDate)) activities=\(activityCount) rows=\(rows.count) query=\(queryMs)ms saveWait=\(waitMs)ms save=\(saveMs)ms")
                        self.finishWindow(rows, lastActivity: lastActivity, end: toDate, manager: manager, done: done)
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
                              end: Date, manager: CMMotionActivityManager?, done: Int) {
        advanceCursor(to: end)
        guard let manager, motionActivityManager === manager else { return }
        LAST_ACTIVITY = lastActivity
        CONFIG.sensorObserver?.onActivityChanged(data: rows)
        guard motionActivityManager === manager else { return }
        notificationCenter.post(name: .actionAwareActivityRecognition, object: self)
        guard motionActivityManager === manager else { return }
        fetchNextWindow(done: done + 1)
    }

    // MARK: Debug trace

    private func age(_ date: Date?) -> String {
        guard let date else { return "?s" }
        return String(format: "%.1fs", Date().timeIntervalSince(date))
    }

    static func authorizationDescription() -> String {
        guard #available(iOS 11.0, *) else { return "n/a" }
        switch CMMotionActivityManager.authorizationStatus() {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    /// One line per timer tick, and a STALL line while a query or save has not finished for long
    private func traceTick() {
        tickCount += 1
        trace.isEnabled = CONFIG.debug
        guard trace.isEnabled else { return }
        let cursor = UserDefaults.standard.object(forKey: Self.KEY_LAST_UPDATE_DATETIME) as? Date
        trace.log("TICK #\(tickCount) run=\(runID) app=\(trace.appState) protectedData=\(trace.protectedDataAvailable) manager=\(motionActivityManager != nil) isQuerying=\(isQuerying) isSaving=\(isSaving) cursor=\(trace.format(cursor)) lag=\(cursor.map { Int(Date().timeIntervalSince($0) / 60) } ?? -1)min")
        if isQuerying, let started = queryStartedAt, Date().timeIntervalSince(started) > Self.stallThreshold {
            trace.log("STALL query #\(querySeq) outstanding \(age(started)) window=\(trace.format(queryWindow?.start))..\(trace.format(queryWindow?.end)) authorization=\(Self.authorizationDescription())")
        }
        if isSaving, let started = saveStartedAt, Date().timeIntervalSince(started) > Self.stallThreshold {
            trace.log("STALL save outstanding \(age(started))")
        }
    }

    private func traceTickEnd(_ windows: Int, _ reason: String) {
        trace.log("TICK END windows=\(windows) reason=\(reason)")
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
        trace.log("STOP run=\(runID) isQuerying=\(isQuerying) (#\(querySeq)) isSaving=\(isSaving) cursor=\(trace.format(UserDefaults.standard.object(forKey: Self.KEY_LAST_UPDATE_DATETIME) as? Date))")
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
