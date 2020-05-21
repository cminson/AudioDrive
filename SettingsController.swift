//
//  SettingsController.swift
//  AudioDrive
//
//  Created by Christopher on 5/9/20.
//  Copyright © 2020 Christopher Minson. All rights reserved.
//

import UIKit
import GoogleSignIn
import GoogleAPIClientForREST
import GTMSessionFetcher

let COLOR_REDDISH = UIColor(hex: "#990033ff")
let COLOR_GREENISH = UIColor(hex: "#006400ff")


extension UIColor {
    public convenience init?(hex: String) {
        let r, g, b, a: CGFloat

        if hex.hasPrefix("#") {
            let start = hex.index(hex.startIndex, offsetBy: 1)
            let hexColor = String(hex[start...])

            if hexColor.count == 8 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0

                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
                    g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
                    b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
                    a = CGFloat(hexNumber & 0x000000ff) / 255

                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            }
        }
        return nil
    }
}



class SettingsController: UIViewController, GIDSignInDelegate {
    
    @IBOutlet weak var UIUploadFolder: UITextField!
    @IBOutlet weak var UIAudioType: UISegmentedControl!
    @IBOutlet weak var UIAudioSampleRate: UISegmentedControl!
    @IBOutlet weak var UIAudioBitRate: UISegmentedControl!
    @IBOutlet weak var UIPendingUploadLabel: UILabel!
    @IBOutlet weak var UIDeletePendingsButton: UIButton!
    
    @IBOutlet weak var UIGoogleButton: UIButton!
    
        
    var parentController: ViewController?
    
    override func viewDidLoad() {
        
        print("View Did Load")

        super.viewDidLoad()
        self.title = "Settings"
        
        //UIDeletePendingsButton.backgroundColor = COLOR_GREENISH
        UIDeletePendingsButton.layer.borderWidth = 1
        UIDeletePendingsButton.layer.borderColor = UIColor.lightGray.cgColor
        
        /*
        let count = countUploadableFiles()
        if (count > 0) && signedIntoGoogle() == false {
            UIDeletePendingsButton.isHidden = false
            UIPendingUploadLabel.isHidden = false
            UIPendingUploadLabel.text = "audios/ awaiting upload: \(count)"
        } else {
            UIDeletePendingsButton.isHidden = true
            UIPendingUploadLabel.isHidden = true
        }
         */
        UIDeletePendingsButton.isHidden = true
        UIPendingUploadLabel.isHidden = true

        
        GIDSignIn.sharedInstance()?.clientID = CLIENT_ID
        GIDSignIn.sharedInstance().delegate = self

        GIDSignIn.sharedInstance()?.presentingViewController = self
        GIDSignIn.sharedInstance()?.restorePreviousSignIn()
    }
    

