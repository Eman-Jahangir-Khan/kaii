rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }

        match /users/{uid} {

          // Username 7 din mein sirf ek baar badal sakta hai, aur naya username
          // usernames collection mein mere naam reserve hona chahiye
          function usernameChangeOk() {
            let oldName = resource.data.get('username', null);
            let newName = request.resource.data.get('username', null);
            let oldAt = resource.data.get('usernameChangedAt', null);
            let newAt = request.resource.data.get('usernameChangedAt', null);
            return
              // username nahi badla: usernameChangedAt bhi wohi rahe
              (newName == oldName && newAt == oldAt)
              // username badla
              || (newName != oldName
                  && newName is string
                  && newName.matches('^[a-z0-9_.]{6,20}$')
                  && newAt == request.time
                  && (oldAt == null
                      || request.time >= oldAt + duration.value(7, 'd'))
                  && getAfter(/databases/$(database)/documents/usernames/$(newName)).data.uid
                       == request.auth.uid);
          }

          allow read: if signedIn();
          allow create, delete: if signedIn() && request.auth.uid == uid;
          allow update: if signedIn() && request.auth.uid == uid
            && (resource == null || usernameChangeOk());
        }

        match /usernames/{username} {
        // signup se pehle availability check ke liye single get sab ko allowed
          allow get: if true;
          allow read: if signedIn();
          allow create: if signedIn()
            && request.resource.data.uid == request.auth.uid
            && username.matches('^[a-z0-9_.]{6,20}$');
          // sirf apna username doc delete ho sake (purana naam free karne ke liye)
          allow delete: if request.auth != null && resource.data.uid == request.auth.uid;
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

              allow delete: if signedIn() && isParticipant()
                && resource.data.get('status', 'accepted') == 'pending'
                && resource.data.requestedBy == request.auth.uid;

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
              && request.resource.data.type in ['text', 'system', 'image', 'video']
              && (request.resource.data.type != 'image'
                  || (request.resource.data.imageUrl is string
                      && request.resource.data.imageUrl.matches(
                           'https://res\\.cloudinary\\.com/.*')))
              && (request.resource.data.type != 'video'
                  || (request.resource.data.videoUrl is string
                      && request.resource.data.videoUrl.matches(
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

      }
    }

    // Apne rules ke andar, `match /databases/{database}/documents { ... }` ke andar paste karo.
    // Ye groups ke liye hain; baqi (users, chats, usernames) jaise pehle the waise hi rehne do.

    match /groups/{groupId} {

          // map mein sirf meri apni entry badle
          function myMapEntryOnly(field) {
            let before = resource.data.get(field, {});
            let after = request.resource.data.get(field, {});
            return after.diff(before).affectedKeys().hasOnly([request.auth.uid]);
          }

          // list mein sirf meri apni uid add / remove ho
          function myUidOnly(field) {
            let me = request.auth.uid;
            let before = resource.data.get(field, []);
            let after = request.resource.data.get(field, []);
            return before.removeAll([me]).hasOnly(after.removeAll([me]))
                && after.removeAll([me]).hasOnly(before.removeAll([me]));
          }

      allow read: if request.auth != null
                  && (request.auth.uid in resource.data.get('members', [])
                      || request.auth.uid in resource.data.get('everMembers', []));

      allow create: if request.auth != null
                    && request.resource.data.createdBy == request.auth.uid
                    && request.auth.uid in request.resource.data.members
                    && request.auth.uid in request.resource.data.admins;

      allow update: if request.auth != null && (

        // 1. member: admin kuch bhi, baaki sirf chat ki activity
        (
          request.auth.uid in resource.data.members
          && (
            request.auth.uid in resource.data.admins
            || request.resource.data.diff(resource.data).affectedKeys()
                 .hasOnly(['lastMessage', 'lastMessageAt', 'lastSenderId',
                           'lastSenderName', 'unread', 'lastRead', 'typing',
                           'myPreview', 'markedUnread'])
          )
        )

        // 2. member ya chhodne wala: sirf apna personal data
        //    (theme, clear chat, pin, mark unread, delete group)
        || (
          request.auth.uid in resource.data.everMembers
          && request.resource.data.diff(resource.data).affectedKeys()
               .hasOnly(['chatTheme', 'clearedAt', 'deletedAt', 'unread',
                         'pinnedBy', 'markedUnread'])
          && myMapEntryOnly('chatTheme')
          && myMapEntryOnly('clearedAt')
          && myMapEntryOnly('deletedAt')
          && myMapEntryOnly('unread')
          && myUidOnly('pinnedBy')
          && myUidOnly('markedUnread')
        )

        // 3. group chhodna (khud nikalna)
        || (
          request.auth.uid in resource.data.members
          && request.resource.data.diff(resource.data).affectedKeys()
               .hasOnly(['members', 'admins', 'leftAt', 'leftBy', 'leftSnapshot',
                         'lastMessage', 'lastMessageAt', 'lastSenderId',
                         'lastSenderName'])
          && !(request.auth.uid in request.resource.data.members)
        )
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

        match /statuses/{statusId} {

          function signedIn() {
            return request.auth != null;
          }

          // parent status ka data (comments/views ke rules ke liye)
          function parent() {
            return get(/databases/$(database)/documents/statuses/$(statusId)).data;
          }
          function canSeeParent() {
            return signedIn() &&
              (parent().ownerId == request.auth.uid ||
               request.auth.uid in parent().visibleTo);
          }
          function isParentOwner() {
            return signedIn() && parent().ownerId == request.auth.uid;
          }

          // likes / viewedBy mein sirf meri apni uid add ya remove ho sakti hai
          function onlyMyUidChanged(field) {
            let before = resource.data.get(field, []).toSet();
            let after = request.resource.data.get(field, []).toSet();
            return before.difference(after)
              .union(after.difference(before))
              .hasOnly([request.auth.uid]);
          }

          allow read: if signedIn() &&
            (resource.data.ownerId == request.auth.uid ||
             request.auth.uid in resource.data.visibleTo);

                    allow create: if signedIn() &&
                      request.resource.data.ownerId == request.auth.uid &&
                      request.resource.data.visibleTo is list &&
                      request.resource.data.mediaType in ['image', 'video', 'text'] &&
                      request.resource.data.mediaUrl is string &&
                      (request.resource.data.mediaType != 'text' ||
                        (request.resource.data.caption is string &&
                         request.resource.data.caption.size() > 0 &&
                         request.resource.data.caption.size() <= 200));

          allow update: if signedIn() &&
            (resource.data.ownerId == request.auth.uid ||
             request.auth.uid in resource.data.visibleTo) &&
            request.resource.data.diff(resource.data).affectedKeys()
              .hasOnly(['likes', 'viewedBy']) &&
            onlyMyUidChanged('likes') &&
            onlyMyUidChanged('viewedBy');

          allow delete: if signedIn() && resource.data.ownerId == request.auth.uid;

          match /comments/{commentId} {
            allow read: if canSeeParent();
            allow create: if canSeeParent() &&
              request.resource.data.userId == request.auth.uid &&
              request.resource.data.text is string &&
              request.resource.data.text.size() > 0 &&
              request.resource.data.text.size() <= 500;
            allow delete: if signedIn() &&
              (resource.data.userId == request.auth.uid || isParentOwner());
          }

          match /views/{viewerId} {
            allow read: if signedIn() &&
              (viewerId == request.auth.uid || isParentOwner());
            allow create, update: if canSeeParent() && viewerId == request.auth.uid;
          }

        }

        match /statusSettings/{uid} {
          allow read, write: if request.auth != null && request.auth.uid == uid;
        }

        match /users/{uid}/contacts/{other} {
          allow read, write: if request.auth != null && request.auth.uid == uid;
        }


        match /calls/{callId} {
          allow create: if request.auth != null
                        && request.resource.data.callerId == request.auth.uid;
          allow read: if request.auth != null
                      && (resource.data.calleeId == request.auth.uid
                          || resource.data.callerId == request.auth.uid
                          || request.auth.uid in resource.data.participants);
          allow update: if request.auth != null
                        && request.auth.uid in resource.data.participants;
        }

  }
}