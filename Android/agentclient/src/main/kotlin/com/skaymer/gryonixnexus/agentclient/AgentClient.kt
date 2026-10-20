// Generated verbs by Tools/port-agent-client-to-kotlin.py — do not hand-edit
// the section between the GENERATED markers; re-run the script instead. The
// hand-written section below it is the six verbs the script names as its own
// exceptions, each for a stated reason.
package com.skaymer.gryonixnexus.agentclient

import com.squareup.wire.ProtoAdapter
import gryonixnexusd.v1.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import okio.ByteString.Companion.toByteString

class AgentClient(private val transport: AgentTransport) {
    constructor(factory: AgentStreamFactory, deviceUID: String = "") :
        this(ConnectTransport(factory, deviceUID))

    // ─────────────────────── GENERATED VERBS BEGIN ───────────────────────
    suspend fun getState(): State =
        unary("/gryonixnexusd.v1.Control/GetState", GetStateRequest(), State.ADAPTER)

    suspend fun discover(): DiscoverResult =
        unary("/gryonixnexusd.v1.Control/Discover", DiscoverRequest(), DiscoverResult.ADAPTER)

    fun hostMetrics(intervalSeconds: Int = 0): Flow<MetricsSample> =
        stream("/gryonixnexusd.v1.Control/HostMetrics", HostMetricsRequest(interval_seconds = intervalSeconds), MetricsSample.ADAPTER)

    fun logs(serviceID: String, tail: Int = 0): Flow<LogLine> =
        stream("/gryonixnexusd.v1.Control/Logs", LogsRequest(service_id = serviceID, tail = tail), LogLine.ADAPTER)

    suspend fun listSerialDevices(): SerialDeviceList =
        unary("/gryonixnexusd.v1.Control/ListSerialDevices", ListSerialDevicesRequest(), SerialDeviceList.ADAPTER)

    suspend fun listBackups(serviceID: String): BackupList =
        unary("/gryonixnexusd.v1.Backup/ListBackups", ListBackupsRequest(service_id = serviceID), BackupList.ADAPTER)

    /** Every service's backups on the host, in one reply */
    suspend fun listAllBackups(): AllBackups =
        unary("/gryonixnexusd.v1.Backup/ListAllBackups", ListAllBackupsRequest(), AllBackups.ADAPTER)

    suspend fun estimateBackup(serviceID: String): BackupEstimate =
        unary("/gryonixnexusd.v1.Backup/EstimateBackup", EstimateBackupRequest(service_id = serviceID), BackupEstimate.ADAPTER)

    fun runBackup(serviceID: String, encryption: BackupEncryption = BackupEncryption.BACKUP_ENCRYPTION_UNSPECIFIED, passphrase: String = ""): Flow<BackupEvent> =
        stream("/gryonixnexusd.v1.Backup/RunBackup", RunBackupRequest(service_id = serviceID, encryption = encryption, passphrase = passphrase), BackupEvent.ADAPTER)

    suspend fun deleteBackup(serviceID: String, path: String): BackupList =
        unary("/gryonixnexusd.v1.Backup/DeleteBackup", DeleteBackupRequest(service_id = serviceID, path = path), BackupList.ADAPTER)

    suspend fun getBackupSchedule(): BackupSchedulePolicy =
        unary("/gryonixnexusd.v1.Backup/GetBackupSchedule", GetBackupScheduleRequest(), BackupSchedulePolicy.ADAPTER)

    suspend fun setBackupSchedule(schedule: String, retention: Int, services: List<String>, passphrase: String = ""): BackupSchedulePolicy =
        unary("/gryonixnexusd.v1.Backup/SetBackupSchedule", SetBackupScheduleRequest(schedule = schedule, retention = retention, services = services, passphrase = passphrase), BackupSchedulePolicy.ADAPTER)

    suspend fun setBackupDestination(destination: BackupDestination, secret: String = ""): BackupSchedulePolicy =
        unary(
            "/gryonixnexusd.v1.Backup/SetBackupDestination",
            SetBackupDestinationRequest(destination = destination, secret = secret),
            BackupSchedulePolicy.ADAPTER,
        )

    suspend fun testBackupDestination(): BackupDestinationTest =
        unary(
            "/gryonixnexusd.v1.Backup/TestBackupDestination",
            TestBackupDestinationRequest(),
            BackupDestinationTest.ADAPTER,
        )

    suspend fun setBackupDrives(drives: BackupDrives): BackupSchedulePolicy =
        unary("/gryonixnexusd.v1.Backup/SetBackupDrives", SetBackupDrivesRequest(drives = drives), BackupSchedulePolicy.ADAPTER)

    /** Stages a drive archive where a restore reads it */
    suspend fun fetchDriveBackup(serviceID: String, path: String): BackupArchive =
        unary(
            "/gryonixnexusd.v1.Backup/FetchDriveBackup",
            FetchDriveBackupRequest(service_id = serviceID, path = path),
            BackupArchive.ADAPTER,
        )

    suspend fun listMailboxes(): List<Mailbox> =
        unary("/gryonixnexusd.v1.Mail/ListMailboxes", ListMailboxesRequest(), MailboxList.ADAPTER).mailboxes

