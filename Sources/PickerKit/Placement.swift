import Foundation

public enum PickerPlacement {
    public static func frame(pointer: CGPoint, size: CGSize, visibleFrame: CGRect,
                             constrainsWidthToScreen: Bool = true) -> CGRect {
        let margin: CGFloat = 12
        let usable = visibleFrame.insetBy(dx: min(margin, visibleFrame.width / 4),
                                         dy: min(margin, visibleFrame.height / 4))
        let width = constrainsWidthToScreen ? min(size.width, usable.width) : size.width
        let height = min(size.height, usable.height)
        let x = max(usable.minX, min(pointer.x - width / 2, usable.maxX - width))
        let y = min(max(pointer.y - height + 24, usable.minY), usable.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public static func screenIndex(pointer: CGPoint, frames: [CGRect]) -> Int? {
        if let index = frames.firstIndex(where: { $0.contains(pointer) }) { return index }
        return frames.indices.min { left, right in
            distance(pointer, frames[left]) < distance(pointer, frames[right])
        }
    }

    private static func distance(_ point: CGPoint, _ frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
