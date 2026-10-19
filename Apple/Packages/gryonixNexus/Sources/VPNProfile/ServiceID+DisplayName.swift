import ServiceCatalog

public extension ServiceID {
    var displayName: String {
        ServiceRegistry.service(self)?.displayName ?? rawValue
    }
}