    suspend fun createMailbox(address: String, password: String): List<Mailbox> =
        unary("/gryonixnexusd.v1.Mail/CreateMailbox", CreateMailboxRequest(address = address, password = password), MailboxList.ADAPTER).mailboxes

    suspend fun deleteMailbox(address: String): List<Mailbox> =
        unary("/gryonixnexusd.v1.Mail/DeleteMailbox", DeleteMailboxRequest(address = address), MailboxList.ADAPTER).mailboxes

    suspend fun setMailboxPassword(address: String, password: String): List<Mailbox> =
        unary("/gryonixnexusd.v1.Mail/SetMailboxPassword", SetMailboxPasswordRequest(address = address, password = password), MailboxList.ADAPTER).mailboxes

    suspend fun getDkimRecords(): List<DkimRecord> =
        unary("/gryonixnexusd.v1.Dkim/GetDkimRecords", GetDkimRecordsRequest(), DkimRecordList.ADAPTER).records

    suspend fun serviceStatus(serviceID: String): ServiceStatusResponse =
        unary("/gryonixnexusd.v1.Control/ServiceStatus", ServiceStatusRequest(service_id = serviceID), ServiceStatusResponse.ADAPTER)

    fun controlService(serviceID: String, action: ServiceAction): Flow<ServiceOperationEvent> =
        stream("/gryonixnexusd.v1.Control/ControlService", ControlServiceRequest(service_id = serviceID, action = action), ServiceOperationEvent.ADAPTER)

    suspend fun listContainers(): ContainerInventory =
        unary("/gryonixnexusd.v1.Containers/ListContainers", ListContainersRequest(), ContainerInventory.ADAPTER)

    suspend fun setContainerGroupName(key: String, displayName: String): ContainerInventory =
        unary("/gryonixnexusd.v1.Containers/SetContainerGroupName", SetContainerGroupNameRequest(key = key, display_name = displayName), ContainerInventory.ADAPTER)

    fun controlContainerGroup(key: String, action: ServiceAction): Flow<ContainerOperationEvent> =
        stream("/gryonixnexusd.v1.Containers/ControlContainerGroup", ControlContainerGroupRequest(key = key, action = action), ContainerOperationEvent.ADAPTER)

    fun containerGroupLogs(key: String, tail: Int = 0): Flow<LogLine> =
        stream("/gryonixnexusd.v1.Containers/ContainerGroupLogs", ContainerGroupLogsRequest(key = key, tail = tail), LogLine.ADAPTER)

    suspend fun inspectContainer(name: String): ContainerDetail =
        unary("/gryonixnexusd.v1.Containers/InspectContainer", InspectContainerRequest(name = name), ContainerDetail.ADAPTER)

    suspend fun containerBackupPlan(key: String): ContainerBackupPlan =
        unary("/gryonixnexusd.v1.Containers/GetContainerBackupPlan", GetContainerBackupPlanRequest(key = key), ContainerBackupPlan.ADAPTER)

    fun runContainerGroupBackup(key: String): Flow<ContainerBackupEvent> =
        stream("/gryonixnexusd.v1.Containers/RunContainerGroupBackup", RunContainerGroupBackupRequest(key = key), ContainerBackupEvent.ADAPTER)

    suspend fun previewContainerGroupRemoval(key: String, purgeData: Boolean, purgeBackups: Boolean): ContainerRemovalPreview =
        unary("/gryonixnexusd.v1.Containers/PreviewContainerGroupRemoval", PreviewContainerGroupRemovalRequest(key = key, purge_data = purgeData, purge_backups = purgeBackups), ContainerRemovalPreview.ADAPTER)

    fun removeContainerGroup(key: String, purgeData: Boolean, purgeBackups: Boolean): Flow<ContainerRemovalEvent> =
        stream("/gryonixnexusd.v1.Containers/RemoveContainerGroup", RemoveContainerGroupRequest(key = key, purge_data = purgeData, purge_backups = purgeBackups), ContainerRemovalEvent.ADAPTER)

    fun updateContainerGroup(key: String, skipBackup: Boolean): Flow<ContainerUpdateEvent> =
        stream("/gryonixnexusd.v1.Containers/UpdateContainerGroup", UpdateContainerGroupRequest(key = key, skip_backup = skipBackup), ContainerUpdateEvent.ADAPTER)

    suspend fun containerBackupSchedule(key: String): ContainerBackupSchedule =
        unary("/gryonixnexusd.v1.Containers/GetContainerBackupSchedule", GetContainerBackupScheduleRequest(key = key), ContainerBackupSchedule.ADAPTER)

    suspend fun setContainerBackupSchedule(key: String, schedule: String): ContainerBackupSchedule =
        unary("/gryonixnexusd.v1.Containers/SetContainerBackupSchedule", SetContainerBackupScheduleRequest(key = key, schedule = schedule), ContainerBackupSchedule.ADAPTER)

    suspend fun containerGroupBackups(key: String): ContainerBackupList =
        unary("/gryonixnexusd.v1.Containers/ListContainerGroupBackups", ListContainerGroupBackupsRequest(key = key), ContainerBackupList.ADAPTER)

