import Foundation

/// Automatic recordings never overwrite an existing file and do not open a save panel.
enum RecordingDestination {
    static func makeURL(preferences:Preferences = .shared, moviesDirectory:URL?=nil,
                        date:Date=Date(), identifier:String=UUID().uuidString) throws -> URL {
        let fm=FileManager.default
        let folder:URL
        if preferences.defaults.data(forKey:"folderBookmark") != nil {
            guard let selected=preferences.folderURL else {
                throw CaptureFailure.message("默认保存位置已失效。请在 Snapliq 设置中重新选择文件夹。")
            }
            folder=selected
        } else {
            let movies=try moviesDirectory ?? fm.url(for:.moviesDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            folder=movies.appendingPathComponent(Product.name,isDirectory:true)
            try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        }
        let scoped=folder.startAccessingSecurityScopedResource()
        defer{if scoped{folder.stopAccessingSecurityScopedResource()}}
        var isDirectory:ObjCBool=false
        guard fm.fileExists(atPath:folder.path,isDirectory:&isDirectory),isDirectory.boolValue,
              fm.isWritableFile(atPath:folder.path) else {
            throw CaptureFailure.message("无法写入默认保存文件夹：\(folder.path)\n请在 Snapliq 设置中选择可用位置。")
        }
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX")
        formatter.dateFormat="yyyy-MM-dd_HH-mm-ss-SSS"
        let stem=Product.name+"-"+formatter.string(from:date)+"-"+identifier
        var url=folder.appendingPathComponent(stem).appendingPathExtension("mp4"),suffix=2
        while fm.fileExists(atPath:url.path) {
            url=folder.appendingPathComponent(stem+"-\(suffix)").appendingPathExtension("mp4");suffix+=1
        }
        return url
    }
}
