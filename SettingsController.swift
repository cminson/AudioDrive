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

    
    @IBOutlet weak var UIGoogleButton: UIButton!
    
        
    var parentController: ViewController?
    
    override func viewDidLoad() {
        
        print("View Did Load")

        super.viewDidLoad()
        self.title = "Settings"
        
        GIDSignIn.sharedInstance()?.clientID = CLIENT_ID
        GIDSignIn.sharedInstance().delegate = self

        GIDSignIn.sharedInstance()?.presentingViewController = self
        GIDSignIn.sharedInstance()?.restorePreviousSignIn()
    }
    

    override func viewWillAppear(_ animated: Bool) {

        print("ViewWillAppear")
        
        Settings().loadSettings()
        UIUploadFolder.text = ConfigUploadFolder
        

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
        
        let audioBitRate = UIAudioBitRate.titleForSegment(at: UIAudioBitRate.selectedSegmentIndex)!

       
        Settings().saveSettings(uploadFolder: uploadFolder,
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
        parentController?.connectToGoogleDrive(uploadFiles: true)
      }
      
      
      func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!,
                withError error: Error!) {
          
          print("User disconnecting")
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