    suspend fun checkUpdates(): UpdateCheckResult =
        unary("/gryonixnexusd.v1.Update/CheckUpdates", CheckUpdatesRequest(), UpdateCheckResult.ADAPTER)

    fun runUpdate(serviceID: String): Flow<UpdateEvent> =
        stream("/gryonixnexusd.v1.Update/RunUpdate", RunUpdateRequest(service_id = serviceID), UpdateEvent.ADAPTER)

    suspend fun getUpdatePolicy(): UpdatePolicy =
        unary("/gryonixnexusd.v1.Update/GetUpdatePolicy", GetUpdatePolicyRequest(), UpdatePolicy.ADAPTER)

    suspend fun setUpdateSchedule(schedule: String, services: List<String>): UpdatePolicy =
        unary("/gryonixnexusd.v1.Update/SetUpdateSchedule", SetUpdateScheduleRequest(schedule = schedule, services = services), UpdatePolicy.ADAPTER)

    suspend fun getAgentUpdateStatus(): AgentUpdateStatus =
        unary("/gryonixnexusd.v1.AgentUpdate/GetAgentUpdateStatus", GetAgentUpdateStatusRequest(), AgentUpdateStatus.ADAPTER)

    suspend fun setAgentAutoUpdate(enabled: Boolean): AgentUpdateStatus = unary(
        "/gryonixnexusd.v1.AgentUpdate/SetAgentAutoUpdate",
        SetAgentAutoUpdateRequest(enabled = enabled),
        AgentUpdateStatus.ADAPTER,
    )

    fun applyAgentUpdate(): Flow<AgentUpdateEvent> =
        stream("/gryonixnexusd.v1.AgentUpdate/ApplyAgentUpdate", ApplyAgentUpdateRequest(), AgentUpdateEvent.ADAPTER)

    suspend fun removeAgent(): RemoveAgentResponse =
        unary("/gryonixnexusd.v1.AgentUpdate/RemoveAgent", RemoveAgentRequest(), RemoveAgentResponse.ADAPTER)

    suspend fun getLockdown(): LockdownState =
        unary("/gryonixnexusd.v1.Lockdown/GetLockdown", GetLockdownRequest(), LockdownState.ADAPTER)

    suspend fun setLockdown(mode: LockdownMode, hosts: List<String> = emptyList()): LockdownState =
        unary("/gryonixnexusd.v1.Lockdown/SetLockdown", SetLockdownRequest(mode = mode, hosts = hosts), LockdownState.ADAPTER)

    suspend fun getSecurityStatus(): SecurityStatus =
        unary("/gryonixnexusd.v1.Security/GetSecurityStatus", GetSecurityStatusRequest(), SecurityStatus.ADAPTER)

    suspend fun getSSHPasswordState(loginUser: String, appPublicKey: String): SshPasswordState =
        unary("/gryonixnexusd.v1.Security/GetSshPasswordState", GetSshPasswordStateRequest(login_user = loginUser, app_public_key = appPublicKey), SshPasswordState.ADAPTER)

    suspend fun listSSHUsers(loginUser: String, appPublicKey: String): SshUsers =
        unary("/gryonixnexusd.v1.Security/ListSshUsers", ListSshUsersRequest(login_user = loginUser, app_public_key = appPublicKey), SshUsers.ADAPTER)

    suspend fun setSSHKeyOnlyUsers(everyone: Boolean, users: List<String>, loginUser: String, appPublicKey: String): SshUsers =
        unary("/gryonixnexusd.v1.Security/SetSshKeyOnlyUsers", SetSshKeyOnlyUsersRequest(everyone = everyone, users = users, login_user = loginUser, app_public_key = appPublicKey), SshUsers.ADAPTER)

    suspend fun setSSHPasswordLogin(open: Boolean, loginUser: String, appPublicKey: String): SshPasswordState =
        unary("/gryonixnexusd.v1.Security/SetSshPasswordLogin", SetSshPasswordLoginRequest(allow_passwords = open, login_user = loginUser, app_public_key = appPublicKey), SshPasswordState.ADAPTER)

    fun controlSecurity(action: SecurityAction): Flow<SecurityOperationEvent> =
        stream("/gryonixnexusd.v1.Security/ControlSecurity", ControlSecurityRequest(action = action), SecurityOperationEvent.ADAPTER)

    suspend fun getSecurityDecisions(): SecurityDecisions =
        unary("/gryonixnexusd.v1.Security/GetSecurityDecisions", GetSecurityDecisionsRequest(), SecurityDecisions.ADAPTER)

    suspend fun setSecurityDecision(
        value: String,
        banned: Boolean,
        id: String = "",
        durationSeconds: Long = 0,
        reason: String = "",
    ): SecurityDecisions =
        unary(
            "/gryonixnexusd.v1.Security/SetSecurityDecision",
            SetSecurityDecisionRequest(value_ = value, id = id, banned = banned, duration_seconds = durationSeconds, reason = reason),
            SecurityDecisions.ADAPTER,
        )

    suspend fun getSecurityAutoRules(): SecurityAutoRules =
        unary("/gryonixnexusd.v1.Security/GetSecurityAutoRules", GetSecurityAutoRulesRequest(), SecurityAutoRules.ADAPTER)

