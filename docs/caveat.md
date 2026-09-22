While MUSIXQUARE is an incredible open-source project and a great proof-of-concept for browser-based surround sound, it runs into several inherent limitations because it relies entirely on web browsers and WebRTC. 

If you're studying it to improve your own app, here are the main problems and limitations MUSIXQUARE faces:

### 1. The "Live Audio" Sync Problem
As I mentioned earlier, their brilliant `SharedClock` sync algorithm works flawlessly for **Local Files** and **YouTube** because the app knows the exact length of the song and can easily jump around to future/past timestamps. However, for **Live System Audio** (like streaming a live DJ set or microphone), you can't "skip ahead" to audio that hasn't been recorded yet. Because of this, their System Audio mode falls back to standard WebRTC streams (just like your app) and they explicitly label it as "Beta" and limit it to only 4 devices. 

### 2. The Host Bottleneck (Peer-to-Peer Limits)
MUSIXQUARE uses a "Mesh" Peer-to-Peer network. This means the Host computer establishes a direct, individual connection with *every single phone*.
* If you connect 1 phone, the Host uploads 1 audio stream. 
* If you connect 15 phones for a massive party, your Host computer now has to encode and upload 15 separate audio streams simultaneously. 
This heavily taxes the Host's CPU and Wi-Fi bandwidth, which is why it struggles to scale to large numbers of devices without dedicated server infrastructure.

### 3. Mobile Browsers Kill Background Sync
Modern mobile browsers (especially Safari on iOS) are very aggressive about saving battery. If a guest is playing audio and then **locks their phone screen** or switches to another app:
* The browser throttles the Javascript timers that run the `SharedClock` sync loop.
* The browser might suspend the WebRTC connection entirely.
This causes the audio to drift wildly out of sync, stutter, or just die completely. Native apps (like Spotify or Sonos) have OS-level permissions to run precisely in the background, but web browsers do not.

### 4. Audio "Wobble" (Pitch Shifting)
To keep the devices in sync, MUSIXQUARE constantly tweaks the `playbackRate` (speeding the audio up to 1.05x or slowing it down to 0.95x). If a phone's network connection is unstable, the app will constantly speed up and slow down the audio to try and catch up. To an audiophile, this can sound like a slight "wobble" or pitch distortion in the music. 

**The Takeaway:**
If you want to build a synchronized audio app in the browser, MUSIXQUARE is the gold standard to look at. However, it ultimately proves that web browsers are not designed to be professional-grade, multi-device audio receivers due to battery throttling, WebRTC bottlenecks, and real-time live streaming latency.