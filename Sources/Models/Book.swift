import Foundation

struct Book: Identifiable, Hashable {
    let id: String      // 完整文件名（含扩展名），同名不同格式的书不会冲突
    let url: URL
    let title: String

    var formatLabel: String {
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "TXT" : ext
    }
}