    suspend fun setSecurityAutoRules(rules: SecurityAutoRules): SecurityAutoRules =
        unary(
            "/gryonixnexusd.v1.Security/SetSecurityAutoRules",
            SetSecurityAutoRulesRequest(rules = rules),
            SecurityAutoRules.ADAPTER,
        )

    suspend fun getSecurityAllowlist(): SecurityAllowlist =
        unary("/gryonixnexusd.v1.Security/GetSecurityAllowlist", GetSecurityAllowlistRequest(), SecurityAllowlist.ADAPTER)

    suspend fun setSecurityAllowlist(
        value: String,
        allowed: Boolean,
        comment: String = "",
        durationSeconds: Long = 0,
    ): SecurityAllowlist =
        unary(
            "/gryonixnexusd.v1.Security/SetSecurityAllowlist",
            SetSecurityAllowlistRequest(value_ = value, allowed = allowed, comment = comment, duration_seconds = durationSeconds),
            SecurityAllowlist.ADAPTER,
        )

    suspend fun getDynamicDNS(): DynamicDNSState =
        unary("/gryonixnexusd.v1.Dns/GetDynamicDNS", GetDynamicDNSRequest(), DynamicDNSState.ADAPTER)

    suspend fun setDynamicDNS(zone: String, names: List<String>, token: String = ""): DynamicDNSState =
        unary("/gryonixnexusd.v1.Dns/SetDynamicDNS", SetDynamicDNSRequest(zone = zone, names = names, token = token), DynamicDNSState.ADAPTER)

    suspend fun searchMods(serviceID: String, query: String, gameVersion: String, loader: String, limit: Int = 0, offset: Int = 0): ModSearchResult =
        unary("/gryonixnexusd.v1.Mods/SearchMods", SearchModsRequest(service_id = serviceID, query = query, game_version = gameVersion, loader = loader, limit = limit, offset = offset), ModSearchResult.ADAPTER)

    suspend fun modVersions(serviceID: String, project: String, gameVersion: String, loader: String): ModVersionList =
        unary("/gryonixnexusd.v1.Mods/ModVersions", ModVersionsRequest(service_id = serviceID, project = project, game_version = gameVersion, loader = loader), ModVersionList.ADAPTER)

    suspend fun listModFiles(serviceID: String): ModFileList =
        unary("/gryonixnexusd.v1.Mods/ListModFiles", ListModFilesRequest(service_id = serviceID), ModFileList.ADAPTER)

    suspend fun uploadModFile(serviceID: String, slot: ModSlot, name: String, content: ByteArray): ModFileList =
        unary("/gryonixnexusd.v1.Mods/UploadModFile", UploadModFileRequest(service_id = serviceID, slot = slot, name = name, content = content.toByteString()), ModFileList.ADAPTER)

    suspend fun deleteModFile(serviceID: String, slot: ModSlot, name: String): ModFileList =
        unary("/gryonixnexusd.v1.Mods/DeleteModFile", DeleteModFileRequest(service_id = serviceID, slot = slot, name = name), ModFileList.ADAPTER)

    suspend fun vaultwardenTwoFactor(): VaultwardenTwoFactor =
        unary("/gryonixnexusd.v1.Vaultwarden/GetVaultwardenTwoFactor", GetVaultwardenTwoFactorRequest(), VaultwardenTwoFactor.ADAPTER)

    fun removeService(serviceID: String, purgeData: Boolean, purgeBackups: Boolean): Flow<UninstallEvent> =
        stream("/gryonixnexusd.v1.Uninstall/RemoveService", RemoveServiceRequest(service_id = serviceID, purge_data = purgeData, purge_backups = purgeBackups), UninstallEvent.ADAPTER)

    fun runRestore(serviceID: String, archivePath: String, passphrase: String = ""): Flow<RestoreEvent> =
        stream("/gryonixnexusd.v1.Restore/RunRestore", RunRestoreRequest(service_id = serviceID, archive_path = archivePath, passphrase = passphrase), RestoreEvent.ADAPTER)

    suspend fun listPreRestoreCopies(serviceID: String): PreRestoreCopyList =
        unary("/gryonixnexusd.v1.Restore/ListPreRestoreCopies", ListPreRestoreCopiesRequest(service_id = serviceID), PreRestoreCopyList.ADAPTER)

    suspend fun deletePreRestoreCopy(path: String): PreRestoreCopyList =
        unary("/gryonixnexusd.v1.Restore/DeletePreRestoreCopy", DeletePreRestoreCopyRequest(path = path), PreRestoreCopyList.ADAPTER)

    suspend fun listMeshUsers(): List<MeshUser> =
        unary("/gryonixnexusd.v1.Mesh/ListMeshUsers", ListMeshUsersRequest(), MeshUserList.ADAPTER).users

    suspend fun createMeshUser(name: String): List<MeshUser> =
        unary("/gryonixnexusd.v1.Mesh/CreateMeshUser", CreateMeshUserRequest(name = name), MeshUserList.ADAPTER).users