    override func viewWillAppear(_ animated: Bool) {

        print("ViewWillAppear")
        
        Settings().loadSettings()
        UIUploadFolder.text = ConfigUploadFolder
        
        if (ConfigAudioType == "Mono") {
            UIAudioType.selectedSegmentIndex = 0
        }
        else {
            UIAudioType.selectedSegmentIndex = 1
        }
        

        if (ConfigAudioBitRate == "96,000") {
            UIAudioBitRate.selectedSegmentIndex = 0
        }
        else if (ConfigAudioBitRate == "128,000") {
            UIAudioBitRate.selectedSegmentIndex = 1
        }
        else {
            UIAudioBitRate.selectedSegmentIndex = 2
        }
        
        if GIDSignIn.sharedInstance()?.currentUser != nil {
            // we're signed in, so display sign out option
            UIGoogleButton.setTitle("Sign Out of Google", for: .normal)
            UIGoogleButton.backgroundColor = COLOR_REDDISH
        } else {
            // we're signed out, so display sign in option

            UIGoogleButton.setTitle("Sign Into Google", for: .normal)
            UIGoogleButton.backgroundColor = COLOR_GREENISH
        }
        
        super.viewWillAppear(animated)
        
    }

    
    override func viewWillDisappear(_ animated: Bool) {
        
        var uploadFolder = DEFAULT_UPLOAD_FOLDER
        if (uploadFolder.count > 0) {uploadFolder = UIUploadFolder.text!}
        
        let audioType = UIAudioType.titleForSegment(at: UIAudioType.selectedSegmentIndex)!
        let audioBitRate = UIAudioBitRate.titleForSegment(at: UIAudioBitRate.selectedSegmentIndex)!

       
        Settings().saveSettings(uploadFolder: uploadFolder,
                                audioType: audioType,
                                audioBitRate: audioBitRate
        )
        Settings().loadSettings()
               
        super.viewWillDisappear(animated)
    }
    
    
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!,
                withError error: Error!) {
    
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
        print("Settings Controller:  User signed in")
        
        // update button state to show we are signed out
        UIGoogleButton.setTitle("Sign Out Of Google", for: .normal)
        UIGoogleButton.backgroundColor = COLOR_REDDISH
        
        // update parent UI for the new google state
        parentController?.setGoogleStatusUI()
        
        // upload anything that is hanging around locally
        parentController?.configureUploadFolderID(uploadFiles: true)
      }
      
      
      func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!,
                withError error: Error!) {
          
          print("User disconnecting")
      }
    
    
    @IBAction func deletePendingUploadFiles(_ sender: Any) {
        
        let alert = UIAlertController(title: "Are you sure?",
                                        message: "This action will delete all  audio recordings on this device that are queued for uploading",
                                        preferredStyle: UIAlertController.Style.alert)

          alert.addAction(UIAlertAction(title: "No, Don't Delete", style: UIAlertAction.Style.default, handler: { _ in
              //Cancel Action
          }))
          alert.addAction(UIAlertAction(title: "Yes, Do It",
                                        style: UIAlertAction.Style.default,
                                        handler: {(_: UIAlertAction!) in
                                         
                                          self.deleteAllFiles()
          }))
          self.present(alert, animated: true, completion: nil)
    }
        
        
    func deleteAllFiles()  {
        print("deleteAllFiles")
        
        var count = countUploadableFiles()
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
            for audioFile in audioFileList {
                deleteFile(named: audioFile)
                count -= 1
                UIPendingUploadLabel.text = "audios awaiting upload: \(count)"
            }
        } catch (let error) {
                print("deleteAllFiles \(error)")
        }
    }

    
    func countUploadableFiles() -> Int {
          
          print("countUploadableFiles")
          let fileManager = FileManager.default
          do {
              let audioFileList = try fileManager.contentsOfDirectory(atPath: PATH_DOCUMENTS)
              var count = 0
              for audioFile in audioFileList {
                  if audioFile.contains(NATIVE_AUDIO_SUFFIX) == false {continue}                  
                  count += 1
              }
              return count
          } catch (let error) {
              print("List Error \(error)")
               return 0
          }
      }

    
    func deleteFile(named audioFileName:String) {
    
        print("deleteFile")
        do {
             let audioFilePath = "file://" + PATH_DOCUMENTS + audioFileName
             print(audioFilePath)
             try FileManager.default.removeItem(at: URL(string: audioFilePath)!)
           
        } catch (let error) {
            print("deleteFile \(error)")
        }
    }

    
    @IBAction func SignIntoGoogle(_ sender: Any) {
        
        if signedIntoGoogle() {
            checkGoogleSignOut()
        } else
        {
            googleSignIn()
            
        }
    }
       
       
    func signedIntoGoogle() -> Bool {
           
           if GIDSignIn.sharedInstance()?.currentUser != nil {
               return true
           }
           return false
       }
       

    
    func googleSignIn() {
        
        GIDSignIn.sharedInstance()?.signIn()
        GIDSignIn.sharedInstance()?.scopes = [kGTLRAuthScopeDrive]
        print("Signed In")
    }
    
    
    func googleSignOut() {
        
        UIGoogleButton.setTitle("Sign Into Google", for: .normal)
        UIGoogleButton.backgroundColor = COLOR_GREENISH

        GIDSignIn.sharedInstance()?.signOut()

        print("Signed Out")
    }

    
     
    func checkGoogleSignOut() {
        let alert = UIAlertController(title: "Are you sure?",
                                      message: "Audio files will not upload until you sign back into google again",
                                      preferredStyle: UIAlertController.Style.alert)

        alert.addAction(UIAlertAction(title: "No, Don't Sign Out", style: UIAlertAction.Style.default, handler: { _ in
            //Cancel Action
        }))
        alert.addAction(UIAlertAction(title: "Yes, Sign out",
                                      style: UIAlertAction.Style.default,
                                      handler: {(_: UIAlertAction!) in
                                        //Sign out action
                                        self.googleSignOut()
        }))
        self.present(alert, animated: true, completion: nil)
    }
    

    

}
