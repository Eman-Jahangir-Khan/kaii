# 💬 Kaii

**Kaii** is a WhatsApp-style real-time chatting app built with **Flutter** and **Firebase**. It supports one-to-one chats, group chats, 24-hour status stories, photo/video sharing, and voice/video calls.

---

## ✨ Features

### 🔐 Authentication
- Sign up / login with Firebase Authentication
- Unique username for every user
- Delete account (username is freed for others; deleted users show as "Unknown user")

### 💬 One-to-One Chat
- Real-time messaging
- Find users by username, send a chat request, and message once accepted
- Cancel a pending request
- Block / unblock users
- Last seen

### 👥 Group Chat
- Create groups and add members
- Group info screen
- Real-time group messaging

### 📸 Media Sharing
- Share photos and videos in chats and groups
- Pick from Gallery or capture with Camera
- Media stored on Cloudinary

### 🟢 Status (Stories)
- 24-hour status as image or video
- Visibility control: all contacts / only selected / all contacts except selected
- Full-screen viewer with auto-play to the next contact
- "Viewed by" list with likes
- Reply to a status (goes to the owner's chat with the status quoted)

### 📞 Calls
- Voice and video calls using Agora
- Incoming call screen (CallKit)
- Minimize call banner
- Call history screen and call log inside chats

### 👤 Profile & Contacts
- Edit nickname
- Change username (once every 7 days, must be unique)
- Private saved name for each contact
- Contact info: shared media, groups in common, block option

---

## 🛠️ Tech Stack

| Area | Technology |
|------|------------|
| Framework | Flutter (Dart) |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| Media Storage | Cloudinary |
| Calls | Agora |

---

## 📸 Screenshots

> Add your screenshots in a `screenshots/` folder and link them here.

| Login | Chats | Chat Screen |
|-------|-------|-------------|
| ![Login](screenshots/login.png) | ![Chats](screenshots/chats.png) | ![Chat](screenshots/chat.png) |

| Status | Group Chat | Calls |
|--------|------------|-------|
| ![Status](screenshots/status.png) | ![Group](screenshots/group.png) | ![Calls](screenshots/calls.png) |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK installed
- A Firebase project
- A Cloudinary account
- An Agora account

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/<your-username>/kaii.git
   cd kaii
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up Firebase**
    - Create a project in the [Firebase Console](https://console.firebase.google.com/)
    - Enable **Authentication** and **Cloud Firestore**
    - Add your Android/iOS app and download `google-services.json` (place it in `android/app/`) and/or `GoogleService-Info.plist`
    - Add the Firestore security rules from your `rules.js` file

4. **Set up Cloudinary**
    - Create an unsigned upload preset
    - Add your cloud name and upload preset in the app's config file

5. **Set up Agora**
    - Create a project and copy the App ID
    - Add it in the app's config file

6. **Run the app**
   ```bash
   flutter run
   ```

> ⚠️ Never upload secret keys to GitHub. Keep private keys out of the repository.

---

## 📂 Project Structure

```
lib/
├── main.dart
├── screens/
├── repositories/
├── models/
└── widgets/
```

> Update this to match your actual folders.

---

## 🔮 Future Improvements
- Voice messages
- Group calls
- Mute Notification

---

## 👩‍💻 Author

**Eman Jahangir Khan**
BS Information Technology, University of the Punjab
Flutter Developer

- GitHub: [Eman-Jahangir-Khan](https://github.com/Eman-Jahangir-Khan)
- LinkedIn: [Eman Jahangir Khan](www.linkedin.com/in/eman-jahangir-khan-99b2b537a)

---

⭐ If you like this project, give it a star!