//
//  ActivityRecognitionData.swift
//  com.aware.ios.sensor.activityrecognition
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import Foundation
import com_awareframework_ios_core
import GRDB

public struct ActivityRecognitionData: BaseDbModelSQLite {
    
    public static let TABLE_NAME = "ios_activity_recognition"
    public static let databaseTableName = TABLE_NAME

    public var timezone: Int = AwareUtils.getTimeZone()
    public var os: String = "iOS"
    public var jsonVersion: Int = 1
    public var id: Int64?
    public var timestamp: Int64
    public var deviceId: String = AwareUtils.getCommonDeviceId()
    public var label: String
    
    public var activities:String = ""
    public var confidence:Int    = 0
    public var stationary:Bool   = false
    public var walking:Bool      = false
    public var running:Bool      = false
    public var automotive:Bool   = false
    public var cycling:Bool      = false
    public var unknown:Bool      = false
    
    
    public init(_ dict: Dictionary<String, Any>) {
        self.timestamp  = dict["timestamp"] as? Int64 ?? 0
        self.label      = dict["label"] as? String ?? ""
        self.activities = dict["activities"] as? String ?? ""
        self.confidence = dict["confidence"] as? Int ?? 0
        self.stationary = dict["stationary"] as? Bool ?? false
        self.walking    = dict["walking"] as? Bool ?? false
        self.running    = dict["running"] as? Bool ?? false
        self.automotive = dict["automotive"] as? Bool ?? false
        self.cycling    = dict["cycling"] as? Bool ?? false
        self.unknown    = dict["unknown"] as? Bool ?? false
    }
    
    public static func createTable(queue: GRDB.DatabaseQueue) {
        do {
            try queue.write { db in
                try db.create(table: ActivityRecognitionData.TABLE_NAME, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("deviceId", .text).notNull()
                    t.column("timestamp", .integer).notNull()
                    t.column("label", .text).notNull()
                    t.column("timezone", .integer).notNull()
                    t.column("os", .text).notNull()
                    t.column("jsonVersion", .integer).notNull()
                    
                    t.column("activities", .text).notNull()
                    t.column("confidence", .integer).notNull()
                    t.column("stationary", .boolean).notNull()
                    t.column("walking",    .boolean).notNull()
                    t.column("running",    .boolean).notNull()
                    t.column("automotive", .boolean).notNull()
                    t.column("cycling",    .boolean).notNull()
                    t.column("unknown",    .boolean).notNull()
                }
            }
        } catch {
            print(error)
        }

    }
    


    public func toDictionary() -> Dictionary<String, Any> {
        return [
            "id":self.id ?? -1,
            "timestamp": timestamp,
            "device_id":deviceId,
            "label":label,
            
            "activities":activities,
            "confidence":confidence,
            "stationary":stationary,
            "walking":walking,
            "running":running,
            "automotive":automotive,
            "cycling":cycling,
            "unknown":unknown
        ]
    }
    
}
