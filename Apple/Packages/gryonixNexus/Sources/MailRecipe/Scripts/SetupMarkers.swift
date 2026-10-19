public enum SetupMarkers {
    /// `GRYONIXNEXUS_STEP <index>/<total>` — printed before each section
    public static let step = "GRYONIXNEXUS_STEP"
    public static let reportBegin = "GRYONIXNEXUS_REPORT_BEGIN"
    public static let reportEnd = "GRYONIXNEXUS_REPORT_END"
    /// Very last line of a successful run
    public static let done = "GRYONIXNEXUS_DONE"
    public static let dnsCheckFailed = "GRYONIXNEXUS_DNS_CHECK_FAILED"

    public static let portsInUse = "GRYONIXNEXUS_PORTS_IN_USE"

    public static let distribution = "GRYONIXNEXUS_DISTRO"

    /// Where the script leaves a copy of its own report
    public static let reportFilePath = "/var/lib/gryonixnexus/install-report.txt"
}
