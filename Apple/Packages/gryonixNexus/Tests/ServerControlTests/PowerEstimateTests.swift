import Foundation
@testable import ServerControl
import XCTest

final class PowerEstimateTests: XCTestCase {
    private func probe(_ fields: [String]) -> PowerHardware? {
        PowerHardware.parse(([PowerHardware.beginMarker] + fields + [PowerHardware.endMarker])
            .joined(separator: "\n"))
    }

    private func assertTotals(_ estimate: PowerEstimate, idle: Double, peak: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(estimate.profile.idleWatts, idle, accuracy: 0.05, file: file, line: line)
        XCTAssertEqual(estimate.profile.peakWatts, peak, accuracy: 0.05, file: file, line: line)
    }

    func testAKvmServerCountsAShareOfTheHost() throws {
        let hardware = try XCTUnwrap(probe([
            "cpu= AMD EPYC-Milan Processor", "sockets=1", "cores= 6", "threads=12", "mem=25157267456",
            "board=Standard PC (i440FX + PIIX, 1996)", "chassis=1", "virt=kvm", "disks=vda:1:virtio ",
        ]))
        let estimate = PowerEstimate(hardware)
        XCTAssertTrue(estimate.isVirtual)
        XCTAssertEqual(estimate.parts.map(\.kind), [.virtualShare, .memory])
        assertTotals(estimate, idle: 25.9, peak: 88.7)
    }

    func testAVirtualMachineIsKnownByItsBoardWithoutSystemd() throws {
        let hardware = try XCTUnwrap(probe(["board=KVM", "threads=2"]))
        XCTAssertTrue(hardware.isVirtual)
        XCTAssertFalse(try XCTUnwrap(probe(["board=Standard PC", "virt=none"])).isVirtual)
    }

    func testAnN100MiniPc() throws {
        let hardware = try XCTUnwrap(probe([
            "cpu= Intel(R) N100", "sockets=1", "cores= 4", "threads=4", "mem=17179869184",
            "board=Mini PC", "chassis=35", "virt=none", "disks=nvme0n1:0:nvme ", "gpus=0x8086 ",
        ]))
        let estimate = PowerEstimate(hardware)
        XCTAssertEqual(estimate.parts.map(\.kind), [.processor, .compactBoard, .memory, .nvme, .powerSupply])
        XCTAssertEqual(estimate.parts.first?.name, "Intel N100")
        assertTotals(estimate, idle: 9.8, peak: 32.0)
    }

    func testAProcessorReadingGetsTheRestOfTheMachineAdded() throws {
        let hardware = try XCTUnwrap(probe([
            "cpu= Intel(R) N100", "sockets=1", "cores= 4", "threads=4", "mem=17179869184",
            "board=Mini PC", "chassis=35", "virt=none", "disks=nvme0n1:0:nvme ", "gpus=0x8086 ",
        ]))
        let estimate = PowerEstimate(hardware)
        XCTAssertEqual(estimate.unseenWatts(source: "rapl", measured: 5, cpuPercent: 0),
                       6.3 + 11.3 * 1.5 / 8.3, accuracy: 1e-9)
        XCTAssertEqual(estimate.unseenWatts(source: "ipmi", measured: 40, cpuPercent: 0), 0)
        XCTAssertEqual(estimate.unseenWatts(source: "ups", measured: 40, cpuPercent: 0), 0)

        let reading = MetricsHistoryPoint(date: Date(), cpuPercent: 0, memUsedBytes: 1, memTotalBytes: 2,
                                          diskUsedBytes: 1, diskTotalBytes: 2, netReceivedPerSecond: nil,
                                          netSentPerSecond: nil, diskReadPerSecond: nil,
                                          diskWrittenPerSecond: nil, load1: 0, temperatureCelsius: nil,
                                          powerWatts: 5, powerSource: "rapl")
        let once = EnergyMath.filled([reading], profile: estimate.profile, estimate: estimate)
        XCTAssertEqual(once[0].powerWatts ?? 0, 5 + 6.3 + 11.3 * 1.5 / 8.3, accuracy: 1e-9)
        XCTAssertEqual(once[0].powerSource, "rapl+estimate")
        XCTAssertTrue(EnergyMath.isMeasured(once))
        XCTAssertEqual(EnergyMath.filled(once, profile: estimate.profile, estimate: estimate), once)
    }

