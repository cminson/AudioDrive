//
//  Settings.swift
//  AudioDrive
//
//  Created by Christopher on 5/11/20.
//  Copyright © 2020 Christopher Minson. All rights reserved.
//

import Foundation


let KEY_UPLOAD_FOLDER = "KEY_UPLOAD_FOLDER"
let KEY_AUDIO_BIT_RATE = "KEY_AUDIO_BIT_RATE"

let DEFAULT_UPLOAD_FOLDER = "Audio Drive"
let DEFAULT_AUDIO_BIT_RATE =  "96,000"

var ConfigUploadFolder = DEFAULT_UPLOAD_FOLDER
var ConfigAudioBitRate = DEFAULT_AUDIO_BIT_RATE

class Settings {
    
    func loadSettings() {
        
        let defaults = UserDefaults.standard
        ConfigUploadFolder = defaults.string(forKey: "KEY_UPLOAD_FOLDER") ?? DEFAULT_UPLOAD_FOLDER
        ConfigAudioBitRate = defaults.string(forKey: "KEY_AUDIO_BIT_RATE") ?? DEFAULT_AUDIO_BIT_RATE
    }
    
    func saveSettings(uploadFolder: String,  audioBitRate: String) {
        
        let defaults = UserDefaults.standard
        defaults.set(uploadFolder, forKey: KEY_UPLOAD_FOLDER)
        defaults.set(audioBitRate, forKey: KEY_AUDIO_BIT_RATE)
    }
    
}
