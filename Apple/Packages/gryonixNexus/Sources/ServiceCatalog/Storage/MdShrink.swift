import Foundation

/// Moves one member's data off md RAID 5 or 6
extension MdChange {
    /// Data disks left once the member is gone
    private var dataDisks: Int { spec.devices - (spec.level == "raid6" ? 2 : 1) }

    private var room: String {
        "room=$(( $(mdadm --detail \"$ARRAY\" | awk '/Used Dev Size :/ {print $5}') * \(dataDisks) ))"
    }

    var shrinkCheck: [String] {
        [
            "if [ \"$(blkid -s TYPE -o value \"$ARRAY\" || true)\" != ext4 ]; then",
            "  echo \"Only an array with ext4 on it can give a disk back.\"",
            "  exit 3",
            "fi",
            room,
            "MOUNT=\"$(findmnt -no TARGET \"$ARRAY\" | head -n 1 || true)\"",
            "if [ -n \"$MOUNT\" ] && [ \"$(df -k --output=used \"$MOUNT\" | tail -n 1 | tr -d ' ')\" -gt $((room * 9 / 10)) ]; then",
            "  echo \"The data does not fit on the disks that stay. Free some space first.\"",
            "  exit 3",
            "fi",
        ]
    }

    /// Stops the services on the array while its filesystem shrinks
    private var pause: [String] {
        [
            "MOUNT=\"$(findmnt -no TARGET \"$ARRAY\" | head -n 1 || true)\"",
            "stopped=\"\"",
            "restore() {",
            "  if [ -n \"$MOUNT\" ] && ! mountpoint -q \"$MOUNT\"; then mount \"$MOUNT\" || true; fi",
            "  if [ -n \"$stopped\" ]; then docker start $stopped >/dev/null || true; fi",
            "}",
            "trap restore EXIT",
            "if [ -n \"$MOUNT\" ]; then",
            "  if command -v docker >/dev/null 2>&1; then",
            "    for c in $(docker ps -q); do",
            "      if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' \"$c\" | grep -qF -- \"$MOUNT\"; then",
            "        stopped=\"$stopped $c\"",
            "      fi",
            "    done",
            "    if [ -n \"$stopped\" ]; then docker stop $stopped >/dev/null; fi",
            "  fi",
            "  umount \"$MOUNT\"",
            "fi",
        ]
    }

    var shrinkJob: [String] {
        [room] + pause + [
            "e2fsck -f -y \"$ARRAY\" || [ $? -le 1 ]",
            "resize2fs \"$ARRAY\" \"${room}K\"",
            "mdadm --grow \"$ARRAY\" --array-size=\"$room\"",
            "restore",
            "mdadm --grow \"$ARRAY\" --raid-devices=\(spec.devices) --backup-file=\(Self.reshapeBackup)",
            "mdadm --wait \"$ARRAY\" || true",
            "sleep 5",
            "spare=\"$(mdadm --detail \"$ARRAY\" | awk '/spare/ && $NF ~ /^\\/dev\\// {print $NF}' | head -n 1)\"",
            "if [ -n \"$spare\" ] && [ \"$spare\" != \"$OLD\" ]; then",
            "  mdadm \"$ARRAY\" --replace \"$OLD\" --with \"$spare\"",
            "  mdadm --wait \"$ARRAY\" || true",
            "  sleep 5",
            "fi",
            "mdadm \"$ARRAY\" --remove \"$OLD\"",
            "mdadm --zero-superblock \"$OLD\" >/dev/null 2>&1 || true",
            "rm -f \(Self.reshapeBackup)",
        ]
    }
}