    func testADualXeonRackServer() throws {
        let hardware = try XCTUnwrap(probe([
            "cpu= Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz", "sockets=2", "cores= 14", "threads=56",
            "mem=137438953472", "board=PowerEdge R730", "chassis=23", "virt=none",
            "disks=sda:1:sata sdb:1:sata sdc:0:sata sr0:1:sata ", "gpus=0x102b ",
        ]))
        XCTAssertEqual(hardware.hdd, 2)
        XCTAssertEqual(hardware.ssd, 1)
        XCTAssertEqual(hardware.graphics, 0)
        let estimate = PowerEstimate(hardware)
        XCTAssertEqual(estimate.parts.first?.count, 2)
        XCTAssertTrue(estimate.parts.contains { $0.kind == .serverBoard })
        assertTotals(estimate, idle: 104.6, peak: 376.2)
    }

    func testARaspberryPiIsOneBoardPlusItsDisk() throws {
        let hardware = try XCTUnwrap(probe([
            "cpu=", "lscpu=  Cortex-A72", "sockets=0", "threads=4", "mem=3981262848",
            "board=Raspberry Pi 4 Model B Rev 1.4", "chassis=", "virt=none", "disks=mmcblk0:0: sda:0:usb ",
        ]))
        XCTAssertEqual(hardware.processor, "Cortex-A72")
        let estimate = PowerEstimate(hardware)
        XCTAssertEqual(estimate.parts.map(\.kind), [.singleBoard, .ssd, .powerSupply])
        assertTotals(estimate, idle: 3.8, peak: 11.1)
    }

    func testDiscreteGraphicsSkipTheAmdProcessorsOwn() throws {
        let hardware = try XCTUnwrap(probe(["cpu=AMD Ryzen 5 5600G", "gpus=0x1002 0x10de "]))
        XCTAssertEqual(hardware.graphics, 1)
        XCTAssertEqual(try XCTUnwrap(probe(["cpu=Intel Core i5-12400", "gpus=0x1002 "])).graphics, 1)
    }

    func testProcessorFiguresFollowTheModel() {
        let cases: [(String, Int, Double, Double, ProcessorPower.Platform)] = [
            ("AMD Ryzen 5 5600X 6-Core Processor", 6, 18, 105, .desktop),
            ("Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz", 4, 2, 20, .compact),
            ("Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz", 6, 10, 150, .desktop),
            ("Intel(R) Core(TM) i7-1165G7 @ 2.80GHz", 4, 3, 28, .compact),
            ("Intel(R) Core(TM) i5-10400 CPU @ 2.90GHz", 6, 7, 70, .desktop),
            ("Intel(R) Celeron(R) J4125 CPU @ 2.00GHz", 4, 2, 12, .compact),
            ("AMD EPYC 7302 16-Core Processor", 16, 34.8, 160, .server),
            ("AMD EPYC 3151 4-Core Processor", 4, 10, 50, .compact),
            ("Intel(R) Core(TM) Ultra 7 155H", 16, 4, 55, .compact),
            ("Mystery CPU", 4, 6, 26, .desktop),
        ]
        for (model, cores, idle, peak, platform) in cases {
            let figures = ProcessorPower.figures(model: model, cores: cores)
            XCTAssertEqual(figures.idle, idle, accuracy: 0.01, model)
            XCTAssertEqual(figures.peak, peak, accuracy: 0.01, model)
            XCTAssertEqual(figures.platform, platform, model)
        }
    }

    func testTheEstimateSurvivesStorage() throws {
        let estimate = PowerEstimate(try XCTUnwrap(probe(["cpu=Intel N100", "chassis=35"])),
                                     at: Date(timeIntervalSince1970: 100))
        let decoded = try JSONDecoder().decode(PowerEstimate.self, from: JSONEncoder().encode(estimate))
        XCTAssertEqual(decoded, estimate)
    }
}
