import Foundation
import SwiftProtobuf

/// Typed façade over the agent's Connect-RPC API
public struct AgentClient: Sendable {
    private let transport: any AgentTransport
    /// Called once per stream with the run's job id
    public var onJobStarted: (@Sendable (String) -> Void)?

    public init(transport: any AgentTransport) {
        self.transport = transport
    }

    /// Convenience: build a client over an SSH/Unix byte-stream factory
    public init(factory: AgentStreamFactory, deviceUID: String = "") {
        self.transport = ConnectTransport(factory: factory, deviceUID: deviceUID)
    }

    // MARK: Control

    public func getState() async throws -> Gryonixnexusd_V1_State {
        try await unary("/gryonixnexusd.v1.Control/GetState", Gryonixnexusd_V1_GetStateRequest())
    }

    public func discover() async throws -> Gryonixnexusd_V1_DiscoverResult {
        try await unary("/gryonixnexusd.v1.Control/Discover", Gryonixnexusd_V1_DiscoverRequest())
    }

    public func hostMetrics(intervalSeconds: UInt32 = 0) -> AsyncThrowingStream<Gryonixnexusd_V1_MetricsSample, Error> {
        var req = Gryonixnexusd_V1_HostMetricsRequest()
        req.intervalSeconds = intervalSeconds
        return stream("/gryonixnexusd.v1.Control/HostMetrics", req)
    }

    public func logs(serviceID: String, tail: UInt32 = 0) -> AsyncThrowingStream<Gryonixnexusd_V1_LogLine, Error> {
        var req = Gryonixnexusd_V1_LogsRequest()
        req.serviceID = serviceID
        req.tail = tail
        return stream("/gryonixnexusd.v1.Control/Logs", req)
    }

    /// One downsampled history bucket the on-host collector keeps
    public func metricsHistory(bucket: String, limit: UInt32 = 0,
                               since: Date? = nil) async throws -> Gryonixnexusd_V1_MetricsHistoryResponse {
        var req = Gryonixnexusd_V1_MetricsHistoryRequest()
        req.bucket = bucket
        req.limit = limit
        if let since { req.since = Int64(since.timeIntervalSince1970 * 1000) }
        return try await unary("/gryonixnexusd.v1.Control/MetricsHistory", req)
    }

    /// The USB serial adapters udev lists on the host
    public func listSerialDevices() async throws -> Gryonixnexusd_V1_SerialDeviceList {
        try await unary("/gryonixnexusd.v1.Control/ListSerialDevices",
                        Gryonixnexusd_V1_ListSerialDevicesRequest())
    }

    // MARK: Backups

    public func listBackups(serviceID: String) async throws -> Gryonixnexusd_V1_BackupList {
        var req = Gryonixnexusd_V1_ListBackupsRequest()
        req.serviceID = serviceID
        return try await unary("/gryonixnexusd.v1.Backup/ListBackups", req)
    }

    /// Every service's backups on the host, in one reply
    public func listAllBackups() async throws -> Gryonixnexusd_V1_AllBackups {
        try await unary("/gryonixnexusd.v1.Backup/ListAllBackups", Gryonixnexusd_V1_ListAllBackupsRequest())
    }

    public func estimateBackup(serviceID: String) async throws -> Gryonixnexusd_V1_BackupEstimate {
        var req = Gryonixnexusd_V1_EstimateBackupRequest()
        req.serviceID = serviceID
        return try await unary("/gryonixnexusd.v1.Backup/EstimateBackup", req)
    }

    /// Runs one backup, streaming the wrapper's output
    public func runBackup(serviceID: String,
                          encryption: Gryonixnexusd_V1_BackupEncryption = .unspecified,
                          passphrase: String = "") -> AsyncThrowingStream<Gryonixnexusd_V1_BackupEvent, Error> {
        var req = Gryonixnexusd_V1_RunBackupRequest()
        req.serviceID = serviceID
        req.encryption = encryption
        req.passphrase = passphrase
        return stream("/gryonixnexusd.v1.Backup/RunBackup", req)
    }

    @discardableResult
    public func deleteBackup(serviceID: String, path: String) async throws -> Gryonixnexusd_V1_BackupList {
        var req = Gryonixnexusd_V1_DeleteBackupRequest()
        req.serviceID = serviceID
        req.path = path
        return try await unary("/gryonixnexusd.v1.Backup/DeleteBackup", req)
    }

    public func getBackupSchedule() async throws -> Gryonixnexusd_V1_BackupSchedulePolicy {
        try await unary("/gryonixnexusd.v1.Backup/GetBackupSchedule", Gryonixnexusd_V1_GetBackupScheduleRequest())
    }

    @discardableResult
    public func setBackupSchedule(schedule: String, retention: Int, services: [String],
                                  passphrase: String = "") async throws -> Gryonixnexusd_V1_BackupSchedulePolicy {
        var req = Gryonixnexusd_V1_SetBackupScheduleRequest()
        req.schedule = schedule
        req.retention = Int32(retention)
        req.services = services
        req.passphrase = passphrase
        return try await unary("/gryonixnexusd.v1.Backup/SetBackupSchedule", req)
    }

    @discardableResult
    public func setBackupDestination(_ destination: Gryonixnexusd_V1_BackupDestination,
                                     secret: String = "") async throws
        -> Gryonixnexusd_V1_BackupSchedulePolicy {
        var req = Gryonixnexusd_V1_SetBackupDestinationRequest()
        req.destination = destination
        req.secret = secret
        return try await unary("/gryonixnexusd.v1.Backup/SetBackupDestination", req)
    }

    public func testBackupDestination() async throws -> Gryonixnexusd_V1_BackupDestinationTest {
        try await unary("/gryonixnexusd.v1.Backup/TestBackupDestination",
                        Gryonixnexusd_V1_TestBackupDestinationRequest())
    }

    @discardableResult
    public func setBackupDrives(_ drives: Gryonixnexusd_V1_BackupDrives) async throws
        -> Gryonixnexusd_V1_BackupSchedulePolicy {
        var req = Gryonixnexusd_V1_SetBackupDrivesRequest()
        req.drives = drives
        return try await unary("/gryonixnexusd.v1.Backup/SetBackupDrives", req)
    }

    /// Stages a drive archive where a restore reads it
    public func fetchDriveBackup(serviceID: String, path: String) async throws -> Gryonixnexusd_V1_BackupArchive {
        var req = Gryonixnexusd_V1_FetchDriveBackupRequest()
        req.serviceID = serviceID
        req.path = path
        return try await unary("/gryonixnexusd.v1.Backup/FetchDriveBackup", req)
    }