    suspend fun createMeshAuthKey(userID: String, reusable: Boolean, expirationHours: Int): MeshAuthKey =
        unary("/gryonixnexusd.v1.Mesh/CreateMeshAuthKey", CreateMeshAuthKeyRequest(user_id = userID, reusable = reusable, expiration_hours = expirationHours), MeshAuthKey.ADAPTER)

    suspend fun listModels(): ModelList =
        unary("/gryonixnexusd.v1.Models/ListModels", ListModelsRequest(), ModelList.ADAPTER)

    fun pullModel(name: String): Flow<ModelPullEvent> =
        stream("/gryonixnexusd.v1.Models/PullModel", PullModelRequest(name = name), ModelPullEvent.ADAPTER)

    suspend fun deleteModel(name: String): ModelList =
        unary("/gryonixnexusd.v1.Models/DeleteModel", DeleteModelRequest(name = name), ModelList.ADAPTER)

    suspend fun listMeshNodes(): List<MeshNode> =
        unary("/gryonixnexusd.v1.Mesh/ListMeshNodes", ListMeshNodesRequest(), MeshNodeList.ADAPTER).nodes

    suspend fun deleteMeshNode(nodeID: String): List<MeshNode> =
        unary("/gryonixnexusd.v1.Mesh/DeleteMeshNode", DeleteMeshNodeRequest(node_id = nodeID), MeshNodeList.ADAPTER).nodes

    suspend fun publishMeshNames(names: List<String>, nodeName: String = ""): List<MeshName> =
        unary("/gryonixnexusd.v1.Mesh/PublishMeshNames", PublishMeshNamesRequest(names = names, node_name = nodeName), MeshNameList.ADAPTER).records

    suspend fun listVPNClients(name: String): List<VpnClient> =
        unary("/gryonixnexusd.v1.Vpn/ListVpnClients", ListVpnClientsRequest(protocol = name), VpnClientList.ADAPTER).clients

    suspend fun addVPNClient(name: String, clientName: String, dns: List<String> = emptyList()): List<VpnClient> =
        unary("/gryonixnexusd.v1.Vpn/AddVpnClient", AddVpnClientRequest(protocol = name, name = clientName, dns = dns), VpnClientList.ADAPTER).clients

    suspend fun setVPNClientDNS(name: String, clientID: String, dns: List<String>): List<VpnClient> =
        unary("/gryonixnexusd.v1.Vpn/SetVpnClientDns", SetVpnClientDnsRequest(protocol = name, client_id = clientID, dns = dns), VpnClientList.ADAPTER).clients

    suspend fun vpnDefaultDNS(): VpnDns =
        unary("/gryonixnexusd.v1.Vpn/GetVpnDns", GetVpnDnsRequest(), VpnDns.ADAPTER)

    suspend fun setVPNDefaultDNS(dns: List<String>): VpnDns =
        unary("/gryonixnexusd.v1.Vpn/SetVpnDns", VpnDns(dns = dns), VpnDns.ADAPTER)

    suspend fun vpnDNSPriority(): VpnDnsPriority =
        unary("/gryonixnexusd.v1.Vpn/GetVpnDnsPriority", GetVpnDnsPriorityRequest(), VpnDnsPriority.ADAPTER)

    suspend fun setVPNDNSPriority(resolvers: List<String>): VpnDnsPriority =
        unary("/gryonixnexusd.v1.Vpn/SetVpnDnsPriority", VpnDnsPriority(resolvers = resolvers), VpnDnsPriority.ADAPTER)

    /** The VPN's directories, packed on this machine */
    suspend fun exportVPNState(directories: List<String>): VpnState =
        unary("/gryonixnexusd.v1.Vpn/ExportVpnState", ExportVpnStateRequest(directories = directories), VpnState.ADAPTER)

    /** Unpacks another machine's VPN directories here */
    suspend fun importVPNState(state: VpnState, replace: Boolean): ImportVpnStateResponse =
        unary(
            "/gryonixnexusd.v1.Vpn/ImportVpnState",
            ImportVpnStateRequest(archive = state.archive, directories = state.directories, replace = replace),
            ImportVpnStateResponse.ADAPTER,
        )

    suspend fun refreshCertificates(): Boolean =
        unary("/gryonixnexusd.v1.Install/RefreshCertificates", RefreshCertificatesRequest(), RefreshCertificatesResponse.ADAPTER).reloaded

    suspend fun deleteVPNClient(name: String, clientID: String): List<VpnClient> =
        unary("/gryonixnexusd.v1.Vpn/DeleteVpnClient", DeleteVpnClientRequest(protocol = name, client_id = clientID), VpnClientList.ADAPTER).clients

    suspend fun vpnClientConfig(name: String, clientID: String): VpnClientConfig =
        unary("/gryonixnexusd.v1.Vpn/GetVpnClientConfig", GetVpnClientConfigRequest(protocol = name, client_id = clientID), VpnClientConfig.ADAPTER)

    suspend fun listDevices(): List<Device> =
        unary("/gryonixnexusd.v1.Pairing/ListDevices", ListDevicesRequest(), DeviceList.ADAPTER).devices

