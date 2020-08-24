//
//  Created by Tapash Majumder on 8/18/20.
//  Copyright © 2020 Iterable. All rights reserved.
//

import XCTest

@testable import IterableSDK

class TaskRunnerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        IterableLogUtil.sharedInstance = IterableLogUtil(dateProvider: SystemDateProvider(),
                                                         logDelegate: DefaultLogDelegate())
        try! persistenceContextProvider.mainQueueContext().deleteAllTasks()
        try! persistenceContextProvider.mainQueueContext().save()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    func testMultipleTasksInSequence() throws {
        let expectation1 = expectation(description: #function)
        expectation1.expectedFulfillmentCount = 3
        
        var scheduledTaskIds = [String]()
        var taskIds = [String]()
        let notificationCenter = MockNotificationCenter()
        notificationCenter.addCallback(forNotification: .iterableTaskFinishedWithSuccess) { notification in
            let taskSendRequestValue = IterableNotificationUtil.notificationToTaskSendRequestValue(notification)!
            taskIds.append(taskSendRequestValue.taskId)
            expectation1.fulfill()
        }

        let taskRunner = IterableTaskRunner(networkSession: MockNetworkSession(),
                                            notificationCenter: notificationCenter,
                                            timeInterval: 0.5)
        taskRunner.start()

        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))
        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))
        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))

        wait(for: [expectation1], timeout: 15.0)
        XCTAssertEqual(taskIds, scheduledTaskIds)

        XCTAssertEqual(try persistenceContextProvider.mainQueueContext().findAllTasks().count, 0)
        taskRunner.stop()
    }

    func testFailureWithRetry() throws {
        let networkError = IterableError.general(description: "The Internet connection appears to be offline.")
        let networkSession = MockNetworkSession(statusCode: 0, data: nil, error: networkError)

        var scheduledTaskIds = [String]()
        var retryTaskIds = [String]()
        let notificationCenter = MockNotificationCenter()
        notificationCenter.addCallback(forNotification: .iterableTaskFinishedWithRetry) { notification in
            let taskSendRequestError = IterableNotificationUtil.notificationToTaskSendRequestError(notification)!
            if !retryTaskIds.contains(taskSendRequestError.taskId) {
                retryTaskIds.append(taskSendRequestError.taskId)
            }
        }

        let taskRunner = IterableTaskRunner(networkSession: networkSession,
                                            notificationCenter: notificationCenter,
                                            timeInterval: 1.0)
        taskRunner.start()

        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))
        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))
        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))

        let predicate = NSPredicate { _, _ in
            return retryTaskIds.count == 1
        }
        let expectation2 = expectation(for: predicate, evaluatedWith: nil, handler: nil)
        wait(for: [expectation2], timeout: 5.0)
        XCTAssertEqual(scheduledTaskIds[0], retryTaskIds[0])
        
        XCTAssertEqual(try persistenceContextProvider.mainQueueContext().findAllTasks().count, 3)
        taskRunner.stop()
    }

    func testFailureWithNoRetry() throws {
        let networkSession = MockNetworkSession(statusCode: 401, data: nil, error: nil)

        let expectation1 = expectation(description: #function)
        expectation1.expectedFulfillmentCount = 3

        var scheduledTaskIds = [String]()
        var failedTaskIds = [String]()
        let notificationCenter = MockNotificationCenter()
        notificationCenter.addCallback(forNotification: .iterableTaskFinishedWithNoRetry) { notification in
            let taskSendRequestError = IterableNotificationUtil.notificationToTaskSendRequestError(notification)!
            failedTaskIds.append(taskSendRequestError.taskId)
            expectation1.fulfill()
        }

        let taskRunner = IterableTaskRunner(networkSession: networkSession,
                                            notificationCenter: notificationCenter,
                                            timeInterval: 0.5)
        taskRunner.start()

        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))
        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))
        scheduledTaskIds.append(try scheduleSampleTask(notificationCenter: notificationCenter))

        wait(for: [expectation1], timeout: 15.0)
        XCTAssertEqual(failedTaskIds, scheduledTaskIds)

        XCTAssertEqual(try persistenceContextProvider.mainQueueContext().findAllTasks().count, 0)
        taskRunner.stop()
    }
    
    private func scheduleSampleTask(notificationCenter: NotificationCenterProtocol) throws -> String {
        let apiKey = "zee-api-key"
        let eventName = "CustomEvent1"
        let dataFields = ["var1": "val1", "var2": "val2"]
        
        let requestCreator = RequestCreator(apiKey: apiKey, auth: auth, deviceMetadata: deviceMetadata)
        guard case let Result.success(trackEventRequest) = requestCreator.createTrackEventRequest(eventName, dataFields: dataFields) else {
            throw IterableError.general(description: "Could not create trackEvent request")
        }
        
        let apiCallRequest = IterableAPICallRequest(apiKey: apiKey,
                                                    endPoint: Endpoint.api,
                                                    auth: auth,
                                                    deviceMetadata: deviceMetadata,
                                                    iterableRequest: trackEventRequest)
        
        return try IterableTaskScheduler(persistenceContextProvider: persistenceContextProvider,
                                         notificationCenter: notificationCenter,
                                         dateProvider: dateProvider).schedule(apiCallRequest: apiCallRequest)
    }
    
    private let deviceMetadata = DeviceMetadata(deviceId: IterableUtil.generateUUID(),
                                                platform: JsonValue.iOS.jsonStringValue,
                                                appPackageName: Bundle.main.appPackageName ?? "")
    
    private lazy var persistenceContextProvider: IterablePersistenceContextProvider = {
        let provider = CoreDataPersistenceContextProvider(dateProvider: dateProvider)
        return provider
    }()

    private let dateProvider = MockDateProvider()
}

extension TaskRunnerTests: AuthProvider {
    var auth: Auth {
        Auth(userId: nil, email: "user@example.com", authToken: nil)
    }
}