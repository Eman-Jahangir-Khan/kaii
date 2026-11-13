rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }

    match /users/{uid} {
      allow read: if signedIn();
      allow write: if signedIn() && request.auth.uid == uid;
    }

    match /usernames/{username} {
      allow read: if signedIn();
      allow create: if signedIn();
    }

    match /chats/{chatId} {
      function isMine() {
        return chatId.matches(request.auth.uid + '_.*')
            || chatId.matches('.*_' + request.auth.uid);
      }
      function isParticipant() {
        return request.auth.uid in resource.data.participants;
      }

      // In lists mein har user sirf apna hi uid add / remove kar sake
      function listOk(field) {
        let me = request.auth.uid;
        let before = resource.data.get(field, []);
        let after = request.resource.data.get(field, []);
        return before.removeAll([me]).hasOnly(after.removeAll([me]))
            && after.removeAll([me]).hasOnly(before.removeAll([me]));
      }

      // In maps mein har user sirf apni hi entry badal sake
      function mapOk(field) {
        let before = resource.data.get(field, {});
        let after = request.resource.data.get(field, {});
        return after.diff(before).affectedKeys().hasOnly([request.auth.uid]);
      }

      function fieldsOk() {
        return request.resource.data.participants == resource.data.participants
          && listOk('blockedBy')
          && listOk('pinnedBy')
          && listOk('markedUnread')
          && mapOk('deletedAt')
          && mapOk('clearedAt')
          && mapOk('chatTheme')
          && mapOk('myPreview');
      }

      allow read: if signedIn() &&
        ((resource == null && isMine()) ||
         (resource != null && isParticipant()));

      // naya request: status pending aur requestedBy mera apna
      allow create: if signedIn()
        && request.resource.data.participants.size() == 2
        && request.auth.uid in request.resource.data.participants
        && chatId == request.resource.data.participants[0] + '_'
                     + request.resource.data.participants[1]
        && request.resource.data.status == 'pending'
        && request.resource.data.requestedBy == request.auth.uid;

      allow update: if signedIn() && isParticipant() && fieldsOk() && (
        // accepted (ya purani) chat mein normal activity
        (resource.data.get('status', 'accepted') == 'accepted'
          && request.resource.data.get('status', 'accepted') == 'accepted')
        // sirf samne wala accept ya reject kar sakta hai
        || (resource.data.status == 'pending'
          && resource.data.requestedBy != request.auth.uid
          && request.resource.data.status in ['accepted', 'rejected'])
        // jis ne reject kiya wo baad mein khud request bhej sakta hai
        || (resource.data.get('status', 'accepted') == 'rejected'
          && resource.data.requestedBy != request.auth.uid
          && request.resource.data.status == 'pending'
          && request.resource.data.requestedBy == request.auth.uid)
      );

      match /messages/{msgId} {
        function chat() {
          return get(/databases/$(database)/documents/chats/$(chatId)).data;
        }
        function inChat() {
          return signedIn() && request.auth.uid in chat().participants;
        }
        function changed() {
          return request.resource.data.diff(resource.data).affectedKeys();
        }
        function isSender() {
          return resource.data.senderId == request.auth.uid;
        }
        // deletedFor mein sirf apna uid add / remove
        function myDeletedForOnly() {
          let me = request.auth.uid;
          let before = resource.data.get('deletedFor', []);
          let after = request.resource.data.get('deletedFor', []);
          return before.removeAll([me]).hasOnly(after.removeAll([me]))
              && after.removeAll([me]).hasOnly(before.removeAll([me]));
        }
        // reactions mein sirf apni entry (ek emoji, chhota sa)
        function myReactionOnly() {
          let me = request.auth.uid;
          let before = resource.data.get('reactions', {});
          let after = request.resource.data.get('reactions', {});
          return after.diff(before).affectedKeys().hasOnly([me])
              && (!(me in after)
                  || (after[me] is string && after[me].size() <= 8));
        }

        allow read: if inChat();

        allow create: if inChat()
          && request.resource.data.senderId == request.auth.uid
          && chat().get('status', 'accepted') == 'accepted'
          && chat().get('blockedBy', []).size() == 0
                    && request.resource.data.type in ['text', 'system', 'image']
                    && (request.resource.data.type != 'image'
                        || (request.resource.data.imageUrl is string
                            && request.resource.data.imageUrl.matches(
                                 'https://res\\.cloudinary\\.com/.*')))
          && request.resource.data.text is string
          && request.resource.data.text.size() <= 4000
          && request.resource.data.get('readAt', null) == null
          && request.resource.data.createdAt == request.time;

        allow update: if inChat() && (
          // 1. samne wale ke message ko read mark karna
          (changed().hasOnly(['readAt']) && !isSender()
            && request.resource.data.readAt == request.time)
          // 2. delete for me
          || (changed().hasOnly(['deletedFor']) && myDeletedForOnly())
          // 3. delete for everyone: sirf bhejne wala, 1 ghante ke andar
          || (isSender()
            && changed().hasOnly(['deletedForAll', 'text'])
            && request.resource.data.deletedForAll == true
            && request.resource.data.text == ''
            && request.time < resource.data.createdAt + duration.value(65, 'm'))
          // 4. edit: sirf bhejne wala, 15 minute ke andar
          || (isSender()
            && changed().hasOnly(['text', 'edited', 'editedAt'])
            && resource.data.get('deletedForAll', false) != true
            && request.resource.data.text is string
            && request.resource.data.text.size() > 0
            && request.resource.data.text.size() <= 4000
            && request.resource.data.edited == true
            && request.resource.data.editedAt == request.time
            && request.time < resource.data.createdAt + duration.value(17, 'm'))
          // 5. pin / unpin
          || (changed().hasOnly(['pinned', 'pinnedAt', 'pinnedBy'])
            && request.resource.data.get('pinnedBy', request.auth.uid)
                 == request.auth.uid)
          // 6. apni reaction
          || (changed().hasOnly(['reactions']) && myReactionOnly())
        );

        // sirf expire hone wale (disappearing) messages hard delete ho sakte hain
        allow delete: if inChat() && resource.data.get('expiresAt', null) != null;
      }
    }

    // Apne rules ke andar, `match /databases/{database}/documents { ... }` ke andar paste karo.
    // Ye groups ke liye hain; baqi (users, chats, usernames) jaise pehle the waise hi rehne do.

    match /groups/{groupId} {

            allow read: if request.auth != null
                        && request.auth.uid in resource.data.everMembers;

      allow create: if request.auth != null
                    && request.resource.data.createdBy == request.auth.uid
                    && request.auth.uid in request.resource.data.members
                    && request.auth.uid in request.resource.data.admins;

      allow update: if request.auth != null
                    && request.auth.uid in resource.data.members
                    && (
                      // admin sab kuch badal sakta hai (naam, photo, members, admins)
                      request.auth.uid in resource.data.admins

                      // har member in fields ko badal sakta hai (send, read, typing)
                      || request.resource.data.diff(resource.data).affectedKeys()
                           .hasOnly(['lastMessage', 'lastMessageAt', 'lastSenderId',
                                     'lastSenderName', 'unread', 'lastRead', 'typing'])

                      // koi bhi member khud group chhod sakta hai
                      || (request.resource.data.diff(resource.data).affectedKeys()
                            .hasOnly(['members', 'admins', 'leftAt', 'leftBy', 'lastMessage',
                                      'lastMessageAt', 'lastSenderId', 'lastSenderName'])
                          && !(request.auth.uid in request.resource.data.members))
                    );

      match /messages/{messageId} {
        function groupPath() {
          return /databases/$(database)/documents/groups/$(groupId);
        }
        // getAfter: group banane / chhodne wale batch ka system message bhi chal jaye
        function isMember() {
          return request.auth != null
              && (request.auth.uid in getAfter(groupPath()).data.members
                  || (exists(groupPath())
                      && request.auth.uid in get(groupPath()).data.members));
        }
        function isAdmin() {
          return request.auth.uid in get(groupPath()).data.admins;
        }

        allow read: if request.auth != null
                    && request.auth.uid in get(groupPath()).data.everMembers;

        allow create: if isMember() && request.resource.data.senderId == request.auth.uid;

        allow update: if request.auth != null
                      && request.auth.uid in get(groupPath()).data.members
                      && (
                        // apna message (edit / delete for everyone)
                        resource.data.senderId == request.auth.uid

                        // koi bhi member: reaction aur "delete for me"
                        || request.resource.data.diff(resource.data).affectedKeys()
                             .hasOnly(['reactions', 'deletedFor'])

                                                     // koi bhi member: pin / unpin
                        || request.resource.data.diff(resource.data).affectedKeys()
                             .hasOnly(['pinned', 'pinnedAt', 'pinnedBy'])

                        // admin kisi ka bhi message sab ke liye delete kar sakta hai
                        || (isAdmin()
                            && request.resource.data.diff(resource.data).affectedKeys()
                                 .hasOnly(['deletedForAll', 'text']))
                      );
      }
    }
  }
}