//
//  ViewController.swift
//  AudioDrive
//
//  Created by Christopher on 5/7/20.
//  Copyright © 2020 Christopher Minson. All rights reserved.
//

import UIKit
import Foundation
import SystemConfiguration
import AVFoundation
import CoreMedia
import GoogleSignIn
import GoogleAPIClientForREST
import GTMSessionFetcher
import lame


/*
 *
 * This is the main view controller.  All non-settings logic happens here.
 *
 */

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
    var AudioFileName : String = ""
    var AudioFilePath : String = ""
    var RecorderTakingInput = true
    
    var DOCUMENTS_URL : URL!
    var DOCUMENTS_PATH = ""
    
    var AudioEngine : AVAudioEngine!
    var AudioFile : AVAudioFile!
    var AudioPlayer : AVAudioPlayerNode!
    var Outref: ExtAudioFileRef?
    var AudioFilePlayer: AVAudioPlayerNode!
    var Mixer : AVAudioMixerNode!
    var IsPlay = false
    var MP3Active = false
 
    var TMP_WAV_PATH = ""
    let TMP_WAV_NAME = "tmp.wav"

    var ActiveSet = Set<String>()

    // setup google session, recording logic
    override func viewDidLoad() {
        
        super.viewDidLoad()
        title = "Audio Drive"
        Settings().loadSettings()
        
        DOCUMENTS_URL = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
        DOCUMENTS_PATH = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/"
        TMP_WAV_PATH = DOCUMENTS_PATH + TMP_WAV_NAME
        
        deactivateRecordingUI()
        
        GIDSignIn.sharedInstance().delegate = self
        GIDSignIn.sharedInstance()?.presentingViewController = self
        GIDSignIn.sharedInstance()?.scopes = [kGTLRAuthScopeDrive]
        GIDSignIn.sharedInstance()?.restorePreviousSignIn()

        UIMeter.isHidden = true
        
        // Decibel meter commented out for know TBD
        /*
        let height = UIMeter.frame.height
        let width = UIMeter.frame.width
        let rectFrame: CGRect = CGRect(x:CGFloat(0), y:CGFloat(0), width:CGFloat(width), height:CGFloat(height))
        UIMeterUpdate = UIView(frame: rectFrame)
        UIMeter.backgroundColor = COLOR_GREENISH
        UIMeterUpdate.backgroundColor = .green
        UIMeter.addSubview(UIMeterUpdate)
         */
          
        RecordingActive = false
        UICancelRecordingButton.isHidden = true
        
        AudioEngine = AVAudioEngine()
        AudioFilePlayer = AVAudioPlayerNode()
        Mixer = AVAudioMixerNode()
        AudioEngine.attach(AudioFilePlayer)
        AudioEngine.attach(Mixer)
     }
    

    // this is where we update the UI to reflect google login status
    override func viewWillAppear(_ animated: Bool) {

        //print("view will appear")
        connectToGoogleDrive(uploadFiles: false)
        setGoogleStatusUI()
        
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) != .authorized {
            AVCaptureDevice.requestAccess(for: AVMediaType.audio,
                completionHandler: { (granted: Bool) in
            })
        }
        
        super.viewWillAppear(animated)
    }
    
    
    override func didReceiveMemoryWarning() {
        
        super.didReceiveMemoryWarning()
    }
    
    
    // invoked when we move to setting screen.  give settings a handle to Self so that it
    // can flag this view about any setting changes
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
    
    // GIDSignInDelegate: involed by google framework on signin
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!,
                withError error: Error!) {
    
          //print("SIGN IN: ViewControler")
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
        
          setGoogleStatusUI()
          connectToGoogleDrive(uploadFiles: false)

          // print("User signed in")
    }
      

    // invoked by google framework on disconnect from google
    func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!,
                withError error: Error!) {
          
          // print("User disconnecting")
      }

    
    // this gets invoked when user cancels recording (touches the 'X' in lower right)
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
    
    
    // show our google login status on top of view
    func setGoogleStatusUI() {
            
        if signedIntoGoogle() == true {
             UISettingsButton.setImage(UIImage(named: "googleok"), for: UIControl.State.normal)
            UIUploadStatusText.text = "google drive ready to receive uploads"
          } else {
             UISettingsButton.setImage(UIImage(named: "googlealert"), for: UIControl.State.normal)
            UIUploadStatusText.text = "log into google to activate uploading to drive"
          }
    }

    
    // toggle button.  either start a recording or stop the current recording
    @IBAction func recordButtonClicked(_ sender: Any) {
        
        guard RecorderTakingInput == true else {return}
        
        print("record button clickec")
        RecorderTakingInput = false
        if RecordingActive == false {
            RecordingActive = true
            RecordingTime = 0

            UIRecordingButton.setImage(UIImage(named: "recorderon"), for: UIControl.State.normal)
            TimerClock = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(updateRecordingTimeDisplay), userInfo: nil, repeats: true)
        
            UIUploadStatusText.text = ""
            activateRecordingUI()
            
            var fileExists: Bool
            var audioFileName, audioFilePath : String
            
            let fileManager = FileManager.default
            repeat {
                let format = DateFormatter()
                format.dateFormat = "yyMMdd.HHmmss"
                let formattedDate = format.string(from: Date())
                
                audioFileName = AUDIO_PREFIX + formattedDate +  MP3_AUDIO_SUFFIX
                audioFilePath = DOCUMENTS_URL.appendingPathComponent(audioFileName).path
                fileExists = fileManager.fileExists(atPath: audioFilePath)
            } while (fileExists == true)
            
            AudioFileName = audioFileName
            AudioFilePath = audioFilePath
            
            ActiveSet.insert(audioFileName)
            print("Inserting into Set \(audioFileName)")
            startRecording()
            RecorderTakingInput = true
            UICancelRecordingButton.isHidden = false

        } else {
            RecordingActive = false
            UICancelRecordingButton.isHidden = true

            ActiveSet.remove(AudioFileName)

            stopRecording()

            UIRecordingButton.setImage(UIImage(named: "recorderoff"), for: UIControl.State.normal)
            TimerClock.invalidate()
            
            deactivateRecordingUI()

            // if not signed in, just keep file stored locally until next log in
            if self.signedIntoGoogle() == false {
                self.UIUploadStatusText.text = "\(AudioFileName) stored locally until next login"
                self.RecorderTakingInput = true
                return
            }
            
            // if upload folder hasn't been set yet, also store locally
            guard let _ = UploadFolderID else {
                 self.UIUploadStatusText.text = "\(AudioFileName) stored locally until next login"
                 self.RecorderTakingInput = true
                 return
            }
            
            UIUploadStatusText.text = "uploading audio file"

            let dispatchQueue = DispatchQueue(label: "Upload", qos: .background)
            dispatchQueue.async {
                
                let audioFileName = self.AudioFileName
                let audioFilePath = self.AudioFilePath
                self.RecorderTakingInput = true
                
                //print(audioFileName)
                 
                guard self.signedIntoGoogle() == true else {return}

                // upload the MP3.  this upload will delete the MP3 audio if successful
                //print("uploading file \(audioFileName)")
                self.uploadFile(
                    audioFileName: audioFileName,
                    folderID: UploadFolderID!,
                    audioFileURL: URL(string: "file://" + audioFilePath)!,
                    mimeType: "audio/mpeg",
                    service: GoogleDriveService)
                
            }
        }
    }
    
    
    // record the MP3.  Painfully use lame to tap into the byte stream and perform the encoding
    func startRecording() {


        var sampleRateLAME : Int32 = 44100
        let numberChannels : UInt32 =  1

        // configure to create WAV recording, start it
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord)
        try! AVAudioSession.sharedInstance().setActive(true)

        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        sampleRateLAME = Int32(sampleRate)
        
        let format = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16,
                                    sampleRate: sampleRate,
             channels: numberChannels,
             interleaved: true)
                 
        print("connect  \(sampleRate) \(sampleRateLAME)")

        AudioEngine.connect(AudioEngine.inputNode, to: Mixer, format: format)
        AudioEngine.connect(Mixer, to: AudioEngine.mainMixerNode, format: format)

        _ = ExtAudioFileCreateWithURL(URL(fileURLWithPath: TMP_WAV_PATH) as CFURL,
             kAudioFileWAVEType,
             (format?.streamDescription)!,
             nil,
             AudioFileFlags.eraseFile.rawValue,
             &Outref)


        Mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount((format?.sampleRate)!), format: format, block: { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in

            let audioBuffer : AVAudioBuffer = buffer
            _ = ExtAudioFileWrite(self.Outref!, buffer.frameLength, audioBuffer.audioBufferList)
        })

        try! AudioEngine.start()
        
        
        // begin MP3 mixin
        var rate: Int32 = 96
        switch ConfigAudioBitRate {
        case "96,000":
            rate = 96
        case "128,000":
            rate = 128
        case "192,000":
            rate = 192
        default:
            print("ERROR \(ConfigAudioBitRate)")
            fatalError(ConfigAudioBitRate)
        }
        let numberLAMEChannels : Int32 = 1
        
        //print("rate = \(rate) ")
        MP3Active = true
        var total = 0
        var read = 0
        var write: Int32 = 0

        var pcm: UnsafeMutablePointer<FILE> = fopen(TMP_WAV_PATH, "rb")
        fseek(pcm, 4*1024, SEEK_CUR)
        let mp3: UnsafeMutablePointer<FILE> = fopen(AudioFilePath, "wb")
        let PCM_SIZE: Int = 8192
        let MP3_SIZE: Int32 = 8192
        let pcmbuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(PCM_SIZE*2))
        let mp3buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MP3_SIZE))

        let lame = lame_init()
        lame_set_num_channels(lame, numberLAMEChannels)
        lame_set_mode(lame, MONO)
        
        lame_set_in_samplerate(lame, sampleRateLAME)
        lame_set_brate(lame, rate)
        lame_set_VBR(lame, vbr_off)
        lame_init_params(lame)

        DispatchQueue.global(qos: .default).async {
            while true {
                pcm = fopen(self.TMP_WAV_PATH, "rb")
                     fseek(pcm, 4*1024 + total, SEEK_CUR)
                     read = fread(pcmbuffer, MemoryLayout<Int16>.size, PCM_SIZE, pcm)
                     if read != 0 {
                         write = lame_encode_buffer(lame, pcmbuffer, nil, Int32(read), mp3buffer, MP3_SIZE)
                         fwrite(mp3buffer, Int(write), 1, mp3)
                         total += read * MemoryLayout<Int16>.size
                         fclose(pcm)
                     } else if !self.MP3Active {
                         _ = lame_encode_flush(lame, mp3buffer, MP3_SIZE)
                         _ = fwrite(mp3buffer, Int(write), 1, mp3)
                         break
                     } else {
                         fclose(pcm)
                         usleep(50)
                     }
            }
            lame_close(lame)
            fclose(mp3)
            fclose(pcm)
        }
    }
         
    
    // terminate recording.  disconnect the lame tap, stop everywhere, delete the tmp files
    func stopRecording() {

        // stop audio engine and player
        // then halt the MP3 encoding (by setting MP3Active = false
        AudioFilePlayer.stop()
        AudioEngine.stop()
        Mixer.removeTap(onBus: 0)

        MP3Active = false
        ExtAudioFileDispose(Outref!)

        try! AVAudioSession.sharedInstance().setActive(false)
        deleteFile(named: TMP_WAV_NAME)
     }

    
    // cancel recording.  same as stopRecording, except we delete the MP3
    func cancelRecording() {
        
        RecordingActive = false
        stopRecording()

        UIRecordingButton.setImage(UIImage(named: "recorderoff"), for: UIControl.State.normal)
        TimerClock.invalidate()
         
        deactivateRecordingUI()
        
        deleteFile(named: AudioFileName)
        
        UICancelRecordingButton.isHidden = true
        UIUploadStatusText.text = "recording cancelled and deleted"
    }
    
    
    func activateRecordingUI() {
        
        UIRecordingTimer.text = "00:00:00:00"

        UIRecordingTimer.isHidden = false
        //UIMeter.isHidden = false
 
    }
    
    
    func deactivateRecordingUI() {
        
        UIRecordingTimer.text = "00:00:00:00"
        
        UIRecordingTimer.isHidden = true
        //UIMeter.isHidden = true
    }

    
    // our old decible code.  TBD
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
         
         //print("audioRecorderDidFinishRecording")
    }

    
    @IBAction func unwindSettingsScreen(unwindSegue: UIStoryboardSegue) {
        
        //print("unwindSettingsScreen")
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
        
    // upload a specific file to google.  typically this is the file we just recorded
    func uploadFile(
        audioFileName: String,
        folderID: String,
        audioFileURL: URL,
        mimeType: String,
        service: GTLRDriveService) {
        
        let file = GTLRDrive_File()
        file.name = audioFileName
                
        // if folder is root, no need to set parent
        // otherwise set parent to folder ID
        if folderID != GOOGLE_DRIVE_ROOT_FOLDER {
            //print("Setting FOLDER")
            file.parents = [folderID]
        }
                
        // Optionally, GTLRUploadParameters can also be created with a Data object.
        let uploadParameters = GTLRUploadParameters(fileURL: audioFileURL, mimeType: mimeType)
        
        let query = GTLRDriveQuery_FilesCreate.query(withObject: file, uploadParameters: uploadParameters)
        
        service.uploadProgressBlock = { _, totalBytesUploaded, totalBytesExpectedToUpload in
            
            if self.signedIntoGoogle() == true {
                let rate = (totalBytesUploaded * 100) / totalBytesExpectedToUpload
                //print("progress... \(totalBytesUploaded)  \(totalBytesExpectedToUpload) \(rate)")
            
                self.UIUploadStatusText.text = "uploading \(audioFileName) \(rate)%"
            }
            else {
                self.UIUploadStatusText.text = ""
            }
        }
        
        //
        let _ = service.executeQuery(query) { (_, result, error) in
            
            guard error == nil else {
                //print("Upload FAILED")
                self.UIUploadStatusText.text = "\(audioFileName) did not upload.  check your connection"
                //fatalError(error!.localizedDescription)
                return
            }
            
            //print("Upload Successful")
            if folderID == GOOGLE_DRIVE_ROOT_FOLDER {
                self.UIUploadStatusText.text = "\(audioFileName) uploaded to home folder in google"
             } else {
                 self.UIUploadStatusText.text = "\(audioFileName) uploaded to \(ConfigUploadFolder) in google"
             }

            // lastly, delete mp3 file, indicating completion
            self.deleteFile(named: audioFileName)

            
        }
        

    }
    
    //
    // upload all pending files.
    // these are the MP3s that were recorded when we weren't logged into google
    // now that we're logged in (presumably), iterate through these files and send them off to google drive
    //
    func uploadAllFiles() {
    
        guard signedIntoGoogle() else {return}
        
        //print("uploadAllFiles")
        
        let countAudioFiles = countUploadableFiles()
        //print("Will upload \(countAudioFiles) Files")
        self.RecorderTakingInput = true


        // for every mp3 file ...
        // upload the mp3
        do {
            let audioFileList = try FileManager.default.contentsOfDirectory(atPath: DOCUMENTS_PATH)
            
            for audioFileName in audioFileList {
                if audioFileName.contains(MP3_AUDIO_SUFFIX) == false {continue}

                if ActiveSet.contains(audioFileName) {
                    //print("Skipping \(audioFileName)")
                    continue
                }
                ActiveSet.insert(audioFileName)
                let audioPath = DOCUMENTS_PATH + audioFileName

                uploadFile(
                         audioFileName: audioFileName,
                         folderID: UploadFolderID!,
                         audioFileURL: URL(string: "file://" + audioPath)!,
                         mimeType: "audio/mpeg",
                         service: GoogleDriveService)
            }
        } catch (let error) {
            print("uploadAllFiles Error  \(error)")
            return
        }
    }
    
    
    func copyFile(srcPath: String, destPath: String) {
    
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(atPath: srcPath, toPath: destPath)
        } catch (let error) {
            print("Copy Error \(error)")
            return
        }
    }
    
    
    func deleteMP3AudioFiles() {
    
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
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
        
        let filePath = DOCUMENTS_PATH + audioFileName
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
               return true
        } else {
               return false
        }
    }
    
    func deleteNativeAudioFiles() {
       
           let fileManager = FileManager.default
           do {
               let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
               for audioFileNative in audioFileList {
                if audioFileNative.contains(NATIVE_AUDIO_SUFFIX) == false {continue}

                //print(audioFileNative)
                deleteFile(named: audioFileNative)
               }
           } catch (let error) {
               print("deleteNativeAudioFiles Error \(error)")
               return
           }
       }
    
    
    func deleteFile(named audioFileName:String) {
   
       do {
            let audioFilePath = "file://" + DOCUMENTS_PATH + audioFileName
            //print(audioFilePath)
            try FileManager.default.removeItem(at: URL(string: audioFilePath)!)
          
       } catch (let error) {
           print("List Error \(error)")
           return
       }
   }
    
    
    func countUploadableFiles() -> Int {
        
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
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
     
         let fileManager = FileManager.default
         do {
             let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
             for audioFile in audioFileList {
                deleteFile(named: audioFile)
             }
         } catch (let error) {
             print("deleteAllFiles \(error)")
             return
         }
     }


    func listAllFiles() {
    
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
            for audioFile in audioFileList {
                print(audioFile)
            }
        } catch (let error) {
            print("List Error \(error)")
            return
        }
    }
    
    
    // get a handle to the google upload folder.
    // then upload all pending files in the background
    func connectToGoogleDrive(uploadFiles: Bool) {
        
        guard signedIntoGoogle() == true else {return}
        
        //print("configureUploadFolderID")
    
        // if target folder is empty or weird, make target folder ROOT
        let vaildateNameString =  ConfigUploadFolder.replacingOccurrences(of: " ", with: "")
        if (vaildateNameString.count < 1) || vaildateNameString.isAlphanumeric == false {
            UploadFolderID = GOOGLE_DRIVE_ROOT_FOLDER
            return
        }

        //print(ConfigUploadFolder)
        getFolderID(name: ConfigUploadFolder, service: GoogleDriveService, user: AudioDriveGoogleUser!) { folderID in
            // new folder, create it
            if folderID == nil {
                //print("Creating new folder \(ConfigUploadFolder)")
                self.createFolder(
                    name: ConfigUploadFolder,
                    service: GoogleDriveService) {
                        UploadFolderID = $0
                        self.setGoogleStatusUI()
                        if uploadFiles == true {self.uploadAllFiles()}
                  }
            } else {
                // Folder already exists
                //print("folder exists \(ConfigUploadFolder)")
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