    public func getSecurityAutoRules() async throws -> Gryonixnexusd_V1_SecurityAutoRules {
        try await unary("/gryonixnexusd.v1.Security/GetSecurityAutoRules",
                        Gryonixnexusd_V1_GetSecurityAutoRulesRequest())
    }

    @discardableResult
    public func setSecurityAutoRules(_ rules: Gryonixnexusd_V1_SecurityAutoRules) async throws
        -> Gryonixnexusd_V1_SecurityAutoRules {
        var req = Gryonixnexusd_V1_SetSecurityAutoRulesRequest()
        req.rules = rules
        return try await unary("/gryonixnexusd.v1.Security/SetSecurityAutoRules", req)
    }

    // MARK: Mailboxes

    /// The mailboxes of the docker-mailserver engine
    public func listMailboxes() async throws -> [Gryonixnexusd_V1_Mailbox] {
        let response: Gryonixnexusd_V1_MailboxList = try await unary(
            "/gryonixnexusd.v1.Mail/ListMailboxes", Gryonixnexusd_V1_ListMailboxesRequest())
        return response.mailboxes
    }

    /// Creates a mailbox
    @discardableResult
    public func createMailbox(address: String, password: String) async throws -> [Gryonixnexusd_V1_Mailbox] {
        var req = Gryonixnexusd_V1_CreateMailboxRequest()
        req.address = address
        req.password = password
        let response: Gryonixnexusd_V1_MailboxList = try await unary("/gryonixnexusd.v1.Mail/CreateMailbox", req)
        return response.mailboxes
    }

    @discardableResult
    public func deleteMailbox(address: String) async throws -> [Gryonixnexusd_V1_Mailbox] {
        var req = Gryonixnexusd_V1_DeleteMailboxRequest()
        req.address = address
        let response: Gryonixnexusd_V1_MailboxList = try await unary("/gryonixnexusd.v1.Mail/DeleteMailbox", req)
        return response.mailboxes
    }

    @discardableResult
    public func setMailboxPassword(address: String, password: String) async throws -> [Gryonixnexusd_V1_Mailbox] {
        var req = Gryonixnexusd_V1_SetMailboxPasswordRequest()
        req.address = address
        req.password = password
        let response: Gryonixnexusd_V1_MailboxList = try await unary("/gryonixnexusd.v1.Mail/SetMailboxPassword", req)
        return response.mailboxes
    }

    // MARK: DKIM

    public func getDkimRecords() async throws -> [Gryonixnexusd_V1_DkimRecord] {
        let response: Gryonixnexusd_V1_DkimRecordList = try await unary(
            "/gryonixnexusd.v1.Dkim/GetDkimRecords", Gryonixnexusd_V1_GetDkimRecordsRequest())
        return response.records
    }

    // MARK: Management

    /// Live status of one service
    public func serviceStatus(serviceID: String) async throws -> Gryonixnexusd_V1_ServiceStatusResponse {
        var req = Gryonixnexusd_V1_ServiceStatusRequest()
        req.serviceID = serviceID
        return try await unary("/gryonixnexusd.v1.Control/ServiceStatus", req)
    }

    /// Start / stop / restart one service
    public func controlService(serviceID: String, action: Gryonixnexusd_V1_ServiceAction)
    -> AsyncThrowingStream<Gryonixnexusd_V1_ServiceOperationEvent, Error> {
        var req = Gryonixnexusd_V1_ControlServiceRequest()
        req.serviceID = serviceID
        req.action = action
        return stream("/gryonixnexusd.v1.Control/ControlService", req)
    }

    // MARK: Containers

    public func listContainers() async throws -> Gryonixnexusd_V1_ContainerInventory {
        try await unary("/gryonixnexusd.v1.Containers/ListContainers",
                        Gryonixnexusd_V1_ListContainersRequest())
    }

    public func setContainerGroupName(key: String, displayName: String)
    async throws -> Gryonixnexusd_V1_ContainerInventory {
        var req = Gryonixnexusd_V1_SetContainerGroupNameRequest()
        req.key = key
        req.displayName = displayName
        return try await unary("/gryonixnexusd.v1.Containers/SetContainerGroupName", req)
    }

    /// Start / stop / restart one group, streaming what the engine says
    public func controlContainerGroup(key: String, action: Gryonixnexusd_V1_ServiceAction)
    -> AsyncThrowingStream<Gryonixnexusd_V1_ContainerOperationEvent, Error> {
        var req = Gryonixnexusd_V1_ControlContainerGroupRequest()
        req.key = key
        req.action = action
        return stream("/gryonixnexusd.v1.Containers/ControlContainerGroup", req)
    }

    public func containerGroupLogs(key: String, tail: UInt32 = 0)
    -> AsyncThrowingStream<Gryonixnexusd_V1_LogLine, Error> {
        var req = Gryonixnexusd_V1_ContainerGroupLogsRequest()
        req.key = key
        req.tail = tail
        return stream("/gryonixnexusd.v1.Containers/ContainerGroupLogs", req)
    }

    public func inspectContainer(name: String) async throws -> Gryonixnexusd_V1_ContainerDetail {
        var req = Gryonixnexusd_V1_InspectContainerRequest()
        req.name = name
        return try await unary("/gryonixnexusd.v1.Containers/InspectContainer", req)
    }

    public func containerBackupPlan(key: String) async throws -> Gryonixnexusd_V1_ContainerBackupPlan {
        var req = Gryonixnexusd_V1_GetContainerBackupPlanRequest()
        req.key = key
        return try await unary("/gryonixnexusd.v1.Containers/GetContainerBackupPlan", req)
    }

    public func setContainerBackupPlan(key: String, plan: Gryonixnexusd_V1_ContainerBackupPlan?)
    async throws -> Gryonixnexusd_V1_ContainerBackupPlan {
        var req = Gryonixnexusd_V1_SetContainerBackupPlanRequest()
        req.key = key
        if let plan { req.plan = plan }
        return try await unary("/gryonixnexusd.v1.Containers/SetContainerBackupPlan", req)
    }

    /// Runs the group's backup plan, streaming what it does
    public func runContainerGroupBackup(key: String)
    -> AsyncThrowingStream<Gryonixnexusd_V1_ContainerBackupEvent, Error> {
        var req = Gryonixnexusd_V1_RunContainerGroupBackupRequest()
        req.key = key
        return stream("/gryonixnexusd.v1.Containers/RunContainerGroupBackup", req)
    }

    public func previewContainerGroupRemoval(key: String, purgeData: Bool, purgeBackups: Bool)
    async throws -> Gryonixnexusd_V1_ContainerRemovalPreview {
        var req = Gryonixnexusd_V1_PreviewContainerGroupRemovalRequest()
        req.key = key
        req.purgeData = purgeData
        req.purgeBackups = purgeBackups
        return try await unary("/gryonixnexusd.v1.Containers/PreviewContainerGroupRemoval", req)
    }

