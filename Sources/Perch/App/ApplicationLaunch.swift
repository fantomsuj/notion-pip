@MainActor
enum ApplicationLaunch {
    static func run<InstanceLease, PreparedApplication>(
        claimInstance: () throws -> InstanceLease?,
        prepareApplication: () -> PreparedApplication,
        runApplication: (PreparedApplication, InstanceLease) -> Void
    ) rethrows {
        guard let instanceLease = try claimInstance() else { return }
        let preparedApplication = prepareApplication()
        withExtendedLifetime((instanceLease, preparedApplication)) {
            runApplication(preparedApplication, instanceLease)
        }
    }
}
