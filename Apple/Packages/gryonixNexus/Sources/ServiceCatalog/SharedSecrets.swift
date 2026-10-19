public enum SharedSecrets {
    /// Where they live
    public static let directory = "/etc/gryonixnexus"

    public static func ensureSection(path: String, prefix: String = "") -> String {
        #"""
        install -d -m 755 '\#(directory)'
        if [ ! -s '\#(path)' ]; then
          ( umask 077 && printf '\#(prefix)%s\n' "$(openssl rand -hex 24)" > '\#(path)' )
          chmod 600 '\#(path)'
        fi
        """#
    }
}