    suspend fun revoke(deviceID: String): Boolean =
        unary("/gryonixnexusd.v1.Pairing/Revoke", RevokeRequest(device_id = deviceID), RevokeResponse.ADAPTER).revoked

    suspend fun sessionPolicy(): SessionPolicy =
        unary("/gryonixnexusd.v1.Pairing/GetSessionPolicy", GetSessionPolicyRequest(), SessionPolicy.ADAPTER)

    suspend fun setSessionPolicy(months: Int): SessionPolicy =
        unary("/gryonixnexusd.v1.Pairing/SetSessionPolicy", SetSessionPolicyRequest(auto_logout_months = months), SessionPolicy.ADAPTER)

    suspend fun vault(): VaultSnapshot =
        unary("/gryonixnexusd.v1.Vault/GetVault", GetVaultRequest(), VaultSnapshot.ADAPTER)

    suspend fun putVaultEntries(entries: List<VaultEntry>): VaultSnapshot =
        unary("/gryonixnexusd.v1.Vault/PutVaultEntries", PutVaultEntriesRequest(entries = entries), VaultSnapshot.ADAPTER)

    suspend fun deleteVaultEntry(
        id: String,
        deviceUID: String = "",
        deletedAtMs: Long = System.currentTimeMillis(),
    ): VaultSnapshot =
        unary(
            "/gryonixnexusd.v1.Vault/DeleteVaultEntry",
            DeleteVaultEntryRequest(id = id, device_uid = deviceUID, deleted_at = deletedAtMs),
            VaultSnapshot.ADAPTER,
        )
    suspend fun getNotifySettings(): NotifySettings =
        unary("/gryonixnexusd.v1.Notify/GetNotifySettings", GetNotifySettingsRequest(), NotifySettings.ADAPTER)

    suspend fun registerNotifyDevice(
        platform: String,
        token: String,
        appVersion: String,
        locale: String,
        muted: List<String> = emptyList(),
        proof: String = "",
        name: String = "",
    ): NotifySettings =
        unary(
            "/gryonixnexusd.v1.Notify/RegisterNotifyDevice",
            RegisterNotifyDeviceRequest(platform = platform, token = token, app_version = appVersion, locale = locale, muted = muted, device_proof = proof, name = name),
            NotifySettings.ADAPTER,
        )

    suspend fun unregisterNotifyDevice(token: String): NotifySettings =
        unary("/gryonixnexusd.v1.Notify/UnregisterNotifyDevice", UnregisterNotifyDeviceRequest(token = token), NotifySettings.ADAPTER)

    suspend fun sendTestNotification(): NotifyTestResult =
        unary("/gryonixnexusd.v1.Notify/SendTestNotification", SendTestNotificationRequest(), NotifyTestResult.ADAPTER)

    suspend fun watchLiveActivity(jobID: String, token: String, title: String): NotifyTestResult =
        unary("/gryonixnexusd.v1.Notify/WatchLiveActivity", WatchLiveActivityRequest(job_id = jobID, token = token, title = title), NotifyTestResult.ADAPTER)

    suspend fun testLiveActivity(token: String, title: String): NotifyTestResult =
        unary("/gryonixnexusd.v1.Notify/TestLiveActivity", TestLiveActivityRequest(token = token, title = title), NotifyTestResult.ADAPTER)

    // ──────────────────────── GENERATED VERBS END ────────────────────────

    // The ones the script does not express, or expresses wrongly.

    suspend fun runStorageTask(request: StorageTaskRequest): StorageTaskResult =
        unary("/gryonixnexusd.v1.Storage/RunStorageTask", request, StorageTaskResult.ADAPTER)

    suspend fun setNotifySettings(request: SetNotifySettingsRequest): NotifySettings =
        unary("/gryonixnexusd.v1.Notify/SetNotifySettings", request, NotifySettings.ADAPTER)

    suspend fun watchTunnelActivity(request: WatchTunnelActivityRequest): NotifyTestResult =
        unary("/gryonixnexusd.v1.Notify/WatchTunnelActivity", request, NotifyTestResult.ADAPTER)

    suspend fun pair(code: String, devicePublicKey: String, label: String, deviceUID: String = ""): Device =
        pairing(code, devicePublicKey, label, deviceUID).device ?: Device()

    suspend fun pairing(
        code: String,
        devicePublicKey: String,
        label: String,
        deviceUID: String = "",
        authorizeSshKey: Boolean = false,
        transferID: String = "",
    ): PairResponse =
        unary(
            "/gryonixnexusd.v1.Pairing/Pair",
            PairRequest(
                code = code,
                device_public_key = devicePublicKey,
                label = label,
                device_uid = deviceUID,
                authorize_ssh_key = authorizeSshKey,
                transfer_id = transferID,
            ),
            PairResponse.ADAPTER,
        )

    /** A one-time SSH key for an export file */
    suspend fun createTransfer(validMinutes: Int = 0): CreateTransferResponse =
        unary(
            "/gryonixnexusd.v1.Pairing/CreateTransfer",
            CreateTransferRequest(valid_minutes = validMinutes),
            CreateTransferResponse.ADAPTER,
        )