    public func removeContainerGroup(key: String, purgeData: Bool, purgeBackups: Bool)
    -> AsyncThrowingStream<Gryonixnexusd_V1_ContainerRemovalEvent, Error> {
        var req = Gryonixnexusd_V1_RemoveContainerGroupRequest()
        req.key = key
        req.purgeData = purgeData
        req.purgeBackups = purgeBackups
        return stream("/gryonixnexusd.v1.Containers/RemoveContainerGroup", req)
    }

    public func updateContainerGroup(key: String, skipBackup: Bool)
    -> AsyncThrowingStream<Gryonixnexusd_V1_ContainerUpdateEvent, Error> {
        var req = Gryonixnexusd_V1_UpdateContainerGroupRequest()
        req.key = key
        req.skipBackup = skipBackup
        return stream("/gryonixnexusd.v1.Containers/UpdateContainerGroup", req)
    }

    public func containerBackupSchedule(key: String)
    async throws -> Gryonixnexusd_V1_ContainerBackupSchedule {
        var req = Gryonixnexusd_V1_GetContainerBackupScheduleRequest()
        req.key = key
        return try await unary("/gryonixnexusd.v1.Containers/GetContainerBackupSchedule", req)
    }

    public func setContainerBackupSchedule(key: String, schedule: String)
    async throws -> Gryonixnexusd_V1_ContainerBackupSchedule {
        var req = Gryonixnexusd_V1_SetContainerBackupScheduleRequest()
        req.key = key
        req.schedule = schedule
        return try await unary("/gryonixnexusd.v1.Containers/SetContainerBackupSchedule", req)
    }

    /// What a foreign group's backups ARE
    public func containerGroupBackups(key: String)
    async throws -> Gryonixnexusd_V1_ContainerBackupList {
        var req = Gryonixnexusd_V1_ListContainerGroupBackupsRequest()
        req.key = key
        return try await unary("/gryonixnexusd.v1.Containers/ListContainerGroupBackups", req)
    }

    // MARK: Updates

    public func checkUpdates() async throws -> Gryonixnexusd_V1_UpdateCheckResult {
        try await unary("/gryonixnexusd.v1.Update/CheckUpdates", Gryonixnexusd_V1_CheckUpdatesRequest())
    }

    /// Applies one service's update, streaming the wrapper's output
    public func runUpdate(serviceID: String) -> AsyncThrowingStream<Gryonixnexusd_V1_UpdateEvent, Error> {
        var req = Gryonixnexusd_V1_RunUpdateRequest()
        req.serviceID = serviceID
        return stream("/gryonixnexusd.v1.Update/RunUpdate", req)
    }

    public func getUpdatePolicy() async throws -> Gryonixnexusd_V1_UpdatePolicy {
        try await unary("/gryonixnexusd.v1.Update/GetUpdatePolicy", Gryonixnexusd_V1_GetUpdatePolicyRequest())
    }

    /// Sets the schedule
    public func setUpdateSchedule(schedule: String, services: [String]) async throws -> Gryonixnexusd_V1_UpdatePolicy {
        var req = Gryonixnexusd_V1_SetUpdateScheduleRequest()
        req.schedule = schedule
        req.services = services
        return try await unary("/gryonixnexusd.v1.Update/SetUpdateSchedule", req)
    }

    // MARK: AgentUpdate

    public func getAgentUpdateStatus() async throws -> Gryonixnexusd_V1_AgentUpdateStatus {
        try await unary("/gryonixnexusd.v1.AgentUpdate/GetAgentUpdateStatus", Gryonixnexusd_V1_GetAgentUpdateStatusRequest())
    }

    public func setAgentAutoUpdate(_ enabled: Bool) async throws -> Gryonixnexusd_V1_AgentUpdateStatus {
        var req = Gryonixnexusd_V1_SetAgentAutoUpdateRequest()
        req.enabled = enabled
        return try await unary("/gryonixnexusd.v1.AgentUpdate/SetAgentAutoUpdate", req)
    }

    public func applyAgentUpdate() -> AsyncThrowingStream<Gryonixnexusd_V1_AgentUpdateEvent, Error> {
        stream("/gryonixnexusd.v1.AgentUpdate/ApplyAgentUpdate", Gryonixnexusd_V1_ApplyAgentUpdateRequest())
    }

    public func removeAgent() async throws -> Gryonixnexusd_V1_RemoveAgentResponse {
        try await unary("/gryonixnexusd.v1.AgentUpdate/RemoveAgent", Gryonixnexusd_V1_RemoveAgentRequest())
    }

    // MARK: Lockdown

    public func getLockdown() async throws -> Gryonixnexusd_V1_LockdownState {
        try await unary("/gryonixnexusd.v1.Lockdown/GetLockdown", Gryonixnexusd_V1_GetLockdownRequest())
    }

    /// Changes the admin-guard state
    public func setLockdown(mode: Gryonixnexusd_V1_LockdownMode,
                            hosts: [String] = []) async throws -> Gryonixnexusd_V1_LockdownState {
        var req = Gryonixnexusd_V1_SetLockdownRequest()
        req.mode = mode
        req.hosts = hosts
        return try await unary("/gryonixnexusd.v1.Lockdown/SetLockdown", req)
    }

    // MARK: Security

    public func getSecurityStatus() async throws -> Gryonixnexusd_V1_SecurityStatus {
        try await unary("/gryonixnexusd.v1.Security/GetSecurityStatus",
                        Gryonixnexusd_V1_GetSecurityStatusRequest())
    }

    public func getSSHPasswordState(loginUser: String,
                                    appPublicKey: String) async throws -> Gryonixnexusd_V1_SshPasswordState {
        var req = Gryonixnexusd_V1_GetSshPasswordStateRequest()
        req.loginUser = loginUser
        req.appPublicKey = appPublicKey
        return try await unary("/gryonixnexusd.v1.Security/GetSshPasswordState", req)
    }

    public func listSSHUsers(loginUser: String,
                             appPublicKey: String) async throws -> Gryonixnexusd_V1_SshUsers {
        var req = Gryonixnexusd_V1_ListSshUsersRequest()
        req.loginUser = loginUser
        req.appPublicKey = appPublicKey
        return try await unary("/gryonixnexusd.v1.Security/ListSshUsers", req)
    }

    public func setSSHKeyOnlyUsers(everyone: Bool, users: [String], loginUser: String,
                                   appPublicKey: String) async throws -> Gryonixnexusd_V1_SshUsers {
        var req = Gryonixnexusd_V1_SetSshKeyOnlyUsersRequest()
        req.everyone = everyone
        req.users = users
        req.loginUser = loginUser
        req.appPublicKey = appPublicKey
        return try await unary("/gryonixnexusd.v1.Security/SetSshKeyOnlyUsers", req)
    }

