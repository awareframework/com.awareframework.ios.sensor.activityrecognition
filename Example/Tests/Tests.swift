import XCTest
import RealmSwift
import com_awareframework_ios_sensor_activityrecognition

class Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        // Realm.Configuration.defaultConfiguration.inMemoryIdentifier = self.name
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testStorage(){
        #if targetEnvironment(simulator)
        print("Controller tests (start and stop) require a real device.")
        #else
        
        class Observer:ActivityRecognitionObserver {
            weak var arExpectation: XCTestExpectation?
            func onActivityChanged(data: Array<ActivityRecognitionData>) {
                if let expect = arExpectation {
                    expect.fulfill()
                    arExpectation = nil
                }
            }
        }
        let arExpect = expectation(description: "Activity Recognition Observer")
        let observer = Observer()
        observer.arExpectation = arExpect
        let sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config().apply{config in
            config.debug = true
            config.interval = 1
            config.sensorObserver = observer
            config.dbType = .REALM
        })
        
        let arStorageeExpect = expectation(description: "Activity Recognition Storagee")
        var isDone = false
        let obs = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareActivityRecognition,
                                                         object: nil,
                                                         queue: .main) { (notification) in
            if let engine = sensor.dbEngine {
                if let results = engine.fetch(ActivityRecognitionData.TABLE_NAME,
                                              ActivityRecognitionData.self,
                                              nil) as? Results<Object>{
                    // arStorageeExpect.fulfill()
                    if !isDone{
                        arStorageeExpect.fulfill()
                        print(results)
                        XCTAssertNotEqual(results.count, 0)
                        isDone = true
                    }
                }else{
                    XCTFail()
                }
            }else{
                 XCTFail()
            }
        }
        sensor.setLastUpdateDateTime(Date().addingTimeInterval(-1*60*15))
        sensor.start()
        
        wait(for: [arExpect,arStorageeExpect], timeout: 30)
        sensor.stop()
        sensor.CONFIG.sensorObserver = nil
        NotificationCenter.default.removeObserver(obs)
        
        #endif
        
    }
    
    func testControllers(){
        
        let sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config().apply{ config in
            config.debug = true
        })
        
        /// test set label action ///
        let expectSetLabel = expectation(description: "set label")
        let newLabel = "hello"
        let labelObserver = NotificationCenter.default.addObserver(forName: .actionAwareActivityRecognitionSetLabel, object: nil, queue: .main) { (notification) in
            let dict = notification.userInfo;
            if let d = dict as? Dictionary<String,String>{
                XCTAssertEqual(d[ActivityRecognitionSensor.EXTRA_LABEL], newLabel)
            }else{
                XCTFail()
            }
            expectSetLabel.fulfill()
        }
        sensor.set(label:newLabel)
        wait(for: [expectSetLabel], timeout: 5)
        NotificationCenter.default.removeObserver(labelObserver)
        
        
        /// test sync action ////
        let expectSync = expectation(description: "sync")
        let syncObserver = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareActivityRecognitionSync , object: nil, queue: .main) { (notification) in
            expectSync.fulfill()
            print("sync")
        }
        sensor.sync()
        wait(for: [expectSync], timeout: 5)
        NotificationCenter.default.removeObserver(syncObserver)
        
        
        #if targetEnvironment(simulator)
        
        print("Controller tests (start and stop) require a real device.")
        
        #else
        
        //// test start action ////
        let expectStart = expectation(description: "start")
        let observer = NotificationCenter.default.addObserver(forName: .actionAwareActivityRecognitionStart,
                                                              object: nil,
                                                              queue: .main) { (notification) in
                                                                expectStart.fulfill()
                                                                print("start")
        }
        sensor.start()
        wait(for: [expectStart], timeout: 5)
        NotificationCenter.default.removeObserver(observer)
        
        
        /// test stop action ////
        let expectStop = expectation(description: "stop")
        let stopObserver = NotificationCenter.default.addObserver(forName: .actionAwareActivityRecognitionStop, object: nil, queue: .main) { (notification) in
            expectStop.fulfill()
            print("stop")
        }
        sensor.stop()
        wait(for: [expectStop], timeout: 5)
        NotificationCenter.default.removeObserver(stopObserver)
        
        #endif
        
    }
    
    func testConfig(){
        
        let interval = 1

        // default check
        var sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config.init())
        XCTAssertEqual(10, sensor.CONFIG.interval)
        
        sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config.init().apply{config in
            config.interval = interval
        })
        XCTAssertEqual(interval, sensor.CONFIG.interval)
        
        sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config(["interval":interval]))
        XCTAssertEqual(interval, sensor.CONFIG.interval)
        
        sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config())
        sensor.CONFIG.set(config: ["interval":interval])
        XCTAssertEqual(interval, sensor.CONFIG.interval)
        
        sensor.CONFIG.interval = -10
        XCTAssertEqual(interval, sensor.CONFIG.interval)
    }
    
//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        self.measure() {
//            // Put the code you want to measure the time of here.
//        }
//    }
    
    func testActivityRecognitionData (){
        let dict = ActivityRecognitionData().toDictionary()
        XCTAssertEqual(dict["activities"] as? String, "")
        XCTAssertEqual(dict["confidence"] as? Int, 0)
        XCTAssertFalse(dict["stationary"] as! Bool)
        XCTAssertFalse(dict["walking"] as! Bool)
        XCTAssertFalse(dict["running"] as! Bool)
        XCTAssertFalse(dict["automotive"] as! Bool)
        XCTAssertFalse(dict["cycling"] as! Bool)
        XCTAssertFalse(dict["unknown"] as! Bool)
    }
}
