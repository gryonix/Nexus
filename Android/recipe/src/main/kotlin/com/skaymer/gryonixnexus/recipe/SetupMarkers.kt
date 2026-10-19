package com.skaymer.gryonixnexus.recipe

object SetupMarkers {
    /** `GRYONIXNEXUS_STEP <index>/<total>` — printed before each section */
    const val STEP = "GRYONIXNEXUS_STEP"

    const val REPORT_BEGIN = "GRYONIXNEXUS_REPORT_BEGIN"
    const val REPORT_END = "GRYONIXNEXUS_REPORT_END"

    /** Very last line of a successful run */
    const val DONE = "GRYONIXNEXUS_DONE"

    const val DNS_CHECK_FAILED = "GRYONIXNEXUS_DNS_CHECK_FAILED"

    const val PORTS_IN_USE = "GRYONIXNEXUS_PORTS_IN_USE"

    const val DISTRIBUTION = "GRYONIXNEXUS_DISTRO"

    /** Where the script leaves a copy of its own report */
    const val REPORT_FILE_PATH = "/var/lib/gryonixnexus/install-report.txt"
}
