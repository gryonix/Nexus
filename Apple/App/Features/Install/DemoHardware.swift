#if DEBUG
/// A sample probe answer for screenshots
enum DemoHardware {
    static let probeOutput = """
    GRYONIXNEXUS_HW_BEGIN
    cpu=8
    mem=16777216000
    arch=x86_64
    rootfree=64424509440
    lsblk={"blockdevices": [{"name":"sda","path":"/dev/sda","size":512110190592,"rota":false,"type":"disk","model":"Samsung SSD 860","tran":"sata","children": [{"name":"sda1","type":"part","mountpoint":"/boot/efi","fstype":"vfat"},{"name":"sda2","type":"part","mountpoint":"/","fstype":"ext4"}]},{"name":"nvme0n1","path":"/dev/nvme0n1","size":256060514304,"rota":false,"type":"disk","model":"WD Blue SN570","tran":"nvme"},{"name":"sdb","path":"/dev/sdb","size":4000787030016,"rota":"1","type":"disk","model":"WDC WD40EFRX","tran":"sata"},{"name":"sdc","path":"/dev/sdc","size":4000787030016,"rota":"1","type":"disk","fstype":"ext4","model":"WDC WD40EFRX","tran":"sata"}]}
    GRYONIXNEXUS_HW_END
    """

    /// A mirror with one failed disk and a blank spare
    static let degradedProbe = #"""
    GRYONIXNEXUS_HW_BEGIN
    cpu=12
    mem=25157267456
    arch=x86_64
    rootfree=675069329408
    lsblk={   "blockdevices": [      {         "name": "vdb",         "path": "/dev/vdb",         "size": 1073741824,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": "linux_raid_member",         "label": "my-vps:gryonixnexus",         "uuid": "dd96909c-ae31-5ffe-3a59-f52c051376ba",         "model": null,         "tran": null,         "children": [            {               "name": "md127",               "path": "/dev/md127",               "size": 1071644672,               "rota": true,               "type": "raid1",               "mountpoint": null,               "fstype": "ext4",               "label": "gnx-storage",               "uuid": "a9221f08-6e30-4d2d-b8ea-7f1b739ebe76",               "model": null,               "tran": null            }         ]      },{         "name": "vdc",         "path": "/dev/vdc",         "size": 1073741824,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": "linux_raid_member",         "label": "my-vps:gryonixnexus",         "uuid": "dd96909c-ae31-5ffe-3a59-f52c051376ba",         "model": null,         "tran": null      },{         "name": "vdd",         "path": "/dev/vdd",         "size": 1073741824,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": "linux_raid_member",         "label": "my-vps:gryonixnexus",         "uuid": "dd96909c-ae31-5ffe-3a59-f52c051376ba",         "model": null,         "tran": null,         "children": [            {               "name": "md127",               "path": "/dev/md127",               "size": 1071644672,               "rota": true,               "type": "raid1",               "mountpoint": null,               "fstype": "ext4",               "label": "gnx-storage",               "uuid": "a9221f08-6e30-4d2d-b8ea-7f1b739ebe76",               "model": null,               "tran": null            }         ]      },{         "name": "vde",         "path": "/dev/vde",         "size": 1073741824,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": null,         "label": null,         "uuid": null,         "model": null,         "tran": null      },{         "name": "vdf",         "path": "/dev/vdf",         "size": 1073741824,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": null,         "label": null,         "uuid": null,         "model": null,         "tran": null      },{         "name": "vdg",         "path": "/dev/vdg",         "size": 1073741824,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": null,         "label": null,         "uuid": null,         "model": null,         "tran": null      },{         "name": "vda",         "path": "/dev/vda",         "size": 773094113280,         "rota": true,         "type": "disk",         "mountpoint": null,         "fstype": null,         "label": null,         "uuid": null,         "model": null,         "tran": "virtio",         "children": [            {               "name": "vda1",               "path": "/dev/vda1",               "size": 772959878656,               "rota": true,               "type": "part",               "mountpoint": "/",               "fstype": "ext4",               "label": null,               "uuid": "df4df5bb-613a-4382-8cf9-653304605a1f",               "model": null,               "tran": "virtio"            },{               "name": "vda14",               "path": "/dev/vda14",               "size": 3145728,               "rota": true,               "type": "part",               "mountpoint": null,               "fstype": null,               "label": null,               "uuid": null,               "model": null,               "tran": "virtio"            },{               "name": "vda15",               "path": "/dev/vda15",               "size": 130023424,               "rota": true,               "type": "part",               "mountpoint": "/boot/efi",               "fstype": "vfat",               "label": null,               "uuid": "6EA5-B51D",               "model": null,               "tran": "virtio"            }         ]      }   ]}
    mdstat=Personalities : [raid1] [raid6] [raid5] [raid4] [raid10] [raid0] |md127 : active (auto-read-only) raid1 vdb[0] vdd[2](F)|      1046528 blocks super 1.2 [2/1] [U_]|      |unused devices: <none>|
    GRYONIXNEXUS_HW_END
    """#

    /// The same machine with its storage array mounted
    static var mountedArrayProbe: String {
        degradedProbe.replacingOccurrences(
            of: #""mountpoint": null,               "fstype": "ext4",               "label": "gnx-storage""#,
            with: #""mountpoint": "/srv/gryonixnexus-storage",               "fstype": "ext4",               "label": "gnx-storage""#)
    }
}
#endif