    public func setSSHPasswordLogin(open: Bool, loginUser: String,
                                    appPublicKey: String) async throws -> Gryonixnexusd_V1_SshPasswordState {
        var req = Gryonixnexusd_V1_SetSshPasswordLoginRequest()
        req.allowPasswords = open
        req.loginUser = loginUser
        req.appPublicKey = appPublicKey
        return try await unary("/gryonixnexusd.v1.Security/SetSshPasswordLogin", req)
    }

    public func controlSecurity(action: Gryonixnexusd_V1_SecurityAction)
    -> AsyncThrowingStream<Gryonixnexusd_V1_SecurityOperationEvent, Error> {
        var req = Gryonixnexusd_V1_ControlSecurityRequest()
        req.action = action
        return stream("/gryonixnexusd.v1.Security/ControlSecurity", req)
    }

    /// Who the defence is blocking right now
    public func getSecurityDecisions() async throws -> Gryonixnexusd_V1_SecurityDecisions {
        try await unary("/gryonixnexusd.v1.Security/GetSecurityDecisions",
                        Gryonixnexusd_V1_GetSecurityDecisionsRequest())
    }

    /// Ban an address by hand, or lift a ban
    public func setSecurityDecision(value: String, banned: Bool, id: String = "",
                                    duration: TimeInterval = 0,
                                    reason: String = "") async throws -> Gryonixnexusd_V1_SecurityDecisions {
        var req = Gryonixnexusd_V1_SetSecurityDecisionRequest()
        req.value = value
        req.id = id
        req.banned = banned
        req.durationSeconds = UInt64(max(0, duration))
        req.reason = reason
        return try await unary("/gryonixnexusd.v1.Security/SetSecurityDecision", req)
    }

    public func getSecurityAllowlist() async throws -> Gryonixnexusd_V1_SecurityAllowlist {
        try await unary("/gryonixnexusd.v1.Security/GetSecurityAllowlist",
                        Gryonixnexusd_V1_GetSecurityAllowlistRequest())
    }

    /// Put an address beyond banning, or stop protecting it
    public func setSecurityAllowlist(value: String, allowed: Bool, comment: String = "",
                                     duration: TimeInterval = 0) async throws -> Gryonixnexusd_V1_SecurityAllowlist {
        var req = Gryonixnexusd_V1_SetSecurityAllowlistRequest()
        req.value = value
        req.allowed = allowed
        req.comment = comment
        req.durationSeconds = UInt64(max(0, duration))
        return try await unary("/gryonixnexusd.v1.Security/SetSecurityAllowlist", req)
    }

    // MARK: Dynamic DNS

    public func getDynamicDNS() async throws -> Gryonixnexusd_V1_DynamicDNSState {
        try await unary("/gryonixnexusd.v1.Dns/GetDynamicDNS", Gryonixnexusd_V1_GetDynamicDNSRequest())
    }

    public func setDynamicDNS(zone: String,
                              names: [String],
                              token: String = "") async throws -> Gryonixnexusd_V1_DynamicDNSState {
        var req = Gryonixnexusd_V1_SetDynamicDNSRequest()
        req.zone = zone
        req.names = names
        req.token = token
        return try await unary("/gryonixnexusd.v1.Dns/SetDynamicDNS", req)
    }

    // MARK: Storage

    public func runStorageTask(_ request: Gryonixnexusd_V1_StorageTaskRequest) async throws -> Gryonixnexusd_V1_StorageTaskResult {
        try await unary("/gryonixnexusd.v1.Storage/RunStorageTask", request)
    }

    // MARK: Notifications

    public func getNotifySettings() async throws -> Gryonixnexusd_V1_NotifySettings {
        try await unary("/gryonixnexusd.v1.Notify/GetNotifySettings", Gryonixnexusd_V1_GetNotifySettingsRequest())
    }

    public func setNotifySettings(_ request: Gryonixnexusd_V1_SetNotifySettingsRequest) async throws -> Gryonixnexusd_V1_NotifySettings {
        try await unary("/gryonixnexusd.v1.Notify/SetNotifySettings", request)
    }

    public func registerNotifyDevice(platform: String, token: String, appVersion: String,
                                     locale: String, muted: [String] = [],
                                     proof: String = "") async throws -> Gryonixnexusd_V1_NotifySettings {
        var req = Gryonixnexusd_V1_RegisterNotifyDeviceRequest()
        req.deviceProof = proof
        req.platform = platform
        req.token = token
        req.appVersion = appVersion
        req.locale = locale
        req.muted = muted
        return try await unary("/gryonixnexusd.v1.Notify/RegisterNotifyDevice", req)
    }

    public func unregisterNotifyDevice(token: String) async throws -> Gryonixnexusd_V1_NotifySettings {
        var req = Gryonixnexusd_V1_UnregisterNotifyDeviceRequest()
        req.token = token
        return try await unary("/gryonixnexusd.v1.Notify/UnregisterNotifyDevice", req)
    }

    public func sendTestNotification() async throws -> Gryonixnexusd_V1_NotifyTestResult {
        try await unary("/gryonixnexusd.v1.Notify/SendTestNotification", Gryonixnexusd_V1_SendTestNotificationRequest())
    }

    public func watchLiveActivity(jobID: String, token: String, title: String) async throws -> Gryonixnexusd_V1_NotifyTestResult {
        var req = Gryonixnexusd_V1_WatchLiveActivityRequest()
        req.jobID = jobID
        req.token = token
        req.title = title
        return try await unary("/gryonixnexusd.v1.Notify/WatchLiveActivity", req)
    }

    public func testLiveActivity(token: String, title: String) async throws -> Gryonixnexusd_V1_NotifyTestResult {
        var req = Gryonixnexusd_V1_TestLiveActivityRequest()
        req.token = token
        req.title = title
        return try await unary("/gryonixnexusd.v1.Notify/TestLiveActivity", req)
    }

    /// Hands the VPN session's activity token to the server
    public func watchTunnelActivity(_ req: Gryonixnexusd_V1_WatchTunnelActivityRequest) async throws
        -> Gryonixnexusd_V1_NotifyTestResult {
        try await unary("/gryonixnexusd.v1.Notify/WatchTunnelActivity", req)
    }

    // MARK: Mods

