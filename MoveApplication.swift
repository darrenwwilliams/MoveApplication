//
//  MoveApplication.swift
//
//  Created by Darren Williams on 1/27/17.
//  Copyright © 2017 BlackFog, Inc. All rights reserved.
//  https://www.blackfog.com
//
//  Usage:
//	- Call this directly from your applicationWillFinishLaunching as the first line
//    as:
//      MoveApplication.toApplicationsFolder()
//
//  - Make sure you also link the DiskArbitration framework to your project
//
//  1.0 January 30, 2017
//  - Initial release

import Cocoa
import DiskArbitration

open class MoveApplication
{
    class func toApplicationsFolder()
    {
        let bundleUrl = Bundle.main.bundleURL
        
        let isNestedApplication = isApplicationAtPathNested(bundleUrl)
        
        // Skip if the application is already in some Applications folder
        if (isInApplicationsFolder(bundleUrl) && !isNestedApplication) {
            return
        }
        
        let fileManager =  FileManager.default
        let volumeUrl = bundleUrl.deletingLastPathComponent()
        
        // Are we on a disk image?
        let applicationsUrl = installLocation()
        let applicationName = bundleUrl.lastPathComponent
        let destinationUrl = applicationsUrl.appendingPathComponent(applicationName)
        
        var needsAuthorization = false
        // Check if we need admin password to write to the Applications directory
        if (!fileManager.isWritableFile(atPath: applicationsUrl.path)) {
            needsAuthorization = true
        }
        
        if (fileManager.fileExists(atPath: destinationUrl.path) &&
            !fileManager.isWritableFile(atPath: destinationUrl.path)) {
            needsAuthorization = true
        }
        
        if (needsAuthorization) {
            
            if (!appleScriptCopy(source: bundleUrl,destination: destinationUrl)) {
                print("Failed to copy application")
                return
            }
            
        }
        else {
            
            // If a copy already exists in the Applications folder, put it in the Trash
            if (fileManager.fileExists(atPath: destinationUrl.path)) {
                
                //delete old version
                if (!deleteFile(source: destinationUrl)) {
                    print("Failed to delete old application")
                    return
                }
                
            }
            if (!copyBundle(source: bundleUrl,destination: destinationUrl)) {
                print("Failed to copy application")
                return
            }
            
        }
        
        let isDMG = isDMGVolume(at: volumeUrl)
        
        //trash the source file if started from wrong location
        if (!isDMG && !isNestedApplication) {
            //this is an async task
            trashFile(source: bundleUrl)
        }
        // Relaunch
        relaunchApplication(source: destinationUrl)
        
        // Launched from within a disk image? -- unmount
        if isDMG {
            unmountVolume(at: volumeUrl)
        }
        
        NSApplication.shared().terminate(self)
    }

    class func isApplicationAtPathNested(_ path: URL) -> Bool
    {
        let components = path.deletingLastPathComponent().pathComponents
        
        for component in components as [NSString] {
            if (component.pathExtension == "app") {
                return true
            }
        }
        
        return false
    }
    
    class func isInApplicationsFolder(_ path: URL) -> Bool
    {
        let applicationDirs = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .localDomainMask, true)
        let pathString = path.path
        
        for appDir in applicationDirs {
            if (pathString.hasPrefix(appDir)) {
                return true
            }
        }
        
        return false
    }
    
    class func installLocation() -> URL
    {
        let applicationDirs = FileManager.default.urls(for: FileManager.SearchPathDirectory.applicationDirectory, in: FileManager.SearchPathDomainMask.localDomainMask)
        
        return applicationDirs.first!
    }
    
    class func isApplicationRunning() -> Bool
    {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).isEmpty {
            return false
        }
        return true
    }
    
    class func copyBundle(source: URL, destination: URL) -> Bool
    {
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return false
        }
        return true
    }
    
    class func deleteFile(source: URL) -> Bool
    {
        do {
            try FileManager.default.removeItem(at: source)
        } catch {
            return false
        }
        return true
    }
    
    class func trashFile(source: URL)
    {
        NSWorkspace.shared().recycle([source]) { trashedFiles, error in
            guard let error = error else {
                return
            }
            
            print("Failed to move file to trash: \(error.localizedDescription)")
        }
    }
    
    /**
        This process will not trigger privileges as it is available to all users so it is safe
        to use. While not exactly a clean technique it is permitted under Apples current rules
    */
    class func relaunchApplication(source: URL)
    {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        
        let quotedDestinationPath = shellQuotedString(string: source.path)
        
        // Before we launch the new app, clear xattr:com.apple.quarantine
        let preOpenCmd = "/usr/bin/xattr -d -r com.apple.quarantine \(quotedDestinationPath)"
        
        let script = "(while /bin/kill -0 \(currentPid) >&/dev/null; do /bin/sleep 0.1; done; \(preOpenCmd); /usr/bin/open \(quotedDestinationPath)) &"
        
        let args = [ "-c", script]
        
        Process.launchedProcess(launchPath: "/bin/sh", arguments: args)
        
        return
    }
    
    class func shellQuotedString(string: String) -> String
    {
        let quoted = "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
        
        return quoted
    }
    
    /**
		Takes BSD style volume as the parameter as in /Volume/Some Volume
    */
    class func isDMGVolume(at: URL) -> Bool
    {
        if (at.isFileURL) {
            if let session = DASessionCreate(kCFAllocatorDefault) {
                
                if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, at as NSURL) {
                    
                    let desc = DADiskCopyDescription(disk)
                    
                    if let dict = desc as? [String: AnyObject] {
                        
                        if let model = dict[kDADiskDescriptionDeviceModelKey as String] {
                            let modelString = model as! String
                            
                            if modelString == "Disk Image" {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }
    
    class func unmountVolume(at: URL)
    {
        if (at.isFileURL) {
            if let session = DASessionCreate(kCFAllocatorDefault) {
                if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, at as NSURL) {
                    DADiskUnmount(disk,DADiskUnmountOptions(kDADiskUnmountOptionForce),nil,nil)
                }
            }
        }
    }
    
    /**
        Uses Applescript to prompt for a file copy since swift api does not allow this for some reason.
        Opting to use this technique rather than linking in the deprecated ExecuteWithPrivileges
        api in the security framework.
    */
    class func appleScriptCopy(source: URL, destination: URL) -> Bool
    {
        var command = "/bin/cp -pfR "
        
        command.append(shellQuotedString(string: source.path))
        command.append(" ")
        command.append(shellQuotedString(string: destination.path))
        
        if let scriptObject = NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges") {
            var errorDict: NSDictionary? = nil
            _ = scriptObject.executeAndReturnError(&errorDict)
            if errorDict != nil {
                // script execution failed, handle error
                print("Error copying file: \(errorDict?.description)")
                return false
            }
        } else {
            // script failed to compile, handle error
            print("Failed to execute copy script")
            return false
        }
        
        return true
    }
    
}
