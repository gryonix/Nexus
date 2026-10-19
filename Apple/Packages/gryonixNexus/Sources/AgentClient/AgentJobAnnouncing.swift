import Foundation

/// An event that names the agent job it belongs to
public protocol AgentJobCarrying {
    var jobID: String { get }
}

extension Gryonixnexusd_V1_AgentUpdateEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_BackupEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_ContainerBackupEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_ContainerOperationEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_ContainerRemovalEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_ContainerUpdateEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_InstallServiceEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_ModelPullEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_MoveEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_RestoreEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_SecurityOperationEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_ServiceOperationEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_UninstallEvent: AgentJobCarrying {}
extension Gryonixnexusd_V1_UpdateEvent: AgentJobCarrying {}