    /// Search the mod catalogue FROM THE SERVER
    public func searchMods(serviceID: String,
                           query: String,
                           gameVersion: String,
                           loader: String,
                           limit: UInt32 = 0,
                           offset: UInt32 = 0) async throws -> Gryonixnexusd_V1_ModSearchResult {
        var req = Gryonixnexusd_V1_SearchModsRequest()
        req.serviceID = serviceID
        req.query = query
        req.gameVersion = gameVersion
        req.loader = loader
        req.limit = limit
        req.offset = offset
        return try await unary("/gryonixnexusd.v1.Mods/SearchMods", req)
    }

    public func modVersions(serviceID: String,
                            project: String,
                            gameVersion: String,
                            loader: String) async throws -> Gryonixnexusd_V1_ModVersionList {
        var req = Gryonixnexusd_V1_ModVersionsRequest()
        req.serviceID = serviceID
        req.project = project
        req.gameVersion = gameVersion
        req.loader = loader
        return try await unary("/gryonixnexusd.v1.Mods/ModVersions", req)
    }

    public func listModFiles(serviceID: String) async throws -> Gryonixnexusd_V1_ModFileList {
        var req = Gryonixnexusd_V1_ListModFilesRequest()
        req.serviceID = serviceID
        return try await unary("/gryonixnexusd.v1.Mods/ListModFiles", req)
    }

    /// Send one jar up
    public func uploadModFile(serviceID: String,
                              slot: Gryonixnexusd_V1_ModSlot,
                              name: String,
                              content: Data) async throws -> Gryonixnexusd_V1_ModFileList {
        var req = Gryonixnexusd_V1_UploadModFileRequest()
        req.serviceID = serviceID
        req.slot = slot
        req.name = name
        req.content = content
        return try await unary("/gryonixnexusd.v1.Mods/UploadModFile", req)
    }

    public func deleteModFile(serviceID: String,
                              slot: Gryonixnexusd_V1_ModSlot,
                              name: String) async throws -> Gryonixnexusd_V1_ModFileList {
        var req = Gryonixnexusd_V1_DeleteModFileRequest()
        req.serviceID = serviceID
        req.slot = slot
        req.name = name
        return try await unary("/gryonixnexusd.v1.Mods/DeleteModFile", req)
    }

    // MARK: Old copies left by restores

    public func listPreRestoreCopies(serviceID: String) async throws -> Gryonixnexusd_V1_PreRestoreCopyList {
        var req = Gryonixnexusd_V1_ListPreRestoreCopiesRequest()
        req.serviceID = serviceID
        return try await unary("/gryonixnexusd.v1.Restore/ListPreRestoreCopies", req)
    }

    public func deletePreRestoreCopy(path: String) async throws -> Gryonixnexusd_V1_PreRestoreCopyList {
        var req = Gryonixnexusd_V1_DeletePreRestoreCopyRequest()
        req.path = path
        return try await unary("/gryonixnexusd.v1.Restore/DeletePreRestoreCopy", req)
    }

    // MARK: Vaultwarden

    public func vaultwardenTwoFactor() async throws -> Gryonixnexusd_V1_VaultwardenTwoFactor {
        try await unary("/gryonixnexusd.v1.Vaultwarden/GetVaultwardenTwoFactor",
                        Gryonixnexusd_V1_GetVaultwardenTwoFactorRequest())
    }

    // MARK: Uninstall

    public func removeService(serviceID: String, purgeData: Bool,
                              purgeBackups: Bool) -> AsyncThrowingStream<Gryonixnexusd_V1_UninstallEvent, Error> {
        var req = Gryonixnexusd_V1_RemoveServiceRequest()
        req.serviceID = serviceID
        req.purgeData = purgeData
        req.purgeBackups = purgeBackups
        return stream("/gryonixnexusd.v1.Uninstall/RemoveService", req)
    }

    // MARK: Restore

    public func runRestore(serviceID: String, archivePath: String,
                           passphrase: String = "") -> AsyncThrowingStream<Gryonixnexusd_V1_RestoreEvent, Error> {
        var req = Gryonixnexusd_V1_RunRestoreRequest()
        req.serviceID = serviceID
        req.archivePath = archivePath
        req.passphrase = passphrase
        return stream("/gryonixnexusd.v1.Restore/RunRestore", req)
    }

    // MARK: Install

    public func installService(serviceID: String, domain: String,
                               additionalDomains: [String] = [], localOnly: Bool = false,
                               adminUsername: String = "", language: String = "",
                               settings: [String: String] = [:],
                               host: AgentHostSurface = AgentHostSurface()) -> AsyncThrowingStream<Gryonixnexusd_V1_InstallServiceEvent, Error> {
        let req = Self.installRequest(serviceID: serviceID, domain: domain, additionalDomains: additionalDomains,
                                      localOnly: localOnly, adminUsername: adminUsername, language: language,
                                      settings: settings, host: host)
        return stream("/gryonixnexusd.v1.Install/InstallService", req)
    }

    /// One service's install request, as InstallService and plans take it
    public static func installRequest(serviceID: String, domain: String,
                                      additionalDomains: [String] = [], localOnly: Bool = false,
                                      adminUsername: String = "", language: String = "",
                                      settings: [String: String] = [:],
                                      host: AgentHostSurface = AgentHostSurface())
        -> Gryonixnexusd_V1_InstallServiceRequest {
        var req = Gryonixnexusd_V1_InstallServiceRequest()
        req.serviceID = serviceID
        req.domain = domain
        req.additionalDomains = additionalDomains
        req.localOnly = localOnly
        req.adminUsername = adminUsername
        req.language = language
        req.settings = settings
        req.hostRole = host.role
        req.ptrIp = host.ptrIP
        req.ptrHostname = host.ptrHostname
        req.tunnelEndpoint = host.tunnelEndpoint
        req.relayWgPort = host.relayWGPort
        req.relayForwardedPorts = host.relayForwardedPorts
        req.relayForwardedUdpPorts = host.relayForwardedUDPPorts
        req.homeWgAddress = host.homeWGAddress
        req.dashboardPublicKey = host.dashboardPublicKey
        return req
    }

    /// Caddy asks again for missing certificates
    @discardableResult
    public func refreshCertificates() async throws -> Bool {
        let response: Gryonixnexusd_V1_RefreshCertificatesResponse =
            try await unary("/gryonixnexusd.v1.Install/RefreshCertificates", Gryonixnexusd_V1_RefreshCertificatesRequest())
        return response.reloaded
    }

    public func startInstallPlan(_ services: [Gryonixnexusd_V1_InstallServiceRequest],
                                 purpose: Gryonixnexusd_V1_InstallPlanPurpose = .add) async throws
        -> Gryonixnexusd_V1_InstallPlan {
        var req = Gryonixnexusd_V1_StartInstallPlanRequest()
        req.services = services
        req.purpose = purpose
        return try await unary("/gryonixnexusd.v1.Install/StartInstallPlan", req)
    }

