import CoreGraphics

enum ScrollWheelTransform {
    static func apply(to event: CGEvent) {
        // This is an event-format filter, not physical device identification.
        // Leave trackpad, momentum and smooth-scroll mouse gestures untouched.
        guard event.type == .scrollWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return }
        // Native line deltas are signed 16-bit; point deltas are signed 32-bit.
        let integerFields: [(CGEventField, Int64)] = [(.scrollWheelEventDeltaAxis1, Int64(Int16.max)),
            (.scrollWheelEventDeltaAxis2, Int64(Int16.max)), (.scrollWheelEventPointDeltaAxis1, Int64(Int32.max)),
            (.scrollWheelEventPointDeltaAxis2, Int64(Int32.max))]
        let fixedFields: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let integers = integerFields.map { event.getIntegerValueField($0.0) }
        let fixed = fixedFields.map { event.getDoubleValueField($0) }
        for ((field, limit), value) in zip(integerFields, integers) {
            let reversed = value == .min ? Int64.max : -value
            event.setIntegerValueField(field, value: min(limit, max(-limit - 1, reversed)))
        }
        for (field, value) in zip(fixedFields, fixed) {
            // The native fixed-point field is signed 16.16; avoid wrapping its minimum.
            let reversed = min(Double(Int32.max) / 65_536, max(Double(Int32.min) / 65_536, -value))
            event.setDoubleValueField(field, value: reversed)
        }
    }
}