    suspend fun metricsHistory(bucket: String, limit: Int = 0, sinceEpochMillis: Long? = null): MetricsHistoryResponse =
        unary(
            "/gryonixnexusd.v1.Control/MetricsHistory",
            MetricsHistoryRequest(bucket = bucket, limit = limit, since = sinceEpochMillis ?: 0L),
            MetricsHistoryResponse.ADAPTER,
        )

    fun watchInstall(jobID: String, fromSequence: Long = 0L): Flow<InstallServiceEvent> =
        stream(
            "/gryonixnexusd.v1.Install/WatchInstall",
            WatchInstallRequest(job_id = jobID, from_sequence = fromSequence),
            InstallServiceEvent.ADAPTER,
        )

    fun watchJob(jobID: String, fromSequence: Long = 0L): Flow<JobEvent> =
        stream(
            "/gryonixnexusd.v1.Jobs/WatchJob",
            WatchJobRequest(job_id = jobID, from_sequence = fromSequence),
            JobEvent.ADAPTER,
        )

    /** What this host has been doing, newest first */
    suspend fun listJobs(kind: JobKind = JobKind.JOB_KIND_UNSPECIFIED,
                         runningOnly: Boolean = false): List<Job> =
        unary(
            "/gryonixnexusd.v1.Jobs/ListJobs",
            ListJobsRequest(kind = kind, running_only = runningOnly),
            JobList.ADAPTER,
        ).jobs

    suspend fun prepareMoveSend(transferID: String): String =
        unary(
            "/gryonixnexusd.v1.Move/PrepareMoveSend",
            PrepareMoveSendRequest(transfer_id = transferID),
            PrepareMoveSendResponse.ADAPTER,
        ).public_key

    suspend fun prepareMoveReceive(
        transferID: String,
        serviceID: String,
        controlUser: String,
        publicKey: String,
        expectedBytes: Long,
    ): PrepareMoveReceiveResponse =
        unary(
            "/gryonixnexusd.v1.Move/PrepareMoveReceive",
            PrepareMoveReceiveRequest(
                transfer_id = transferID, service_id = serviceID, control_user = controlUser,
                public_key = publicKey, expected_bytes = expectedBytes,
            ),
            PrepareMoveReceiveResponse.ADAPTER,
        )

    fun sendMoveData(
        transferID: String,
        serviceID: String,
        archivePath: String,
        host: String,
        port: Int,
        user: String,
        hostKeys: String,
    ): Flow<MoveEvent> =
        stream(
            "/gryonixnexusd.v1.Move/SendMoveData",
            SendMoveDataRequest(
                transfer_id = transferID, service_id = serviceID, archive_path = archivePath,
                host = host, port = port, user = user, host_keys = hostKeys,
            ),
            MoveEvent.ADAPTER,
        )

    fun acceptMoveData(transferID: String, serviceID: String, sha256: String, bytes: Long, archiveName: String): Flow<MoveEvent> =
        stream(
            "/gryonixnexusd.v1.Move/AcceptMoveData",
            AcceptMoveDataRequest(
                transfer_id = transferID, service_id = serviceID, sha256 = sha256,
                bytes = bytes, archive_name = archiveName,
            ),
            MoveEvent.ADAPTER,
        )

    suspend fun discardMoveTransfer(transferID: String) {
        unary(
            "/gryonixnexusd.v1.Move/DiscardMoveTransfer",
            DiscardMoveTransferRequest(transfer_id = transferID),
            DiscardMoveTransferResponse.ADAPTER,
        )
    }

    suspend fun setServiceUpstream(request: SetServiceUpstreamRequest): ServiceUpstreamState =
        unary("/gryonixnexusd.v1.Move/SetServiceUpstream", request, ServiceUpstreamState.ADAPTER)

    suspend fun probeServiceUpstream(serviceID: String): ServiceUpstreamProbe =
        unary(
            "/gryonixnexusd.v1.Move/ProbeServiceUpstream",
            ProbeServiceUpstreamRequest(service_id = serviceID),
            ServiceUpstreamProbe.ADAPTER,
        )

    suspend fun cancelJob(jobID: String): Job =
        unary(
            "/gryonixnexusd.v1.Jobs/CancelJob",
            CancelJobRequest(job_id = jobID),
            Job.ADAPTER,
        )

    /** Install a service */
    fun installService(
        serviceID: String,
        domain: String,
        additionalDomains: List<String> = emptyList(),
        localOnly: Boolean = false,
        adminUsername: String = "",
        language: String = "",
        settings: Map<String, String> = emptyMap(),
        host: AgentHostSurface = AgentHostSurface(),
    ): Flow<InstallServiceEvent> = stream(
        "/gryonixnexusd.v1.Install/InstallService",
        installRequest(serviceID, domain, additionalDomains, localOnly, adminUsername, language, settings, host),
        InstallServiceEvent.ADAPTER,
    )

    /** The agent installs the whole list itself */
    suspend fun startInstallPlan(
        services: List<InstallServiceRequest>,
        purpose: gryonixnexusd.v1.InstallPlanPurpose = gryonixnexusd.v1.InstallPlanPurpose.INSTALL_PLAN_PURPOSE_ADD,
    ): InstallPlan = unary(
        "/gryonixnexusd.v1.Install/StartInstallPlan",
        StartInstallPlanRequest(services = services, purpose = purpose),
        InstallPlan.ADAPTER,
    )