    /// A plan by id; empty id means newest
    public func installPlan(id: String = "") async throws -> Gryonixnexusd_V1_InstallPlan {
        var req = Gryonixnexusd_V1_GetInstallPlanRequest()
        req.planID = id
        return try await unary("/gryonixnexusd.v1.Install/GetInstallPlan", req)
    }

    public func watchInstall(jobID: String,
                             fromSequence: UInt64 = 0) -> AsyncThrowingStream<Gryonixnexusd_V1_InstallServiceEvent, Error> {
        var req = Gryonixnexusd_V1_WatchInstallRequest()
        req.jobID = jobID
        req.fromSequence = fromSequence
        return stream("/gryonixnexusd.v1.Install/WatchInstall", req)
    }

    // ───────────────────────────── Jobs ─────────────────────────────

    public func watchJob(jobID: String,
                         fromSequence: UInt64 = 0) -> AsyncThrowingStream<Gryonixnexusd_V1_JobEvent, Error> {
        var req = Gryonixnexusd_V1_WatchJobRequest()
        req.jobID = jobID
        req.fromSequence = fromSequence
        return stream("/gryonixnexusd.v1.Jobs/WatchJob", req)
    }

    /// What this host has been doing, newest first
    public func listJobs(kind: Gryonixnexusd_V1_JobKind = .unspecified,
                         runningOnly: Bool = false) async throws -> [Gryonixnexusd_V1_Job] {
        var req = Gryonixnexusd_V1_ListJobsRequest()
        req.kind = kind
        req.runningOnly = runningOnly
        let response: Gryonixnexusd_V1_JobList = try await unary("/gryonixnexusd.v1.Jobs/ListJobs", req)
        return response.jobs
    }

    public func cancelJob(jobID: String) async throws -> Gryonixnexusd_V1_Job {
        var req = Gryonixnexusd_V1_CancelJobRequest()
        req.jobID = jobID
        return try await unary("/gryonixnexusd.v1.Jobs/CancelJob", req)
    }

    public func provisionHost(domain: String, additionalDomains: [String] = [],
                              localOnly: Bool = false, adminUsername: String = "",
                              language: String = "", settings: [String: String] = [:],
                              host: AgentHostSurface = AgentHostSurface()) async throws
        -> Gryonixnexusd_V1_ProvisionHostResponse {
        var req = Gryonixnexusd_V1_ProvisionHostRequest()
        req.domain = domain
        req.additionalDomains = additionalDomains
        req.localOnly = localOnly
        req.adminUsername = adminUsername
        req.language = language
        req.settings = settings
        req.hostRole = host.role
        req.ptrIp = host.ptrIP
        req.ptrHostname = host.ptrHostname
        req.tunnelEndpoint = host.tunnelEndpoint
        req.relayWgPort = host.relayWGPort
        req.relayForwardedPorts = host.relayForwardedPorts
        req.relayForwardedUdpPorts = host.relayForwardedUDPPorts
        req.homeWgAddress = host.homeWGAddress
        req.dashboardPublicKey = host.dashboardPublicKey
        return try await unary("/gryonixnexusd.v1.Install/ProvisionHost", req)
    }

    // MARK: VPN clients

    /// The client devices of one VPN protocol

    /// The mesh users a join key can belong to
    public func listMeshUsers() async throws -> [Gryonixnexusd_V1_MeshUser] {
        let response: Gryonixnexusd_V1_MeshUserList =
            try await unary("/gryonixnexusd.v1.Mesh/ListMeshUsers", Gryonixnexusd_V1_ListMeshUsersRequest())
        return response.users
    }

    @discardableResult
    public func createMeshUser(name: String) async throws -> [Gryonixnexusd_V1_MeshUser] {
        var req = Gryonixnexusd_V1_CreateMeshUserRequest()
        req.name = name
        let response: Gryonixnexusd_V1_MeshUserList =
            try await unary("/gryonixnexusd.v1.Mesh/CreateMeshUser", req)
        return response.users
    }

    /// Mint a join key
    public func createMeshAuthKey(userID: String, reusable: Bool,
                                  expirationHours: UInt32) async throws -> Gryonixnexusd_V1_MeshAuthKey {
        var req = Gryonixnexusd_V1_CreateMeshAuthKeyRequest()
        req.userID = userID
        req.reusable = reusable
        req.expirationHours = expirationHours
        return try await unary("/gryonixnexusd.v1.Mesh/CreateMeshAuthKey", req)
    }

    // MARK: - The models the local engine runs

    public func listModels() async throws -> Gryonixnexusd_V1_ModelList {
        try await unary("/gryonixnexusd.v1.Models/ListModels", Gryonixnexusd_V1_ListModelsRequest())
    }

    /// Fetch one
    public func pullModel(name: String)
    -> AsyncThrowingStream<Gryonixnexusd_V1_ModelPullEvent, Error> {
        var req = Gryonixnexusd_V1_PullModelRequest()
        req.name = name
        return stream("/gryonixnexusd.v1.Models/PullModel", req)
    }

    @discardableResult
    public func deleteModel(name: String) async throws -> Gryonixnexusd_V1_ModelList {
        var req = Gryonixnexusd_V1_DeleteModelRequest()
        req.name = name
        return try await unary("/gryonixnexusd.v1.Models/DeleteModel", req)
    }

    public func listMeshNodes() async throws -> [Gryonixnexusd_V1_MeshNode] {
        let response: Gryonixnexusd_V1_MeshNodeList =
            try await unary("/gryonixnexusd.v1.Mesh/ListMeshNodes", Gryonixnexusd_V1_ListMeshNodesRequest())
        return response.nodes
    }

    @discardableResult
    public func deleteMeshNode(nodeID: String) async throws -> [Gryonixnexusd_V1_MeshNode] {
        var req = Gryonixnexusd_V1_DeleteMeshNodeRequest()
        req.nodeID = nodeID
        let response: Gryonixnexusd_V1_MeshNodeList =
            try await unary("/gryonixnexusd.v1.Mesh/DeleteMeshNode", req)
        return response.nodes
    }

    /// Publish this deployment's service names inside the mesh
    @discardableResult
    public func publishMeshNames(_ names: [String],
                                 nodeName: String = "") async throws -> [Gryonixnexusd_V1_MeshName] {
        var req = Gryonixnexusd_V1_PublishMeshNamesRequest()
        req.names = names
        req.nodeName = nodeName
        let response: Gryonixnexusd_V1_MeshNameList =
            try await unary("/gryonixnexusd.v1.Mesh/PublishMeshNames", req)
        return response.records
    }

