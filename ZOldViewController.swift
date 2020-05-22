//
//  ViewController.swift
//  AudioDrive
//
//  Created by Christopher on 5/7/20.
//  Copyright © 2020 Christopher Minson. All rights reserved.
//

/*
import UIKit
import Foundation
import SystemConfiguration
import AVFoundation
import CoreMedia
import mobileffmpeg
import GoogleSignIn
import GoogleAPIClientForREST
import GTMSessionFetcher



var PATH_DOCUMENTS = ""     // where all talks are stored

let NATIVE_AUDIO_SUFFIX = ".m4a"
let MP3_AUDIO_SUFFIX = ".mp3"
let AUDIO_PREFIX = "ad."
let APP_TITLE = "Audio Drive"
let GOOGLE_DRIVE_ROOT_FOLDER = "!ROOT!"     // special string indicating upload is root directory, not subfolder
let MAX_DECIBLES : Float = 70.0

var AudioDriveGoogleUser: GIDGoogleUser?


extension String {
    var isAlphanumeric: Bool {
        return !isEmpty && range(of: "[^a-zA-Z0-9]", options: .regularExpression) == nil
    }
}



class ViewController: UIViewController, AVAudioRecorderDelegate, GIDSignInDelegate  {
    
    //MARK: Properties
    @IBOutlet weak var UIRecordingButton: UIButton!
    @IBOutlet weak var UIRecordingTimer: UILabel!
    @IBOutlet weak var UIUploadStatusText: UILabel!
    @IBOutlet weak var UIMeter: UIView!
    @IBOutlet weak var UISettingsButton: UIButton!
    @IBOutlet weak var UICancelRecordingButton: UIButton!
    
    var UIMeterUpdate: UIView = UIView()
    var RecordingSession: AVAudioSession!
    var AudioRecorder: AVAudioRecorder!
    
    var TimerClock : Timer!
    var RecordingTime : Int = 0
    var RecordingActive: Bool! = false
    
    var AveragePower : Float? = 0.0
    var AudioFileNameNative : String = ""
    var AudioFileNameMP3 : String = ""
    var AudioFilePathNative : String = ""
    var AudioFilePathMP3 : String = ""
    var RecorderTakingInput = true
    var AudioFileNameCurrentlyRecording = ""
    
    let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        title = "Audio Drive"
        Settings().loadSettings()
        
        PATH_DOCUMENTS = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/"
        print("DocumentPath: ", PATH_DOCUMENTS)
        
        deactivateRecordingUI()
        
        GIDSignIn.sharedInstance().delegate = self
        GIDSignIn.sharedInstance()?.presentingViewController = self
        GIDSignIn.sharedInstance()?.scopes = [kGTLRAuthScopeDrive]
        GIDSignIn.sharedInstance()?.restorePreviousSignIn()

        let height = UIMeter.frame.height
        let width = UIMeter.frame.width
        let rectFrame: CGRect = CGRect(x:CGFloat(0), y:CGFloat(0), width:CGFloat(width), height:CGFloat(height))
        UIMeterUpdate = UIView(frame: rectFrame)
        UIMeter.backgroundColor = COLOR_GREENISH
        UIMeterUpdate.backgroundColor = .green
        UIMeter.addSubview(UIMeterUpdate)
          
        RecordingActive = false
        recordingInit()
        UICancelRecordingButton.isHidden = true
        
     }
    

    override func viewWillAppear(_ animated: Bool) {

        print("view will appear")
        configureUploadFolderID(uploadFiles: false)
        setGoogleStatusUI()
        
        super.viewWillAppear(animated)
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
       
       super.prepare(for: segue, sender: sender)
       
       switch segue.identifier ?? "" {
       case "SETTINGS":
            guard let controller = segue.destination as? SettingsController else {
                fatalError("Unexpected destination")
            }
            controller.parentController = self
       default:
           fatalError("Unexpected Segue Identifier; \(segue.identifier!)")
       }
    }
    
    //GIDSignInDelegate
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!,
                withError error: Error!) {
    
          print("SIGN IN: ViewControler")
          if let error = error {
              if (error as NSError).code == GIDSignInErrorCode.hasNoAuthInKeychain.rawValue {
                  print("The user has not signed in before or they have since signed out.")
              } else {
                  print("\(error.localizedDescription)")
              }
              return
          }
          
          AudioDriveGoogleUser = user
          GoogleDriveService.authorizer = user.authentication.fetcherAuthorizer()
          configureUploadFolderID(uploadFiles: false)

         
          print("User signed in")
    }
      
      
      func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!,
                withError error: Error!) {
          
          print("User disconnecting")
      }

    
    
    @IBAction func checkCancelRecording(_ sender: Any) {
    
        let alert = UIAlertController(title: "Delete this recording - are you sure?",
                                         message: "This action will cancel the current recording and delete it (it wont be uploaded)",
                                         preferredStyle: UIAlertController.Style.alert)

           alert.addAction(UIAlertAction(title: "No, Don't Delete", style: UIAlertAction.Style.default, handler: { _ in
               //Cancel Action
           }))
           alert.addAction(UIAlertAction(title: "Yes, Do It",
                                         style: UIAlertAction.Style.default,
                                         handler: {(_: UIAlertAction!) in
                                          
                                           self.cancelRecording()
           }))
           self.present(alert, animated: true, completion: nil)
    }
    
    
    func setGoogleStatusUI() {
            
        if signedIntoGoogle() == true {
             UISettingsButton.setImage(UIImage(named: "googleok"), for: UIControl.State.normal)
            UIUploadStatusText.text = "google drive ready to receive uploads"
          } else {
             UISettingsButton.setImage(UIImage(named: "googlealert"), for: UIControl.State.normal)
            UIUploadStatusText.text = "log into google to activate uploading to drive"
          }
    }

    
    @IBAction func recordButtonClicked(_ sender: Any) {
        
        guard RecorderTakingInput == true else {return}
        
        RecorderTakingInput = false
        if RecordingActive == false {
            RecordingActive = true
            RecordingTime = 0

            UIRecordingButton.setImage(UIImage(named: "recorderon"), for: UIControl.State.normal)
            TimerClock = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(updateRecordingTimeDisplay), userInfo: nil, repeats: true)
        
            UIUploadStatusText.text = ""
            activateRecordingUI()
            (AudioFileNameNative, AudioFileNameMP3, AudioFilePathNative, AudioFilePathMP3) = generateRecordingPaths()
            AudioFileNameCurrentlyRecording = AudioFileNameNative
            startRecording(path: AudioFilePathNative)
            startMeterThread()
            RecorderTakingInput = true
            UICancelRecordingButton.isHidden = false

        } else {
            RecordingActive = false
            UICancelRecordingButton.isHidden = true

            stopRecording()
            AudioFileNameCurrentlyRecording = ""

            UIRecordingButton.setImage(UIImage(named: "recorderoff"), for: UIControl.State.normal)
            TimerClock.invalidate()
            
            deactivateRecordingUI()

            // if not signed in, just keep file stored locally until next log in
            if self.signedIntoGoogle() == false {
                self.UIUploadStatusText.text = "\(AudioFileNameMP3) stored locally until next login"
                self.RecorderTakingInput = true
                return
            }
            
            // if upload folder hasn't been set yet, also store locally
            guard let uploadFolderID = UploadFolderID else {
                 self.UIUploadStatusText.text = "\(AudioFileNameMP3) stored locally until next login"
                 self.RecorderTakingInput = true
                 return
            }
            
            UIUploadStatusText.text = "uploading audio file"

            let dispatchQueue = DispatchQueue(label: "Upload", qos: .background)
            dispatchQueue.async {
                
                let audioFileNative = self.AudioFileNameNative
                let audioFileMP3 = self.AudioFileNameMP3
                let audioPathNative = self.AudioFilePathNative
                let audioPathMP3 = self.AudioFilePathMP3
                self.RecorderTakingInput = true
                
                print(audioFileMP3)
                // generate MP3 file from native encoding
                let command = "-y -i \(audioPathNative) \(audioPathMP3)"
                MobileFFmpeg.execute(command)
                
                if self.audioFileExists(named: audioFileMP3) == false {
                    print("MP3 not generated - deleting ")
                    //self.deleteFile(named: audioFileMP3)
                    
                }
                
                guard self.signedIntoGoogle() == true else {return}

                // upload the MP3.  this upload will delete the native and MP3 audio if successful
                print("uploading file \(audioFileMP3)")
                self.uploadFile(
                    audioFileMP3: audioFileMP3,
                    audioFileNative: audioFileNative,
                    folderID: UploadFolderID!,
                    MP3fileURL: URL(string: "file://" + audioPathMP3)!,
                    mimeType: "audio/mpeg",
                    service: GoogleDriveService)
                
            }
        }
    }
   
    
    func recordingInit() {
         RecordingSession = AVAudioSession.sharedInstance()

         do {
             try RecordingSession.setCategory(.playAndRecord, mode: .default)
             try RecordingSession.setActive(true)
             RecordingSession.requestRecordPermission() { [unowned self] allowed in
                 DispatchQueue.main.async {
                     if allowed {
                         print("enabled recording UI")
                     } else {
                         print("Failed to init recording UI")
                         
                     }
                 }
             }
         } catch {
             print("ERROR")
         }
     }
     

    func startRecording(path pathNativeRecording: String) {
         
         var bitRate: Int = 16000
         let sampleRate: Int = SAMPLE_RATE
         
         
         switch ConfigAudioBitRate {
         case "96,000":
             bitRate = 96000
         case "128,000":
             bitRate = 128000
         case "192,000":
             bitRate = 192000
         default:
             print("ERROR \(ConfigAudioBitRate)")
             fatalError(ConfigAudioBitRate)
         }
             
        let numberChannels = ConfigAudioType == "Mono" ? 1 : 2
        
        let settings:[String : Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVEncoderAudioQualityKey : AVAudioQuality.min.rawValue,
            AVEncoderBitRateKey : bitRate,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey : sampleRate
        ]
          
         do {
             print("create AVAudio:  sampleRate=\(sampleRate) bitrate=\(bitRate) numberChannels=\(numberChannels)  ")
             AudioRecorder = try AVAudioRecorder(url: URL(string: pathNativeRecording)!, settings: settings)
             AudioRecorder.isMeteringEnabled = true
             AudioRecorder.delegate = self
             print("start recording", pathNativeRecording)

             AudioRecorder.record()
             print("AudioRecorder returns")

         } catch let error as NSError {
            print("Recording Start Error!")
            print(error.localizedDescription);
            AudioRecorder = nil
            
            UIRecordingButton.setImage(UIImage(named: "recorderoff"), for: UIControl.State.normal)
            TimerClock.invalidate()
            
            deactivateRecordingUI()
            UIUploadStatusText.text = ""

         }
     }
     
     
     func stopRecording() {
         
        print("stop recording")
        AudioRecorder.stop()
        AudioRecorder = nil
         
     }
    
    
    func cancelRecording() {
        
        RecordingActive = false
        stopRecording()

        UIRecordingButton.setImage(UIImage(named: "recorderoff"), for: UIControl.State.normal)
        TimerClock.invalidate()
         
        deactivateRecordingUI()
        
        deleteFile(named: AudioFileNameNative)
        deleteFile(named: AudioFileNameMP3)
        
        UICancelRecordingButton.isHidden = true
        UIUploadStatusText.text = "recording cancelled and deleted"
    }
    

    
    
    func activateRecordingUI() {
        
        UIRecordingTimer.text = "00:00:00:00"

        UIRecordingTimer.isHidden = false
        UIMeter.isHidden = false
 
    }
    
    
    func deactivateRecordingUI() {
        
        UIRecordingTimer.text = "00:00:00:00"
        
        UIRecordingTimer.isHidden = true
        UIMeter.isHidden = true
    }

    
    func startMeterThread() {
        
        OperationQueue().addOperation({[weak self] in
        repeat {
            if let recorder = self?.AudioRecorder {
                recorder.updateMeters()
                self?.AveragePower = recorder.averagePower(forChannel: 0)

                self?.performSelector(onMainThread: #selector(ViewController.updateMeter), with: self, waitUntilDone: false)
            }
            Thread.sleep(forTimeInterval: 0.05)//20 FPS
        }
            while (self?.AudioRecorder != nil)
        })
    }
     
     
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
         
         print("audioRecorderDidFinishRecording")
    }

    
    @IBAction func unwindSettingsScreen(unwindSegue: UIStoryboardSegue) {
        
        print("unwindSettingsScreen")
    }
    
    
    @objc func updateMeter() {
           
           if let power = AveragePower {
            let meterValue = Int((power + MAX_DECIBLES) * 1.4)
               if meterValue > 0 {
                   //print(meterValue)

                   self.UIMeterUpdate.frame.size.width = CGFloat(meterValue)
               }
           }
       }
    
    
    @objc func updateRecordingTimeDisplay() {
        
        RecordingTime += 1
        
        let displayCS = (RecordingTime % 100)
        let displaySecond = (RecordingTime / 100) % 60
        let displayMinute = (RecordingTime / (100 * 60)) % 60
        let displayHour = RecordingTime / (100 * 60 * 60)
        
        UIRecordingTimer.text = String(format: "%02d:%02d:%02d:%02d", displayHour, displayMinute, displaySecond, displayCS)
    }
    
    
    func signedIntoGoogle() -> Bool {
        
        if isInternetAvailable() == false {return false}
        
        if GIDSignIn.sharedInstance()?.currentUser != nil {
            return true
        }
        return false
    }
    
    
    func generateRecordingPaths () -> (String, String, String, String) {
        
        var fileExists: Bool
        var audioFileNative, audioFileMP3, audioPathNative, audioPathMP3 : String

        let documentDirectory = getDocumentsDirectory()
        
        let fileManager = FileManager.default
        repeat {
            let format = DateFormatter()
            format.dateFormat = "yyMMdd.HHmmss"
            let formattedDate = format.string(from: Date())
            
            audioFileNative = AUDIO_PREFIX + formattedDate +  NATIVE_AUDIO_SUFFIX
            audioPathNative = documentDirectory.appendingPathComponent(audioFileNative).path
            audioFileMP3 = AUDIO_PREFIX + formattedDate +  MP3_AUDIO_SUFFIX
            audioPathMP3 = documentDirectory.appendingPathComponent(audioFileMP3).path
            fileExists = fileManager.fileExists(atPath: audioPathNative)
        } while (fileExists == true)
        
        return (audioFileNative, audioFileMP3, audioPathNative, audioPathMP3)
    }
        
    
    func uploadFile(
        audioFileMP3: String,
        audioFileNative: String,
        folderID: String,
        MP3fileURL: URL,
        mimeType: String,
        service: GTLRDriveService) {
        
        let file = GTLRDrive_File()
        file.name = audioFileMP3
        
        // if folder is root, no need to set parent
        // otherwise set parent to folder ID
        if folderID != GOOGLE_DRIVE_ROOT_FOLDER {
            //print("Setting FOLDER")
            file.parents = [folderID]
        }
        
        // Optionally, GTLRUploadParameters can also be created with a Data object.
        let uploadParameters = GTLRUploadParameters(fileURL: MP3fileURL, mimeType: mimeType)
        
        let query = GTLRDriveQuery_FilesCreate.query(withObject: file, uploadParameters: uploadParameters)
        
        service.uploadProgressBlock = { _, totalBytesUploaded, totalBytesExpectedToUpload in
            let rate = (totalBytesUploaded * 100) / totalBytesExpectedToUpload
            print("progress... \(totalBytesUploaded)  \(totalBytesExpectedToUpload) \(rate)")
            
            self.UIUploadStatusText.text = "uploading \(audioFileMP3) \(rate)%"
        }
        
        service.executeQuery(query) { (_, result, error) in
            
            guard error == nil else {
                print("Upload FAILED")
                self.UIUploadStatusText.text = "\(audioFileMP3) did not upload.  check your connection"
                //fatalError(error!.localizedDescription)
                return
            }
            
            print("Upload Successful")
            if folderID == GOOGLE_DRIVE_ROOT_FOLDER {
                self.UIUploadStatusText.text = "\(audioFileMP3) uploaded to home folder in google"
             } else {
                 self.UIUploadStatusText.text = "\(audioFileMP3) uploaded to \(ConfigUploadFolder) in google"
             }

            // lastly, delete both native and mp3 file, indicating completion
            self.deleteFile(named: audioFileMP3)
            self.deleteFile(named: audioFileNative)
            
        }
    }
    
    //
    // upload all pending files
    //
    func uploadAllFiles() {
    
        print("uploadAllFiles")
        
        let countAudioFiles = countUploadableFiles()
        print("Will upload \(countAudioFiles) Files")
        self.RecorderTakingInput = true


        // for every native m4a file ...
        // convert to mp3
        // upload the mp3
        do {
            let audioFileList = try FileManager.default.contentsOfDirectory(atPath: PATH_DOCUMENTS)
            
            for audioFileNative in audioFileList {
                if audioFileNative.contains(NATIVE_AUDIO_SUFFIX) == false {continue}
                print("Here: \(audioFileNative) \(AudioFileNameCurrentlyRecording)")

                if audioFileNative == AudioFileNameCurrentlyRecording {
                    print("Skipping \(AudioFileNameCurrentlyRecording)")
                    continue
                }
                let audioFileMP3 = audioFileNative.replacingOccurrences(of: NATIVE_AUDIO_SUFFIX, with: MP3_AUDIO_SUFFIX)
                
                let audioPathNative = PATH_DOCUMENTS + audioFileNative
                let audioPathMP3 = PATH_DOCUMENTS + audioFileMP3
                let command = "-y -i \(audioPathNative) \(audioPathMP3)"
                print(command)
                self.UIUploadStatusText.text = "uploading \(audioFileMP3)"
                MobileFFmpeg.execute(command)
                if self.audioFileExists(named: audioFileMP3) == false {
                     print("MP3 not generated - deleting ")
                     self.deleteFile(named: audioFileNative)
                     continue
                 }
                
                uploadFile(
                         audioFileMP3: audioFileMP3,
                         audioFileNative: audioFileNative,
                         folderID: UploadFolderID!,
                         MP3fileURL: URL(string: "file://" + audioPathMP3)!,
                         mimeType: "audio/mpeg",
                         service: GoogleDriveService)
            }
        } catch (let error) {
            print("uploadAllFiles Error  \(error)")
            return
        }
    }
    
    
    func copyFile(srcPath: String, destPath: String) {
    
        print("copyFile")
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(atPath: srcPath, toPath: destPath)
        } catch (let error) {
            print("Copy Error \(error)")
            return
        }
    }
    
    
    func deleteMP3AudioFiles() {
    
        print("deleteMP3AudioFiles")
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
            for audioFileMP3 in audioFileList {
                if audioFileMP3.contains(MP3_AUDIO_SUFFIX) == false {continue}

                deleteFile(named: audioFileMP3)
            }
        } catch (let error) {
            print("deleteMP3AudioFiles Error \(error)")
            return
        }
    }
    
    func audioFileExists(named audioFileName: String) -> Bool {
        
        let filePath = PATH_DOCUMENTS + audioFileName
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
               return true
        } else {
               return false
        }
    }
    
    func deleteNativeAudioFiles() {
       
           print("deleteNativeAudioFiles")
           let fileManager = FileManager.default
           do {
               let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
               for audioFileNative in audioFileList {
                if audioFileNative.contains(NATIVE_AUDIO_SUFFIX) == false {continue}

                print(audioFileNative)
                deleteFile(named: audioFileNative)
               }
           } catch (let error) {
               print("deleteNativeAudioFiles Error \(error)")
               return
           }
       }
    
    
    func deleteFile(named audioFileName:String) {
   
       print("deleteFile")
       do {
            let audioFilePath = "file://" + PATH_DOCUMENTS + audioFileName
            print(audioFilePath)
            try FileManager.default.removeItem(at: URL(string: audioFilePath)!)
          
       } catch (let error) {
           print("List Error \(error)")
           return
       }
   }
    
    
    func countUploadableFiles() -> Int {
        
        print("countUploadableFiles")
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
            var count = 0
            for audioFile in audioFileList {
                if audioFile.contains(MP3_AUDIO_SUFFIX) == false {continue}
                
                count += 1

            }
            return count
        } catch (let error) {
            print("List Error \(error)")
             return 0
        }
    }
    
    func deleteAllFiles() {
     
         print("deleteAllFiles")
         let fileManager = FileManager.default
         do {
             let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
             for audioFile in audioFileList {
                deleteFile(named: audioFile)
             }
         } catch (let error) {
             print("deleteAllFiles \(error)")
             return
         }
     }


    
    
    func listAllFiles() {
    
        print("listAllFiles")
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
            for audioFile in audioFileList {
                print(audioFile)
            }
        } catch (let error) {
            print("List Error \(error)")
            return
        }
    }
    
    
    func configureUploadFolderID(uploadFiles: Bool) {
        
        guard signedIntoGoogle() == true else {return}
        
        print("configureUploadFolderID")
    
        // if target folder is empty or weird, make target folder ROOT
        let vaildateNameString =  ConfigUploadFolder.replacingOccurrences(of: " ", with: "")
        if (vaildateNameString.count < 1) || vaildateNameString.isAlphanumeric == false {
            UploadFolderID = GOOGLE_DRIVE_ROOT_FOLDER
            return
        }

        print(ConfigUploadFolder)
        getFolderID(name: ConfigUploadFolder, service: GoogleDriveService, user: AudioDriveGoogleUser!) { folderID in
            // new folder, create it
            if folderID == nil {
                print("Creating new folder \(ConfigUploadFolder)")
                self.createFolder(
                    name: ConfigUploadFolder,
                    service: GoogleDriveService) {
                        UploadFolderID = $0
                        self.setGoogleStatusUI()
                        if uploadFiles == true {self.uploadAllFiles()}
                  }
            } else {
                // Folder already exists
                print("folder exists \(ConfigUploadFolder)")
                UploadFolderID = folderID
                if uploadFiles == true {self.uploadAllFiles()}
            }
        }
    }

    
    func getFolderID(
        name: String,
        service: GTLRDriveService,
        user: GIDGoogleUser,
        completion: @escaping (String?) -> Void) {
        
        let query = GTLRDriveQuery_FilesList.query()

        // Comma-separated list of areas the search applies to. E.g., appDataFolder, photos, drive.
        query.spaces = "drive"
        
        // Comma-separated list of access levels to search in. Some possible values are "user,allTeamDrives" or "user"
        query.corpora = "user"
            
        let withName = "name = '\(name)'" // Case insensitive!
        let foldersOnly = "mimeType = 'application/vnd.google-apps.folder'"
        let ownedByUser = "'\(user.profile!.email!)' in owners"
        query.q = "\(withName) and \(foldersOnly) and \(ownedByUser)"
        
        service.executeQuery(query) { (_, result, error) in
            guard error == nil else {
                fatalError(error!.localizedDescription)
            }
                                     
            let folderList = result as! GTLRDrive_FileList

            // For brevity, assumes only one folder is returned.
            completion(folderList.files?.first?.identifier)
        }
    }
    
        
    func createFolder(
        name: String,
        service: GTLRDriveService,
        completion: @escaping (String) -> Void) {
        
        let folder = GTLRDrive_File()
        folder.mimeType = "application/vnd.google-apps.folder"
        folder.name = name
        
        // Google Drive folders are files with a special MIME-type.
        let query = GTLRDriveQuery_FilesCreate.query(withObject: folder, uploadParameters: nil)
        
        GoogleDriveService.executeQuery(query) { (_, file, error) in
            guard error == nil else {
                fatalError(error!.localizedDescription)
            }
            
            let folder = file as! GTLRDrive_File
            completion(folder.identifier!)
        }
    }
    
    
    
    
    func getDocumentsDirectory() -> URL {
          let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
          return paths[0]
    }
    
    
    func isInternetAvailable() -> Bool
    {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags = SCNetworkReachabilityFlags()
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) {
            return false
        }
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        return (isReachable && !needsConnection)
    }
    
}

 */
