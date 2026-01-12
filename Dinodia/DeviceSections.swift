import Foundation

enum DeviceLayoutSize {
    case small
    case medium
    case large
}

struct DeviceRow {
    let key: String
    let devices: [UIDevice]
}

struct DeviceSection {
    let title: String
    let data: [DeviceRow]
}

struct LayoutSection: Identifiable {
    let key: String
    let title: String
    let span: Int
    let devices: [UIDevice]

    var id: String { key }
}

struct LayoutRow: Identifiable {
    let key: String
    let sections: [LayoutSection]

    var id: String { key }
}

struct DeviceDimension {
    let width: Int
    let height: Int
}

func getDeviceLayoutSize(_ device: UIDevice) -> DeviceLayoutSize {
    let label = getPrimaryLabel(for: device)
    if label == "Spotify" || label == "Boiler" { return .medium }
    return .small
}

func getDeviceDimensions(_ size: DeviceLayoutSize) -> DeviceDimension {
    switch size {
    case .small:
        return DeviceDimension(width: 1, height: 1)
    case .medium:
        return DeviceDimension(width: 2, height: 1)
    case .large:
        return DeviceDimension(width: 2, height: 2)
    }
}

func buildDeviceSections(_ devices: [UIDevice]) -> [DeviceSection] {
    var groups: [String: [UIDevice]] = [:]
    for device in devices {
        let label = getGroupLabel(for: device)
        groups[label, default: []].append(device)
    }

    let sortedLabels = sortLabels(Array(groups.keys))
    var sections: [DeviceSection] = []
    for label in sortedLabels where label != OTHER_LABEL {
        let list = groups[label] ?? []
        guard !list.isEmpty else { continue }
        var rows: [DeviceRow] = []
        var index = 0
        while index < list.count {
            let slice = Array(list[index..<min(index + 4, list.count)])
            let key = "\(label)-\(slice.map { $0.entityId }.joined(separator: "|"))"
            rows.append(DeviceRow(key: key, devices: slice))
            index += 4
        }
        sections.append(DeviceSection(title: label, data: rows))
    }
    return sections
}

private func flattenSectionDevices(_ section: DeviceSection) -> [UIDevice] {
    section.data.flatMap { $0.devices }
}

func buildSectionLayoutRows(_ sections: [DeviceSection], maxColumns: Int) -> [LayoutRow] {
    var rows: [LayoutRow] = []
    var currentSections: [LayoutSection] = []
    var usedColumns = 0

    func pushRow() {
        guard !currentSections.isEmpty else { return }
        rows.append(LayoutRow(key: "row-\(rows.count)", sections: currentSections))
        currentSections = []
        usedColumns = 0
    }

    for (sectionIndex, section) in sections.enumerated() {
        let devices = flattenSectionDevices(section)
        let span = getSectionSpan(for: devices, maxColumns: maxColumns)
        if usedColumns + span > maxColumns, !currentSections.isEmpty {
            pushRow()
        }
        let layoutSection = LayoutSection(
            key: "section-\(sectionIndex)-\(currentSections.count)-\(section.title)",
            title: section.title,
            span: span,
            devices: devices
        )
        currentSections.append(layoutSection)
        usedColumns += span
        if usedColumns >= maxColumns {
            pushRow()
        }
    }

    pushRow()
    return rows
}

private func getSectionSpan(for devices: [UIDevice], maxColumns: Int) -> Int {
    guard !devices.isEmpty else { return 1 }
    var totalWidth = 0
    var maxWidth = 1
    for device in devices {
        let size = getDeviceLayoutSize(device)
        let dimension = getDeviceDimensions(size)
        totalWidth += dimension.width
        maxWidth = max(maxWidth, dimension.width)
    }
    let normalized = min(maxColumns, totalWidth)
    return min(maxColumns, max(maxWidth, normalized))
}