    public func listVPNClients(protocol name: String) async throws -> [Gryonixnexusd_V1_VpnClient] {
        var req = Gryonixnexusd_V1_ListVpnClientsRequest()
        req.protocol = name
        let response: Gryonixnexusd_V1_VpnClientList = try await unary("/gryonixnexusd.v1.Vpn/ListVpnClients", req)
        return response.clients
    }

    /// Add a device
    @discardableResult
    public func addVPNClient(protocol name: String, clientName: String,
                             dns: [String] = []) async throws -> [Gryonixnexusd_V1_VpnClient] {
        var req = Gryonixnexusd_V1_AddVpnClientRequest()
        req.protocol = name
        req.name = clientName
        req.dns = dns
        let response: Gryonixnexusd_V1_VpnClientList = try await unary("/gryonixnexusd.v1.Vpn/AddVpnClient", req)
        return response.clients
    }

    @discardableResult
    public func deleteVPNClient(protocol name: String, clientID: String) async throws -> [Gryonixnexusd_V1_VpnClient] {
        var req = Gryonixnexusd_V1_DeleteVpnClientRequest()
        req.protocol = name
        req.clientID = clientID
        let response: Gryonixnexusd_V1_VpnClientList = try await unary("/gryonixnexusd.v1.Vpn/DeleteVpnClient", req)
        return response.clients
    }

    /// Change one device's DNS
    @discardableResult
    public func setVPNClientDNS(protocol name: String, clientID: String,
                                dns: [String]) async throws -> [Gryonixnexusd_V1_VpnClient] {
        var req = Gryonixnexusd_V1_SetVpnClientDnsRequest()
        req.protocol = name
        req.clientID = clientID
        req.dns = dns
        let response: Gryonixnexusd_V1_VpnClientList = try await unary("/gryonixnexusd.v1.Vpn/SetVpnClientDns", req)
        return response.clients
    }

    /// The DNS new devices get, with the server's own resolver
    public func vpnDefaultDNS() async throws -> Gryonixnexusd_V1_VpnDns {
        try await unary("/gryonixnexusd.v1.Vpn/GetVpnDns", Gryonixnexusd_V1_GetVpnDnsRequest())
    }

    @discardableResult
    public func setVPNDefaultDNS(_ dns: [String]) async throws -> Gryonixnexusd_V1_VpnDns {
        var req = Gryonixnexusd_V1_VpnDns()
        req.dns = dns
        return try await unary("/gryonixnexusd.v1.Vpn/SetVpnDns", req)
    }

    public func vpnDNSPriority() async throws -> Gryonixnexusd_V1_VpnDnsPriority {
        try await unary("/gryonixnexusd.v1.Vpn/GetVpnDnsPriority", Gryonixnexusd_V1_GetVpnDnsPriorityRequest())
    }

    @discardableResult
    public func setVPNDNSPriority(_ resolvers: [String]) async throws -> Gryonixnexusd_V1_VpnDnsPriority {
        var req = Gryonixnexusd_V1_VpnDnsPriority()
        req.resolvers = resolvers
        return try await unary("/gryonixnexusd.v1.Vpn/SetVpnDnsPriority", req)
    }

    /// The VPN's directories, packed on this machine
    public func exportVPNState(directories: [String]) async throws -> Gryonixnexusd_V1_VpnState {
        var req = Gryonixnexusd_V1_ExportVpnStateRequest()
        req.directories = directories
        return try await unary("/gryonixnexusd.v1.Vpn/ExportVpnState", req)
    }

    /// Unpacks another machine's VPN directories here
    @discardableResult
    public func importVPNState(_ state: Gryonixnexusd_V1_VpnState,
                               replace: Bool) async throws -> Gryonixnexusd_V1_ImportVpnStateResponse {
        var req = Gryonixnexusd_V1_ImportVpnStateRequest()
        req.archive = state.archive
        req.directories = state.directories
        req.replace = replace
        return try await unary("/gryonixnexusd.v1.Vpn/ImportVpnState", req)
    }

    public func vpnClientConfig(protocol name: String, clientID: String) async throws
        -> Gryonixnexusd_V1_VpnClientConfig {
        var req = Gryonixnexusd_V1_GetVpnClientConfigRequest()
        req.protocol = name
        req.clientID = clientID
        return try await unary("/gryonixnexusd.v1.Vpn/GetVpnClientConfig", req)
    }

    // MARK: Pairing

    /// Enroll this device
    public func pair(code: String, devicePublicKey: String, label: String,
                     deviceUID: String = "") async throws -> Gryonixnexusd_V1_Device {
        try await pairing(code: code, devicePublicKey: devicePublicKey, label: label,
                          deviceUID: deviceUID).device
    }

    public func pairing(code: String, devicePublicKey: String, label: String, deviceUID: String = "",
                        authorizeSSHKey: Bool = false, transferID: String = "")
        async throws -> Gryonixnexusd_V1_PairResponse {
        var req = Gryonixnexusd_V1_PairRequest()
        req.code = code
        req.devicePublicKey = devicePublicKey
        req.label = label
        req.deviceUid = deviceUID
        req.authorizeSshKey = authorizeSSHKey
        req.transferID = transferID
        return try await unary("/gryonixnexusd.v1.Pairing/Pair", req)
    }

    /// A one-time SSH key for an export file
    public func createTransfer(validMinutes: Int32 = 0) async throws -> Gryonixnexusd_V1_CreateTransferResponse {
        var req = Gryonixnexusd_V1_CreateTransferRequest()
        req.validMinutes = validMinutes
        return try await unary("/gryonixnexusd.v1.Pairing/CreateTransfer", req)
    }

    public func listDevices() async throws -> [Gryonixnexusd_V1_Device] {
        let response: Gryonixnexusd_V1_DeviceList = try await unary(
            "/gryonixnexusd.v1.Pairing/ListDevices", Gryonixnexusd_V1_ListDevicesRequest())
        return response.devices
    }

    @discardableResult
    public func revoke(deviceID: String) async throws -> Bool {
        var req = Gryonixnexusd_V1_RevokeRequest()
        req.deviceID = deviceID
        let response: Gryonixnexusd_V1_RevokeResponse = try await unary("/gryonixnexusd.v1.Pairing/Revoke", req)
        return response.revoked
    }

    public func sessionPolicy() async throws -> Gryonixnexusd_V1_SessionPolicy {
        try await unary("/gryonixnexusd.v1.Pairing/GetSessionPolicy",
                        Gryonixnexusd_V1_GetSessionPolicyRequest())
    }

    /// `months` is one of 0 (never), 1, 3, 6, 12
    public func setSessionPolicy(months: Int32) async throws -> Gryonixnexusd_V1_SessionPolicy {
        var req = Gryonixnexusd_V1_SetSessionPolicyRequest()
        req.autoLogoutMonths = months
        return try await unary("/gryonixnexusd.v1.Pairing/SetSessionPolicy", req)
    }

