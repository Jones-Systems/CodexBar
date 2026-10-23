import Testing
@testable import CodexBar

struct JonesUpdateAdmissionTests {
    @Test
    func `positive length through 256 MiB is admitted only at the exact capacity boundary`() throws {
        let lengths: [UInt64] = [1, 12345, JonesUpdateAdmission.maximumArchiveLength]
        for length in lengths {
            let required = 4 * Int64(length) + JonesUpdateAdmission.reserveBytes
            let capacity = JonesUpdateAdmission.Capacity(appVolume: required, cacheVolume: required)
            #expect(try JonesUpdateAdmission.validate(archiveLength: length, capacity: capacity) == required)
            #expect(throws: JonesUpdateAdmission.Rejection.insufficientAppCapacity(required: required)) {
                try JonesUpdateAdmission.validate(
                    archiveLength: length, capacity: .init(appVolume: required - 1, cacheVolume: required))
            }
            #expect(throws: JonesUpdateAdmission.Rejection.insufficientCacheCapacity(required: required)) {
                try JonesUpdateAdmission.validate(
                    archiveLength: length, capacity: .init(appVolume: required, cacheVolume: required - 1))
            }
        }
    }

    @Test
    func `unknown zero and overflowing lengths are denied before arithmetic`() {
        let capacity = JonesUpdateAdmission.Capacity(appVolume: .max, cacheVolume: .max)
        let unknownLengths: [UInt64?] = [nil, 0]
        for length in unknownLengths {
            #expect(throws: JonesUpdateAdmission.Rejection.unknownLength) {
                try JonesUpdateAdmission.validate(archiveLength: length, capacity: capacity)
            }
        }
        for length in [JonesUpdateAdmission.maximumArchiveLength + 1, UInt64.max] {
            #expect(throws: JonesUpdateAdmission.Rejection.archiveTooLarge) {
                try JonesUpdateAdmission.validate(archiveLength: length, capacity: capacity)
            }
        }
    }

    @Test
    func `each volume must have a known nonnegative capacity`() {
        let unknownCapacities: [Int64?] = [nil, -1, .min]
        for unknown in unknownCapacities {
            #expect(throws: JonesUpdateAdmission.Rejection.unknownAppCapacity) {
                try JonesUpdateAdmission.validate(
                    archiveLength: 1, capacity: .init(appVolume: unknown, cacheVolume: .max))
            }
            #expect(throws: JonesUpdateAdmission.Rejection.unknownCacheCapacity) {
                try JonesUpdateAdmission.validate(
                    archiveLength: 1, capacity: .init(appVolume: .max, cacheVolume: unknown))
            }
        }
    }
}