    /** A plan by id; empty id means newest */
    suspend fun installPlan(id: String = ""): InstallPlan = unary(
        "/gryonixnexusd.v1.Install/GetInstallPlan",
        GetInstallPlanRequest(plan_id = id),
        InstallPlan.ADAPTER,
    )

    companion object {
        /** One service's install request, as InstallService and plans take it */
        fun installRequest(
            serviceID: String,
            domain: String,
            additionalDomains: List<String> = emptyList(),
            localOnly: Boolean = false,
            adminUsername: String = "",
            language: String = "",
            settings: Map<String, String> = emptyMap(),
            host: AgentHostSurface = AgentHostSurface(),
        ): InstallServiceRequest = InstallServiceRequest(
            service_id = serviceID,
            domain = domain,
            additional_domains = additionalDomains,
            local_only = localOnly,
            admin_username = adminUsername,
            language = language,
            settings = settings,
            host_role = host.role,
            ptr_ip = host.ptrIP,
            ptr_hostname = host.ptrHostname,
            tunnel_endpoint = host.tunnelEndpoint,
            relay_wg_port = host.relayWGPort,
            relay_forwarded_ports = host.relayForwardedPorts,
            relay_forwarded_udp_ports = host.relayForwardedUDPPorts,
            home_wg_address = host.homeWGAddress,
            dashboard_public_key = host.dashboardPublicKey,
        )
    }

    suspend fun provisionHost(
        domain: String,
        additionalDomains: List<String> = emptyList(),
        localOnly: Boolean = false,
        adminUsername: String = "",
        language: String = "",
        settings: Map<String, String> = emptyMap(),
        host: AgentHostSurface = AgentHostSurface(),
    ): ProvisionHostResponse = unary(
        "/gryonixnexusd.v1.Install/ProvisionHost",
        ProvisionHostRequest(
            domain = domain,
            additional_domains = additionalDomains,
            local_only = localOnly,
            admin_username = adminUsername,
            language = language,
            settings = settings,
            host_role = host.role,
            ptr_ip = host.ptrIP,
            ptr_hostname = host.ptrHostname,
            tunnel_endpoint = host.tunnelEndpoint,
            relay_wg_port = host.relayWGPort,
            relay_forwarded_ports = host.relayForwardedPorts,
            relay_forwarded_udp_ports = host.relayForwardedUDPPorts,
            home_wg_address = host.homeWGAddress,
            dashboard_public_key = host.dashboardPublicKey,
        ),
        ProvisionHostResponse.ADAPTER,
    )

    /** Set — or CLEAR — a container group's backup plan */
    suspend fun setContainerBackupPlan(key: String, plan: ContainerBackupPlan?): ContainerBackupPlan =
        unary(
            "/gryonixnexusd.v1.Containers/SetContainerBackupPlan",
            SetContainerBackupPlanRequest(key = key, plan = plan),
            ContainerBackupPlan.ADAPTER,
        )

    // ─────────────────────────── the plumbing ───────────────────────────

    private suspend fun <Q : com.squareup.wire.Message<Q, *>, R : Any> unary(
        path: String,
        request: Q,
        adapter: ProtoAdapter<R>,
    ): R {
        val bytes = transport.unary(path, request.encode())
        return try {
            adapter.decode(bytes)
        } catch (error: Throwable) {
            throw AgentError.Decode("${adapter.type}: $error")
        }
    }

    private fun <Q : com.squareup.wire.Message<Q, *>, R : Any> stream(
        path: String,
        request: Q,
        adapter: ProtoAdapter<R>,
    ): Flow<R> = kotlinx.coroutines.flow.flow {
        kotlinx.coroutines.coroutineScope {
            var watch: kotlinx.coroutines.Job? = null
            transport.serverStream(path, request.encode()).collect { payload ->
                val message = try {
                    adapter.decode(payload)
                } catch (error: Throwable) {
                    throw AgentError.Decode("${adapter.type}: $error")
                }
                val jobId = StreamJobWatch.jobIdOf(message)
                if (watch == null && jobId.isNotEmpty()) watch = launch { failWhenServerEnds(jobId) }
                emit(message)
            }
            watch?.cancel()
        }
    }

    /** Fails the stream when its server job has ended */
    private suspend fun failWhenServerEnds(jobId: String) {
        StreamJobWatch.awaitServerEnd(jobId, { id -> listJobs().firstOrNull { it.job_id == id }?.outcome })
        throw AgentError.Transport("the server finished job $jobId but its stream went quiet")
    }
}

data class AgentHostSurface(
    val role: HostRole = HostRole.HOST_ROLE_UNSPECIFIED,
    val ptrIP: String = "",
    val ptrHostname: String = "",
    val tunnelEndpoint: String = "",
    val relayWGPort: Int = 0,
    val relayForwardedPorts: List<Int> = emptyList(),
    val relayForwardedUDPPorts: List<Int> = emptyList(),
    val homeWGAddress: String = "",
    val dashboardPublicKey: String = "",
)