    // MARK: Vault

    public func vault() async throws -> Gryonixnexusd_V1_VaultSnapshot {
        try await unary("/gryonixnexusd.v1.Vault/GetVault", Gryonixnexusd_V1_GetVaultRequest())
    }

    /// Upsert
    @discardableResult
    public func putVaultEntries(_ entries: [Gryonixnexusd_V1_VaultEntry]) async throws
        -> Gryonixnexusd_V1_VaultSnapshot {
        var req = Gryonixnexusd_V1_PutVaultEntriesRequest()
        req.entries = entries
        return try await unary("/gryonixnexusd.v1.Vault/PutVaultEntries", req)
    }

    @discardableResult
    public func deleteVaultEntry(id: String, deviceUID: String = "",
                                 deletedAt: Date = Date()) async throws
        -> Gryonixnexusd_V1_VaultSnapshot {
        var req = Gryonixnexusd_V1_DeleteVaultEntryRequest()
        req.id = id
        req.deviceUid = deviceUID
        req.deletedAt = Int64(deletedAt.timeIntervalSince1970 * 1000)
        return try await unary("/gryonixnexusd.v1.Vault/DeleteVaultEntry", req)
    }

    // MARK: Move

    public func prepareMoveSend(transferID: String) async throws -> String {
        var req = Gryonixnexusd_V1_PrepareMoveSendRequest()
        req.transferID = transferID
        let response: Gryonixnexusd_V1_PrepareMoveSendResponse = try await unary("/gryonixnexusd.v1.Move/PrepareMoveSend", req)
        return response.publicKey
    }

    public func prepareMoveReceive(transferID: String, serviceID: String, controlUser: String,
                                   publicKey: String, expectedBytes: Int64)
        async throws -> Gryonixnexusd_V1_PrepareMoveReceiveResponse {
        var req = Gryonixnexusd_V1_PrepareMoveReceiveRequest()
        req.transferID = transferID
        req.serviceID = serviceID
        req.controlUser = controlUser
        req.publicKey = publicKey
        req.expectedBytes = expectedBytes
        return try await unary("/gryonixnexusd.v1.Move/PrepareMoveReceive", req)
    }

    public func sendMoveData(transferID: String, serviceID: String, archivePath: String,
                             host: String, port: UInt32, user: String,
                             hostKeys: String) -> AsyncThrowingStream<Gryonixnexusd_V1_MoveEvent, Error> {
        var req = Gryonixnexusd_V1_SendMoveDataRequest()
        req.transferID = transferID
        req.serviceID = serviceID
        req.archivePath = archivePath
        req.host = host
        req.port = port
        req.user = user
        req.hostKeys = hostKeys
        return stream("/gryonixnexusd.v1.Move/SendMoveData", req)
    }

    public func acceptMoveData(transferID: String, serviceID: String, sha256: String,
                               bytes: Int64, archiveName: String) -> AsyncThrowingStream<Gryonixnexusd_V1_MoveEvent, Error> {
        var req = Gryonixnexusd_V1_AcceptMoveDataRequest()
        req.transferID = transferID
        req.serviceID = serviceID
        req.sha256 = sha256
        req.bytes = bytes
        req.archiveName = archiveName
        return stream("/gryonixnexusd.v1.Move/AcceptMoveData", req)
    }

    public func discardMoveTransfer(transferID: String) async throws {
        var req = Gryonixnexusd_V1_DiscardMoveTransferRequest()
        req.transferID = transferID
        let _: Gryonixnexusd_V1_DiscardMoveTransferResponse = try await unary("/gryonixnexusd.v1.Move/DiscardMoveTransfer", req)
    }

    public func setServiceUpstream(_ request: Gryonixnexusd_V1_SetServiceUpstreamRequest)
        async throws -> Gryonixnexusd_V1_ServiceUpstreamState {
        try await unary("/gryonixnexusd.v1.Move/SetServiceUpstream", request)
    }

    public func probeServiceUpstream(serviceID: String) async throws -> Gryonixnexusd_V1_ServiceUpstreamProbe {
        var req = Gryonixnexusd_V1_ProbeServiceUpstreamRequest()
        req.serviceID = serviceID
        return try await unary("/gryonixnexusd.v1.Move/ProbeServiceUpstream", req)
    }

    // MARK: Encoding glue

    private func unary<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
        _ path: String, _ request: Request
    ) async throws -> Response {
        let requestData: Data = try request.serializedBytes()
        let responseData = try await transport.unary(path: path, request: requestData)
        do {
            return try Response(serializedBytes: responseData)
        } catch {
            throw AgentError.decode("\(Response.self): \(error)")
        }
    }

    private func stream<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
        _ path: String, _ request: Request
    ) -> AsyncThrowingStream<Response, Error> {
        let requestData: Data = (try? request.serializedBytes()) ?? Data()
        let raw = transport.serverStream(path: path, request: requestData)
        let announce = onJobStarted
        return AsyncThrowingStream { continuation in
            let task = Task {
                var announced = false
                do {
                    for try await payload in raw {
                        let message = try Response(serializedBytes: payload)
                        if !announced, let carrier = message as? AgentJobCarrying, !carrier.jobID.isEmpty {
                            announced = true
                            announce?(carrier.jobID)
                        }
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct AgentHostSurface: Sendable {
    public var role: Gryonixnexusd_V1_HostRole
    public var ptrIP: String
    public var ptrHostname: String
    /// Scenario B's home half: `<vps public ip>:<wg port>`
    public var tunnelEndpoint: String
    public var relayWGPort: UInt32
    public var relayForwardedPorts: [UInt32]
    public var relayForwardedUDPPorts: [UInt32]
    public var homeWGAddress: String
    public var dashboardPublicKey: String

    public init(role: Gryonixnexusd_V1_HostRole = .singleHost,
                ptrIP: String = "", ptrHostname: String = "",
                tunnelEndpoint: String = "",
                relayWGPort: UInt32 = 0, relayForwardedPorts: [UInt32] = [],
                relayForwardedUDPPorts: [UInt32] = [],
                homeWGAddress: String = "", dashboardPublicKey: String = "") {
        self.role = role
        self.ptrIP = ptrIP
        self.ptrHostname = ptrHostname
        self.tunnelEndpoint = tunnelEndpoint
        self.relayWGPort = relayWGPort
        self.relayForwardedPorts = relayForwardedPorts
        self.relayForwardedUDPPorts = relayForwardedUDPPorts
        self.homeWGAddress = homeWGAddress
        self.dashboardPublicKey = dashboardPublicKey
    }
}
